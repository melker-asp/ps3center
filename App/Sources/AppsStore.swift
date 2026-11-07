import AppKit
import Foundation
import Observation
import PS3Kit
import PS3KitFixtures

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

    /// What "Update All" is about to do, shown for review before anything happens. The rules are
    /// PS3Kit's, shared with `ps3 apps update`.
    typealias UpdatePlan = PS3Kit.UpdatePlan
    /// The outcome of "Update All", shown above the list until it is closed.
    typealias UpdateReport = PS3Kit.UpdateReport

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

    /// The .pkg files in the Mac's package folders (From Mac).
    private(set) var packages: [LocalPackage] = []
    private(set) var packagesLoaded = false
    private(set) var isLoadingPackages = false
    /// APP_VER per title ID of the packages installed on the console ("" without one).
    private(set) var packageVersions: [String: String] = [:]
    /// Whether the console has been asked, so that a missing version means "not installed".
    private(set) var packagesChecked = false
    /// XMB icons of the installed packages, by title ID.
    private(set) var packageIcons: [String: NSImage] = [:]
    /// True while `load` reads the console, which then asks about the packages itself.
    private var isChecking = false

    private var queue: [String] = []
    /// Queued packages from the Mac by id (their path); other ids in `queue` are catalog ids.
    private var queuedPackages: [String: LocalPackage] = [:]
    private var runner: Task<Void, Never>?
    private var runnerToken = UUID()
    private var forceNext = false
    private var host: String?

    /// The Updates list's groups (`AppGroups`, the same as `ps3 apps`).
    var groups: AppGroups { AppGroups(statuses) }
    /// Updates the user has not ignored: what the badges count and "Update All" offers.
    var updates: [AppStatus] { groups.updates }
    var ignoredUpdates: [AppStatus] { groups.ignored }
    var current: [AppStatus] { groups.current }
    var manual: [AppStatus] { groups.manual }
    var available: [AppStatus] { statuses.filter { $0.installed == nil && $0.installable } }
    var installableUpdates: [AppStatus] { updates.filter(\.canInstall) }
    /// Browse's "New": apps whose latest release is less than 30 days old.
    var newReleases: [AppStatus] { statuses.filter { $0.isNewRelease() && $0.isListed } }

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
        isChecking = true
        defer { isChecking = false }
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
        // One FTP session at a time: the packages are asked about after the catalog.
        if packagesLoaded { await checkPackages(host: host, refreshIcons: refreshIcons) }
    }

    // MARK: Packages on the Mac

    /// Reads the Mac's package folders, then asks the console which of them are installed,
    /// unless the catalog check or an install is using the console (they ask when done).
    func loadPackages(host: String?) async {
        if let host { self.host = host }
        isLoadingPackages = true
        packages = await Task.detached { PackageLibrary.scan() }.value
        packagesLoaded = true
        isLoadingPackages = false
        guard let host = self.host, !isChecking, runner == nil else { return }
        await checkPackages(host: host)
    }

    private func checkPackages(host: String, refreshIcons: Bool = false) async {
        let titleIDs = packages.compactMap(\.titleID)
        guard let versions = try? await AppsService(host: host).installedVersions(of: titleIDs) else { return }
        packageVersions = versions
        packagesChecked = true
        let data = await AppsService(host: host).icons(titleIDs: Array(versions.keys), refresh: refreshIcons)
        packageIcons = data.compactMapValues { NSImage(data: $0) }
    }

    /// The installed APP_VER of `package` ("" without one), nil when not installed or not known.
    func installedVersion(of package: LocalPackage) -> String? {
        package.titleID.flatMap { packageVersions[$0.uppercased()] }
    }

    /// The catalog row with the package's title ID: its compatibility applies to the package.
    func catalogStatus(of package: LocalPackage) -> AppStatus? {
        guard let id = package.catalogID else { return nil }
        return statuses.first { $0.id == id }
    }

    /// Queues `package` for installing from where it lies, after the same safety check as an
    /// install by name when its title ID is in the catalog.
    func install(_ package: LocalPackage) {
        if let op = operations[package.id], !op.isFailed, op.stage != .done { return }
        queuedPackages[package.id] = package
        operations[package.id] = Operation(stage: .queued)
        queue.append(package.id)
        startRunner()
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
        Notifier.post(title: fresh.count == 1 ? "New version of \(names)" : "\(fresh.count) app updates",
                      body: fresh.count == 1 ? "Ready to install under Apps." : names)
    }

    /// Fixture mode (`PS3CENTER_FIXTURES=1`): canned rows and README, no network.
    func loadFixture(statuses: [AppStatus] = Fixtures.appStatuses()) {
        self.statuses = statuses
        phase = .loaded
        lastChecked = Date()
        readmes[Fixtures.readme.repo] = .loaded(Fixtures.readme)
        packages = Fixtures.packages
        packageVersions = Fixtures.packageVersions
        packagesLoaded = true
        packagesChecked = true
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

    /// "Ignore": skips this release. It moves to Ignored and comes back when a newer one is out.
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

    // MARK: Update All

    /// What the review before "Update All" shows.
    func updatePlan() -> UpdatePlan {
        UpdatePlan(statuses)
    }

    /// "02.40 → 02.41", in the same APP_VER form as the Updates list (`AppStatus.versionChange`).
    static func versionChange(_ status: AppStatus) -> String {
        status.versionChange
    }

    /// Runs the reviewed plan: queues the chosen updates and keeps the rest for the report.
    func updateAll(_ chosen: [AppStatus], from plan: UpdatePlan) {
        guard batch == nil, !chosen.isEmpty else { return }
        let pending = Set(installableUpdates.map(\.id).filter { operations[$0]?.stage != .done })
        let started = UpdateBatch(plan: plan, chosen: chosen, pending: pending)
        guard !started.queued.isEmpty else {
            report = started.report([:])
            return
        }
        batch = started
        report = nil
        started.queued.forEach(install)
    }

    func dismissReport() {
        report = nil
    }

    /// Called when the queue is empty: turns the batch into the report.
    private func finishBatch() {
        guard let batch else { return }
        self.batch = nil
        var outcomes: [String: UpdateBatch.Outcome] = [:]
        for line in batch.installs {
            switch operations[line.id]?.stage {
            case .done: outcomes[line.id] = .done
            case .failed(let message): outcomes[line.id] = .failed(message)
            default: break
            }
        }
        let report = batch.report(outcomes)
        self.report = report
        let done = report.done, failed = report.failed
        let title = failed.isEmpty && done.count == 1 ? "\(done[0].name) is updated"
            : "\(done.count) of \(batch.installs.count) updates done"
        Notifier.post(title: title, body: failed.isEmpty ? "Everything went fine." : "Failed: " + failed.map(\.name).joined(separator: ", "))
    }

    /// Fixture mode: the report after an "Update All" with one of each outcome.
    func loadFixtureReport() {
        let byID = Dictionary(uniqueKeysWithValues: statuses.map { ($0.id, $0) })
        func line(_ id: String, _ detail: (AppStatus) -> String) -> [UpdateReport.Line] {
            guard let status = byID[id] else { return [] }
            return [UpdateReport.Line(id: id, name: status.name, detail: detail(status))]
        }
        report = UpdateReport(
            done: line("apollo", Self.versionChange),
            failed: line("webman") { _ in "The connection to the PS3 dropped during the upload" },
            skipped: line("hen", \.skipReason) + line("artemis") { _ in "Ignored" },
            finished: Date())
    }

    /// "Install Anyway": restarts the waiting install without waiting for the game to end.
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
        if let package = queuedPackages[id] {
            await perform(package)
            return
        }
        guard let host, let entry = Catalog.entries.first(where: { $0.id == id }) else { return }
        guard let root = MirrorRoot.resolve() else {
            archiveMissing = true
            operations[id] = Operation(stage: .failed("Choose the PS3 folder first"))
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
            try? await WebMAN(host: host).popup("\(entry.name) installed from the Mac")
        } catch is CancellationError {
            // forceWaiting() re-queued it.
        } catch {
            operations[id] = Operation(stage: .failed(ConsoleErrorCode.annotate(error.localizedDescription)))
        }
    }

    /// A package from the Mac: uploaded and installed, and left in its folder.
    private func perform(_ package: LocalPackage) async {
        guard let host else {
            operations[package.id] = Operation(stage: .failed("The PS3 isn't connected"))
            return
        }
        var options = TransferOptions()
        options.force = forceNext
        forceNext = false
        operations[package.id] = Operation(stage: .uploading(0))
        do {
            try await AppsService(host: host).installOwnPackage(package.url, options: options) { event in
                Task { @MainActor [weak self] in self?.handle(event, for: package.id) }
            }
            operations[package.id] = Operation(stage: .done)
            try? await WebMAN(host: host).popup("\(package.title) installed from the Mac")
        } catch is CancellationError {
            // forceWaiting() re-queued it.
        } catch {
            operations[package.id] = Operation(stage: .failed(ConsoleErrorCode.annotate(error.localizedDescription)))
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
        panel.prompt = "Choose"
        panel.message = "Choose the PS3 folder (the one with dev_hdd0/ and _Installed/)."
        guard panel.runModal() == .OK, let url = panel.url, MirrorRoot.looksLikeMirror(url) else { return }
        guard (try? ConfigStore.edit({ $0.root = url.path })) != nil else { return }
        archiveMissing = false
        for (id, op) in operations { if case .failed = op.stage { operations[id] = nil } }
    }
}
