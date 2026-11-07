import AppKit
import Foundation
import Observation
import PS3Kit

/// Backs the Apps tab: catalog status, icons, and a one-at-a-time install queue
/// (webMAN's FTP server handles a single transfer well).
@MainActor
@Observable
final class AppsStore {
    enum Phase: Equatable {
        case idle, loading, loaded, failed(String)
    }

    enum ReadmeState {
        case loading, loaded(Readme), failed(String)
    }

    struct Operation: Equatable {
        enum Stage: Equatable {
            case queued, downloading, uploading(Double), waitingForGame(String), installing, uninstalling, done, failed(String)
        }
        var stage: Stage

        var isFailed: Bool {
            if case .failed = stage { return true }
            return false
        }
    }

    /// What "Uppdatera alla" is about to do, shown for review before anything happens: the
    /// updates it can install, and the ones it leaves alone and why.
    struct UpdatePlan: Identifiable {
        struct Skip: Identifiable {
            let status: AppStatus
            /// Short enough for one line; the catalog's full advice is in `status.note`.
            let reason: String
            var id: String { status.id }
        }

        let id = UUID()
        let installs: [AppStatus]
        let skipped: [Skip]
    }

    /// The outcome of "Uppdatera alla" once the queue is empty: Klart, Misslyckades and Hoppade
    /// över, each with its reason. Shown above the list until it is closed.
    struct UpdateReport: Equatable {
        struct Line: Equatable, Identifiable {
            let id: String
            let name: String
            let detail: String
        }

        var done: [Line]
        var failed: [Line]
        var skipped: [Line]
        let finished: Date
    }

    /// A running "Uppdatera alla": what it queued, and what it left out and why.
    private struct UpdateBatch {
        let installs: [UpdateReport.Line]
        let skipped: [UpdateReport.Line]
    }

    private(set) var phase: Phase = .idle
    private(set) var statuses: [AppStatus] = []
    private(set) var icons: [String: NSImage] = [:]
    /// XMB backgrounds (PIC1.PNG) of installed apps, for the detail page's banner.
    private(set) var backgrounds: [String: NSImage] = [:]
    private var backgroundsTried: Set<String> = []
    private(set) var operations: [String: Operation] = [:]
    private(set) var lastChecked: Date?
    private(set) var report: UpdateReport?
    private var batch: UpdateBatch?
    /// READMEs by repo, fetched when a program's detail page opens.
    private(set) var readmes: [String: ReadmeState] = [:]
    /// The program whose detail page is open in the Apps tab.
    var selectedID: String?
    var archiveMissing = false

    private var queue: [String] = []
    private var runner: Task<Void, Never>?
    private var runnerToken = UUID()
    private var forceNext = false
    private var host: String?

    /// Updates the user has not ignored: what the badges count and "Uppdatera alla" offers.
    var updates: [AppStatus] { statuses.filter(\.isPendingUpdate) }
    var ignoredUpdates: [AppStatus] { statuses.filter { $0.state == .updateAvailable && $0.ignored } }
    var current: [AppStatus] { statuses.filter { $0.state == .upToDate } }
    var manual: [AppStatus] { statuses.filter { $0.state == .manual || $0.state == .error } }
    var available: [AppStatus] { statuses.filter { $0.installed == nil && $0.installable } }
    var installableUpdates: [AppStatus] { updates.filter(\.canInstall) }

    var waitingGame: String? {
        for op in operations.values { if case .waitingForGame(let game) = op.stage { return game } }
        return nil
    }

    var isBusy: Bool { runner != nil }
    var isUpdatingAll: Bool { batch != nil }

    var selected: AppStatus? {
        guard let selectedID else { return nil }
        return statuses.first { $0.id == selectedID }
    }

    static func entry(for status: AppStatus) -> CatalogEntry? {
        Catalog.entries.first { $0.id == status.id }
    }

    func load(host: String, refreshIcons: Bool = false) async {
        self.host = host
        if statuses.isEmpty { phase = .loading }
        do {
            let next = try await AppsService(host: host).check()
            statuses = next
            notifyNewUpdates(in: next)
            phase = .loaded
            lastChecked = Date()
            let installed = Catalog.entries.filter { entry in next.contains { $0.id == entry.id && $0.installed != nil } }
            let data = await AppsService(host: host).icons(for: installed, refresh: refreshIcons)
            icons = data.compactMapValues { NSImage(data: $0) }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// One notice per new version, remembered between launches.
    private func notifyNewUpdates(in next: [AppStatus]) {
        let key = "notifiedUpdates"
        var seen = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        let fresh = next.filter { $0.isPendingUpdate && !seen.contains("\($0.id) \($0.latest ?? "")") }
        guard !fresh.isEmpty else { return }
        for status in fresh { seen.insert("\(status.id) \(status.latest ?? "")") }
        UserDefaults.standard.set(Array(seen), forKey: key)
        let names = fresh.map(\.name).joined(separator: ", ")
        Notifier.post(title: fresh.count == 1 ? "Ny version av \(names)" : "\(fresh.count) programuppdateringar",
                      body: fresh.count == 1 ? "Finns att installera under Appar." : names)
    }

    /// Fixture mode (`PS3CENTER_FIXTURES=1`): canned rows and README, no network.
    func loadFixture(statuses: [AppStatus] = Fixtures.appStatuses()) {
        self.statuses = statuses
        phase = .loaded
        lastChecked = Date()
        readmes[Fixtures.readme.repo] = .loaded(Fixtures.readme)
    }

    func loadBackground(for entry: CatalogEntry) async {
        guard let host, !backgroundsTried.contains(entry.id),
              statuses.first(where: { $0.id == entry.id })?.installed != nil else { return }
        backgroundsTried.insert(entry.id)
        if let data = await AppsService(host: host).background(for: entry), let image = NSImage(data: data) {
            backgrounds[entry.id] = image
        }
    }

    func loadReadme(for entry: CatalogEntry) async {
        guard let repo = entry.repository else { return }
        switch readmes[repo] {
        case .some(.loading), .some(.loaded): return
        case .some(.failed), nil: break
        }
        readmes[repo] = .loading
        do {
            readmes[repo] = .loaded(try await GitHub.readme(repo: repo))
        } catch {
            readmes[repo] = .failed(error.localizedDescription)
        }
    }

    // MARK: Queue

    func install(_ status: AppStatus) {
        // Not twice at once; again after it finished or failed.
        if let op = operations[status.id], op.stage != .done, !op.isFailed { return }
        operations[status.id] = Operation(stage: .queued)
        queue.append(status.id)
        startRunner()
    }

    /// Removes an installed app (its folder in /dev_hdd0/game), then reads the list again.
    func uninstall(_ status: AppStatus) {
        guard let host, let entry = Self.entry(for: status) else { return }
        if let op = operations[status.id], op.stage != .done, !op.isFailed { return }
        operations[status.id] = Operation(stage: .uninstalling)
        Task {
            do {
                try await AppsService(host: host).uninstall(entry, options: TransferOptions()) { _ in }
                operations[status.id] = nil
                await load(host: host)
            } catch {
                operations[status.id] = Operation(stage: .failed(ConsoleErrorCode.annotate(error.localizedDescription)))
            }
        }
    }

    // MARK: Ignore

    /// "Ignorera": skips this release. It moves to Ignorerade and comes back when a newer one is out.
    func ignore(_ status: AppStatus) {
        guard let latest = status.latest, (try? IgnoredUpdates.ignore(status.id, version: latest)) != nil else { return }
        setIgnored(true, for: status.id)
    }

    func unignore(_ status: AppStatus) {
        guard (try? IgnoredUpdates.unignore(status.id)) != nil else { return }
        setIgnored(false, for: status.id)
    }

    private func setIgnored(_ ignored: Bool, for id: String) {
        guard let index = statuses.firstIndex(where: { $0.id == id }) else { return }
        statuses[index].ignored = ignored
    }

    // MARK: Uppdatera alla

    /// What the review before "Uppdatera alla" shows.
    func updatePlan() -> UpdatePlan {
        let notAutomatic = updates.filter { !$0.canInstall }.map { UpdatePlan.Skip(status: $0, reason: Self.skipReason(for: $0)) }
        let ignored = ignoredUpdates.map { UpdatePlan.Skip(status: $0, reason: "Ignorerad") }
        return UpdatePlan(installs: installableUpdates, skipped: notAutomatic + ignored)
    }

    /// Why an update is not part of "Uppdatera alla", in a few words.
    static func skipReason(for status: AppStatus) -> String {
        if status.compatibility.blocksInstall { return status.compatibility.summary }
        if let action = entry(for: status)?.action, case .notifyOnly = action { return "Installeras aldrig automatiskt" }
        return status.note ?? "Releasen saknar paket"
    }

    static func versionChange(_ status: AppStatus) -> String {
        "\(status.installed ?? "?") → \(status.latest ?? "?")"
    }

    /// Runs the reviewed plan: queues the chosen updates and keeps the rest for the report.
    func updateAll(_ chosen: [AppStatus], from plan: UpdatePlan) {
        guard batch == nil, !chosen.isEmpty else { return }
        let chosenIDs = Set(chosen.map(\.id))
        let unchecked = plan.installs.filter { !chosenIDs.contains($0.id) }
            .map { UpdateReport.Line(id: $0.id, name: $0.name, detail: "Bortvald i granskningen") }
        let skipped = plan.skipped.map { UpdateReport.Line(id: $0.id, name: $0.status.name, detail: $0.reason) }
        batch = UpdateBatch(installs: chosen.map { UpdateReport.Line(id: $0.id, name: $0.name, detail: Self.versionChange($0)) },
                            skipped: unchecked + skipped)
        report = nil
        chosen.forEach(install)
    }

    func dismissReport() {
        report = nil
    }

    /// Called when the queue is empty: turns the batch into the report.
    private func finishBatch() {
        guard let batch else { return }
        self.batch = nil
        var done: [UpdateReport.Line] = []
        var failed: [UpdateReport.Line] = []
        var skipped = batch.skipped
        for line in batch.installs {
            switch operations[line.id]?.stage {
            case .done: done.append(line)
            case .failed(let message): failed.append(UpdateReport.Line(id: line.id, name: line.name, detail: message))
            default: skipped.append(UpdateReport.Line(id: line.id, name: line.name, detail: "Kördes inte"))
            }
        }
        report = UpdateReport(done: done, failed: failed, skipped: skipped, finished: Date())
        let title = failed.isEmpty && done.count == 1 ? "\(done[0].name) är uppdaterat"
            : "\(done.count) av \(batch.installs.count) uppdateringar klara"
        Notifier.post(title: title, body: failed.isEmpty ? "Allt gick bra." : "Gick inte: " + failed.map(\.name).joined(separator: ", "))
    }

    /// Fixture mode: the report after an "Uppdatera alla" with one of each outcome.
    func loadFixtureReport() {
        let byID = Dictionary(uniqueKeysWithValues: statuses.map { ($0.id, $0) })
        func line(_ id: String, _ detail: (AppStatus) -> String) -> [UpdateReport.Line] {
            guard let status = byID[id] else { return [] }
            return [UpdateReport.Line(id: id, name: status.name, detail: detail(status))]
        }
        report = UpdateReport(
            done: line("apollo", Self.versionChange),
            failed: line("webman") { _ in "Kontakten med PS3:an bröts under uppladdningen" },
            skipped: line("hen", Self.skipReason) + line("artemis") { _ in "Ignorerad" },
            finished: Date())
    }

    /// "Kör ändå": restarts the waiting install without waiting for the game to end.
    func forceWaiting() {
        guard waitingGame != nil, let id = operations.first(where: { if case .waitingForGame = $0.value.stage { return true }; return false })?.key else { return }
        runner?.cancel()
        runner = nil
        forceNext = true
        queue.insert(id, at: 0)
        operations[id] = Operation(stage: .queued)
        startRunner()
    }

    private func startRunner() {
        guard runner == nil else { return }
        let token = UUID()
        runnerToken = token
        runner = Task { [weak self] in
            await self?.drain(token: token)
        }
    }

    private func drain(token: UUID) async {
        while let id = queue.first, !Task.isCancelled {
            queue.removeFirst()
            await perform(id)
        }
        // A cancelled runner (forceWaiting) must not clear its replacement.
        guard runnerToken == token else { return }
        runner = nil
        finishBatch()
        if let host { await load(host: host, refreshIcons: true) }
    }

    private func perform(_ id: String) async {
        guard let host, let entry = Catalog.entries.first(where: { $0.id == id }) else { return }
        guard let root = MirrorRoot.resolve() else {
            archiveMissing = true
            operations[id] = Operation(stage: .failed("Välj PS3-mappen först"))
            return
        }
        var options = TransferOptions()
        options.force = forceNext
        forceNext = false
        operations[id] = Operation(stage: .downloading)
        do {
            try await AppsService(host: host).install(entry, archive: MirrorRoot.packageArchive(in: root), options: options) { event in
                Task { @MainActor [weak self] in self?.handle(event, for: id) }
            }
            operations[id] = Operation(stage: .done)
            try? await WebMAN(host: host).popup("\(entry.name) installerat från Macen")
        } catch is CancellationError {
            // forceWaiting() re-queued it.
        } catch {
            operations[id] = Operation(stage: .failed(ConsoleErrorCode.annotate(error.localizedDescription)))
        }
    }

    private func handle(_ event: TransferEvent, for id: String) {
        guard operations[id]?.stage != .done else { return }
        switch event {
        case .started: operations[id] = Operation(stage: .uploading(0))
        case .progress(_, let sent, let total, _): operations[id] = Operation(stage: .uploading(total > 0 ? Double(sent) / Double(total) : 0))
        case .waitingForGame(let game): operations[id] = Operation(stage: .waitingForGame(game))
        case .installing: operations[id] = Operation(stage: .installing)
        default: break
        }
    }

    // MARK: Mirror folder

    func chooseMirrorFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Välj"
        panel.message = "Välj PS3-mappen (den med dev_hdd0/ och _Installerat/)."
        guard panel.runModal() == .OK, let url = panel.url, MirrorRoot.looksLikeMirror(url) else { return }
        var config = ConfigStore.load()
        config.root = url.path
        try? ConfigStore.save(config)
        archiveMissing = false
        for (id, op) in operations { if case .failed = op.stage { operations[id] = nil } }
    }
}
