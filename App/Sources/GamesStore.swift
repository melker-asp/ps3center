import AppKit
import Foundation
import Observation
import PS3Kit

/// Backs the Spel tab: the games on the console, their XMB icons and backgrounds, and the
/// actions on them (start, mount, quit, remove), one at a time.
@MainActor
@Observable
final class GamesStore {
    enum Phase: Equatable {
        case idle, loading, loaded, failed(String)
    }

    /// The pills above the grid. PS3 covers disc and PSN games; Film covers Blu-ray and DVD.
    enum Filter: String, CaseIterable, Identifiable {
        case all, ps3, ps2, ps1, psp, film

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "Alla"
            case .ps3: return "PS3"
            case .ps2: return "PS2"
            case .ps1: return "PS1"
            case .psp: return "PSP"
            case .film: return "Film"
            }
        }

        func matches(_ game: Game) -> Bool {
            switch self {
            case .all: return true
            case .ps3: return game.platform == .ps3 || game.platform == .psn
            case .ps2: return game.platform == .ps2
            case .ps1: return game.platform == .ps1
            case .psp: return game.platform == .psp
            case .film: return game.platform == .bluRay || game.platform == .dvd
            }
        }
    }

    /// What is happening to a game right now, shown instead of its buttons.
    struct Busy: Equatable {
        enum Kind { case starting, mounting, unmounting, exiting, deleting, updating }
        let id: String
        let kind: Kind
        /// For updates: what is happening ("Hämtar 02.12") and how far it has come.
        var step: String?
        var progress: Double?

        var label: String {
            if let step { return step }
            switch kind {
            case .starting: return "Startar…"
            case .mounting: return "Monterar…"
            case .unmounting: return "Avmonterar…"
            case .exiting: return "Avslutar spelet…"
            case .deleting: return "Tar bort…"
            case .updating: return "Uppdaterar…"
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var games: [Game] = []
    private(set) var icons: [String: NSImage] = [:]
    /// Box art from CoverService, by game id.
    private(set) var covers: [String: NSImage] = [:]
    /// Official updates newer than what each game has, by game id (after "Sök uppdateringar").
    private(set) var patches: [String: [GamePatch]] = [:]
    private(set) var isCheckingUpdates = false
    private(set) var updatesChecked: Date?
    /// XMB backgrounds (PIC1.PNG), fetched when a game's page opens.
    private(set) var backgrounds: [String: NSImage] = [:]
    private var backgroundsTried: Set<String> = []
    private(set) var lastChecked: Date?
    private(set) var isLoading = false
    private(set) var busy: Busy?
    /// The last failed action per game, shown on its page until the next action.
    private(set) var failures: [String: String] = [:]
    var filter: Filter = .all
    var search = ""
    /// The game whose page is open in the Spel tab.
    var selectedID: String?
    private var host: String?

    // MARK: The Mac's games

    /// Which library the tab shows: the console's games or the Mac's game folders.
    var source: Game.Source = .console
    private(set) var macGames: [Game] = []
    /// Whether each Mac game is on the console, by game id.
    private(set) var macStates: [String: MacGameState] = [:]
    private(set) var isLoadingMac = false
    private(set) var macLoaded = false
    /// Mac games picked for sending, by id.
    var selection: Set<String> = []

    var selectedMacGames: [Game] { macGames.filter { selection.contains($0.id) } }
    var selectedSize: Int64 { selectedMacGames.compactMap(\.size).reduce(0, +) }

    func loadMac() async {
        isLoadingMac = true
        defer { isLoadingMac = false }
        let scanned = await Task.detached { LocalLibrary().scan() }.value
        macGames = scanned
        macLoaded = true
        macStates = LibraryMatch.states(mac: scanned, console: games)
        selection = selection.filter { id in scanned.contains { $0.id == id } }
        for game in scanned {
            if let path = game.iconPath, let image = NSImage(contentsOfFile: path) { icons[game.id] = image }
        }
        let files = await CoverService().covers(for: scanned)
        for (id, file) in files {
            if let image = NSImage(contentsOf: file) { covers[id] = image }
        }
    }

    /// Starts a Mac game through the game server, as webMAN sees it (/net0/PS3ISO/…).
    func playFromMac(_ game: Game, exitingRunning: Bool) {
        guard let netPath = game.netPath else { return }
        var net = game
        net.path = "/net0" + netPath
        net.source = .console
        perform(.starting, on: game) { try await $0.play(net, exitingRunning: exitingRunning) }
    }

    func toggleSelection(_ game: Game) {
        if selection.contains(game.id) { selection.remove(game.id) } else { selection.insert(game.id) }
    }

    /// The games the pills and the search let through, from the library being shown.
    var shown: [Game] { source == .console ? games : macGames }

    var visible: [Game] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return shown.filter { game in
            filter.matches(game) && (query.isEmpty
                || game.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || game.titleID?.range(of: query, options: .caseInsensitive) != nil)
        }
    }

    var selected: Game? {
        guard let selectedID else { return nil }
        return games.first { $0.id == selectedID }
    }

    func count(_ filter: Filter) -> Int {
        shown.filter(filter.matches).count
    }

    func load(host: String, refresh: Bool = false) async {
        self.host = host
        if games.isEmpty { phase = .loading }
        isLoading = true
        defer { isLoading = false }
        do {
            let library = GameLibraryService(host: host)
            let next = try await library.scan(refresh: refresh)
            games = next
            phase = .loaded
            lastChecked = Date()
            if macLoaded { macStates = LibraryMatch.states(mac: macGames, console: next) }
            let data = await library.icons(for: next, refresh: refresh)
            icons = data.compactMapValues { NSImage(data: $0) }
            let files = await CoverService().covers(for: next, refresh: refresh)
            covers = files.compactMapValues { NSImage(contentsOf: $0) }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Fixture mode (`PS3CENTER_FIXTURES=1`): canned games, no network.
    func loadFixture(games: [Game] = Fixtures.games) {
        self.games = games
        phase = .loaded
        lastChecked = Date()
        patches = Fixtures.patches
        updatesChecked = Date()
        macGames = Fixtures.macGames
        macStates = LibraryMatch.states(mac: macGames, console: games)
        macLoaded = true
    }

    func loadBackground(for game: Game) async {
        guard let host, !backgroundsTried.contains(game.id) else { return }
        backgroundsTried.insert(game.id)
        if let data = await GameLibraryService(host: host).background(for: game), let image = NSImage(data: data) {
            backgrounds[game.id] = image
        }
    }

    // MARK: Covers and updates

    /// A picture dropped on a game's page becomes its cover.
    func setCustomCover(from file: URL, for game: Game) {
        guard let data = try? Data(contentsOf: file), let image = NSImage(data: data) else { return }
        do {
            try CoverService().setCustomCover(data, for: game)
            covers[game.id] = image
        } catch {
            failures[game.id] = error.localizedDescription
        }
    }

    /// Asks Sony's update server which PS3 and PSN games have newer patches.
    func checkUpdates(refresh: Bool = false) async {
        guard let host, !isCheckingUpdates else { return }
        isCheckingUpdates = true
        defer { isCheckingUpdates = false }
        patches = await GameUpdateService(host: host).check(games, refresh: refresh)
        updatesChecked = Date()
    }

    var updateCount: Int { patches.count }

    func installUpdates(for game: Game) {
        guard let host, busy == nil, let pending = patches[game.id], !pending.isEmpty else { return }
        busy = Busy(id: game.id, kind: .updating)
        failures[game.id] = nil
        Task {
            do {
                try await GameUpdateService(host: host).install(pending, for: game, options: TransferOptions()) { event in
                    Task { @MainActor [weak self] in self?.handleUpdate(event, for: game.id) }
                }
                self.patches[game.id] = nil
                if let index = self.games.firstIndex(where: { $0.id == game.id }), let last = pending.last {
                    self.games[index].updateVersion = last.version
                }
            } catch {
                self.failures[game.id] = error.localizedDescription
            }
            self.busy = nil
        }
    }

    private func handleUpdate(_ event: TransferEvent, for id: String) {
        guard var current = busy, current.id == id else { return }
        switch event {
        case .started(let route, _):
            current.step = route.remote.hasPrefix("http") ? "Hämtar från Sony…" : "Skickar till PS3:an…"
            current.progress = 0
        case .progress(let route, let sent, let total, _):
            let fraction = total > 0 ? Double(sent) / Double(total) : 0
            current.step = (route.remote.hasPrefix("http") ? "Hämtar " : "Skickar ") + "\(Int(fraction * 100)) %"
            current.progress = fraction
        case .waitingForGame:
            current.step = "Väntar tills spelet avslutas…"
            current.progress = nil
        case .installing:
            current.step = "Installerar…"
            current.progress = nil
        default:
            return
        }
        busy = current
    }

    // MARK: Actions

    func play(_ game: Game, exitingRunning: Bool) {
        perform(.starting, on: game) { try await $0.play(game, exitingRunning: exitingRunning) }
    }

    func mount(_ game: Game, exitingRunning: Bool) {
        perform(.mounting, on: game) { try await $0.mount(game, exitingRunning: exitingRunning) }
    }

    func unmount(_ game: Game) {
        perform(.unmounting, on: game) { try await $0.unmount() }
    }

    func exitGame(_ game: Game) {
        perform(.exiting, on: game) { _ = try await $0.exitGame() }
    }

    func delete(_ game: Game) {
        guard let host, busy == nil else { return }
        busy = Busy(id: game.id, kind: .deleting)
        failures[game.id] = nil
        Task {
            do {
                try await GameLibraryService(host: host).delete(game, options: TransferOptions()) { _ in }
                self.games.removeAll { $0.id == game.id }
                self.selectedID = nil
            } catch {
                self.failures[game.id] = error.localizedDescription
            }
            self.busy = nil
        }
    }

    private func perform(_ kind: Busy.Kind, on game: Game, _ action: @escaping @Sendable (GameLibraryService) async throws -> Void) {
        guard let host, busy == nil else { return }
        busy = Busy(id: game.id, kind: kind)
        failures[game.id] = nil
        Task {
            do {
                try await action(GameLibraryService(host: host))
            } catch {
                self.failures[game.id] = error.localizedDescription
            }
            self.busy = nil
        }
    }
}
