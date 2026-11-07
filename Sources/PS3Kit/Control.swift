import Darwin
import Foundation
import Network

// MARK: Virtual pad

/// A button on webMAN's virtual pad (`/pad.ps3?<button>`, include/feat/vpad.h). Only these fixed
/// names are ever sent: webMAN reads "cross=" or "circle=" as "change the enter button" and
/// restarts the console, so no free text goes to /pad.ps3.
public enum PadButton: String, CaseIterable, Sendable {
    case up, down, left, right
    /// The console's own enter and back buttons: ✕ and ◯, swapped on Asian consoles.
    case accept, cancel
    case cross, circle, square, triangle
    case start, select
    case ps = "psbtn"
    case l1, l2, r1, r2, l3, r3

    public var label: String {
        switch self {
        case .up: return "↑"
        case .down: return "↓"
        case .left: return "←"
        case .right: return "→"
        case .accept: return "OK"
        case .cancel: return "Tillbaka"
        case .cross: return "✕"
        case .circle: return "◯"
        case .square: return "□"
        case .triangle: return "△"
        case .start: return "START"
        case .select: return "SELECT"
        case .ps: return "PS"
        default: return rawValue.uppercased()
        }
    }

    /// A name as typed in the CLI, in English or Swedish ("ner", "x", "ok", "tillbaka").
    public init?(name: String) {
        let aliases: [String: PadButton] = [
            "upp": .up, "ner": .down, "ned": .down, "vänster": .left, "höger": .right,
            "x": .cross, "kryss": .cross, "o": .circle, "cirkel": .circle, "fyrkant": .square, "triangel": .triangle,
            "ok": .accept, "enter": .accept, "tillbaka": .cancel, "back": .cancel, "ps": .ps, "psbtn": .ps,
        ]
        let key = name.lowercased()
        guard let button = aliases[key] ?? PadButton(rawValue: key) else { return nil }
        self = button
    }
}

extension WebMAN {
    /// Presses go on a connection of their own, so they never wait behind the status polls.
    static let padSession = makeSession()

    /// Presses and releases one button, as on a controller. Not logged: nothing on the console is
    /// stored by it, and a log line per press would bury the rest.
    public func press(_ button: PadButton) async throws {
        _ = try await fetch(encoded: Self.encodeCommand("/pad.ps3?" + button.rawValue), timeout: 5, session: Self.padSession)
    }

    /// Disconnects the virtual pad, so it does not stay connected as a second controller.
    public func padOff() async throws {
        _ = try await fetch(encoded: Self.encodeCommand("/pad.ps3?off"), timeout: 5, session: Self.padSession)
    }

    public func ejectDisc() async throws {
        OperationLog.record("eject", host)
        try await get("/eject.ps3")
    }

    public func insertDisc() async throws {
        OperationLog.record("insert", host)
        try await get("/insert.ps3")
    }

    /// What the TV shows, as an image (`/xmb.ps3$screenshot?show`; `fast` is smaller). webMAN
    /// answers with the picture, or with a page that shows it; both are handled.
    public func screenshot(fast: Bool = true) async throws -> Data {
        let answer = try await data(encoded: "/xmb.ps3$screenshot?show" + (fast ? "?fast" : ""), timeout: 20)
        if ImageKind(answer) != nil { return answer }
        let page = String(decoding: answer, as: UTF8.self)
        if let source = Self.imageSource(in: page) {
            let image = try await data(encoded: Self.encodeCommand(source), timeout: 20)
            if ImageKind(image) != nil { return image }
        }
        throw PS3Error.invalidFile("webMAN gav ingen skärmbild. Den går bara att ta i XMB:n, inte under ett spel.")
    }

    /// The first `<img src="/…">` on a page from the console itself.
    static func imageSource(in page: String) -> String? {
        guard let match = ConsoleSnapshot.firstMatch(#"<img[^>]*src=["']?(/[^"' >]+)"#, in: page) else { return nil }
        return match[1].removingPercentEncoding ?? match[1]
    }
}

/// The picture formats webMAN's screenshot can come as.
public enum ImageKind: String, Sendable {
    case bmp, jpeg, png

    public init?(_ data: Data) {
        let head = [UInt8](data.prefix(4))
        if head.starts(with: [0x42, 0x4D]) { self = .bmp }
        else if head.starts(with: [0xFF, 0xD8]) { self = .jpeg }
        else if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { self = .png }
        else { return nil }
    }

    public var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
}

// MARK: Fan

/// Changing webMAN's dynamic fan target (`/cpursx.ps3?max=<°C>`, include/cpursx.h). Only in the
/// dynamic mode, which keeps the console at or under the target by speeding the fan up, and
/// only within 60–75 °C. A fixed low speed is never set: it can let the console overheat.
public enum FanControl {
    public static let targets = 60...75

    /// Why the target cannot be set to `celsius` now, or nil when it can.
    public static func refusal(target celsius: Int, snapshot: ConsoleSnapshot) -> String? {
        guard snapshot.fanTargetMax != nil else {
            return "webMAN styr inte fläkten med ett mål just nu (SYSCON, AUTO eller fast hastighet). PS3 Center ändrar bara målet i det dynamiska läget; läget väljs i webMAN:s inställningar."
        }
        guard targets.contains(celsius) else {
            return "Målet måste vara mellan \(targets.lowerBound) och \(targets.upperBound) °C."
        }
        return nil
    }
}

extension WebMAN {
    /// Sets the dynamic fan target after checking the current mode. Logged.
    public func setFanTarget(_ celsius: Int) async throws {
        let current = try await snapshot()
        if let refusal = FanControl.refusal(target: celsius, snapshot: current) { throw PS3Error.refused(refusal) }
        OperationLog.record("fan", "\(host) max \(celsius) °C (förut \(current.fanTargetMax ?? 0) °C)")
        // The answer is the status page, which shows PSID/IDPS: it is not kept.
        _ = try await get("/cpursx.ps3?max=\(celsius)")
    }
}

// MARK: Reachability

/// Whether the console is off, or on with HEN not enabled (webMAN does not run until it is).
public enum Reachability {
    public enum State: Equatable, Sendable {
        case webMAN
        /// The console answers on the network, but webMAN does not.
        case henOff
        case unreachable
    }

    public static func henOffAdvice(host: String) -> String {
        "PS3:an på \(host) är på, men webMAN svarar inte: HEN är inte aktiverat. Aktivera HEN på PS3:an (\u{201D}Enable HEN\u{201D} under Spel) så ansluter PS3 Center av sig själv."
    }

    public static func probe(_ host: String, timeout: TimeInterval = 2) async -> State {
        if await WebMAN(host: host).isReachable(timeout: timeout + 1) { return .webMAN }
        if await ping(host, timeout: timeout) { return .henOff }
        if await answersTCP(host, port: 80, timeout: timeout) { return .henOff }
        return .unreachable
    }

    /// One ICMP echo over an unprivileged datagram socket, as macOS allows without root.
    public static func ping(_ host: String, timeout: TimeInterval) async -> Bool {
        await Task.detached { Self.echo(host, timeout: timeout) }.value
    }

    static func echo(_ host: String, timeout: TimeInterval) -> Bool {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return false }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var wait = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - timeout.rounded(.down)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))

        let identifier = UInt16.random(in: 1...UInt16.max)
        var packet: [UInt8] = [8, 0, 0, 0, UInt8(identifier >> 8), UInt8(identifier & 0xFF), 0, 1] + Array("ps3center".utf8)
        let sum = checksum(packet)
        packet[2] = UInt8(sum >> 8)
        packet[3] = UInt8(sum & 0xFF)
        let sent = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(fd, packet, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent == packet.count else { return false }

        let deadline = Date().addingTimeInterval(timeout)
        let capacity = 1024
        var buffer = [UInt8](repeating: 0, count: capacity)
        while Date() < deadline {
            var from = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &from) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buffer, capacity, 0, $0, &length) }
            }
            guard count > 0 else { return false }
            guard from.sin_addr.s_addr == address.sin_addr.s_addr else { continue }
            // macOS hands over the IP header too.
            let start = buffer[0] >> 4 == 4 ? Int(buffer[0] & 0x0F) * 4 : 0
            if count >= start + 8, buffer[start] == 0 { return true }  // echo reply
        }
        return false
    }

    static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            sum += UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count { sum += UInt32(bytes[index]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        return ~UInt16(sum)
    }

    /// True when the host answers a TCP connection at all: accepted, or refused with a reset
    /// (only a running host refuses). A console that is off gives no answer.
    public static func answersTCP(_ host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let once = Once()
        return await withCheckedContinuation { continuation in
            @Sendable func finish(_ answer: Bool) {
                guard once.claim() else { return }
                connection.cancel()
                continuation.resume(returning: answer)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .waiting(let error), .failed(let error):
                    if case .posix(let code) = error, code == .ECONNREFUSED { finish(true) } else if case .failed = state { finish(false) }
                default: break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }

    final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }
}

// MARK: Play time

/// Time played per game, from what is mounted while a game runs. Kept on the Mac in
/// `~/Library/Application Support/ps3center/playtime.json`; read by the app and `ps3 games info`.
public struct PlayLog: Codable, Equatable, Sendable {
    public struct Record: Codable, Equatable, Sendable {
        public var title: String
        public var seconds: TimeInterval
        public var sessions: Int
        public var lastPlayed: Date
    }

    /// Keyed on the mounted path as webMAN shows it ("/dev_hdd0/PS3ISO/Game.iso", "/net0/PS3ISO/…").
    public var games: [String: Record] = [:]

    public init() {}

    public static var file: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ps3center/playtime.json")
    }

    public static func load() -> PlayLog {
        guard let data = try? Data(contentsOf: file) else { return PlayLog() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(PlayLog.self, from: data)) ?? PlayLog()
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.file, options: .atomic)
    }

    /// A game's record, on the console or (played through the game server) on the Mac.
    public func record(for game: Game) -> Record? {
        if let record = games[game.path] { return record }
        if let netPath = game.netPath { return games["/net0" + netPath] }
        return nil
    }
}

/// Turns the status polls into play time: while a game runs, the time since the previous poll
/// counts, at most twice the poll interval, so a Mac that slept does not add hours.
public struct PlayTracker: Sendable {
    public let interval: TimeInterval
    private var current: String?
    private var lastSeen: Date?

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    /// Adds to `log` and returns true when it changed.
    public mutating func observe(_ snapshot: ConsoleSnapshot?, at now: Date = Date(), log: inout PlayLog) -> Bool {
        guard let snapshot, snapshot.isGameRunning, let path = snapshot.mountedGamePath else {
            current = nil
            lastSeen = nil
            return false
        }
        let title = snapshot.mountedGameName ?? GameName.clean((path as NSString).lastPathComponent)
        var record = log.games[path] ?? PlayLog.Record(title: title, seconds: 0, sessions: 0, lastPlayed: now)
        if current != path {
            record.sessions += 1
        } else if let lastSeen {
            record.seconds += min(now.timeIntervalSince(lastSeen), interval * 2)
        }
        record.title = title
        record.lastPlayed = now
        log.games[path] = record
        current = path
        lastSeen = now
        return true
    }
}
