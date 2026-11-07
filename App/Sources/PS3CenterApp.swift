import SwiftUI

@main
struct PS3CenterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var console = ConsoleStore()
    @State private var apps = AppsStore()
    @State private var games = GamesStore()
    @State private var transfers = TransferStore()
    @State private var netServer = NetServerStore()
    @State private var maintenance = MaintenanceStore()
    @State private var appearance = AppearanceStore()
    @State private var preferences = AppPreferences()
    @State private var router = AppRouter()

    var body: some Scene {
        // One window; closed, the app keeps running in the menu bar.
        Window("PS3 Center", id: WindowOpener.mainID) {
            ContentView()
                .environment(console)
                .environment(apps)
                .environment(games)
                .environment(transfers)
                .environment(netServer)
                .environment(maintenance)
                .environment(appearance)
                .environment(preferences)
                .environment(router)
                .frame(minWidth: 980, minHeight: 680)
                .preferredColorScheme(.dark)
                .task {
                    if Snapshot.usesFixtures {
                        console.loadFixture()
                        apps.loadFixture()
                        games.loadFixture()
                        transfers.loadFixture()
                        netServer.loadFixture()
                        maintenance.loadFixture()
                    } else {
                        console.start()
                        netServer.start()
                        transfers.startWatching()
                    }
                    if let directory = Snapshot.directory {
                        await Snapshot.run(console: console, apps: apps, games: games, transfers: transfers, netServer: netServer, maintenance: maintenance, into: directory)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 820)
        .commands {
            // PS3 Center → Settings… opens the sheet in the window, as the gear does.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { router.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }

        // Settings → General → Show in Menu Bar.
        MenuBarExtra(isInserted: $preferences.showsMenuBarIcon) {
            MenuBarView()
                .environment(console)
                .environment(apps)
                .environment(transfers)
                .environment(netServer)
                .environment(router)
                .preferredColorScheme(.dark)
        } label: {
            Image(systemName: "playstation.logo")
        }
        .menuBarExtraStyle(.window)
    }
}
