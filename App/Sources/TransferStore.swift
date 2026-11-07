import AppKit
import Foundation
import Observation
import PS3Kit
import PS3KitFixtures

/// The send queue in the app: the same queue.json as `ps3 queue`, sent one game at a time.
/// Keeps the Mac awake while it runs, stops cleanly (the console keeps the .part file) when
/// paused or when the Mac is about to sleep, and carries on after it wakes.
@MainActor
@Observable
final class TransferStore {
    private(set) var queue = TransferQueue.load()
    private(set) var isRunning = false
    /// The item being sent.
    private(set) var current: UUID?
    /// Bytes per second of the file being sent.
    private(set) var rate: Double = 0
    private(set) var lastSpeed: SpeedResult? = SpeedTest.last()
    private(set) var isMeasuring = false
    /// What the speed test is doing ("Skickar 45 % · 3,2 MB/s"), or why it failed.
    private(set) var measureStep: String?
    private(set) var measureError: String?
    /// What the queue is waiting for, or the last problem.
    private(set) var note: String?
    /// Paused because the Mac went to sleep; started again when it wakes.
    private(set) var pausedForSleep = false
    var host: String? {
        didSet {
            // Games from a watched folder that arrived while the console was away.
            if host != nil, startWhenOnline {
                startWhenOnline = false
                start()
            }
        }
    }

    /// New games in watched folders (`FolderWatch`), looked for every 20 seconds.
    private let watch = FolderWatch()
    private var watcher: Task<Void, Never>?
    private var startWhenOnline = false

    private var runner: Task<Void, Never>?
    private var lock: QueueLock?
    private var awake: KeepAwake?
    private var observers: [NSObjectProtocol] = []
    private var isFixture = false

    var pending: [TransferQueue.Item] { queue.pending }
    var remainingBytes: Int64 { queue.remainingBytes }

    /// Time left at the current rate, or at the last measured speed.
    var eta: TimeInterval? {
        SpeedTest.estimate(bytes: remainingBytes, rate: rate, measured: lastSpeed)
    }

    init() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemWillSleep() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemDidWake() }
        })
    }

    /// Fixture mode (`PS3CENTER_FIXTURES=1`): a queue in the middle of sending.
    func loadFixture(_ queue: TransferQueue = Fixtures.queue) {
        isFixture = true
        self.queue = queue
        current = queue.items.first { $0.state == .sending }?.id
        isRunning = current != nil
        rate = 3_250_000
        lastSpeed = Fixtures.speed
    }

    // MARK: Watched folders

    func startWatching() {
        guard watcher == nil, !isFixture else { return }
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                await self?.lookInWatchedFolders()
            }
        }
    }

    private func lookInWatchedFolders() async {
        let folders = FolderWatch.watched()
        guard !folders.isEmpty else { return }
        let watch = self.watch
        // Reading the folders (and new games' sizes) stays off the main thread.
        let games = await Task.detached { () -> [(title: String, routes: [Route])] in
            let arrivals = watch.poll(folders)
            return arrivals.isEmpty ? [] : FolderWatch.routes(for: arrivals)
        }.value
        for game in games {
            if host == nil { startWhenOnline = true }
            add(game.routes)
            Notifier.post(title: "New game in the queue", body: "\(game.title) is being sent to the PS3.")
        }
    }

    // MARK: Queue

    /// Changes queue.json and shows the result. This copy is never written back as it is, since
    /// `ps3 queue` may have changed the file since it was read.
    private func edit(_ change: (inout TransferQueue) -> Void) {
        guard !isFixture else {
            change(&queue)
            return
        }
        do {
            queue = try TransferQueue.edit { latest in
                change(&latest)
                return latest
            }
        } catch {
            note = "The queue could not be saved: \(error.localizedDescription)"
        }
    }

    func add(_ routes: [Route]) {
        guard !isFixture else { return }
        var added: [TransferQueue.Item] = []
        edit { added = $0.add(routes) }
        if !added.isEmpty { start() }
    }

    func start() {
        guard runner == nil, !isFixture, let host else { return }
        guard let lock = QueueLock() else {
            note = "The queue is already being sent from `ps3 queue start` in Terminal."
            return
        }
        self.lock = lock
        awake = KeepAwake(reason: "Sending games to the PS3")
        pausedForSleep = false
        note = nil
        runner = Task { await self.run(host: host) }
    }

    /// Stops after closing the connection cleanly, so the next start continues the same file.
    func pause() {
        runner?.cancel()
    }

    func remove(_ id: UUID) {
        guard id != current else { return }
        edit { latest in latest.items.removeAll { $0.id == id } }
    }

    func retry(_ id: UUID) {
        edit {
            $0.update(id) {
                $0.state = .waiting
                $0.message = nil
            }
        }
        start()
    }

    func clearFinished() {
        edit { $0.removeFinished() }
    }

    func setWhenDone(_ choice: TransferQueue.WhenDone) {
        edit { $0.whenDone = choice }
    }

    func setVerify(_ on: Bool) {
        edit { $0.verify = on }
    }

    /// Five seconds of sending, then reading back what arrived: 10–15 seconds in all.
    func measureSpeed() async {
        guard !isMeasuring, !isRunning else { return }
        guard let host else {
            measureError = "Can't reach the PS3 right now."
            return
        }
        isMeasuring = true
        measureError = nil
        measureStep = "Preparing…"
        defer {
            isMeasuring = false
            measureStep = nil
        }
        do {
            lastSpeed = try await SpeedTest.run(host: host, seconds: 5) { event in
                Task { @MainActor [weak self] in self?.measured(event) }
            }
        } catch {
            measureError = "The measurement failed: \(error.localizedDescription)"
        }
    }

    private func measured(_ event: TransferEvent) {
        guard isMeasuring else { return }
        switch event {
        case .progress(_, let sent, let total, let bytesPerSecond):
            measureStep = "Sending \(total > 0 ? Int(Double(sent) / Double(total) * 100) : 0) % · \(Format.rate(bytesPerSecond))"
        case .note(let text):
            measureStep = text
        default:
            break
        }
    }

    /// The loop itself is `QueueRunner.run`, the same as `ps3 queue start`; this only shows it.
    private func run(host: String) async {
        isRunning = true
        let runner = QueueRunner(host: host)
        let result = await runner.run { event in
            Task { @MainActor [weak self] in self?.handle(event) }
        }
        queue = TransferQueue.load()
        current = nil
        rate = 0
        if !result.cancelled, !result.sent.isEmpty {
            let titles = result.sent
            do {
                try await runner.finish(result) { event in
                    Task { @MainActor [weak self] in self?.show(event) }
                }
                note = nil
                Notifier.post(title: titles.count == 1 ? "\(titles[0]) is sent" : "\(titles.count) games are sent",
                              body: result.whenDone == .shutdown ? "The PS3 is shutting down." : "The games are under Game on the PS3.")
            } catch {
                note = error.localizedDescription
            }
        }
        isRunning = false
        self.runner = nil
        lock = nil
        awake = nil
    }

    private func handle(_ event: QueueRunEvent) {
        switch event {
        case .started(let item):
            current = item.id
            note = nil
            queue = TransferQueue.load()
        case .sent(let id, let bytes):
            queue.update(id) { $0.sent = bytes }
        case .done, .failed, .paused:
            queue = TransferQueue.load()
        case .notSaved(let error):
            note = "The queue could not be saved: \(error.localizedDescription)"
        case .transfer(_, let transfer):
            if case .progress(_, _, _, let bytesPerSecond) = transfer { rate = bytesPerSecond }
            show(transfer)
        }
    }

    /// What the queue is waiting for, from the transfer and from `finish`.
    private func show(_ transfer: TransferEvent) {
        switch transfer {
        case .waitingForGame(let game):
            note = "\(game) is running. The game list refreshes once you quit the game."
        case .refreshed:
            note = "The game list is refreshed"
        case .note(let text):
            note = text
        case .started:
            note = nil  // going again after a retry
        default:
            break
        }
    }

    // MARK: Sleep

    private func systemWillSleep() {
        guard isRunning else { return }
        pausedForSleep = true
        pause()
    }

    private func systemDidWake() {
        guard pausedForSleep else { return }
        // Give the network a moment to come back before the queue looks for the console.
        Task {
            try? await Task.sleep(for: .seconds(20))
            if self.pausedForSleep, self.runner == nil { self.start() }
        }
    }
}
