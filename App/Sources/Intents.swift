import AppIntents
import Foundation
import PS3Kit

// Shortcuts and Spotlight: the same PS3Kit calls as the CLI and the window.

struct PS3StatusIntent: AppIntent {
    static let title: LocalizedStringResource = "PS3 Status"

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let host = try await ConsoleLocator.resolve()
        let s = try await WebMAN(host: host).snapshot()
        var parts = ["CPU \(s.cpuTemp.map(String.init) ?? "–") °C, RSX \(s.rsxTemp.map(String.init) ?? "–") °C, fan \(s.fanPercent.map(String.init) ?? "–") %"]
        parts.append(s.isGameRunning ? "Playing \(s.mountedGameName ?? "a game")" : "In the XMB")
        if let free = s.freeBytes { parts.append("\(Format.bytes(free)) free") }
        let text = parts.joined(separator: ". ") + "."
        return .result(dialog: "\(text)")
    }
}

struct PlayGameIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Game on PS3"

    @Parameter(title: "Game")
    var name: String

    @Parameter(title: "Quit the Running Game", default: false)
    var exitingRunning: Bool

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let host = try await ConsoleLocator.resolve()
        let service = GameLibraryService(host: host)
        let games = try await service.scan()
        switch Game.lookup(name, in: games) {
        case .found(let game):
            try await service.play(game, exitingRunning: exitingRunning)
            return .result(dialog: "Starting \(game.title).")
        case .ambiguous(let matches):
            throw PS3Error.refused("Several games match: " + matches.prefix(4).map(\.title).joined(separator: ", ") + ".")
        case .missing:
            throw PS3Error.refused("Found no game called \(name).")
        }
    }
}

struct ShutdownPS3Intent: AppIntent {
    static let title: LocalizedStringResource = "Shut Down PS3"

    @Parameter(title: "Even If a Game Is Running", default: false)
    var force: Bool

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let host = try await ConsoleLocator.resolve()
        let webMAN = WebMAN(host: host)
        let running = try await webMAN.isGameRunning()
        if running, !force {
            throw PS3Error.refused("A game is running. Save and quit it first, or turn on \u{201C}Even If a Game Is Running\u{201D}.")
        }
        try await webMAN.shutdown()
        return .result(dialog: "The PS3 is shutting down.")
    }
}

/// Opens the window with the send review, as when files are dropped on it.
struct SendToPS3Intent: AppIntent {
    static let title: LocalizedStringResource = "Send to PS3"
    static let openAppWhenRun = true

    @Parameter(title: "Files")
    var files: [IntentFile]

    @MainActor
    func perform() async throws -> some IntentResult {
        Inbox.shared.receive(files.compactMap(\.fileURL))
        return .result()
    }
}

struct PS3Shortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PS3StatusIntent(), phrases: ["PS3 status in \(.applicationName)", "How is the PS3 in \(.applicationName)"],
                    shortTitle: "PS3 Status", systemImageName: "gauge.medium")
        AppShortcut(intent: ShutdownPS3Intent(), phrases: ["Shut down the PS3 with \(.applicationName)"],
                    shortTitle: "Shut Down PS3", systemImageName: "power")
    }
}
