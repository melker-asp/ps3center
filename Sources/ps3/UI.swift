import Foundation
import PS3Kit

/// Terminal output in Mole's style: ➤ section headers, ✓ ◎ → ✗ markers, one-line progress bars.
enum UI {
    static let isTTY = isatty(STDOUT_FILENO) == 1
    static let useColor = isTTY && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    enum Color: String {
        case reset = "0", bold = "1", dim = "2", red = "31", green = "32", yellow = "33", blue = "34", cyan = "36", gray = "90"
    }

    static func paint(_ text: String, _ colors: Color...) -> String {
        guard useColor else { return text }
        return "\u{1B}[" + colors.map(\.rawValue).joined(separator: ";") + "m" + text + "\u{1B}[0m"
    }

    static func header(_ title: String, detail: String? = nil) {
        var line = paint("➤ ", .cyan) + paint(title, .bold)
        if let detail { line += "  " + paint(detail, .gray) }
        print(line)
    }

    static func ok(_ text: String) { print("  " + paint("✓", .green) + " " + text) }
    static func skip(_ text: String) { print("  " + paint("◎", .gray) + " " + paint(text, .gray)) }
    static func step(_ text: String) { print("  " + paint("→", .cyan) + " " + text) }
    static func warn(_ text: String) { print("  " + paint("!", .yellow) + " " + paint(text, .yellow)) }
    static func fail(_ text: String) { print("  " + paint("✗", .red) + " " + text) }

    /// "1 game", "3 games".
    static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)" + (n == 1 ? "" : "s") }

    static func row(_ label: String, _ value: String, width: Int = 12) {
        print("  " + paint(label.padding(toLength: width, withPad: " ", startingAt: 0), .gray) + value)
    }

    static func bar(_ fraction: Double, width: Int = 24, color: Color = .green) -> String {
        let clamped = max(0, min(1, fraction.isFinite ? fraction : 0))
        let filled = Int((clamped * Double(width)).rounded())
        return paint(String(repeating: "█", count: filled), color) + paint(String(repeating: "░", count: width - filled), .gray)
    }

    /// Redraws the current line (progress), only on a terminal.
    static func progress(_ text: String) {
        guard isTTY else { return }
        FileHandle.standardOutput.write(Data(("\r\u{1B}[2K  " + text).utf8))
    }

    static func endProgress() {
        guard isTTY else { return }
        FileHandle.standardOutput.write(Data("\r\u{1B}[2K".utf8))
    }

    /// Yes/no question; `defaultYes` decides what Enter means. Non-interactive runs get the default.
    static func confirm(_ question: String, defaultYes: Bool = false) -> Bool {
        guard isatty(STDIN_FILENO) == 1 else { return defaultYes }
        print("  " + paint("?", .cyan) + " " + question + paint(defaultYes ? " [Y/n] " : " [y/N] ", .gray), terminator: "")
        fflush(stdout)
        guard let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else { return defaultYes }
        if answer.isEmpty { return defaultYes }
        return ["y", "yes", "j", "ja"].contains(answer)
    }

    static func json<T: Encodable>(_ value: T, pretty: Bool = true) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }
}

/// Prints TransferEvents for send/install.
struct TransferPrinter {
    let dryRun: Bool
    /// What a finished file is: "uploaded" to the console, "copied" to a USB drive.
    var done = "uploaded"

    func handle(_ event: TransferEvent) {
        switch event {
        case .checking:
            break
        case .skipped(let route, let reason):
            UI.skip("\(route.local.lastPathComponent): \(reason)")
        case .started(let route, let offset):
            let target = UI.paint(route.remote, .gray)
            if dryRun {
                UI.step("\(route.local.lastPathComponent) (\(Format.bytes(route.size - offset))) → \(target)" + (offset > 0 ? UI.paint("  resuming", .yellow) : ""))
            } else {
                let resume = offset > 0 ? " – resuming from \(Format.bytes(offset))" : ""
                UI.step("\(route.local.lastPathComponent) → \(target)\(resume)")
            }
        case .progress(let route, let sent, let total, let rate):
            let fraction = total > 0 ? Double(sent) / Double(total) : 1
            let eta = rate > 0 ? Double(total - sent) / rate : .nan
            UI.progress("\(UI.bar(fraction)) \(Int(fraction * 100))%  \(Format.bytes(sent)) of \(Format.bytes(total))  \(Format.rate(rate))  \(Format.duration(eta)) left  \(UI.paint(route.local.lastPathComponent, .gray))")
        case .finished(let route, let seconds):
            UI.endProgress()
            UI.ok("\(route.local.lastPathComponent) \(done) (\(Format.bytes(route.size)) in \(Format.duration(seconds)))")
        case .waitingForGame(let game):
            UI.warn("\(game) is running. Waiting until you quit the game… (Ctrl-C cancels, --force goes ahead anyway)")
        case .installing(let name):
            UI.step("Installing \(name) on the PS3…")
        case .installed(let name):
            UI.ok("\(name) installed")
        case .refreshed:
            UI.ok("Game list refreshed")
        case .note(let text):
            UI.step(text)
        }
    }
}
