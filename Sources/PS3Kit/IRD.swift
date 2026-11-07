import Compression
import CryptoKit
import Foundation

/// An IRD file (ISO Rebuild Data): what a PS3 disc held, as recorded from the original. It has
/// the disc's file system (the "header", gzip) and the MD5 of every file's decrypted contents,
/// keyed by the block the file starts at. The layout follows 13xforever's ps3-disc-dumper
/// (IrdLibraryClient/IrdFormat/IrdParser.cs); all numbers are little-endian, and the whole file
/// may itself be gzip-compressed.
public struct IRD: Sendable {
    public let version: UInt8
    public let titleID: String
    public let title: String
    public let systemVersion: String
    public let gameVersion: String
    public let appVersion: String
    /// The disc's first blocks, up to the first file (gzip).
    let header: Data
    /// MD5s (hex) by the block a file starts at. A block can have more than one known hash.
    public let fileHashes: [UInt64: [String]]

    public static func parse(_ raw: Data) throws -> IRD {
        var data = raw
        if !data.starts(with: Array("3IRD".utf8)) {
            data = try Gzip.decompress(data)
        }
        guard data.starts(with: Array("3IRD".utf8)) else { throw PS3Error.invalidFile("The file is not an IRD.") }
        var reader = LittleEndianReader(data)
        _ = try reader.bytes(4)
        let version = try reader.u8()
        guard (6...9).contains(version) else { throw PS3Error.invalidFile("IRD version \(version) is not recognized.") }
        let titleID = try reader.ascii(9)
        let titleLength = Int(try reader.u8())
        let title = String(decoding: try reader.bytes(titleLength), as: UTF8.self)
        let systemVersion = try reader.ascii(4)
        let gameVersion = try reader.ascii(5)
        let appVersion = try reader.ascii(5)
        if version == 7 { _ = try reader.u32() }
        let headerLength = Int(try reader.u32())
        let header = try reader.bytes(headerLength)
        let footerLength = Int(try reader.u32())
        _ = try reader.bytes(footerLength)
        let regions = Int(try reader.u8())
        _ = try reader.bytes(regions * 16)
        let fileCount = Int(try reader.u32())
        var hashes: [UInt64: [String]] = [:]
        for _ in 0..<fileCount {
            let block = try reader.u64()
            let md5 = try reader.bytes(16).map { String(format: "%02x", $0) }.joined()
            hashes[block, default: []].append(md5)
        }
        _ = try reader.u32()
        if version == 9 { _ = try reader.bytes(115) }  // PIC
        _ = try reader.bytes(32)  // data1, data2
        if version < 9 { _ = try reader.bytes(115) }
        _ = try reader.u32()  // uid
        let checked = reader.offset
        let crc = try reader.u32()
        guard CRC32.checksum(data.prefix(checked)) == crc else {
            throw PS3Error.invalidFile("The IRD file is broken (the checksum does not match).")
        }
        return IRD(version: version, titleID: titleID, title: title, systemVersion: systemVersion,
                   gameVersion: gameVersion, appVersion: appVersion, header: Data(header), fileHashes: hashes)
    }

    /// The disc's files by upper-cased path ("PS3_GAME/USRDIR/EBOOT.BIN"), with their sizes and
    /// the MD5s they should have.
    public func files() throws -> [String: (size: UInt64, md5: [String])] {
        let image = try Gzip.decompress(header)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("ps3center-ird-\(UUID().uuidString).iso")
        try image.write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        var result: [String: (size: UInt64, md5: [String])] = [:]
        for file in try ISOImage(url: temp, joliet: true).allFiles() {
            result[file.path.uppercased()] = (file.size, fileHashes[file.extent] ?? [])
        }
        return result
    }
}

/// Checks a copy of a PS3 disc against its IRD: every file's MD5 against the original's.
public enum DiscVerifier {
    public struct Report: Sendable {
        public var title: String
        public var checked = 0
        public var matched = 0
        public var mismatched: [String] = []
        /// On the disc, not in the copy (PS3_UPDATE, the system update on the disc, aside).
        public var missing: [String] = []
        /// In the copy, not on the disc.
        public var extra: [String] = []

        public var isIntact: Bool { mismatched.isEmpty && missing.isEmpty && checked > 0 }

        /// Most files wrong at once: the image is still encrypted, as a redump or 3k3y ISO is.
        public var looksEncrypted: Bool { checked >= 4 && mismatched.count * 2 > checked }

        public var summary: String {
            if isIntact { return "\(title): all \(checked) files match the original disc." }
            var parts: [String] = []
            if !mismatched.isEmpty { parts.append("\(mismatched.count) \(mismatched.count == 1 ? "file differs" : "files differ")") }
            if !missing.isEmpty { parts.append("\(missing.count) missing") }
            var text = "\(title): \(matched) of \(checked) files match" + (parts.isEmpty ? "." : "; " + parts.joined(separator: ", ") + ".")
            if looksEncrypted { text += " The image seems to be encrypted; only decrypted ISOs and folders can be checked." }
            return text
        }
    }

    public typealias Progress = @Sendable (_ done: Int, _ total: Int, _ file: String) -> Void

    static func ignoredWhenMissing(_ path: String) -> Bool {
        path.hasPrefix("PS3_UPDATE/")
    }

    /// Compares the copy's files (by upper-cased path) with the disc's.
    static func compare(expected: [String: (size: UInt64, md5: [String])], present: [String: UInt64],
                        title: String, hash: (String) async throws -> String?, progress: Progress) async throws -> Report {
        var report = Report(title: title)
        let paths = expected.keys.sorted()
        for (index, path) in paths.enumerated() {
            try Task.checkCancellation()
            guard let file = expected[path], !file.md5.isEmpty else { continue }
            guard let size = present[path] else {
                if !ignoredWhenMissing(path) { report.missing.append(path) }
                continue
            }
            progress(index, paths.count, path)
            report.checked += 1
            if size != file.size {
                report.mismatched.append(path)
                continue
            }
            if let md5 = try await hash(path), file.md5.contains(md5.lowercased()) {
                report.matched += 1
            } else {
                report.mismatched.append(path)
            }
        }
        report.extra = present.keys.filter { expected[$0] == nil }.sorted()
        progress(paths.count, paths.count, "")
        return report
    }

    /// A game folder on the Mac (PS3_GAME, PS3_DISC.SFB …).
    public static func verify(folder: URL, ird: IRD, progress: Progress = { _, _, _ in }) async throws -> Report {
        let expected = try ird.files()
        var present: [String: UInt64] = [:]
        var locals: [String: URL] = [:]
        // The enumerator may hand back /private/var/… for /var/…, so both sides are resolved.
        let base = folder.resolvingSymlinksInPath().path
        for file in try FileRouter.filesRecursively(in: folder) {
            let full = file.resolvingSymlinksInPath().path
            guard full.hasPrefix(base + "/") else { continue }
            let relative = String(full.dropFirst(base.count + 1)).uppercased()
            present[relative] = UInt64(FileRouter.fileSize(file))
            locals[relative] = file
        }
        return try await compare(expected: expected, present: present, title: ird.title, hash: { path in
            try locals[path].map(TransferService.md5(of:))
        }, progress: progress)
    }

    /// A decrypted disc image on the Mac.
    public static func verify(iso url: URL, ird: IRD, progress: Progress = { _, _, _ in }) async throws -> Report {
        let expected = try ird.files()
        let image = try ISOImage(url: url, joliet: true)
        var present: [String: UInt64] = [:]
        var extents: [String: (extent: UInt64, size: UInt64)] = [:]
        for file in try image.allFiles() {
            let key = file.path.uppercased()
            present[key] = file.size
            extents[key] = (file.extent, file.size)
        }
        return try await compare(expected: expected, present: present, title: ird.title, hash: { path in
            guard let file = extents[path] else { return nil }
            return try image.md5(extent: file.extent, size: file.size)
        }, progress: progress)
    }

    /// A game folder on the console, such as a disc copied with `ps3 rip`. The console works out
    /// each MD5 itself (webMAN's /md5.ps3), which takes a while for a whole disc.
    public static func verify(consoleFolder: String, host: String, ird: IRD, progress: Progress = { _, _, _ in }) async throws -> Report {
        let expected = try ird.files()
        var remotes: [String: String] = [:]
        let present = try await TransferService(host: host).withFTP { ftp -> [String: UInt64] in
            var found: [String: UInt64] = [:]
            func walk(_ path: String, relative: String, depth: Int) async throws {
                guard depth < 32 else { return }
                for entry in try await ftp.list(path) {
                    let child = relative.isEmpty ? entry.name : relative + "/" + entry.name
                    if entry.isDirectory {
                        try await walk(path + "/" + entry.name, relative: child, depth: depth + 1)
                    } else {
                        found[child.uppercased()] = UInt64(entry.size)
                        remotes[child.uppercased()] = path + "/" + entry.name
                    }
                }
            }
            try await walk(consoleFolder, relative: "", depth: 0)
            return found
        }
        let webman = WebMAN(host: host)
        let known = remotes
        return try await compare(expected: expected, present: present, title: ird.title, hash: { path in
            guard let remote = known[path] else { return nil }
            let page = try await webman.long("/md5.ps3" + remote, timeout: 1800)
            return ConsoleSnapshot.firstMatch("([0-9a-fA-F]{32})", in: page)?[1]
        }, progress: progress)
    }
}

/// FlexBy420's IRD database on GitHub: an index of every known IRD by title ID, and the files.
/// The index is kept for a week in ~/Library/Caches/ps3center/ird; the IRD files for good.
public enum IRDLibrary {
    public struct Entry: Codable, Equatable, Sendable {
        public let title: String
        public let gameVersion: String?
        public let appVersion: String?
        public let fileCount: Int?
        public let link: String

        enum CodingKeys: String, CodingKey {
            case title, link
            case gameVersion = "game-ver"
            case appVersion = "app-ver"
            case fileCount = "file-count"
        }
    }

    static let indexURL = URL(string: "https://flexby420.github.io/playstation_3_ird_database/all.json")!
    static let downloadBase = "https://github.com/FlexBy420/playstation_3_ird_database/raw/main/"
    static var cache: URL { GameLibraryService.cacheDirectory("ird") }

    static func parseIndex(_ data: Data) throws -> [String: [Entry]] {
        try JSONDecoder().decode([String: [Entry]].self, from: data)
    }

    public static func index(maxAge: TimeInterval = 7 * 86_400) async throws -> [String: [Entry]] {
        let file = cache.appendingPathComponent("all.json")
        let age = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { Date().timeIntervalSince($0) }
        if let age, age < maxAge, let data = try? Data(contentsOf: file), let index = try? parseIndex(data) { return index }
        do {
            let (data, response) = try await URLSession.shared.data(from: indexURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PS3Error.github("The IRD database is not answering.") }
            let index = try parseIndex(data)
            try? data.write(to: file, options: .atomic)
            return index
        } catch {
            if let data = try? Data(contentsOf: file), let index = try? parseIndex(data) { return index }
            throw error
        }
    }

    /// The IRDs for a disc, those matching its PARAM.SFO versions first.
    public static func candidates(titleID: String, gameVersion: String?, appVersion: String?) async throws -> [Entry] {
        let all = try await index()[titleID.uppercased().replacingOccurrences(of: "-", with: "")] ?? []
        func score(_ entry: Entry) -> Int {
            (entry.gameVersion == gameVersion ? 2 : 0) + (entry.appVersion == appVersion ? 1 : 0)
        }
        return all.sorted { score($0) > score($1) }
    }

    public static func download(_ entry: Entry) async throws -> IRD {
        let file = cache.appendingPathComponent(AppsService.md5(Data(entry.link.utf8)) + ".ird")
        if let data = try? Data(contentsOf: file), let ird = try? IRD.parse(data) { return ird }
        let encoded = entry.link.split(separator: "/").map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        guard let url = URL(string: downloadBase + encoded) else { throw PS3Error.github("Invalid IRD link: \(entry.link)") }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PS3Error.github("The IRD file for \(entry.title) could not be downloaded.") }
        let ird = try IRD.parse(data)
        try? data.write(to: file, options: .atomic)
        return ird
    }
}

// MARK: Small readers

struct LittleEndianReader {
    let data: [UInt8]
    private(set) var offset = 0

    init(_ data: Data) { self.data = [UInt8](data) }

    mutating func bytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= data.count else { throw PS3Error.invalidFile("The IRD file ends too early.") }
        defer { offset += count }
        return Array(data[offset..<(offset + count)])
    }

    mutating func u8() throws -> UInt8 { try bytes(1)[0] }

    mutating func u32() throws -> UInt32 {
        try bytes(4).enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
    }

    mutating func u64() throws -> UInt64 {
        try bytes(8).enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
    }

    mutating func ascii(_ count: Int) throws -> String {
        String(decoding: try bytes(count), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
    }
}

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum<S: Sequence>(_ bytes: S) -> UInt32 where S.Element == UInt8 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}

/// Just enough gzip: one member, any of the optional header fields.
enum Gzip {
    static func decompress(_ data: Data) throws -> Data {
        let b = [UInt8](data)
        guard b.count > 18, b[0] == 0x1F, b[1] == 0x8B, b[2] == 8 else { throw PS3Error.invalidFile("Not gzip-compressed.") }
        let flags = b[3]
        var offset = 10
        if flags & 0x04 != 0 {
            guard offset + 2 <= b.count else { throw PS3Error.invalidFile("Broken gzip data.") }
            offset += 2 + (Int(b[offset]) | Int(b[offset + 1]) << 8)
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {
            while offset < b.count, b[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 }
        guard offset < b.count else { throw PS3Error.invalidFile("Broken gzip data.") }
        return try inflate(Data(b[offset...]))
    }

    /// Raw DEFLATE (COMPRESSION_ZLIB is RFC 1951 without the zlib wrapper).
    static func inflate(_ deflated: Data) throws -> Data {
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw PS3Error.invalidFile("Could not decompress.")
        }
        defer { compression_stream_destroy(stream) }
        let capacity = 1 << 20
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        var output = Data()
        var status = COMPRESSION_STATUS_OK
        deflated.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            stream.pointee.src_ptr = base
            stream.pointee.src_size = raw.count
            repeat {
                stream.pointee.dst_ptr = buffer
                stream.pointee.dst_size = capacity
                status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                output.append(buffer, count: capacity - stream.pointee.dst_size)
            } while status == COMPRESSION_STATUS_OK
        }
        guard status == COMPRESSION_STATUS_END else { throw PS3Error.invalidFile("Broken gzip data.") }
        return output
    }
}

// MARK: Checking a copy

extension DiscVerifier {
    /// A copy of a disc: a game folder or decrypted ISO on the Mac, or a game folder on the console.
    public enum Target: Sendable {
        case folder(URL)
        case iso(URL)
        case console(String)

        /// A folder with PS3_GAME/PARAM.SFO, or a .iso file.
        public static func local(_ url: URL) -> Target? {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("PS3_GAME/PARAM.SFO").path) { return .folder(url) }
            if url.pathExtension.lowercased() == "iso" { return .iso(url) }
            return nil
        }
    }

    /// The copy's PARAM.SFO.
    public static func paramSFO(of target: Target, host: String?) async throws -> ParamSFO {
        let data: Data?
        switch target {
        case .folder(let url):
            data = try? Data(contentsOf: url.appendingPathComponent("PS3_GAME/PARAM.SFO"))
        case .iso(let url):
            data = try ISOImage(url: url).readFile("PS3_GAME/PARAM.SFO")
        case .console(let path):
            guard let host else { throw PS3Error.noHost }
            data = try await TransferService(host: host).withFTP { try await $0.download(path + "/PS3_GAME/PARAM.SFO", limit: 1 << 20) }
        }
        guard let data, let sfo = ParamSFO(data: data), sfo.titleID != nil else {
            throw PS3Error.invalidFile("No PS3_GAME/PARAM.SFO found, so there is no telling which disc it is.")
        }
        return sfo
    }

    static func check(_ target: Target, host: String?, ird: IRD, progress: Progress) async throws -> Report {
        switch target {
        case .folder(let url): return try await verify(folder: url, ird: ird, progress: progress)
        case .iso(let url): return try await verify(iso: url, ird: ird, progress: progress)
        case .console(let path):
            guard let host else { throw PS3Error.noHost }
            return try await verify(consoleFolder: path, host: host, ird: ird, progress: progress)
        }
    }

    /// Checks the copy against `ird`, or against the IRDs FlexBy420's database has for the disc
    /// (those with the copy's versions first, at most three, until one matches). Changes nothing.
    public static func verify(_ target: Target, host: String?, ird: IRD? = nil,
                              events: @Sendable (String) -> Void = { _ in }, progress: Progress = { _, _, _ in }) async throws -> Report {
        if let ird { return try await check(target, host: host, ird: ird, progress: progress) }
        let sfo = try await paramSFO(of: target, host: host)
        let titleID = sfo.titleID ?? ""
        events("Looking for an IRD for \(titleID)")
        let candidates = try await IRDLibrary.candidates(titleID: titleID, gameVersion: sfo.string("VERSION"), appVersion: sfo.string("APP_VER"))
        guard !candidates.isEmpty else {
            throw PS3Error.refused("The IRD database has nothing for \(titleID). If you have an .ird file, you can give it yourself.")
        }
        var best: Report?
        for entry in candidates.prefix(3) {
            events("Downloading \(entry.title) (\(entry.gameVersion ?? "?"))")
            let ird = try await IRDLibrary.download(entry)
            let report = try await check(target, host: host, ird: ird, progress: progress)
            if report.isIntact { return report }
            if report.matched > (best?.matched ?? -1) { best = report }
        }
        guard let result = best else { throw PS3Error.refused("No IRD could be used for \(titleID).") }
        return result
    }
}
