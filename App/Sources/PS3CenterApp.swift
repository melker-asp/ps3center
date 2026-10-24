import SwiftUI

@main
struct PS3CenterApp: App {
    @State private var console = ConsoleStore()
    @State private var apps = AppsStore()
    @State private var games = GamesStore()
    @State private var transfers = TransferStore()
    @State private var appearance = AppearanceStore()

    var body: some Scene {
        WindowGroup("PS3 Center") {
            ContentView()
                .environment(console)
                .environment(apps)
                .environment(games)
                .environment(transfers)
                .environment(appearance)
                .frame(minWidth: 980, minHeight: 680)
                .preferredColorScheme(.dark)
                .task {
                    if Snapshot.usesFixtures {
                        console.loadFixture()
                        apps.loadFixture()
                        games.loadFixture()
                        transfers.loadFixture()
                    } else {
                        console.start()
                    }
                    if let directory = Snapshot.directory {
                        await Snapshot.run(console: console, apps: apps, games: games, transfers: transfers, into: directory)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 820)
    }
}
