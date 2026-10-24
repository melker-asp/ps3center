import Darwin
import Foundation
import Network

/// A read-only ps3netsrv in Swift: webMAN's /net0 … /net4 read games straight from the Mac's
/// game folders, without copying them. The protocol follows aldostools/ps3netsrv
/// (include/netiso.h, src/main.cpp): 16-byte big-endian commands answered with fixed-size
/// big-endian results. Only reading is implemented; a command that writes closes the
/// connection, as ps3netsrv's READ_ONLY build does, so the console can never change the Mac.
///
/// The root is virtual: /PS3ISO, /PS2ISO … are the linked folders of each kind merged. Next to
/// every PS3 ISO, <name>.SFO and <name>.PNG are served from inside the image, which webMAN
/// reads for the title and the icon (with the stock ps3netsrv they have to be extracted by hand).
public final class NetServer: @unchecked Sendable {
    public struct Status: Equatable, Sendable {
        public var isRunning = false
        public var clients = 0
        /// The last game file the console opened, relative to the root ("/PS3ISO/Game.iso").
        public var lastFile: String?
        public var bytesServed: Int64 = 0
        public var error: String?

        public init(isRunning: Bool = false, clients: Int = 0, lastFile: String? = nil, bytesServed: Int64 = 0, error: String? = nil) {
            self.isRunning = isRunning
            self.clients = clients
            self.lastFile = lastFile
            self.bytesServed = bytesServed
            self.error = error
        }
    }

    public static let defaultPort: UInt16 = 38008

    public let port: UInt16
    private let root: NetRoot
    private let allowedHost: String?
    private let onChange: @Sendable (Status) -> Void
    private let queue = DispatchQueue(label: "ps3center.netsrv")
    private let lock = NSLock()
    private var listener: NWListener?
    private var status = Status()
    private var lastReport = Date.distantPast

    /// `allowedHost` (the console's address) is the only client let in; nil lets any in.
    public init(folders: [(kind: GameFolders.Kind, url: URL)] = GameFolders.linked(), allowedHost: String?,
                port: UInt16 = defaultPort, onChange: @escaping @Sendable (Status) -> Void = { _ in }) {
        var byKind: [String: [URL]] = [:]
        for (kind, url) in folders { byKind[kind.name, default: []].append(url) }
        root = NetRoot(folders: byKind)
        self.allowedHost = allowedHost
        self.port = port
        self.onChange = onChange
    }

    public func start() throws {
        guard listener == nil, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let listener = try NWListener(using: .tcp, on: nwPort)
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.update { $0.isRunning = true; $0.error = nil }
            case .failed(let error):
                self?.update { $0.isRunning = false; $0.error = "Spelservern kunde inte starta: \(error.localizedDescription)" }
            case .cancelled:
                self?.update { $0.isRunning = false; $0.clients = 0 }
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    public var currentStatus: Status {
        lock.lock()
        defer { lock.unlock() }
        return status
    }

    private func accept(_ connection: NWConnection) {
        if let allowedHost, case .hostPort(let host, _) = connection.endpoint {
            var address = "\(host)".split(separator: "%").first.map(String.init) ?? ""
            if address.hasPrefix("::ffff:") { address.removeFirst(7) }  // IPv4 on a dual-stack listener
            guard address == allowedHost || address == "127.0.0.1" else {
                connection.cancel()
                return
            }
        }
        update { $0.clients += 1 }
        let session = NetSession(connection: connection, root: root, server: self)
        connection.start(queue: queue)
        Task {
            await session.run()
            self.update { $0.clients = max(0, $0.clients - 1) }
        }
    }

    func update(_ change: (inout Status) -> Void) {
        lock.lock()
        change(&status)
        let current = status
        lock.unlock()
        onChange(current)
    }

    /// Reads are many and small, so they are reported at most twice a second.
    func served(_ bytes: Int, file: String?) {
        lock.lock()
        status.bytesServed += Int64(bytes)
        if let file { status.lastFile = file }
        let now = Date()
        let report = now.timeIntervalSince(lastReport) > 0.5
        if report { lastReport = now }
        let current = status
        lock.unlock()
        if report { onChange(current) }
    }

    /// The Mac's address on the console's network (the same first three numbers), else the first.
    public static func address(facing console: String) -> String? {
        let all = macAddresses()
        let prefix = console.split(separator: ".").prefix(3).joined(separator: ".") + "."
        return all.first { $0.hasPrefix(prefix) } ?? all.first
    }

    /// The Mac's IPv4 addresses on its network interfaces, to enter in webMAN's settings.
    public static func macAddresses() -> [String] {
        var result: [String] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }
        for ifa in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: ifa.pointee.ifa_name)
            guard name.hasPrefix("en"), let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            if !ip.hasPrefix("169.254"), !result.contains(ip) { result.append(ip) }
        }
        return result
    }
}

/// One entry in a listing of the virtual root.
struct NetEntry: Equatable {
    let name: String
    let size: Int64
    let mtime: UInt64
    let isDirectory: Bool
}

/// The virtual root the console sees: kind folders on top, each the linked Mac folders merged.
struct NetRoot: Sendable {
    let folders: [String: [URL]]

    /// Path components after checking the path is safe: absolute and without "..".
    static func components(_ path: String) -> [String]? {
        guard path.hasPrefix("/") else { return nil }
        let parts = path.split(separator: "/").map(String.init)
        guard !parts.contains("..") else { return nil }
        return parts.filter { $0 != "." }
    }

    /// The real file or folder behind a path, from the first linked folder that has it.
    func resolve(_ path: String) -> URL? {
        guard let parts = Self.components(path), let kind = parts.first, let roots = folders[kind] else { return nil }
        let rest = parts.dropFirst().joined(separator: "/")
        for root in roots {
            let url = rest.isEmpty ? root : root.appendingPathComponent(rest)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    func isDirectory(_ path: String) -> Bool {
        guard let parts = Self.components(path) else { return false }
        if parts.isEmpty { return true }
        if parts.count == 1 { return folders[parts[0]] != nil }
        guard let url = resolve(path) else { return false }
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    /// A merged listing. With `subdirs` (webMAN asks with "//" in the path), the files of
    /// subfolders come too, named "sub/file", and the subfolders themselves do not, as in ps3netsrv.
    func list(_ path: String, subdirs: Bool = false) -> [NetEntry]? {
        guard let parts = Self.components(path) else { return nil }
        if parts.isEmpty {
            return folders.keys.sorted().map { NetEntry(name: $0, size: 0, mtime: 0, isDirectory: true) }
        }
        guard let roots = folders[parts[0]] else { return nil }
        let rest = parts.dropFirst().joined(separator: "/")
        var seen = Set<String>()
        var entries: [NetEntry] = []
        var found = false
        for root in roots {
            let folder = rest.isEmpty ? root : root.appendingPathComponent(rest)
            guard let items = Self.read(folder) else { continue }
            found = true
            for item in items where seen.insert(item.name).inserted {
                if subdirs, item.isDirectory {
                    for inner in Self.read(folder.appendingPathComponent(item.name)) ?? [] where !inner.isDirectory {
                        entries.append(NetEntry(name: item.name + "/" + inner.name, size: inner.size, mtime: inner.mtime, isDirectory: false))
                    }
                } else {
                    entries.append(item)
                }
            }
        }
        return found ? entries : nil
    }

    static func read(_ folder: URL) -> [NetEntry]? {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                       options: [.skipsHiddenFiles]) else { return nil }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let mtime = UInt64(max(0, values.contentModificationDate?.timeIntervalSince1970 ?? 0))
            let directory = values.isDirectory ?? false
            return NetEntry(name: url.lastPathComponent, size: directory ? 0 : Int64(values.fileSize ?? 0),
                            mtime: mtime, isDirectory: directory)
        }
        .sorted { $0.name < $1.name }
    }

    /// <name>.SFO and <name>.PNG next to a PS3 ISO, read out of the image.
    func virtualFile(_ path: String) -> Data? {
        let ext = (path as NSString).pathExtension.uppercased()
        guard ext == "SFO" || ext == "PNG" else { return nil }
        let base = (path as NSString).deletingPathExtension
        for candidate in [base + ".iso", base + ".ISO", base + ".iso.0"] {
            guard let url = resolve(candidate), let image = try? ISOImage(url: url) else { continue }
            let inner = ext == "SFO" ? "PS3_GAME/PARAM.SFO" : "PS3_GAME/ICON0.PNG"
            if let data = try? image.readFile(inner) { return data }
        }
        return nil
    }

    func directorySize(_ path: String) -> Int64? {
        guard let url = resolve(path) else { return nil }
        return ((try? FileRouter.filesRecursively(in: url)) ?? []).map(FileRouter.fileSize).reduce(0, +)
    }
}

/// The commands, numbered from NETISO_CMD_OPEN_FILE in netiso.h.
enum NetCommand: UInt16 {
    case openFile = 0x1224, readFileCritical, readCD2048Critical, readFile, createFile, writeFile, openDir,
         readDirEntry, deleteFile, mkdir, rmdir, readDirEntryV2, statFile, getDirSize, readDir
}

/// One console connection: commands are handled one after another, as ps3netsrv's client thread does.
final class NetSession: @unchecked Sendable {
    enum Failure: Error { case closed, refused }

    /// The open file: a file on the Mac, or a .SFO/.PNG made from inside an ISO.
    enum OpenFile {
        case disk(FileHandle, size: UInt64)
        case memory(Data)

        func read(at offset: UInt64, count: Int) -> Data? {
            switch self {
            case .disk(let handle, let size):
                guard offset <= size else { return Data() }
                do {
                    try handle.seek(toOffset: offset)
                    return try handle.read(upToCount: count) ?? Data()
                } catch {
                    return nil
                }
            case .memory(let data):
                guard offset <= UInt64(data.count) else { return Data() }
                let start = data.startIndex + Int(offset)
                return data[start..<min(data.endIndex, start + count)]
            }
        }

        func close() {
            if case .disk(let handle, _) = self { try? handle.close() }
        }
    }

    static let bufferSize = 4 << 20
    static let maxEntries = 4096

    private let connection: NWConnection
    private let root: NetRoot
    private weak var server: NetServer?
    private var file: OpenFile?
    private var filePath: String?
    private var cdSectorSize: UInt64 = 2352
    private var directory: [NetEntry] = []
    private var directoryOpen = false
    private var subdirs = false

    init(connection: NWConnection, root: NetRoot, server: NetServer?) {
        self.connection = connection
        self.root = root
        self.server = server
    }

    func run() async {
        while true {
            do {
                let command = try await receive(16)
                try await handle(command)
            } catch {
                break
            }
        }
        file?.close()
        connection.cancel()
    }

    func handle(_ command: Data) async throws {
        guard let kind = NetCommand(rawValue: command.be16(0)) else { throw Failure.refused }
        switch kind {
        case .openFile: try await openFile(try await receivePath(command))
        case .readFileCritical: try await readCritical(count: Int(command.be32(4)), offset: command.be64(8))
        case .readCD2048Critical: try await readCD(start: UInt64(command.be32(4)), count: Int(command.be32(8)))
        case .readFile: try await readFile(count: Int(command.be32(4)), offset: command.be64(8))
        case .openDir: try await openDir(try await receivePath(command))
        case .readDirEntry: try await readDirEntry(version: 1)
        case .readDirEntryV2: try await readDirEntry(version: 2)
        case .statFile: try await stat(try await receivePath(command))
        case .getDirSize: try await dirSize(try await receivePath(command))
        case .readDir: try await readDir()
        case .createFile, .writeFile, .deleteFile, .mkdir, .rmdir:
            // Read-only: like ps3netsrv's READ_ONLY build, writing ends the connection.
            throw Failure.refused
        }
    }

    // MARK: Files

    private func openFile(_ path: String) async throws {
        file?.close()
        file = nil
        filePath = nil
        cdSectorSize = 2352
        var result = Data()
        if path == "/CLOSEFILE" {
            result.appendBE(Int64(-1))
            result.appendBE(UInt64(0))
            try await send(result)
            return
        }
        if let data = root.virtualFile(path), NetRoot.components(path) != nil {
            file = .memory(data)
            result.appendBE(Int64(data.count))
            result.appendBE(UInt64(0))
        } else if let url = root.resolve(path), !root.isDirectory(path), let handle = try? FileHandle(forReadingFrom: url) {
            let size = UInt64(FileRouter.fileSize(url))
            let opened = OpenFile.disk(handle, size: size)
            file = opened
            filePath = path
            if size >= 0x20_0000, size <= 0x3500_0000 { cdSectorSize = Self.detectSectorSize(opened) }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
            result.appendBE(Int64(size))
            result.appendBE(UInt64(max(0, mtime)))
            server?.served(0, file: path)
        } else {
            result.appendBE(Int64(-1))
            result.appendBE(UInt64(0))
        }
        try await send(result)
    }

    /// CD images of 2–848 MB: the sector size whose 17th sector holds the volume descriptor
    /// (or "PLAYSTATION" as system id), as ps3netsrv detects it. 2352 otherwise.
    static func detectSectorSize(_ file: OpenFile) -> UInt64 {
        for size: UInt64 in [2352, 2048, 2336, 2448, 2328, 2368, 2340] {
            guard let data = file.read(at: size << 4 + 0x18, count: 20), data.count == 20 else { continue }
            let bytes = [UInt8](data)
            if String(decoding: bytes[8..<20], as: UTF8.self) == "PLAYSTATION " { return size }
            if bytes[0] == 1, String(decoding: bytes[1..<6], as: UTF8.self) == "CD001" { return size }
        }
        return 2352
    }

    private func readCritical(count: Int, offset: UInt64) async throws {
        guard let file else { throw Failure.closed }
        var remaining = count
        var position = offset
        while remaining > 0 {
            let size = min(Self.bufferSize, remaining)
            guard let data = file.read(at: position, count: size), data.count == size else { throw Failure.closed }
            try await send(data)
            remaining -= size
            position += UInt64(size)
        }
        server?.served(count, file: nil)
    }

    private func readCD(start: UInt64, count: Int) async throws {
        guard let file, count * 2048 <= Self.bufferSize else { throw Failure.closed }
        var out = Data(capacity: count * 2048)
        for index in 0..<UInt64(count) {
            guard let sector = file.read(at: (start + index) * cdSectorSize + 24, count: 2048), sector.count == 2048 else {
                throw Failure.closed
            }
            out.append(sector)
        }
        try await send(out)
        server?.served(out.count, file: nil)
    }

    private func readFile(count: Int, offset: UInt64) async throws {
        var result = Data()
        guard let file, count <= Self.bufferSize, let data = file.read(at: offset, count: count) else {
            result.appendBE(Int32(-1))
            try await send(result)
            return
        }
        result.appendBE(Int32(data.count))
        result.append(data)
        try await send(result)
        server?.served(data.count, file: nil)
    }

    private func stat(_ path: String) async throws {
        var result = Data()
        if let data = root.virtualFile(path) {
            result.appendBE(Int64(data.count))
            result.appendBE(UInt64(0)); result.appendBE(UInt64(0)); result.appendBE(UInt64(0))
            result.append(0)
        } else if root.isDirectory(path) {
            result.appendBE(Int64(0))
            result.appendBE(UInt64(0)); result.appendBE(UInt64(0)); result.appendBE(UInt64(0))
            result.append(1)
        } else if let url = root.resolve(path) {
            let mtime = UInt64(max(0, (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0))
            result.appendBE(Int64(FileRouter.fileSize(url)))
            result.appendBE(mtime); result.appendBE(mtime); result.appendBE(mtime)
            result.append(0)
        } else {
            result.appendBE(Int64(-1))
            result.appendBE(UInt64(0)); result.appendBE(UInt64(0)); result.appendBE(UInt64(0))
            result.append(0)
        }
        try await send(result)
    }

    // MARK: Folders

    private func openDir(_ path: String) async throws {
        subdirs = path.contains("//")
        let entries = root.list(path, subdirs: subdirs)
        directory = Array((entries ?? []).prefix(Self.maxEntries))
        directoryOpen = entries != nil
        var result = Data()
        result.appendBE(Int32(entries == nil ? -1 : 0))
        try await send(result)
    }

    private func readDirEntry(version: Int) async throws {
        var result = Data()
        guard directoryOpen, !directory.isEmpty else {
            directoryOpen = false
            result.appendBE(Int64(-1))
            if version == 2 { result.appendBE(UInt64(0)); result.appendBE(UInt64(0)); result.appendBE(UInt64(0)) }
            result.appendBE(UInt16(0))
            result.append(0)
            try await send(result)
            return
        }
        let entry = directory.removeFirst()
        let name = Data(entry.name.utf8.prefix(255))
        result.appendBE(entry.isDirectory ? Int64(0) : entry.size)
        if version == 2 { result.appendBE(entry.mtime); result.appendBE(entry.mtime); result.appendBE(entry.mtime) }
        result.appendBE(UInt16(name.count))
        result.append(entry.isDirectory ? 1 : 0)
        result.append(name)
        try await send(result)
    }

    /// The whole listing at once: a count, then 529-byte records (size, mtime, is-directory, name[512]).
    private func readDir() async throws {
        let entries = directoryOpen ? directory : []
        directoryOpen = false
        directory = []
        var result = Data()
        result.appendBE(Int64(entries.count))
        for entry in entries {
            result.appendBE(entry.isDirectory ? Int64(0) : entry.size)
            result.appendBE(entry.mtime)
            result.append(entry.isDirectory ? 1 : 0)
            var name = Data(entry.name.utf8.prefix(511))
            name.append(Data(count: 512 - name.count))
            result.append(name)
        }
        try await send(result)
    }

    private func dirSize(_ path: String) async throws {
        var result = Data()
        result.appendBE(root.directorySize(path) ?? -1)
        try await send(result)
    }

    // MARK: Wire

    private func receivePath(_ command: Data) async throws -> String {
        let length = Int(command.be16(2))
        guard length > 0, length <= 4096 else { throw Failure.refused }
        let data = try await receive(length)
        return String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
    }

    private func receive(_ count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, data.count == count {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: Failure.closed)
                }
            }
        }
    }

    private func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }
}

extension Data {
    func be16(_ offset: Int) -> UInt16 {
        let i = startIndex + offset
        return UInt16(self[i]) << 8 | UInt16(self[i + 1])
    }

    func be32(_ offset: Int) -> UInt32 {
        UInt32(be16(offset)) << 16 | UInt32(be16(offset + 2))
    }

    func be64(_ offset: Int) -> UInt64 {
        UInt64(be32(offset)) << 32 | UInt64(be32(offset + 4))
    }

    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        var big = value.bigEndian
        Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) }
    }
}
