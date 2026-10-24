import ArgumentParser
import Foundation
import PS3Kit

struct Popup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Visa ett meddelande på TV:n.")

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Texten som ska visas.")
    var text: [String]

    func run() async throws {
        let host = try await Console.host(global)
        try await WebMAN(host: host).popup(text.joined(separator: " "))
        UI.ok("Visat på PS3:an")
    }
}

struct Refresh: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Uppdatera webMANs spellista (som SELECT + L3).")

    @OptionGroup var global: GlobalOptions

    @Flag(name: .long, help: "Kör även om ett spel körs.")
    var force = false

    func run() async throws {
        let host = try await Console.host(global)
        let service = TransferService(host: host)
        let printer = TransferPrinter(dryRun: false)
        try await service.waitUntilIdle(force: force) { printer.handle($0) }
        try await service.webman.refreshGames()
        OperationLog.record("refresh", host)
        UI.ok("Spellistan uppdaterad")
    }
}

struct History: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Visa vad PS3 Center har ändrat på konsolen.")

    @Option(name: .shortAndLong, help: "Antal rader.")
    var limit = 20

    @Flag(name: .long, help: "Skriv ut JSON.")
    var json = false

    func run() throws {
        let entries = OperationLog.read(limit: limit)
        if json || !UI.isTTY { UI.json(entries); return }
        guard !entries.isEmpty else { UI.skip("Ingen historik än."); return }
        UI.header("Historik", detail: OperationLog.file.path)
        for e in entries {
            print("  " + UI.paint(String(e.date.prefix(16)).replacingOccurrences(of: "T", with: " "), .gray) + "  "
                  + e.action.padding(toLength: 8, withPad: " ", startingAt: 0) + e.detail)
        }
    }
}

struct Discover: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Leta efter PS3:or med webMAN på nätverket och spara adressen.")

    func run() async throws {
        UI.step("Söker i \(Discovery.localSubnets().map { "\($0).0/24" }.joined(separator: ", "))…")
        let found = await Discovery.scan()
        guard let first = found.first else { throw PS3Error.noHost }
        for host in found { UI.ok("webMAN svarar på \(host)") }
        var config = ConfigStore.load()
        config.host = first
        try ConfigStore.save(config)
        UI.ok("Sparade \(first) som PS3:ans adress")
    }
}

struct Config: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Visa eller ändra inställningar (~/.config/ps3center/config.json).",
        subcommands: [Show.self, Set.self],
        defaultSubcommand: Show.self
    )

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Visa inställningarna.")
        func run() throws {
            let config = ConfigStore.load()
            UI.header("Inställningar", detail: ConfigStore.file.path)
            UI.row("host", config.host ?? UI.paint("(hittas automatiskt)", .gray))
            UI.row("root", config.root ?? (MirrorRoot.resolve().map { $0.path + UI.paint("  (hittad automatiskt)", .gray) } ?? UI.paint("(saknas)", .gray)))
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Ändra en inställning: host eller root.")

        @Argument(help: "host eller root")
        var key: String

        @Argument(help: "Värdet. Tom sträng tar bort inställningen.")
        var value: String

        func run() throws {
            var config = ConfigStore.load()
            let cleaned = value.isEmpty ? nil : value
            switch key {
            case "host": config.host = cleaned
            case "root":
                if let path = cleaned {
                    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
                    guard MirrorRoot.looksLikeMirror(url) else {
                        throw ValidationError("\(url.path) ser inte ut som PS3-mappen (saknar dev_hdd0/ eller _Installerat/).")
                    }
                    config.root = url.path
                } else {
                    config.root = nil
                }
            default: throw ValidationError("Okänd inställning: \(key). Använd host eller root.")
            }
            try ConfigStore.save(config)
            UI.ok("\(key) = \(cleaned ?? "(borttagen)")")
        }
    }
}
