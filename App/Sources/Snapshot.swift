import AppKit
import PS3Kit
import SwiftUI

/// `PS3CENTER_SNAPSHOT_DIR=/some/dir open "PS3 Center.app"` renders each tab to PNG and quits.
/// Uses ImageRenderer, so it needs no screen-recording permission (useful in CI and when
/// checking the design without looking at the screen). With `PS3CENTER_FIXTURES=1` the app
/// uses canned data from PS3Kit's `Fixtures` instead of a console, which is how CI renders.
@MainActor
enum Snapshot {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["PS3CENTER_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static var usesFixtures: Bool {
        ProcessInfo.processInfo.environment["PS3CENTER_FIXTURES"] == "1"
    }

    static func run(console: ConsoleStore, apps: AppsStore, games: GamesStore, transfers: TransferStore, netServer: NetServerStore,
                    maintenance: MaintenanceStore, into directory: URL) async {
        if !usesFixtures {
            // Wait for live data (the console must be reachable).
            // A few samples so the sparklines have something to draw.
            for _ in 0..<80 where console.cpuHistory.count < 6 {
                try? await Task.sleep(for: .milliseconds(500))
            }
            if let host = console.host {
                await apps.load(host: host)
                await games.load(host: host)
            }
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        render(.status, name: "connecting", console: ConsoleStore(), apps: apps, games: games, transfers: transfers, netServer: netServer, maintenance: maintenance, into: directory, splash: true) {
            ConnectionView().frame(height: 640)
        }

        let henOff = ConsoleStore()
        henOff.loadHenOffFixture()
        render(.status, name: "connecting-hen", console: henOff, apps: apps, games: games, transfers: transfers, netServer: netServer, maintenance: maintenance, into: directory, splash: true) {
            ConnectionView().frame(height: 640)
        }

        render(.status, name: "status", console: console, apps: apps, games: games, transfers: transfers, netServer: netServer, maintenance: maintenance, into: directory) { StatusView(scrolls: false) }
        render(.games, name: "games", console: console, apps: apps, games: games, transfers: transfers, netServer: netServer, maintenance: maintenance, into: directory) { GamesView(scrolls: false) }
        // Sorted by Senast tillagt: one list across platforms, with the dates. The viewer's own
        // choice is put back afterwards.
        let savedOrder = UserDefaults.standard.string(forKey: "gamesOrder")
        UserDefaults.standard.set(GameOrder.added.rawValue, forKey: "gamesOrder")
        render(.games, name: "games-added", console: console, apps: apps, games: games, transfers: transfers, netServer: netServer, maintenance: maintenance, into: directory) { GamesView(scrolls: false) }
        UserDefaults.standard.set(savedOrder, forKey: "gamesOrder")
        // Gran Turismo 5 has an update installed; live, the first game.
        if let game = games.games.first(where: { $0.titleID == "BCES00569" }) ?? games.games.first {
            games.selectedID = game.id
            render(.games, name: "games-detail", console: console, apps: apps, games: games, transfers: transfers, netServer: netServer, maintenance: maintenance, into: directory) { GamesView(scrolls: false) }
            games.selectedID = nil
        }
        // An installed game (Journey in the fixtures): Avinstallera instead of Ta bort.
        if let installed = games.games.first(where: \.isInstalled) {
            games.selectedID = installed.id
            render(.games, name: "games-detail-installed", console: console, apps: apps, games: games, transfers: transfers, netServer: netServer, maintenance: maintenance, into: directory) { GamesView(scrolls: false) }
            games.selectedID = nil
        }
        // A PS2 ISO on HEN (Shadow of the Colossus in the fixtures): it will not start there.
        if let ps2 = games.games.first(where: { $0.platform == .ps2 }) {
            await games.checkCompatibility(of: ps2, console: console.snapshot.map(ConsoleProfile.init(snapshot:)))
            games.selectedID = ps2.id
            render(.games, name: "games-detail-ps2", console: console, apps: apps, games: games, transfers: transfers, netServer: netServer, maintenance: maintenance, into: directory) { GamesView(scrolls: false) }
            games.selectedID = nil
        }
        // A copied disc in GAMES (Demon's Souls), checked against its IRD.
        if let copy = games.games.first(where: { $0.platform == .ps3 && $0.isFolder && !$0.isInstalled }) {
            games.selectedID = copy.id
            render(.games, name: "games-detail-ird", console: console, apps: apps, games: games, transfers: transfers, netServer: netServer, maintenance: maintenance, into: directory) { GamesView(scrolls: false) }
            games.selectedID = nil
        }
        // The Mac's library with two games picked for sending.
        games.source = .mac
        games.selection = Set(games.macGames.filter { games.macStates[$0.id] == .notOnConsole }.prefix(2).map(\.id))
        render(.games, name: "games-mac", console: console, apps: apps, games: games, transfers: transfers, netServer: netServer, maintenance: maintenance, into: directory) { GamesView(scrolls: false) }
        games.source = .console
        games.selection = []
        write(FoldersView(live: false), name: "folders", into: directory)
        write(TransfersView(scrolls: false).environment(console).environment(transfers), name: "transfers", into: directory)
        write(NetServerView().environment(console).environment(netServer), name: "netserver", into: directory)
        write(RemoteView(live: false).environment(console), name: "remote", into: directory)
        write(SavesView(live: false).environment(maintenance), name: "saves", into: directory)
        write(MenuBarView(background: Theme.base).environment(console).environment(apps).environment(transfers).environment(netServer),
              name: "menubar", into: directory)
        render(.maintenance, name: "maintenance", console: console, apps: apps, games: games, transfers: transfers, netServer: netServer, maintenance: maintenance, into: directory) {
            MaintenanceView(scrolls: false)
        }
        render(.apps, name: "apps-updates", console: console, apps: apps, games: games, transfers: transfers, netServer: netServer, maintenance: maintenance, into: directory) { AppsView(section: .updates, scrolls: false) }
        // The review before "Uppdatera alla", and in the fixtures the report afterwards.
        write(UpdateReviewView(plan: apps.updatePlan(), scrolls: false).environment(console).environment(apps), name: "apps-review", into: directory)
        if usesFixtures {
            apps.loadFixtureReport()
            render(.apps, name: "apps-report", console: console, apps: apps, games: games, transfers: transfers, netServer: netServer, maintenance: maintenance, into: directory) { AppsView(section: .updates, scrolls: false) }
            apps.dismissReport()
        }
        render(.apps, name: "apps-get", console: console, apps: apps, games: games, transfers: transfers, netServer: netServer, maintenance: maintenance, into: directory) { AppsView(section: .get, scrolls: false) }
        if let entry = Catalog.entry(named: "apollo") {
            apps.selectedID = entry.id
            await apps.loadReadme(for: entry)
            render(.apps, name: "apps-detail", console: console, apps: apps, games: games, transfers: transfers, netServer: netServer, maintenance: maintenance, into: directory) { AppsView(scrolls: false) }
            apps.selectedID = nil
        }
        if usesFixtures {
            // The same console on CFW: PS3 Health is untested there, HEN does not apply.
            console.loadFixture(Fixtures.cfwSnapshot)
            apps.loadFixture(statuses: Fixtures.appStatuses(on: Fixtures.cfwSnapshot))
            apps.selectedID = "ps3health"
            render(.apps, name: "apps-detail-cfw", console: console, apps: apps, games: games, transfers: transfers, netServer: netServer, maintenance: maintenance, into: directory) { AppsView(scrolls: false) }
            apps.selectedID = nil
            console.loadFixture()
            apps.loadFixture()
        }
        render(.status, name: "status-nova-pink", console: console, apps: apps, games: games, transfers: transfers, netServer: netServer, maintenance: maintenance, into: directory, theme: .novaPink) {
            StatusView(scrolls: false)
        }
        write(AppearanceView().environment(AppearanceStore(previewing: .perTab)), name: "appearance", into: directory)
        NSApp.terminate(nil)
    }

    private static func render<Content: View>(_ tab: MainTab, name: String, console: ConsoleStore, apps: AppsStore,
                                              games: GamesStore, transfers: TransferStore, netServer: NetServerStore, maintenance: MaintenanceStore, into directory: URL, splash: Bool = false, theme: AppTheme = .perTab,
                                              @ViewBuilder content: () -> Content) {
        let view = ZStack(alignment: .top) {
            if splash { SplashBackground() } else { Theme.background(for: tab, theme: theme) }
            VStack(spacing: 0) {
                TopBar(selection: .constant(tab)) {}
                    .padding(.top, 14)
                    .padding(.bottom, 20)
                content()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 1180)
        .environment(console)
        .environment(apps)
        .environment(games)
        .environment(transfers)
        .environment(netServer)
        .environment(maintenance)
        write(view, name: name, into: directory)
    }

    private static func write<Content: View>(_ content: Content, name: String, into directory: URL) {
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
