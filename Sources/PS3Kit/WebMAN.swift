import Foundation

/// Thin client for webMAN MOD's HTTP web commands
/// (https://github.com/aldostools/webMAN-MOD/wiki/Web-Commands).
public struct WebMAN: Sendable {
    public let host: String
    public var timeout: TimeInterval

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldUsePipelining = false
        config.httpMaximumConnectionsPerHost = 1
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    public init(host: String, timeout: TimeInterval = 8) {
        self.host = host
        self.timeout = timeout
    }

    // Characters webMAN expects literally in a command path/query.
    private static let commandAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~/?&=;:$@!*,()'")
        return set.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)..<Unicode.Scalar(128)))
    }()

    // For free text inside a query (popup messages): no separators allowed through.
    private static let textAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~!*,()'")
        return set.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)..<Unicode.Scalar(128)))
    }()

    public static func encodeCommand(_ command: String) -> String {
        command.addingPercentEncoding(withAllowedCharacters: commandAllowed) ?? command
    }

    public static func encodeText(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: textAllowed) ?? text
    }

    /// Runs a raw web command such as "/refresh.ps3". `command` must already be encoded.
    @discardableResult
    public func get(encoded command: String, timeout: TimeInterval? = nil) async throws -> String {
        guard let url = URL(string: "http://\(host)\(command)") else {
            throw PS3Error.ftpProtocol("ogiltig adress: \(command)")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout ?? self.timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        // webMAN's server hangs on a reused keep-alive connection, so never reuse one.
        request.setValue("close", forHTTPHeaderField: "Connection")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch let error as URLError where [.timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .cannotFindHost].contains(error.code) {
            throw PS3Error.unreachable(host: host)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw PS3Error.http(status: http.statusCode, command: command)
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    @discardableResult
    public func get(_ command: String, timeout: TimeInterval? = nil) async throws -> String {
        try await get(encoded: Self.encodeCommand(command), timeout: timeout)
    }

    public func isReachable(timeout: TimeInterval = 3) async -> Bool {
        var probe = self
        probe.timeout = timeout
        guard let text = try? await probe.get("/cpursx_ps3") else { return false }
        return text.contains("CPU") && text.contains("RSX")
    }

    // MARK: Commands

    public func popup(_ text: String) async throws {
        try await get(encoded: "/popup.ps3?" + Self.encodeText(text))
    }

    public func refreshGames() async throws {
        try await get("/refresh.ps3", timeout: 60)
    }

    /// Installs a package already on the console. webMAN deletes the .pkg when it is done.
    public func installPackage(remotePath: String) async throws {
        try await get("/install.ps3" + remotePath, timeout: 60)
    }

    /// Runs a PS3MAPI command and returns the raw value of `"response"`.
    public func ps3mapi(_ command: String) async throws -> String {
        let text = try await get(encoded: "/ps3mapi.ps3?" + Self.encodeText(command))
        return Self.extractResponse(text)
    }

    static func extractResponse(_ json: String) -> String {
        guard let range = json.range(of: "\"response\":") else { return json }
        var value = json[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix("}") { value.removeLast() }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    // MARK: Status

    /// Requests run one after another: webMAN serves them sequentially anyway, and parallel
    /// requests each take several seconds while a game is running.
    public func snapshot() async throws -> ConsoleSnapshot {
        let sysInfoText = try await ps3mapi("PS3 GETSYSINFO")
        let statusPage = try await get("/cpursx.ps3")
        var snapshot = ConsoleSnapshot.parse(sysInfo: sysInfoText, statusPage: statusPage)
        snapshot.host = host
        snapshot.totalBytes = await diskTotal()
        snapshot.runningProcess = try? await runningProcess()
        snapshot.computeHealth()
        return snapshot
    }

    /// The disk's size never changes, so GETHDDINFO is asked once per console, not every poll.
    private static let diskTotals = DiskTotals()

    private func diskTotal() async -> Int64? {
        if let known = Self.diskTotals.get(host) { return known > 0 ? known : nil }
        let total = (try? await ps3mapi("PS3 GETHDDINFO")).flatMap { Self.parseDiskSpace($0)?.total }
        Self.diskTotals.set(host, total ?? 0)  // 0: asked, not available
        return total
    }

    /// GETHDDINFO answers "[free,total,minfree,optim]" in bytes (webMAN's ps3mapi_server.h).
    static func parseDiskSpace(_ text: String) -> (free: Int64, total: Int64)? {
        let numbers = text.trimmingCharacters(in: CharacterSet(charactersIn: "[] \"\n"))
            .split(separator: ",").map { Int64($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count >= 2, let free = numbers[0], let total = numbers[1], total > 0, free <= total else { return nil }
        return (free, total)
    }

    /// The foreground process name, or nil when only the XMB (vsh.self) is running.
    public func runningProcess() async throws -> String? {
        let pidText = try await ps3mapi("PROCESS GETCURRENTPID")
        guard let pid = Self.parseHex(pidText), pid != 0 else { return nil }
        let name = try await ps3mapi("PROCESS GETNAME 0x" + String(pid, radix: 16))
        return Self.foregroundName(fromProcessName: name)
    }

    public func isGameRunning() async throws -> Bool {
        try await runningProcess() != nil
    }

    static func parseHex(_ text: String) -> UInt64? {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
        let hex = trimmed.hasPrefix("0x") ? String(trimmed.dropFirst(2)) : trimmed
        return UInt64(hex, radix: 16)
    }

    /// "01030200_main_EBOOT.BIN" -> "EBOOT.BIN"; "01000300_main_vsh.self" -> nil.
    static func foregroundName(fromProcessName raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.lowercased().contains("vsh.self") else { return nil }
        if let range = name.range(of: "_main_") { return String(name[range.upperBound...]) }
        return name
    }
}

final class DiskTotals: @unchecked Sendable {
    private var totals: [String: Int64] = [:]
    private let lock = NSLock()

    func get(_ host: String) -> Int64? {
        lock.lock()
        defer { lock.unlock() }
        return totals[host]
    }

    func set(_ host: String, _ total: Int64) {
        lock.lock()
        defer { lock.unlock() }
        totals[host] = total
    }
}
