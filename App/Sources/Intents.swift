import AppIntents
import Foundation
import PS3Kit

// Genvägar (Shortcuts) and Spotlight: the same PS3Kit calls as the CLI and the window.

struct PS3StatusIntent: AppIntent {
    static let title: LocalizedStringResource = "PS3-status"

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let host = try await ConsoleLocator.resolve()
        let s = try await WebMAN(host: host).snapshot()
        var parts = ["CPU \(s.cpuTemp.map(String.init) ?? "–") °C, RSX \(s.rsxTemp.map(String.init) ?? "–") °C, fläkt \(s.fanPercent.map(String.init) ?? "–") %"]
        parts.append(s.isGameRunning ? "Spelar \(s.mountedGameName ?? "ett spel")" : "I XMB:n")
        if let free = s.freeBytes { parts.append("\(Format.bytes(free)) ledigt") }
        let text = parts.joined(separator: ". ") + "."
        return .result(dialog: "\(text)")
    }
}

struct PlayGameIntent: AppIntent {
    static let title: LocalizedStringResource = "Starta spel på PS3:an"

    @Parameter(title: "Spel")
    var name: String

    @Parameter(title: "Avsluta spelet som körs", default: false)
    var exitingRunning: Bool

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let host = try await ConsoleLocator.resolve()
        let service = GameLibraryService(host: host)
        let games = try await service.scan()
        switch Game.lookup(name, in: games) {
        case .found(let game):
            try await service.play(game, exitingRunning: exitingRunning)
            return .result(dialog: "Startar \(game.title).")
        case .ambiguous(let matches):
            throw PS3Error.refused("Flera spel passar: " + matches.prefix(4).map(\.title).joined(separator: ", ") + ".")
        case .missing:
            throw PS3Error.refused("Hittade inget spel som heter \(name).")
        }
    }
}

struct ShutdownPS3Intent: AppIntent {
    static let title: LocalizedStringResource = "Stäng av PS3:an"

    @Parameter(title: "Även om ett spel körs", default: false)
    var force: Bool

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let host = try await ConsoleLocator.resolve()
        let webMAN = WebMAN(host: host)
        let running = try await webMAN.isGameRunning()
        if running, !force {
            throw PS3Error.refused("Ett spel körs. Spara och avsluta det först, eller slå på \u{201D}Även om ett spel körs\u{201D}.")
        }
        try await webMAN.shutdown()
        return .result(dialog: "PS3:an stängs av.")
    }
}

/// Opens the window with the send review, as when files are dropped on it.
struct SendToPS3Intent: AppIntent {
    static let title: LocalizedStringResource = "Skicka till PS3"
    static let openAppWhenRun = true

    @Parameter(title: "Filer")
    var files: [IntentFile]

    @MainActor
    func perform() async throws -> some IntentResult {
        Inbox.shared.receive(files.compactMap(\.fileURL))
        return .result()
    }
}

struct PS3Shortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PS3StatusIntent(), phrases: ["Status för PS3:an i \(.applicationName)", "Hur mår PS3:an i \(.applicationName)"],
                    shortTitle: "PS3-status", systemImageName: "gauge.medium")
        AppShortcut(intent: ShutdownPS3Intent(), phrases: ["Stäng av PS3:an med \(.applicationName)"],
                    shortTitle: "Stäng av PS3:an", systemImageName: "power")
    }
}
