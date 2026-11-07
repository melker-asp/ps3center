import Foundation
import os

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

        package init(local: String, remote: String, kind: ContentKind, size: Int64) {
            self.local = local
            self.remote = remote
            self.kind = kind
            self.size = size
        }

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

        package init(id: UUID, title: String, files: [File], state: State, sent: Int64, message: String?,
                     addedAt: Date, finishedAt: Date?) {
            self.id = id
            self.title = title
            self.files = files
            self.state = state
            self.sent = sent
            self.message = message
            self.addedAt = addedAt
            self.finishedAt = finishedAt
        }

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

    /// Routes grouped by game, in the order first seen: routes with the same title (a .cue and
    /// its .bin, an ISO and its .SFO) belong together. One queue item, or one row in the review.
    public static func games(in routes: [Route]) -> [(title: String, routes: [Route])] {
        var groups: [(title: String, routes: [Route])] = []
        for route in routes {
            let title = route.title ?? GameName.clean(route.local.lastPathComponent)
            if let index = groups.firstIndex(where: { $0.title == title }) {
                groups[index].routes.append(route)
            } else {
                groups.append((title, [route]))
            }
        }
        return groups
    }

    /// Adds one item per game (`games(in:)`).
    @discardableResult
    public mutating func add(_ routes: [Route]) -> [Item] {
        let added = Self.games(in: routes).compactMap { group -> Item? in
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

    public static var file: URL { StatePaths.support.appendingPathComponent("queue.json") }

    static func store(_ file: URL) -> JSONFile<TransferQueue> { JSONFile(file, empty: TransferQueue()) }

    public static func load(from file: URL = TransferQueue.file) -> TransferQueue {
        store(file).load()
    }

    /// The only way to change the queue: reads the file, applies `change` and writes it back under
    /// a short lock, so what the app and `ps3 queue` do at the same time is all kept. (`QueueLock`
    /// is another lock, held by whichever process sends.) If `change` throws, nothing is written;
    /// if the file cannot be written, this throws.
    @discardableResult
    public static func edit<T>(at file: URL = TransferQueue.file, _ change: (inout TransferQueue) throws -> T) throws -> T {
        try store(file).edit(change)
    }
}

/// Only one process sends from the queue at a time (the app or `ps3 queue start`): an flock on
/// queue.lock, released when the holder ends, even if it crashes.
public final class QueueLock: Sendable {
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

/// What `QueueRunner.run` reports while it works through the queue.
public enum QueueRunEvent: Sendable {
    /// An item starts sending.
    case started(TransferQueue.Item)
    /// Everything the item's transfer reports (progress, notes, retries), for printing.
    case transfer(UUID, TransferEvent)
    /// How many of the item's bytes are on the console now.
    case sent(UUID, Int64)
    case done(TransferQueue.Item)
    case failed(TransferQueue.Item, Error)
    /// Stopped by a pause (or the Mac going to sleep); the next run continues the file.
    case paused(TransferQueue.Item)
    /// queue.json could not be written. The run goes on, and each item is still tried only once.
    case notSaved(Error)
}

/// What one run of the queue sent; `QueueRunner.finish` takes it.
public struct QueueRunResult: Sendable {
    public var sent: [String] = []
    public var failed = 0
    /// Something that shows in the game list arrived, so it should be refreshed.
    public var refresh = false
    /// Stopped by a pause; `finish` is not for a run that was stopped.
    public var cancelled = false
    public var whenDone: TransferQueue.WhenDone = .popup
}

/// Runs queue items against the console; the app and `ps3 queue start` drive it.
public struct QueueRunner: Sendable {
    public let host: String

    public init(host: String) { self.host = host }

    /// Sends what waits in the queue, one item at a time. The app and `ps3 queue start` both use
    /// this, so the rules are the same in both:
    /// - queue.json is read again before each item, since the app and `ps3 queue add` change it;
    /// - each item is tried once per run, even when queue.json cannot be written;
    /// - progress is saved every few seconds and on failure or pause, so a crash loses little and
    ///   the next run continues the console's .part file;
    /// - a cancelled task (pause, the Mac going to sleep) marks the item paused and stops.
    /// Call `finish` with the result afterwards unless it was cancelled.
    public func run(file: URL = TransferQueue.file, events: @escaping @Sendable (QueueRunEvent) -> Void) async -> QueueRunResult {
        await run(file: file, events: events) { item, verify, handler in
            try await send(item, verify: verify, events: handler)
        }
    }

    /// `run` with the sending replaced, for the tests.
    func run(file: URL, events: @escaping @Sendable (QueueRunEvent) -> Void,
             sender: (TransferQueue.Item, Bool, @escaping TransferHandler) async throws -> Void) async -> QueueRunResult {
        var result = QueueRunResult()
        var tried = Set<UUID>()
        @Sendable func save(_ change: (inout TransferQueue) -> Void) {
            do { try TransferQueue.edit(at: file, change) } catch { events(.notSaved(error)) }
        }
        while !Task.isCancelled {
            let queue = TransferQueue.load(from: file)
            result.whenDone = queue.whenDone
            guard let item = queue.pending.first(where: { !tried.contains($0.id) }) else { break }
            tried.insert(item.id)
            save {
                $0.update(item.id) {
                    $0.state = .sending
                    $0.message = nil
                }
            }
            events(.started(item))
            let progress = Progress(item: item)
            do {
                try await sender(item, queue.verify) { event in
                    events(.transfer(item.id, event))
                    guard let sent = progress.note(event) else { return }
                    events(.sent(item.id, sent))
                    if progress.isDueForSave() { save { $0.update(item.id) { $0.sent = sent } } }
                }
                save {
                    $0.update(item.id) {
                        $0.state = .done
                        $0.sent = $0.total
                        $0.finishedAt = Date()
                        $0.message = nil
                    }
                }
                result.sent.append(item.title)
                result.refresh = result.refresh || item.routes.contains(where: \.refreshesGameList)
                events(.done(item))
            } catch {
                let sent = progress.sent
                if Task.isCancelled || error is CancellationError {
                    save {
                        $0.update(item.id) {
                            $0.state = .paused
                            $0.sent = sent
                        }
                    }
                    result.cancelled = true
                    events(.paused(item))
                    break
                }
                save {
                    $0.update(item.id) {
                        $0.state = .failed
                        $0.message = error.localizedDescription
                        $0.sent = sent
                    }
                }
                result.failed += 1
                events(.failed(item, error))
            }
        }
        if Task.isCancelled { result.cancelled = true }
        return result
    }

    /// Bytes of an item on the console while it is sent, from its transfer's events.
    final class Progress: Sendable {
        private struct State {
            var sent: Int64
            var lastSave = Date()
        }
        private let item: TransferQueue.Item
        private let state: OSAllocatedUnfairLock<State>

        init(item: TransferQueue.Item) {
            self.item = item
            state = OSAllocatedUnfairLock(initialState: State(sent: item.sent))
        }

        var sent: Int64 { state.withLock { $0.sent } }

        /// The new total when `event` moved it, else nil.
        func note(_ event: TransferEvent) -> Int64? {
            let total: Int64
            switch event {
            case .progress(let route, let sent, _, _): total = Self.sentBefore(route, in: item) + sent
            case .finished(let route, _), .skipped(let route, _): total = Self.sentBefore(route, in: item) + route.size
            default: return nil
            }
            state.withLock { $0.sent = total }
            return total
        }

        /// True every five seconds, for saving progress now and then.
        func isDueForSave(now: Date = Date()) -> Bool {
            state.withLock { state in
                guard now.timeIntervalSince(state.lastSave) > 5 else { return false }
                state.lastSave = now
                return true
            }
        }

        /// Bytes of the item's files before `route`, which are already on the console.
        static func sentBefore(_ route: Route, in item: TransferQueue.Item) -> Int64 {
            guard let index = item.files.firstIndex(where: { $0.remote == route.remote }) else { return 0 }
            return item.files[..<index].reduce(0) { $0 + $1.size }
        }
    }

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
    public func finish(_ result: QueueRunResult, events: TransferHandler) async throws {
        try await finish(sent: result.sent, refresh: result.refresh, whenDone: result.whenDone, events: events)
    }

    public func finish(sent titles: [String], refresh: Bool, whenDone: TransferQueue.WhenDone, events: TransferHandler) async throws {
        guard !titles.isEmpty else { return }
        let webman = WebMAN(host: host)
        let transfer = TransferService(host: host)
        if refresh {
            try await transfer.refreshGameList(whenGameRuns: .wait, events: events)
        } else if whenDone == .shutdown {
            try await transfer.waitUntilIdle(force: false, events: events)
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
        OperationLog.record(.shutdown, host)
        do { try await get("/shutdown.ps3", timeout: 10) } catch PS3Error.unreachable {}
    }

    /// Restarts the console. On HEN, HEN has to be enabled again afterwards.
    public func restart() async throws {
        OperationLog.record(.restart, host)
        do { try await get("/restart.ps3", timeout: 10) } catch PS3Error.unreachable {}
    }
}
