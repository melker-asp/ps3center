import Foundation
import Network

/// Minimal passive-mode FTP client for webMAN's FTP server.
/// webMAN handles one transfer at a time well, so this client is strictly sequential.
public final class FTPClient {
    public struct Entry: Equatable, Sendable {
        public let name: String
        public let size: Int64
        public let isDirectory: Bool
    }

    struct Reply {
        let code: Int
        let text: String
    }

    public let host: String
    public let port: UInt16
    private var control: LineConnection?

    public init(host: String, port: UInt16 = 21) {
        self.host = host
        self.port = port
    }

    deinit { control?.cancel() }

    static let debugEnabled = ProcessInfo.processInfo.environment["PS3_DEBUG"] == "1"

    static func debug(_ text: @autoclosure () -> String) {
        guard debugEnabled else { return }
        FileHandle.standardError.write(Data(("[ftp] " + text() + "\n").utf8))
    }

    public func connect() async throws {
        let connection = LineConnection(host: host, port: port)
        do {
            try await connection.start(timeout: 6)
        } catch {
            throw PS3Error.unreachable(host: host)
        }
        control = connection
        _ = try await readReply(expect: [220])
        let user = try await command("USER anonymous")
        if user.code == 331 {
            _ = try await command("PASS ps3center@", expect: [230, 202])
        } else if user.code != 230 {
            throw PS3Error.ftp(code: user.code, message: user.text)
        }
        _ = try await command("TYPE I", expect: [200])
    }

    public func close() async {
        if control != nil { _ = try? await command("QUIT") }
        control?.cancel()
        control = nil
    }

    // MARK: Control channel

    @discardableResult
    func command(_ line: String, expect codes: Set<Int>? = nil, timeout: TimeInterval = 20) async throws -> Reply {
        guard let control else { throw PS3Error.ftpProtocol("inte ansluten") }
        Self.debug("> \(line)")
        try await control.send(Data((line + "\r\n").utf8))
        let reply = try await readReply(expect: nil, timeout: timeout)
        Self.debug("< \(reply.code) \(reply.text)")
        if let codes, !codes.contains(reply.code) { throw PS3Error.ftp(code: reply.code, message: reply.text) }
        return reply
    }

    func readReply(expect codes: Set<Int>? = nil, timeout: TimeInterval = 20) async throws -> Reply {
        guard let control else { throw PS3Error.ftpProtocol("inte ansluten") }
        let first = try await control.readLine(timeout: timeout)
        guard first.count >= 3, let code = Int(first.prefix(3)) else {
            throw PS3Error.ftpProtocol(first)
        }
        var text = String(first.dropFirst(4))
        if first.count > 3, first[first.index(first.startIndex, offsetBy: 3)] == "-" {
            // Multi-line reply: runs until "<code> ".
            while true {
                let line = try await control.readLine(timeout: timeout)
                text += "\n" + line
                if line.hasPrefix("\(code) ") { break }
            }
        }
        let reply = Reply(code: code, text: text)
        if let codes, !codes.contains(code) {
            throw PS3Error.ftp(code: code, message: text)
        }
        return reply
    }

    private func openDataConnection() async throws -> LineConnection {
        let reply = try await command("PASV", expect: [227])
        guard let numbers = ConsoleSnapshot.firstMatch(#"(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)"#, in: reply.text),
              let p1 = UInt16(numbers[5]), let p2 = UInt16(numbers[6])
        else { throw PS3Error.ftpProtocol(reply.text) }
        // Always connect to the control host; the address in the reply is not needed.
        let data = LineConnection(host: host, port: p1 * 256 + p2)
        try await data.start(timeout: 6)
        return data
    }

    // MARK: Operations

    /// Size of a remote file, or nil if it does not exist.
    public func size(_ path: String) async throws -> Int64? {
        let reply = try await command("SIZE \(path)")
        switch reply.code {
        case 213: return Int64(reply.text.trimmingCharacters(in: .whitespaces))
        case 550: return nil
        default: throw PS3Error.ftp(code: reply.code, message: reply.text)
        }
    }

    /// Raw MDTM timestamp ("20250605222033"), or nil if the file does not exist.
    public func modificationTime(_ path: String) async throws -> String? {
        let reply = try await command("MDTM \(path)")
        switch reply.code {
        case 213: return reply.text.trimmingCharacters(in: .whitespaces)
        case 550: return nil
        default: throw PS3Error.ftp(code: reply.code, message: reply.text)
        }
    }

    public func list(_ path: String) async throws -> [Entry] {
        let data = try await openDataConnection()
        defer { data.cancel() }
        let reply = try await command("LIST \(path)")
        if reply.code == 550 { return [] }
        guard [125, 150].contains(reply.code) else { throw PS3Error.ftp(code: reply.code, message: reply.text) }
        let raw = try await data.readToEnd(timeout: 30)
        _ = try await readReply(expect: [226, 250])
        let text = String(decoding: raw, as: UTF8.self)
        return text.split(whereSeparator: \.isNewline).compactMap { Self.parseListLine(String($0)) }
            .filter { $0.name != "." && $0.name != ".." }
    }

    static func parseListLine(_ line: String) -> Entry? {
        guard let m = ConsoleSnapshot.firstMatch(#"^([\-dl])\S*\s+\d+\s+\S+\s+\S+\s+(\d+)\s+\w{3}\s+\d+\s+[\d:]+\s(.+)$"#, in: line)
        else { return nil }
        return Entry(name: m[3], size: Int64(m[2]) ?? 0, isDirectory: m[1] == "d")
    }

    public func download(_ path: String, limit: Int = 64 << 20) async throws -> Data? {
        let data = try await openDataConnection()
        defer { data.cancel() }
        let reply = try await command("RETR \(path)")
        if reply.code == 550 { return nil }
        guard [125, 150].contains(reply.code) else { throw PS3Error.ftp(code: reply.code, message: reply.text) }
        let raw = try await data.readToEnd(timeout: 60, limit: limit)
        _ = try await readReply(expect: [226, 250])
        return raw
    }

    public func makeDirectories(_ path: String) async throws {
        var current = ""
        for component in path.split(separator: "/") {
            current += "/" + component
            if current == "/dev_hdd0" || current == "/dev_usb000" { continue }
            _ = try await command("MKD \(current)")  // 550/521 when it already exists
        }
    }

    public func delete(_ path: String) async throws {
        _ = try await command("DELE \(path)", expect: [250])
    }

    /// Uploads `file`. With `offset > 0` the rest of the file is appended (APPE),
    /// which is how webMAN resumes an interrupted upload.
    public func upload(file: URL, to remotePath: String, offset: Int64 = 0,
                       progress: (Int64) -> Void) async throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))

        let data = try await openDataConnection()
        defer { data.cancel() }
        let verb = offset > 0 ? "APPE" : "STOR"
        _ = try await command("\(verb) \(remotePath)", expect: [125, 150])

        var sent = offset
        progress(sent)
        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty else { break }
            try await data.send(chunk)
            sent += Int64(chunk.count)
            progress(sent)
        }
        try await data.finish()
        data.cancel()
        _ = try await readReply(expect: [226, 250], timeout: 300)
    }
}

/// Set from the connection queue when a receive times out.
private final class TimeoutFlag: @unchecked Sendable {
    var value = false
}

/// NWConnection wrapped in async/await, with line reading for the control channel.
final class LineConnection {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "ps3center.ftp")
    private var buffer = Data()

    init(host: String, port: UInt16) {
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    }

    func start(timeout: TimeInterval) async throws {
        let queue = self.queue
        let connection = self.connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Every caller runs on `queue`, so the flag needs no lock.
            let state = TimeoutFlag()
            @Sendable func finish(_ error: Error?) {
                guard !state.value else { return }
                state.value = true
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(nil)
                case .failed(let error), .waiting(let error): finish(error)
                case .cancelled: finish(PS3Error.ftpProtocol("anslutningen stängdes"))
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                if !state.value { connection.cancel(); finish(PS3Error.timeout("anslutning")) }
            }
        }
    }

    func cancel() { connection.cancel() }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    /// Sends FIN so the server sees the end of an upload.
    func finish() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    /// Next chunk, `Data()` if nothing yet, nil at end of stream.
    private func receive(timeout: TimeInterval) async throws -> Data? {
        let queue = self.queue
        let connection = self.connection
        let fired = TimeoutFlag()
        let watchdog = DispatchWorkItem { fired.value = true; connection.cancel() }
        queue.asyncAfter(deadline: .now() + timeout, execute: watchdog)
        defer { watchdog.cancel() }
        do {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, isComplete, error in
                    if let data, !data.isEmpty { continuation.resume(returning: data) }
                    // webMAN closing a data connection surfaces as ENODATA rather than isComplete.
                    else if case .posix(.ENODATA)? = error { continuation.resume(returning: nil) }
                    else if let error { continuation.resume(throwing: error) }
                    else if isComplete { continuation.resume(returning: nil) }
                    else { continuation.resume(returning: Data()) }
                }
            }
        } catch {
            if fired.value { throw PS3Error.timeout("väntar på svar från PS3:an") }
            throw error
        }
    }

    func readLine(timeout: TimeInterval) async throws -> String {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                var lineData = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if lineData.last == 0x0D { lineData = lineData.dropLast() }
                return String(decoding: lineData, as: UTF8.self)
            }
            guard let chunk = try await receive(timeout: timeout) else {
                throw PS3Error.ftpProtocol("anslutningen stängdes")
            }
            buffer.append(chunk)
        }
    }

    func readToEnd(timeout: TimeInterval, limit: Int = .max) async throws -> Data {
        var result = buffer
        buffer.removeAll()
        while let chunk = try await receive(timeout: timeout) {
            result.append(chunk)
            if result.count > limit { throw PS3Error.ftpProtocol("filen är större än väntat") }
        }
        return result
    }
}
