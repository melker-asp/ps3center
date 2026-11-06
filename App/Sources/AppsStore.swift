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

    private(set) var phase: Phase = .idle
    private(set) var statuses: [AppStatus] = []
    private(set) var icons: [String: NSImage] = [:]
    /// XMB backgrounds (PIC1.PNG) of installed apps, for the detail page's banner.
    private(set) var backgrounds: [String: NSImage] = [:]
    private var backgroundsTried: Set<String> = []
    private(set) var operations: [String: Operation] = [:]
    private(set) var lastChecked: Date?
    /// READMEs by repo, fetched when a program's detail page opens.
    private(set) var readmes: [String: ReadmeState] = [:]
    /// The program whose detail page is open in the Apps tab.
    var selectedID: String?
    var archiveMissing = false

    /// The .pkg files in the Mac's package folders (Från Macen).
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

    var updates: [AppStatus] { statuses.filter { $0.state == .updateAvailable } }
    var current: [AppStatus] { statuses.filter { $0.state == .upToDate } }
    var manual: [AppStatus] { statuses.filter { $0.state == .manual || $0.state == .error } }
    var available: [AppStatus] { statuses.filter { $0.installed == nil && $0.installable } }
    var installableUpdates: [AppStatus] { updates.filter(\.canInstall) }

    var waitingGame: String? {
        for op in operations.values { if case .waitingForGame(let game) = op.stage { return game } }
        return nil
    }

    var isBusy: Bool { runner != nil }

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
        let fresh = next.filter { $0.state == .updateAvailable && !seen.contains("\($0.id) \($0.latest ?? "")") }
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
        guard operations[status.id].map({ if case .failed = $0.stage { return true } else { return false } }) ?? true else { return }
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

    func updateAll() {
        installableUpdates.forEach(install)
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

    /// A package from the Mac: uploaded and installed, and left in its folder.
    private func perform(_ package: LocalPackage) async {
        guard let host else {
            operations[package.id] = Operation(stage: .failed("PS3:an är inte ansluten"))
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
            try? await WebMAN(host: host).popup("\(package.title) installerat från Macen")
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
