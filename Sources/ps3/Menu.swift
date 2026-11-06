import ArgumentParser
import Foundation
import PS3Kit

/// `ps3` without arguments in a terminal, like Mole's `mo`: the common commands by number, or
/// any command typed out. Each choice runs the real subcommand, so it asks before changing
/// anything just as it does on its own. Without a terminal the help is printed, as before.
enum MainMenu {
    struct Item {
        let title: String
        let arguments: [String]
    }

    static let items: [Item] = [
        Item(title: "Status", arguments: ["status"]),
        Item(title: "Spelen på PS3:an", arguments: ["games"]),
        Item(title: "Spelen på Macen", arguments: ["games", "mac"]),
        Item(title: "Kön", arguments: ["queue"]),
        Item(title: "Skicka kön", arguments: ["queue", "start"]),
        Item(title: "Program och uppdateringar", arguments: ["apps"]),
        Item(title: "Uppdatera program (frågar för varje)", arguments: ["apps", "update"]),
        Item(title: "Paket på Macen", arguments: ["apps", "mac"]),
        Item(title: "Hastighetstest", arguments: ["speedtest"]),
        Item(title: "Säkerhetskopiera sparfiler och systemfiler", arguments: ["backup"]),
        Item(title: "Städning (bara en rapport)", arguments: ["maintain"]),
        Item(title: "Historik", arguments: ["history"]),
    ]

    static var isInteractive: Bool { UI.isTTY && isatty(STDIN_FILENO) == 1 }

    /// The whole menu first; after a command only a short prompt, and "m" shows it again.
    static func run() async {
        show()
        var first = true
        while true {
            let hint = first ? "(Retur avslutar) " : "(1–\(items.count), m visar menyn, Retur avslutar) "
            print("  " + UI.paint("?", .cyan) + " Välj en siffra eller skriv ett kommando " + UI.paint(hint, .gray), terminator: "")
            fflush(stdout)
            guard let line = readLine(), let arguments = choice(for: line) else { return }
            first = false
            if arguments == ["menu"] {
                print()
                show()
                continue
            }
            print()
            if arguments == ["help"] {
                print(PS3.helpMessage())
            } else {
                await perform(arguments)
            }
            print()
        }
    }

    static func show() {
        UI.header("PS3 Center", detail: "ps3 --help visar alla kommandon")
        for (index, item) in items.enumerated() {
            let number = String(index + 1).leftPadded(to: 2)
            print("  " + UI.paint(number, .cyan) + "  " + item.title.padding(toLength: 44, withPad: " ", startingAt: 0)
                  + UI.paint("ps3 " + item.arguments.joined(separator: " "), .gray))
        }
        print("  " + UI.paint(" h", .cyan) + "  Alla kommandon")
        print()
    }

    /// The arguments for what was typed: a number from the list, "h" for the help, or a command
    /// with or without "ps3" in front ("games play gran"). Nil ends the menu.
    static func choice(for line: String) -> [String]? {
        let text = line.trimmingCharacters(in: .whitespaces)
        if text.isEmpty || ["q", "quit", "exit", "avsluta"].contains(text.lowercased()) { return nil }
        if ["h", "hjälp", "help", "?"].contains(text.lowercased()) { return ["help"] }
        if ["m", "meny", "menu"].contains(text.lowercased()) { return ["menu"] }
        if let number = Int(text) {
            guard items.indices.contains(number - 1) else { return [] }
            return items[number - 1].arguments
        }
        var words = split(text)
        if words.first == "ps3" { words.removeFirst() }
        return words
    }

    /// Splits on spaces, keeping "quoted words" and 'quoted words' together.
    static func split(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var started = false
        for character in text {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
                started = true
            } else if character == " " {
                if started || !current.isEmpty { words.append(current) }
                current = ""
                started = false
            } else {
                current.append(character)
            }
        }
        if started || !current.isEmpty { words.append(current) }
        return words
    }

    private static func perform(_ arguments: [String]) async {
        guard let name = arguments.first else {
            UI.fail("Välj en siffra från 1 till \(items.count).")
            return
        }
        // ArgumentParser would say this in English.
        let known = PS3.configuration.subcommands.map { $0._commandName }
        guard name.hasPrefix("-") || known.contains(name) else {
            UI.fail("Okänt kommando: \(name). Skriv h för alla kommandon.")
            return
        }
        do {
            var command = try PS3.parseAsRoot(arguments)
            // An empty command would be the menu again.
            guard !(command is PS3) else { return }
            if var async = command as? AsyncParsableCommand {
                try await async.run()
            } else {
                try command.run()
            }
        } catch {
            // The help for --help, else the message alone: no English "Error:" and usage lines,
            // since h shows every command. The menu stays.
            let message = PS3.message(for: error)
            if !message.isEmpty {
                if error is CleanExit || PS3.exitCode(for: error) == .success { print(message) } else { UI.fail(message) }
            }
        }
    }
}

extension PS3 {
    /// `ps3` alone: the menu in a terminal, the help in a script or pipe.
    func run() async throws {
        guard MainMenu.isInteractive else {
            print(PS3.helpMessage())
            return
        }
        await MainMenu.run()
    }
}

private extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
