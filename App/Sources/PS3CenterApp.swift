import SwiftUI

@main
struct PS3CenterApp: App {
    @State private var console = ConsoleStore()
    @State private var apps = AppsStore()
    @State private var appearance = AppearanceStore()

    var body: some Scene {
        WindowGroup("PS3 Center") {
            ContentView()
                .environment(console)
                .environment(apps)
                .environment(appearance)
                .frame(minWidth: 980, minHeight: 680)
                .preferredColorScheme(.dark)
                .task {
                    if Snapshot.usesFixtures {
                        console.loadFixture()
                        apps.loadFixture()
                    } else {
                        console.start()
                    }
                    if let directory = Snapshot.directory {
                        await Snapshot.run(console: console, apps: apps, into: directory)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 820)
    }
}
