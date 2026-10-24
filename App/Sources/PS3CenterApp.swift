import SwiftUI

@main
struct PS3CenterApp: App {
    @State private var console = ConsoleStore()
    @State private var apps = AppsStore()
    @State private var games = GamesStore()
    @State private var transfers = TransferStore()
    @State private var netServer = NetServerStore()
    @State private var appearance = AppearanceStore()

    var body: some Scene {
        WindowGroup("PS3 Center") {
            ContentView()
                .environment(console)
                .environment(apps)
                .environment(games)
                .environment(transfers)
                .environment(netServer)
                .environment(appearance)
                .frame(minWidth: 980, minHeight: 680)
                .preferredColorScheme(.dark)
                .task {
                    if Snapshot.usesFixtures {
                        console.loadFixture()
                        apps.loadFixture()
                        games.loadFixture()
                        transfers.loadFixture()
                        netServer.loadFixture()
                    } else {
                        console.start()
                        netServer.start()
                    }
                    if let directory = Snapshot.directory {
                        await Snapshot.run(console: console, apps: apps, games: games, transfers: transfers, netServer: netServer, into: directory)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 820)
    }
}
