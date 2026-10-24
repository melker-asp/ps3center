import SwiftUI

@main
struct PS3CenterApp: App {
    @State private var console = ConsoleStore()
    @State private var apps = AppsStore()

    var body: some Scene {
        WindowGroup("PS3 Center") {
            ContentView()
                .environment(console)
                .environment(apps)
                .frame(minWidth: 980, minHeight: 680)
                .preferredColorScheme(.dark)
                .task {
                    console.start()
                    if let directory = Snapshot.directory {
                        await Snapshot.run(console: console, apps: apps, into: directory)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 820)
    }
}
