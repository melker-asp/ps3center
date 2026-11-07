import Foundation

/// The send queue shared by the app and `ps3 queue`, in
/// ~/Library/Application Support/ps3center/queue.json. One game (or file) per item; items are
/// sent one at a time, since webMAN's FTP does one transfer well, and each file goes through
/// `TransferService.send` (.part files, resuming where it stopped).
public struct TransferQueue: Codable, Equatable, Sendable {
    public enum WhenDone: String, Codable, Sendable, CaseIterable {
        case nothing, popup, shutdown

        public var label: String {
            switch self {
            case .nothing: return "Nothing"
            case .popup: return "Popup on TV"
            case .shutdown: return "Shut Down PS3"
            }
        }
    }

    public struct File: Codable, Equatable, Sendable {
        public var local: String
        public var remote: String
        public var kind: ContentKind
        public var size: Int64

        public var route: Route {
            Route(local: URL(fileURLWithPath: local), remote: remote, kind: kind, size: size, title: nil)
        }
    }

    public struct Item: Codable, Equatable, Identifiable, Sendable {
        public enum State: String, Codable, Sendable {
            case waiting, sending, paused, done, failed
        }

        public var id: UUID
        public var title: String
        public var files: [File]
        public var state: State
        /// Bytes of the item on the console, as far as is known.
        public var sent: Int64
        public var message: String?
        public var addedAt: Date
        public var finishedAt: Date?

        public var total: Int64 { files.reduce(0) { $0 + $1.size } }
        public var fraction: Double { total > 0 ? min(1, Double(sent) / Double(total)) : 0 }
        public var isOpen: Bool { state != .done }

        public var routes: [Route] {
            files.map { Route(local: URL(fileURLWithPath: $0.local), remote: $0.remote, kind: $0.kind, size: $0.size, title: title) }
        }
    }

    public var items: [Item] = []
    public var whenDone: WhenDone = .popup
    /// Compare MD5 on the console with the Mac's after each large file.
    public var verify = false

    public init() {}

    /// Items still to send, in order. An item left as "sending" by a run that stopped counts too.
    public var pending: [Item] { items.filter { $0.state == .waiting || $0.state == .paused || $0.state == .sending } }

    public var remainingBytes: Int64 { pending.reduce(0) { $0 + max(0, $1.total - $1.sent) } }

    /// Adds one item per game: routes with the same title belong together.
    @discardableResult
    public mutating func add(_ routes: [Route]) -> [Item] {
        var groups: [(title: String, routes: [Route])] = []
        for route in routes {
            let title = route.title ?? GameName.clean(route.local.lastPathComponent)
            if let index = groups.firstIndex(where: { $0.title == title }) {
                groups[index].routes.append(route)
            } else {
                groups.append((title, [route]))
            }
        }
        let added = groups.compactMap { group -> Item? in
            let files = group.routes.map { File(local: $0.local.path, remote: $0.remote, kind: $0.kind, size: $0.size) }
            // The same files already waiting are not queued twice.
            guard !items.contains(where: { $0.isOpen && $0.files == files }) else { return nil }
            return Item(id: UUID(), title: group.title, files: files, state: .waiting, sent: 0, message: nil,
                        addedAt: Date(), finishedAt: nil)
        }
        items += added
        return added
    }

    public mutating func update(_ id: UUID, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    public mutating func removeFinished() {
        items.removeAll { $0.state == .done }
    }

    // MARK: Storage

    public static var file: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ps3center/queue.json")
    }

    public static func load(from file: URL = TransferQueue.file) -> TransferQueue {
        guard let data = try? Data(contentsOf: file) else { return TransferQueue() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(TransferQueue.self, from: data)) ?? TransferQueue()
    }

    /// The only way to change the queue: reads the file, applies `change` and writes it back under
    /// a short lock, so what the app and `ps3 queue` do at the same time is all kept. (`QueueLock`
    /// is another lock, held by whichever process sends.) If `change` throws, nothing is written.
    @discardableResult
    public static func edit<T>(at file: URL = TransferQueue.file, _ change: (inout TransferQueue) throws -> T) rethrows -> T {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(file.path + ".lock", O_CREAT | O_RDWR, 0o644)
        if fd >= 0 { flock(fd, LOCK_EX) }
        defer {
            if fd >= 0 {
                flock(fd, LOCK_UN)
                close(fd)
            }
        }
        var queue = load(from: file)
        let result = try change(&queue)
        queue.save(to: file)
        return result
    }

    private func save(to file: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(self).write(to: file, options: .atomic)
    }
}

/// Only one process sends from the queue at a time (the app or `ps3 queue start`): an flock on
/// queue.lock, released when the holder ends, even if it crashes.
public final class QueueLock: @unchecked Sendable {
    private let descriptor: Int32

    /// Nil when another process holds the lock.
    public init?() {
        let path = TransferQueue.file.deletingLastPathComponent().appendingPathComponent("queue.lock").path
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let fd = open(path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return nil
        }
        descriptor = fd
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    /// Whether a process is sending the queue right now (the app or `ps3 queue start`), without
    /// keeping the lock: it is only asked for, shared, and let go at once.
    public static var isHeld: Bool {
        let path = TransferQueue.file.deletingLastPathComponent().appendingPathComponent("queue.lock").path
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return false }  // no lock file: nothing has sent yet
        defer { close(fd) }
        guard flock(fd, LOCK_SH | LOCK_NB) == 0 else { return true }
        flock(fd, LOCK_UN)
        return false
    }
}

/// Runs queue items against the console; the app and `ps3 queue start` drive it.
public struct QueueRunner: Sendable {
    public let host: String

    public init(host: String) { self.host = host }

    /// Sends one item, trying again after network failures (`RetryPolicy`). The game list is
    /// refreshed once, by `finish`, not after every item.
    public func send(_ item: TransferQueue.Item, verify: Bool, events: @escaping TransferHandler) async throws {
        var options = TransferOptions()
        options.refresh = false
        options.popup = false
        options.verify = verify
        let memory = SentMemory()
        let watched: TransferHandler = { event in
            events(event)
            switch event {
            case .progress(let route, let sent, _, _):
                memory.note(route.remote, sent)
            case .started(let route, let offset) where offset == 0 && memory.bytes(route.remote) > 0:
                // webMAN removes a partial file when the data connection breaks with an error.
                events(.note("The PS3 deleted the half-sent file when the connection broke, so \(route.local.lastPathComponent) starts over from the beginning."))
            default:
                break
            }
        }
        let service = TransferService(host: host)
        try await RetryPolicy.run(events: events) {
            try await service.send(item.routes, options: options, events: watched)
        }
    }

    /// After the queue: refreshes the game list when games arrived (once no game runs), then
    /// shows a popup or shuts the console down, as chosen. Never shuts down during a game.
    public func finish(sent titles: [String], refresh: Bool, whenDone: TransferQueue.WhenDone, events: TransferHandler) async throws {
        guard !titles.isEmpty else { return }
        let webman = WebMAN(host: host)
        let transfer = TransferService(host: host)
        if refresh || whenDone == .shutdown {
            try await transfer.waitUntilIdle(force: false, events: events)
        }
        if refresh {
            try await webman.refreshGames()
            events(.refreshed)
        }
        let summary = titles.count == 1 ? "\(titles[0]) was sent from the Mac" : "\(titles.count) games were sent from the Mac"
        switch whenDone {
        case .nothing:
            break
        case .popup:
            try? await webman.popup(summary)
        case .shutdown:
            try? await webman.popup(summary + ". The PS3 is shutting down.")
            try await Task.sleep(nanoseconds: 5_000_000_000)
            try await webman.shutdown()
            events(.note("The PS3 is shutting down"))
        }
    }
}

extension WebMAN {
    /// Turns the console off. It may not answer, since it is going away.
    public func shutdown() async throws {
        OperationLog.record("shutdown", host)
        do { try await get("/shutdown.ps3", timeout: 10) } catch PS3Error.unreachable {}
    }

    /// Restarts the console. On HEN, HEN has to be enabled again afterwards.
    public func restart() async throws {
        OperationLog.record("restart", host)
        do { try await get("/restart.ps3", timeout: 10) } catch PS3Error.unreachable {}
    }
}
