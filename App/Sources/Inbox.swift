import AppKit
import Observation
import PS3Kit
import ServiceManagement
import SwiftUI

/// Files to send that come from outside the window: Finder's "Send to PS3", the menu bar
/// and Shortcuts. The window picks them up and shows the same review as a drop.
@MainActor
@Observable
final class Inbox {
    static let shared = Inbox()

    private(set) var files: [URL] = []
    private(set) var revision = 0

    func receive(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        files = urls
        revision += 1
        WindowOpener.shared.showMain()
    }

    func take() -> [URL] {
        defer { files = [] }
        return files
    }
}

/// Brings the main window forward, opening it again if it was closed.
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()
    static let mainID = "main"

    /// From a view's environment (the window or the menu bar), which AppKit code cannot reach.
    var openWindow: OpenWindowAction?

    func showMain() {
        NSApp.activate()
        let window = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(Self.mainID) == true }
        if let window, window.isVisible || window.isMiniaturized {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        } else if let openWindow {
            openWindow(id: Self.mainID)
        } else {
            window?.makeKeyAndOrderFront(nil)
        }
    }
}

/// Finder's "Send to PS3" (Services menu and Quick Actions), declared as NSServices in
/// project.yml.
@MainActor
final class ServiceProvider: NSObject {
    @objc func sendToPS3(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        Inbox.shared.receive(urls)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services = ServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
    }

    /// The menu bar keeps the game server and the queue going when the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// "Launch at Login", as a login item for the app itself.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Nil when it worked, else why not (an app that is not in Programmappen, for one).
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return "Couldn't change it: \(error.localizedDescription). Put PS3 Center in Applications and try again."
        }
    }
}
