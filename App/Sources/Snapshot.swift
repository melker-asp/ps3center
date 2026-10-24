import AppKit
import SwiftUI

/// `PS3CENTER_SNAPSHOT_DIR=/some/dir open "PS3 Center.app"` renders each tab to PNG and quits.
/// Uses ImageRenderer, so it needs no screen-recording permission (useful in CI and when
/// checking the design without looking at the screen).
@MainActor
enum Snapshot {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["PS3CENTER_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func run(console: ConsoleStore, apps: AppsStore, into directory: URL) async {
        // Wait for live data (the console must be reachable).
        // A few samples so the sparklines have something to draw.
        for _ in 0..<80 where console.cpuHistory.count < 6 {
            try? await Task.sleep(for: .milliseconds(500))
        }
        if let host = console.host { await apps.load(host: host) }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        render(.status, name: "status", console: console, apps: apps, into: directory) { StatusView(scrolls: false) }
        render(.apps, name: "apps-updates", console: console, apps: apps, into: directory) { AppsView(section: .updates, scrolls: false) }
        render(.apps, name: "apps-get", console: console, apps: apps, into: directory) { AppsView(section: .get, scrolls: false) }
        NSApp.terminate(nil)
    }

    private static func render<Content: View>(_ tab: MainTab, name: String, console: ConsoleStore, apps: AppsStore,
                                              into directory: URL, @ViewBuilder content: () -> Content) {
        let view = ZStack(alignment: .top) {
            Theme.background(for: tab)
            VStack(spacing: 0) {
                TabBar(selection: .constant(tab))
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
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
