import AppKit
import Foundation
import Observation
import PS3Kit

/// Finds the console and polls its status, like `ps3 status --watch`.
@MainActor
@Observable
final class ConsoleStore {
    enum Connection: Equatable {
        case connecting
        case scanning
        case online
        case offline(String)
        /// The console answers on the network but webMAN does not: HEN is not enabled.
        case henOff(String)
    }

    private(set) var connection: Connection = .connecting
    private(set) var host: String?
    private(set) var snapshot: ConsoleSnapshot?
    private(set) var latency: TimeInterval?
    /// Polls in a row that got no answer. webMAN is slow at times (while it installs, or a game
    /// runs), so the console only counts as gone after `allowedMisses`.
    private(set) var missedPolls = 0
    private let allowedMisses = 3
    private(set) var cpuHistory: [Double] = []
    private(set) var rsxHistory: [Double] = []
    private(set) var fanHistory: [Double] = []
    private(set) var history: [OperationLog.Entry] = []
    /// ICON0 and PIC1 of the mounted game, fetched again when the mount changes.
    private(set) var gameIcon: NSImage?
    private(set) var gameBackground: NSImage?
    private var artPath: String?
    /// Time played per game, kept up while the console is polled.
    private(set) var playLog = PlayLog.load()
    private var tracker = PlayTracker(interval: 3)
    private var playUnsaved = false
    private var lastPlaySave = Date.distantPast
    private var lastHeatWarning = Date.distantPast
    /// What the last button (shut down, eject, fan …) did, or why it failed.
    private(set) var actionNote: String?
    private(set) var isActing = false
    /// webMAN records the running game (`toggleRecording`); it stops when the game ends.
    private(set) var isRecording = false

    let interval: TimeInterval = 3
    private let historyLength = 40
    private var pollTask: Task<Void, Never>?

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in await self?.run() }
    }

    func retry() {
        pollTask?.cancel()
        pollTask = nil
        connection = .connecting
        start()
    }

    private func run() async {
        while !Task.isCancelled {
            if host == nil {
                do {
                    host = try await ConsoleLocator.resolve { event in
                        if case .scanning = event { Task { @MainActor [weak self] in self?.connection = .scanning } }
                    }
                } catch {
                    // Off, or on with HEN not enabled? Only the second answers on the network.
                    if let known = ConfigStore.load().host, await Reachability.probe(known) == .henOff {
                        connection = .henOff(known)
                    } else {
                        connection = .offline(error.localizedDescription)
                    }
                    try? await Task.sleep(for: .seconds(8))
                    continue
                }
            }
            guard let host else { continue }
            let started = Date()
            do {
                let next = try await WebMAN(host: host).snapshot()
                latency = Date().timeIntervalSince(started)
                record(next)
                missedPolls = 0
                connection = .online
                if next.mountedGamePath != artPath { loadArt(for: next.mountedGamePath, host: host) }
            } catch {
                missedPolls += 1
                // While a long command runs (an install, counting storage, copying the disc) the
                // console is slow, not gone; that command's own timeout ends the wait.
                if connection != .online || (missedPolls >= allowedMisses && !WebMAN.isBusy) {
                    missedPolls = 0
                    connection = .offline(error.localizedDescription)
                    self.host = nil  // look again next round; the IP may have changed
                }
            }
            history = OperationLog.read(limit: 12).reversed()
            try? await Task.sleep(for: .seconds(interval))
        }
    }

    private func loadArt(for path: String?, host: String) {
        artPath = path
        gameIcon = nil
        gameBackground = nil
        guard path != nil else { return }
        Task { [weak self] in
            let art = await GameArt.mounted(host: host)
            guard let self, self.artPath == path else { return }
            self.gameIcon = art.icon.flatMap(NSImage.init(data:))
            self.gameBackground = art.background.flatMap(NSImage.init(data:))
        }
    }

    /// Fixture mode (`PS3CENTER_FIXTURES=1`): canned data, no network.
    func loadFixture(_ snapshot: ConsoleSnapshot = Fixtures.snapshot) {
        pollTask?.cancel()
        pollTask = nil
        host = snapshot.host
        self.snapshot = snapshot
        latency = 0.18
        cpuHistory = Fixtures.series(around: Double(snapshot.cpuTemp ?? 60))
        rsxHistory = Fixtures.series(around: Double(snapshot.rsxTemp ?? 65))
        fanHistory = Fixtures.series(around: Double(snapshot.fanPercent ?? 30), swing: 2)
        history = Fixtures.history
        playLog = Fixtures.playLog
        connection = .online
    }

    /// Fixture for the connection screen when HEN is not enabled.
    func loadHenOffFixture() {
        pollTask?.cancel()
        pollTask = nil
        connection = .henOff("10.0.1.35")
    }

    private func record(_ next: ConsoleSnapshot) {
        snapshot = next
        if !next.isGameRunning { isRecording = false }
        trackPlayTime(next)
        warnIfHot(next)
        func push(_ value: Int?, into array: inout [Double]) {
            guard let value else { return }
            array.append(Double(value))
            if array.count > historyLength { array.removeFirst(array.count - historyLength) }
        }
        push(next.cpuTemp, into: &cpuHistory)
        push(next.rsxTemp, into: &rsxHistory)
        push(next.fanPercent, into: &fanHistory)
    }

    // MARK: Play time and heat

    private func trackPlayTime(_ next: ConsoleSnapshot) {
        let changed = tracker.observe(next, log: &playLog)
        if changed { playUnsaved = true }
        // Saved every half minute while playing, and when the game ends.
        if playUnsaved, !changed || Date().timeIntervalSince(lastPlaySave) > 30 {
            try? playLog.save()
            playUnsaved = false
            lastPlaySave = Date()
        }
    }

    /// The same limits as "Het" on the temperature cards; at most one notice per half hour.
    private func warnIfHot(_ next: ConsoleSnapshot) {
        let cpu = next.cpuTemp ?? 0
        let rsx = next.rsxTemp ?? 0
        guard cpu >= 80 || rsx >= 85, Date().timeIntervalSince(lastHeatWarning) > 1800 else { return }
        lastHeatWarning = Date()
        Notifier.post(title: "The PS3 is hot", body: "CPU \(cpu) °C, RSX \(rsx) °C. Make sure it has air around it.")
    }

    // MARK: Controls

    func shutdown() {
        act("The PS3 is shutting down") { try await $0.shutdown() }
    }

    func restart() {
        act("The PS3 is restarting. Enable HEN again once it has started.") { try await $0.restart() }
    }

    func exitGame() {
        act("The game has quit") { _ = try await GameLibraryService(host: $0.host).exitGame() }
    }

    /// Like SELECT + L3; not while a game runs, as `ps3 refresh` waits for.
    func refreshGames() {
        act("The game list is refreshed") { webMAN in
            let running = try await webMAN.isGameRunning()
            guard !running else { throw PS3Error.gameRunning }
            try await webMAN.refreshGames()
            OperationLog.record("refresh", webMAN.host)
        }
    }

    func eject() {
        act("Ejecting the disc") { try await $0.ejectDisc() }
    }

    func insert() {
        act("Inserting the disc") { try await $0.insertDisc() }
    }

    func setFanTarget(_ celsius: Int) {
        act("The fan now targets \(celsius) °C") { try await $0.setFanTarget(celsius) }
    }

    // MARK: Extras (webMAN commands from fas 9)

    func toggleRecording() {
        guard let host, !isActing, !Snapshot.usesFixtures else { return }
        isActing = true
        actionNote = nil
        Task {
            do {
                let recording = try await WebMAN(host: host).toggleRecording()
                isRecording = recording
                actionNote = recording
                    ? "Recording. Press again to stop."
                    : "The recording is in /dev_hdd0/VIDEO. Import it under Maintenance → Videos & Photos."
            } catch {
                actionNote = error.localizedDescription
            }
            isActing = false
        }
    }

    func reloadXMB() {
        act("Reloading the XMB") { webMAN in
            let running = try await webMAN.isGameRunning()
            guard !running else { throw PS3Error.gameRunning }
            try await webMAN.reloadXMB()
        }
    }

    func beep() {
        act("Beep!") { try await $0.beep() }
    }

    func enableGameScreenshots() {
        act("Screenshots are allowed in games until the next restart: PS button → Save Screenshot.") { try await $0.enableGameScreenshots() }
    }

    func setGameMusic(_ on: Bool) {
        act(on ? "XMB music plays during games" : "No XMB music during games") { try await $0.setGameMusic(on) }
    }

    func press(_ button: PadButton) async {
        guard let host else { return }
        try? await WebMAN(host: host).press(button)
    }

    func padOff() async {
        guard let host else { return }
        try? await WebMAN(host: host).padOff()
    }

    private func act(_ done: String, _ work: @escaping @Sendable (WebMAN) async throws -> Void) {
        guard let host, !isActing, !Snapshot.usesFixtures else { return }
        isActing = true
        actionNote = nil
        Task {
            do {
                try await work(WebMAN(host: host))
                actionNote = done
            } catch {
                actionNote = error.localizedDescription
            }
            isActing = false
        }
    }
}
