import ArgumentParser
import Foundation
import PS3Kit

struct Games: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "games",
        abstract: "Spelen på PS3:an: lista, starta, avsluta och ta bort.",
        discussion: """
        ps3 games                    Alla spel, grupperade per plattform
        ps3 games info gran          Title ID, region, storlek, version och var det ligger
        ps3 games play gran turismo  Starta ett spel (frågar först om ett annat spel körs)
        ps3 games exit               Avsluta spelet som körs
        ps3 games delete <namn>      Ta bort ett spel från PS3:an (frågar först)
        Namnet kan vara en del av titeln, ett title ID (BCES00569, SLES-12345) eller sökvägen.
        Spelen läses från PS3ISO, GAMES, GAMEZ, PS2ISO, PSXISO, PSPISO, BDISO och DVDISO på
        hårddisken och USB-diskar, och från spel som är installerade i /dev_hdd0/game.
        """,
        subcommands: [List.self, Info.self, Play.self, Mount.self, Unmount.self, ExitGame.self, Delete.self],
        defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "Visa spelen på PS3:an (standard).")

        @OptionGroup var global: GlobalOptions

        @Option(name: .long, help: "Bara en plattform: ps3, psn, ps2, ps1, psp, bluray eller dvd.")
        var platform: String?

        @Flag(name: .long, help: "Läs om alla spels PARAM.SFO i stället för att använda cachen.")
        var refresh = false

        @Flag(name: .long, help: "Skriv ut JSON.")
        var json = false

        func run() async throws {
            let asJSON = json || !UI.isTTY
            var only: Game.Platform?
            if let platform {
                guard let match = Game.Platform.allCases.first(where: { $0.rawValue.lowercased() == platform.lowercased() || $0.label.lowercased() == platform.lowercased() }) else {
                    throw ValidationError("Okänd plattform: \(platform). Använd ps3, psn, ps2, ps1, psp, bluray eller dvd.")
                }
                only = match
            }
            let host = try await Console.host(global, quiet: asJSON)
            if !asJSON { UI.progress("Läser spelen på PS3:an…") }
            var games = try await GameLibraryService(host: host).scan(refresh: refresh) { dir in
                if !asJSON { UI.progress("Läser \(dir)…") }
            }
            if let only { games = games.filter { $0.platform == only } }
            if asJSON { UI.json(games); return }
            let snapshot = try? await WebMAN(host: host).snapshot()
            UI.endProgress()
            Games.render(games, snapshot: snapshot)
        }
    }

    struct Info: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Visa allt om ett spel: title ID, region, storlek, version och var det ligger.")

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Del av titeln, ett title ID eller sökvägen.")
        var name: [String] = []

        @Flag(name: .long, help: "Skriv ut JSON.")
        var json = false

        func validate() throws { try Games.requireName(name) }

        func run() async throws {
            let asJSON = json || !UI.isTTY
            let host = try await Console.host(global, quiet: asJSON)
            let game = try await Games.find(name, host: host, quiet: asJSON)
            if asJSON { UI.json(game); return }
            UI.header(game.title, detail: game.platform.label)
            UI.row("Title ID", game.titleID ?? UI.paint("okänt", .gray))
            if let region = game.region { UI.row("Region", region.label) }
            UI.row("Storlek", game.size.map(Format.bytes) ?? UI.paint(game.isInstalled ? "installerat i XMB:n" : "mapp", .gray))
            if let version = game.version { UI.row("Version", version) }
            if let update = game.updateVersion { UI.row("Uppdatering", "\(update) installerad") }
            UI.row("Plats", game.path)
            for companion in game.companions { UI.row("", UI.paint(companion, .gray)) }
            print("\n  Starta med " + UI.paint("ps3 games play \(game.titleID ?? game.title)", .bold) + ".")
        }
    }

    struct Play: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Starta ett spel. Körs ett annat spel frågar den först om det ska avslutas."
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Del av titeln, ett title ID eller sökvägen.")
        var name: [String] = []

        @Flag(name: [.short, .long], help: "Avsluta ett spel som körs utan att fråga.")
        var yes = false

        @Flag(name: .long, help: "Visa vad som skulle hända utan att göra det.")
        var dryRun = false

        func validate() throws { try Games.requireName(name) }

        func run() async throws {
            let host = try await Console.host(global)
            let game = try await Games.find(name, host: host)
            guard let exitFirst = try await Games.confirmExit(before: "starta \(game.title)", host: host, yes: yes) else { return }
            if dryRun {
                UI.step((exitFirst ? "Skulle avsluta spelet som körs och starta " : "Skulle starta ") + game.title)
                return
            }
            UI.progress(exitFirst ? "Avslutar spelet som körs och startar \(game.title)…" : "Startar \(game.title)…")
            try await GameLibraryService(host: host).play(game, exitingRunning: exitFirst)
            UI.endProgress()
            UI.ok("\(game.title) startar på PS3:an")
        }
    }

    struct Mount: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Montera ett spel som skiva utan att starta det, så att det kan startas från XMB:n."
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Del av titeln, ett title ID eller sökvägen.")
        var name: [String] = []

        @Flag(name: [.short, .long], help: "Avsluta ett spel som körs utan att fråga.")
        var yes = false

        @Flag(name: .long, help: "Visa vad som skulle hända utan att göra det.")
        var dryRun = false

        func validate() throws { try Games.requireName(name) }

        func run() async throws {
            let host = try await Console.host(global)
            let game = try await Games.find(name, host: host)
            guard let exitFirst = try await Games.confirmExit(before: "montera \(game.title)", host: host, yes: yes) else { return }
            if dryRun {
                UI.step("Skulle montera \(game.path)")
                return
            }
            try await GameLibraryService(host: host).mount(game, exitingRunning: exitFirst)
            UI.ok("\(game.title) är monterat. Starta det från skivikonen i XMB:n.")
        }
    }

    struct Unmount: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Avmontera spelet från skivikonen (/dev_bdvd).")

        @OptionGroup var global: GlobalOptions

        @Flag(name: .long, help: "Visa vad som skulle hända utan att göra det.")
        var dryRun = false

        func run() async throws {
            let host = try await Console.host(global)
            let snapshot = try await WebMAN(host: host).snapshot()
            guard let mounted = snapshot.mountedGameName else {
                UI.skip("Inget spel är monterat.")
                return
            }
            if snapshot.isGameRunning {
                throw PS3Error.refused("\(mounted) körs. Avsluta spelet först med `ps3 games exit`.")
            }
            if dryRun {
                UI.step("Skulle avmontera \(mounted)")
                return
            }
            try await GameLibraryService(host: host).unmount()
            UI.ok("\(mounted) är avmonterat")
        }
    }

    struct ExitGame: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "exit", abstract: "Avsluta spelet som körs och gå tillbaka till XMB:n.")

        @OptionGroup var global: GlobalOptions

        @Flag(name: .long, help: "Visa vad som skulle hända utan att göra det.")
        var dryRun = false

        func run() async throws {
            let host = try await Console.host(global)
            guard try await WebMAN(host: host).runningProcess() != nil else {
                UI.skip("Inget spel körs.")
                return
            }
            if dryRun {
                UI.step("Skulle avsluta spelet som körs")
                return
            }
            UI.progress("Avslutar spelet…")
            let name = try await GameLibraryService(host: host).exitGame()
            UI.endProgress()
            UI.ok("\(name ?? "Spelet") är avslutat")
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Ta bort ett spel från PS3:an. Frågar först om inte --yes anges.",
            discussion: "Spel som är installerade i XMB:n (PSN, PS1/PS2 Classics) tas bort i XMB:n i stället."
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Del av titeln, ett title ID eller sökvägen.")
        var name: [String] = []

        @Flag(name: [.short, .long], help: "Ta bort utan att fråga.")
        var yes = false

        @Flag(name: .long, help: "Visa vad som skulle tas bort utan att göra det.")
        var dryRun = false

        @Flag(name: .long, help: "Uppdatera spellistan även om ett spel körs.")
        var force = false

        @Flag(name: .long, help: "Uppdatera inte spellistan efteråt.")
        var noRefresh = false

        func validate() throws { try Games.requireName(name) }

        func run() async throws {
            let host = try await Console.host(global)
            let game = try await Games.find(name, host: host)
            let size = game.size.map(Format.bytes) ?? "mapp"
            UI.header(dryRun ? "Förhandsvisning" : "Ta bort", detail: "\(game.title) · \(size)")
            if !dryRun {
                guard yes || UI.confirm("Ta bort \(game.title) (\(size)) från PS3:an? Det går inte att ångra.") else {
                    UI.skip("Inget togs bort.")
                    return
                }
            }
            var options = TransferOptions()
            options.dryRun = dryRun
            options.force = force
            options.refresh = !noRefresh
            let printer = TransferPrinter(dryRun: dryRun)
            try await GameLibraryService(host: host).delete(game, options: options) { printer.handle($0) }
        }
    }

    // MARK: Shared

    static func requireName(_ name: [String]) throws {
        guard !name.isEmpty else { throw ValidationError("Ange ett spel, t.ex. en del av titeln eller ett title ID.") }
    }

    /// Reads the games and finds one by title ID, title or path.
    static func find(_ words: [String], host: String, quiet: Bool = false) async throws -> Game {
        let query = words.joined(separator: " ")
        if !quiet { UI.progress("Läser spelen på PS3:an…") }
        let games = try await GameLibraryService(host: host).scan()
        if !quiet { UI.endProgress() }
        switch Game.lookup(query, in: games) {
        case .found(let game):
            return game
        case .ambiguous(let matches):
            let list = matches.prefix(8).map { "\($0.title) (\($0.titleID ?? $0.platform.label))" }.joined(separator: ", ")
            throw PS3Error.invalidFile("\(query) kan betyda flera: \(list). Skriv mer av titeln, ett title ID eller sökvägen.")
        case .missing:
            throw PS3Error.invalidFile("Hittar inget spel som matchar \(query). Se `ps3 games`.")
        }
    }

    /// When a game runs: asks whether to quit it first (yes with -y; no when there is nobody to
    /// ask). Returns whether it has to be quit, or nil when the answer was no.
    static func confirmExit(before action: String, host: String, yes: Bool) async throws -> Bool? {
        let webman = WebMAN(host: host)
        guard let process = try await webman.runningProcess() else { return false }
        let running = (try? await webman.snapshot().mountedGameName) ?? process
        if yes { return true }
        guard isatty(STDIN_FILENO) == 1, UI.confirm("\(running) körs. Avsluta det och \(action)?", defaultYes: true) else {
            UI.skip("\(running) körs fortfarande. Inget ändrades (-y avslutar spelet utan att fråga).")
            return nil
        }
        return true
    }

    static func render(_ games: [Game], snapshot: ConsoleSnapshot?) {
        guard !games.isEmpty else {
            UI.skip("Inga spel hittades i PS3ISO, GAMES, PS2ISO, PSXISO, PSPISO, BDISO, DVDISO eller /dev_hdd0/game.")
            return
        }
        for platform in Game.Platform.allCases {
            let rows = games.filter { $0.platform == platform }
            guard !rows.isEmpty else { continue }
            let total = rows.compactMap(\.size).reduce(0, +)
            UI.header(platform.label, detail: "\(rows.count) st" + (total > 0 ? " · \(Format.bytes(total))" : ""))
            for game in rows {
                var marker = " "
                if snapshot?.mountedGamePath == game.path {
                    marker = snapshot?.isGameRunning == true ? UI.paint("▶", .green) : UI.paint("◉", .cyan)
                }
                let title = game.title.count > 44 ? String(game.title.prefix(43)) + "…" : game.title
                let id = (game.titleID ?? "").padding(toLength: 12, withPad: " ", startingAt: 0)
                let size = (game.size.map(Format.bytes) ?? (game.isInstalled ? "installerat" : "mapp"))
                    .padding(toLength: 12, withPad: " ", startingAt: 0)
                let detail = [game.region?.label, game.version, game.updateVersion.map { "uppdaterat till \($0)" },
                              game.isOnUSB ? "USB" : nil].compactMap { $0 }.joined(separator: " · ")
                print("  \(marker) \(title.padding(toLength: 46, withPad: " ", startingAt: 0))" + UI.paint(id, .gray) + size + UI.paint(detail, .gray))
            }
            print()
        }
        if let running = games.first(where: { $0.path == snapshot?.mountedGamePath }) {
            print("  " + (snapshot?.isGameRunning == true ? UI.paint("▶", .green) + " spelas nu: " : UI.paint("◉", .cyan) + " monterat: ") + running.title)
        }
        let example = games.first.flatMap { $0.title.split(separator: " ").first }.map { String($0).lowercased() } ?? "gran"
        print("  Starta med " + UI.paint("ps3 games play <namn>", .bold) + ", t.ex. " + UI.paint("ps3 games play \(example)", .bold) + ".")
    }
}
