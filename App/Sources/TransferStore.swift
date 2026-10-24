import AppKit
import Foundation
import Observation
import PS3Kit

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
    var host: String?

    private var runner: Task<Void, Never>?
    private var lock: QueueLock?
    private var awake: KeepAwake?
    private var lastSave = Date.distantPast
    private var observers: [NSObjectProtocol] = []
    private var isFixture = false

    var pending: [TransferQueue.Item] { queue.pending }
    var remainingBytes: Int64 { queue.remainingBytes }

    /// Time left at the current rate, or at the last measured speed.
    var eta: TimeInterval? {
        let speed = rate > 0 ? rate : (lastSpeed?.upload ?? 0)
        return speed > 0 ? Double(remainingBytes) / speed : nil
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

    // MARK: Queue

    func add(_ routes: [Route]) {
        guard !isFixture else { return }
        queue = TransferQueue.load()
        let added = queue.add(routes)
        queue.save()
        if !added.isEmpty { start() }
    }

    func start() {
        guard runner == nil, !isFixture, let host else { return }
        guard let lock = QueueLock() else {
            note = "Kön skickas redan från ps3 queue start i Terminalen."
            return
        }
        self.lock = lock
        awake = KeepAwake(reason: "Skickar spel till PS3:an")
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
        queue = TransferQueue.load()
        queue.items.removeAll { $0.id == id }
        queue.save()
    }

    func retry(_ id: UUID) {
        queue.update(id) {
            $0.state = .waiting
            $0.message = nil
        }
        queue.save()
        start()
    }

    func clearFinished() {
        queue = TransferQueue.load()
        queue.removeFinished()
        queue.save()
    }

    func setWhenDone(_ choice: TransferQueue.WhenDone) {
        queue.whenDone = choice
        if !isFixture { queue.save() }
    }

    func setVerify(_ on: Bool) {
        queue.verify = on
        if !isFixture { queue.save() }
    }

    /// Five seconds of sending, then reading back what arrived: 10–15 seconds in all.
    func measureSpeed() async {
        guard !isMeasuring, !isRunning else { return }
        guard let host else {
            measureError = "Ingen kontakt med PS3:an just nu."
            return
        }
        isMeasuring = true
        measureError = nil
        measureStep = "Förbereder…"
        defer {
            isMeasuring = false
            measureStep = nil
        }
        do {
            lastSpeed = try await SpeedTest.run(host: host, seconds: 5) { event in
                Task { @MainActor [weak self] in self?.measured(event) }
            }
        } catch {
            measureError = "Mätningen misslyckades: \(error.localizedDescription)"
        }
    }

    private func measured(_ event: TransferEvent) {
        guard isMeasuring else { return }
        switch event {
        case .progress(_, let sent, let total, let bytesPerSecond):
            measureStep = "Skickar \(total > 0 ? Int(Double(sent) / Double(total) * 100) : 0) % · \(Format.rate(bytesPerSecond))"
        case .note(let text):
            measureStep = text
        default:
            break
        }
    }

    private func run(host: String) async {
        isRunning = true
        var titles: [String] = []
        var refresh = false
        let runner = QueueRunner(host: host)
        while !Task.isCancelled {
            // Read again each round: `ps3 queue add` may have added something.
            let latest = TransferQueue.load()
            queue.items = latest.items
            guard let item = queue.pending.first else { break }
            current = item.id
            queue.update(item.id) {
                $0.state = .sending
                $0.message = nil
            }
            queue.save()
            do {
                try await runner.send(item, verify: queue.verify) { event in
                    Task { @MainActor [weak self] in self?.handle(event, item: item.id) }
                }
                queue.update(item.id) {
                    $0.state = .done
                    $0.sent = $0.total
                    $0.finishedAt = Date()
                }
                titles.append(item.title)
                refresh = refresh || item.routes.contains(where: \.refreshesGameList)
            } catch {
                if Task.isCancelled || error is CancellationError {
                    queue.update(item.id) { $0.state = .paused }
                    queue.save()
                    break
                }
                queue.update(item.id) {
                    $0.state = .failed
                    $0.message = error.localizedDescription
                }
            }
            queue.save()
        }
        current = nil
        rate = 0
        if !Task.isCancelled, !titles.isEmpty {
            do {
                try await runner.finish(sent: titles, refresh: refresh, whenDone: queue.whenDone) { event in
                    Task { @MainActor [weak self] in self?.handle(event, item: nil) }
                }
                note = nil
                Notifier.post(title: titles.count == 1 ? "\(titles[0]) är skickat" : "\(titles.count) spel är skickade",
                              body: queue.whenDone == .shutdown ? "PS3:an stängs av." : "Spelen finns under Spel på PS3:an.")
            } catch {
                note = error.localizedDescription
            }
        }
        isRunning = false
        self.runner = nil
        lock = nil
        awake = nil
    }

    private func handle(_ event: TransferEvent, item id: UUID?) {
        switch event {
        case .progress(let route, let sent, _, let bytesPerSecond):
            guard let id else { return }
            rate = bytesPerSecond
            queue.update(id) { $0.sent = Self.sentBefore(route, in: $0) + sent }
        case .finished(let route, _), .skipped(let route, _):
            guard let id else { return }
            queue.update(id) { $0.sent = Self.sentBefore(route, in: $0) + route.size }
        case .waitingForGame(let game):
            note = "\(game) körs. Spellistan uppdateras när du har avslutat spelet."
        case .refreshed:
            note = "Spellistan är uppdaterad"
        case .note(let text):
            note = text
        default:
            return
        }
        // Progress is saved now and then, so a crash loses little.
        if Date().timeIntervalSince(lastSave) > 5 {
            lastSave = Date()
            queue.save()
        }
    }

    /// Bytes of the item's files before `route`, which are already on the console.
    static func sentBefore(_ route: Route, in item: TransferQueue.Item) -> Int64 {
        guard let index = item.files.firstIndex(where: { $0.remote == route.remote }) else { return 0 }
        return item.files[..<index].reduce(0) { $0 + $1.size }
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
