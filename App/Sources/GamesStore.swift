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
        enum Kind { case starting, mounting, unmounting, exiting, deleting }
        let id: String
        let kind: Kind

        var label: String {
            switch kind {
            case .starting: return "Startar…"
            case .mounting: return "Monterar…"
            case .unmounting: return "Avmonterar…"
            case .exiting: return "Avslutar spelet…"
            case .deleting: return "Tar bort…"
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var games: [Game] = []
    private(set) var icons: [String: NSImage] = [:]
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

    /// The games the pills and the search let through.
    var visible: [Game] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return games.filter { game in
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
        games.filter(filter.matches).count
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
            let data = await library.icons(for: next, refresh: refresh)
            icons = data.compactMapValues { NSImage(data: $0) }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Fixture mode (`PS3CENTER_FIXTURES=1`): canned games, no network.
    func loadFixture(games: [Game] = Fixtures.games) {
        self.games = games
        phase = .loaded
        lastChecked = Date()
    }

    func loadBackground(for game: Game) async {
        guard let host, !backgroundsTried.contains(game.id) else { return }
        backgroundsTried.insert(game.id)
        if let data = await GameLibraryService(host: host).background(for: game), let image = NSImage(data: data) {
            backgrounds[game.id] = image
        }
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
