import ArgumentParser
import Foundation
import PS3Kit

struct Games: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "games",
        abstract: "Games on the PS3: list, start, quit and delete.",
        discussion: """
        ps3 games                    All games, grouped by platform
        ps3 games --sort added       Recently added first (or --sort size)
        ps3 games info gran          Title ID, region, size, version and where it is
        ps3 games play gran turismo  Start a game (asks first if one is running)
        ps3 games exit               Quit the running game
        ps3 games delete <name>      Delete a game from the PS3 (asks first)
        ps3 games covers             Fetch covers (--to-ps3 also puts them in webMAN)
        ps3 games updates            Official game updates from Sony
        ps3 games update gran        Install the updates for a game (or --all)
        ps3 games mac                Games on the Mac, and whether they are on the PS3
        ps3 games libcrypt <name>   Add the LibCrypt data PAL PS1 games need
        The name can be part of the title, a title ID (BCES00569, SLES-12345)
        or the path. Games are read from PS3ISO, GAMES, GAMEZ, PS2ISO, PSXISO,
        PSPISO, BDISO and DVDISO on the hard drive and USB drives, and from
        games installed in /dev_hdd0/game.
        """,
        subcommands: [List.self, Info.self, Play.self, Mount.self, Unmount.self, ExitGame.self, Delete.self,
                      Covers.self, Updates.self, Update.self, Mac.self, Libcrypt.self],
        defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "Show the games on the PS3.")

        @OptionGroup var global: GlobalOptions

        @Option(name: .long, help: "Only one platform: ps3, psn, ps2, ps1, psp, bluray or dvd.")
        var platform: String?

        @Option(name: .long, help: "Order: name (by platform, default), size (largest first) or added (recently added first). The Swedish namn, storlek and tillagt also work.")
        var sort = "name"

        @Flag(name: .long, help: "Re-read every game's PARAM.SFO instead of using the cache.")
        var refresh = false

        @Flag(name: .long, help: "Print JSON.")
        var json = false

        func run() async throws {
            let asJSON = json || !UI.isTTY
            guard let order = GameOrder(argument: sort) else {
                throw ValidationError("Unknown order: \(sort). Use name, size or added.")
            }
            var only: Game.Platform?
            if let platform {
                guard let match = Game.Platform.allCases.first(where: { $0.rawValue.lowercased() == platform.lowercased() || $0.label.lowercased() == platform.lowercased() }) else {
                    throw ValidationError("Unknown platform: \(platform). Use ps3, psn, ps2, ps1, psp, bluray or dvd.")
                }
                only = match
            }
            let host = try await Console.host(global, quiet: asJSON)
            if !asJSON { UI.progress("Reading the games on the PS3…") }
            var games = try await GameLibraryService(host: host).scan(refresh: refresh) { dir in
                if !asJSON { UI.progress("Reading \(dir)…") }
            }
            if let only { games = games.filter { $0.platform == only } }
            games = order.sorted(games)
            if asJSON { UI.json(games); return }
            let snapshot = try? await WebMAN(host: host).snapshot()
            UI.endProgress()
            Games.render(games, snapshot: snapshot, order: order)
        }
    }

    struct Info: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show everything about a game: title ID, region, size, version and where it is.")

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Part of the title, a title ID or the path.")
        var name: [String] = []

        @Flag(name: .long, help: "Print JSON.")
        var json = false

        func validate() throws { try Games.requireName(name) }

        func run() async throws {
            let asJSON = json || !UI.isTTY
            let host = try await Console.host(global, quiet: asJSON)
            let game = try await Games.find(name, host: host, quiet: asJSON)
            if asJSON { UI.json(game); return }
            UI.header(game.title, detail: game.platform.label)
            UI.row("Title ID", game.titleID ?? UI.paint("unknown", .gray))
            if let region = game.region { UI.row("Region", region.label) }
            UI.row("Size", game.size.map(Format.bytes) ?? UI.paint(game.isInstalled ? "installed in the XMB" : "folder", .gray))
            if let version = game.version { UI.row("Version", version) }
            if let update = game.updateVersion { UI.row("Update", "\(update) installed") }
            UI.row("Location", game.path)
            for companion in game.companions { UI.row("", UI.paint(companion, .gray)) }
            if let played = PlayLog.load().record(for: game) {
                UI.row("Play Time", "\(Format.playTime(played.seconds)) · last played \(Format.day(played.lastPlayed))")
            }
            // PS1 and PS2: what could keep it from starting on this console.
            if game.platform == .ps1 || game.platform == .ps2, let snapshot = try? await WebMAN(host: host).snapshot(),
               let findings = try? await PlayCheck.check(game, console: ConsoleProfile(snapshot: snapshot), host: host) {
                for finding in findings {
                    if finding.blocksPlay { UI.warn(finding.message) } else { UI.step(finding.message) }
                }
            }
            print("\n  Start with " + UI.paint("ps3 games play \(game.titleID ?? game.title)", .bold) + ".")
        }
    }

    struct Libcrypt: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "libcrypt",
            abstract: "Put the LibCrypt data a PAL PS1 game needs in /dev_hdd0/tmp/lsd.",
            discussion: "The data comes from webMAN MOD on GitHub. Without it, protected PAL games stop early on HEN."
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Part of the title, a title ID or the path.")
        var name: [String] = []

        @Flag(name: .long, help: "Show what would happen.")
        var dryRun = false

        func validate() throws { try Games.requireName(name) }

        func run() async throws {
            let host = try await Console.host(global)
            let game = try await Games.find(name, host: host)
            guard let exe = LibCrypt.exe(for: game) else {
                throw PS3Error.refused("\(game.title) has no LibCrypt protection that PS3 Center knows of.")
            }
            let installed = try await TransferService(host: host).withFTP { try await LibCrypt.isInstalled(exe: exe, game: game, ftp: $0) }
            if installed { UI.skip("The LibCrypt data for \(game.title) is already on the PS3."); return }
            try await LibCrypt.install(exe: exe, host: host, dryRun: dryRun) { UI.ok($0) }
        }
    }

    struct Play: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Start a game. If another game is running, asks first whether to quit it."
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Part of the title, a title ID or the path.")
        var name: [String] = []

        @Flag(name: [.short, .long], help: "Quit a running game without asking.")
        var yes = false

        @Flag(name: .long, help: "Show what would happen without doing it.")
        var dryRun = false

        func validate() throws { try Games.requireName(name) }

        func run() async throws {
            let host = try await Console.host(global)
            let game = try await Games.find(name, host: host)
            guard let exitFirst = try await Games.confirmExit(before: "start \(game.title)", host: host, yes: yes) else { return }
            if dryRun {
                UI.step((exitFirst ? "Would quit the running game and start " : "Would start ") + game.title)
                return
            }
            UI.progress(exitFirst ? "Quitting the running game and starting \(game.title)…" : "Starting \(game.title)…")
            try await GameLibraryService(host: host).play(game, exitingRunning: exitFirst)
            UI.endProgress()
            UI.ok("\(game.title) is starting on the PS3")
        }
    }

    struct Mount: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Mount a game as a disc without starting it, so it can be started from the XMB."
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Part of the title, a title ID or the path.")
        var name: [String] = []

        @Flag(name: [.short, .long], help: "Quit a running game without asking.")
        var yes = false

        @Flag(name: .long, help: "Show what would happen without doing it.")
        var dryRun = false

        func validate() throws { try Games.requireName(name) }

        func run() async throws {
            let host = try await Console.host(global)
            let game = try await Games.find(name, host: host)
            guard let exitFirst = try await Games.confirmExit(before: "mount \(game.title)", host: host, yes: yes) else { return }
            if dryRun {
                UI.step("Would mount \(game.path)")
                return
            }
            try await GameLibraryService(host: host).mount(game, exitingRunning: exitFirst)
            UI.ok("\(game.title) is mounted. Start it from the disc icon in the XMB.")
        }
    }

    struct Unmount: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Unmount the game from the disc icon (/dev_bdvd).")

        @OptionGroup var global: GlobalOptions

        @Flag(name: .long, help: "Show what would happen without doing it.")
        var dryRun = false

        func run() async throws {
            let host = try await Console.host(global)
            let snapshot = try await WebMAN(host: host).snapshot()
            guard let mounted = snapshot.mountedGameName else {
                UI.skip("No game is mounted.")
                return
            }
            if snapshot.isGameRunning {
                throw PS3Error.refused("\(mounted) is running. Quit the game first with `ps3 games exit`.")
            }
            if dryRun {
                UI.step("Would unmount \(mounted)")
                return
            }
            try await GameLibraryService(host: host).unmount()
            UI.ok("\(mounted) is unmounted")
        }
    }

    struct ExitGame: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "exit", abstract: "Quit the running game and go back to the XMB.")

        @OptionGroup var global: GlobalOptions

        @Flag(name: .long, help: "Show what would happen without doing it.")
        var dryRun = false

        func run() async throws {
            let host = try await Console.host(global)
            guard try await WebMAN(host: host).runningProcess() != nil else {
                UI.skip("No game is running.")
                return
            }
            if dryRun {
                UI.step("Would quit the running game")
                return
            }
            UI.progress("Quitting the game…")
            let name = try await GameLibraryService(host: host).exitGame()
            UI.endProgress()
            UI.ok("\(name ?? "The game") has quit")
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete or uninstall a game from the PS3. Asks first unless --yes is given.",
            discussion: "A game installed in the XMB (PSN, PS1/PS2 Classics) is uninstalled: its folder in /dev_hdd0/game is removed, the save files stay. What HEN needs is never removed."
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Part of the title, a title ID or the path.")
        var name: [String] = []

        @Flag(name: [.short, .long], help: "Delete without asking.")
        var yes = false

        @Flag(name: .long, help: "Show what would be deleted without doing it.")
        var dryRun = false

        @Flag(name: .long, help: "Refresh the game list even if a game is running.")
        var force = false

        @Flag(name: .long, help: "Do not refresh the game list afterwards.")
        var noRefresh = false

        func validate() throws { try Games.requireName(name) }

        func run() async throws {
            let host = try await Console.host(global)
            let game = try await Games.find(name, host: host)
            let size = game.size.map(Format.bytes) ?? "folder"
            UI.header(dryRun ? "Preview" : "Delete", detail: "\(game.title) · \(size)")
            if !dryRun {
                let question = game.isInstalled
                    ? "Uninstall \(game.title) (\(game.path))? The save files stay."
                    : "Delete \(game.title) (\(size)) from the PS3? This cannot be undone."
                guard yes || UI.confirm(question) else {
                    UI.skip("Nothing was deleted.")
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

    struct Covers: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Fetch covers for the games to the Mac, and with --to-ps3 also to webMAN on the PS3.",
            discussion: """
            PS3: aldostools/Resources (webMAN's online covers) and GameTDB.
            PS2 and PS1: xlenore/ps2-covers and psx-covers. PSP games and
            movies have no covers. Covers are saved in
            ~/Library/Caches/ps3center/covers.
            """
        )

        @OptionGroup var global: GlobalOptions

        @Flag(name: .customLong("to-ps3"), help: "Also put the PS3 covers in /dev_hdd0/tmp/wmtmp/covers, where webMAN looks.")
        var toPS3 = false

        @Flag(name: .long, help: "Ask the sources again, even for games that had no cover last time.")
        var refresh = false

        @Flag(name: .long, help: "Show what would be sent to the PS3 without doing it.")
        var dryRun = false

        func run() async throws {
            let host = try await Console.host(global)
            UI.progress("Reading the games on the PS3…")
            let games = try await GameLibraryService(host: host).scan()
            UI.progress("Fetching covers…")
            let covers = await CoverService().covers(for: games, refresh: refresh)
            UI.endProgress()
            UI.ok("\(covers.count) of \(UI.count(games.count, "game")) have covers" + UI.paint("  ~/Library/Caches/ps3center/covers", .gray))
            let missing = games.filter { covers[$0.id] == nil }
            for game in missing.prefix(12) {
                UI.skip("\(game.title): " + (game.titleID == nil ? "no title ID" : game.platform == .psp || game.platform == .bluRay || game.platform == .dvd ? "no covers for \(game.platform.label)" : "no cover in the sources"))
            }
            if missing.count > 12 { UI.skip("… and \(missing.count - 12) more") }
            guard toPS3 else { return }
            print()
            UI.header(dryRun ? "Preview" : "To the PS3", detail: "/dev_hdd0/tmp/wmtmp/covers")
            let printer = TransferPrinter(dryRun: dryRun)
            let sent = try await CoverService().upload(covers, for: games, host: host, dryRun: dryRun) { printer.handle($0) }
            if sent > 0 { print("\n  Run " + UI.paint("ps3 refresh", .bold) + " so webMAN loads them.") }
        }
    }

    struct Updates: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show official updates (patches) from Sony for the games, or for one game."
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Only this game (part of the title or title ID).")
        var name: [String] = []

        @Flag(name: .long, help: "Ask Sony again instead of using today's answer.")
        var refresh = false

        @Flag(name: .long, help: "Print JSON.")
        var json = false

        struct Row: Encodable {
            let game: Game
            let patches: [GamePatch]
        }

        func run() async throws {
            let asJSON = json || !UI.isTTY
            let host = try await Console.host(global, quiet: asJSON)
            if !asJSON { UI.progress("Reading the games on the PS3…") }
            let games = try await GameLibraryService(host: host).scan()
            let targets = try name.isEmpty ? games : [Games.find(name, in: games)]
            if !asJSON { UI.progress("Asking Sony's update server…") }
            let patches = await GameUpdateService(host: host).check(targets, refresh: refresh)
            let rows = targets.compactMap { game in patches[game.id].map { Row(game: game, patches: $0) } }
            if asJSON { UI.json(rows); return }
            UI.endProgress()
            guard !rows.isEmpty else {
                UI.ok(name.isEmpty ? "All games have the latest update." : "\(targets[0].title) has the latest update.")
                return
            }
            UI.header("Updates", detail: UI.count(rows.count, "game"))
            for row in rows { Games.renderPatches(row.patches, for: row.game) }
            print("\n  Install with " + UI.paint("ps3 games update <name>", .bold) + " or " + UI.paint("ps3 games update --all", .bold) + ".")
        }
    }

    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Download and install official updates for a game, or for all with --all.",
            discussion: """
            Only game patches from Sony's update server, never system
            software. The packages are downloaded on the Mac, checked against
            Sony's SHA-1 and installed like ordinary packages; the PS3 never
            goes out to PSN. A patch that requires newer system software than
            the console's is not installed.
            """
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "The game (part of the title or title ID).")
        var name: [String] = []

        @Flag(name: .long, help: "Update all games that have new patches.")
        var all = false

        @Flag(name: [.short, .long], help: "Answer yes to all questions.")
        var yes = false

        @Flag(name: .long, help: "Show what would be installed without doing it.")
        var dryRun = false

        @Flag(name: .long, help: "Install even if a game is running.")
        var force = false

        func validate() throws {
            guard all || !name.isEmpty else { throw ValidationError("Give a game, or --all for all.") }
        }

        func run() async throws {
            let host = try await Console.host(global)
            UI.progress("Reading the games on the PS3…")
            let games = try await GameLibraryService(host: host).scan()
            let targets = try all ? games : [Games.find(name, in: games)]
            UI.progress("Asking Sony's update server…")
            let patches = await GameUpdateService(host: host).check(targets)
            UI.endProgress()
            let rows = targets.compactMap { game in patches[game.id].map { (game: game, patches: $0) } }
            guard !rows.isEmpty else {
                UI.ok("Nothing to update.")
                return
            }
            UI.header(dryRun ? "Preview" : "Updates", detail: UI.count(rows.count, "game"))
            var options = TransferOptions()
            options.dryRun = dryRun
            options.force = force
            let printer = TransferPrinter(dryRun: dryRun)
            var installed = 0
            for row in rows {
                Games.renderPatches(row.patches, for: row.game)
                if !dryRun {
                    let size = Format.bytes(row.patches.reduce(0) { $0 + $1.size })
                    guard yes || UI.confirm("Install \(UI.count(row.patches.count, "update")) for \(row.game.title) (\(size))?", defaultYes: true) else {
                        UI.skip("\(row.game.title) skipped")
                        continue
                    }
                }
                try await GameUpdateService(host: host).install(row.patches, for: row.game, options: options) { printer.handle($0) }
                if !dryRun { UI.ok("\(row.game.title) updated to \(row.patches.last?.version ?? "")") }
                installed += 1
            }
            if !dryRun, installed > 0 {
                try? await WebMAN(host: host).popup("\(UI.count(installed, "game")) updated from the Mac")
            }
        }
    }

    struct Mac: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "mac",
            abstract: "The games in the Mac's game folders (ps3 config folder) and whether they are already on the PS3."
        )

        @OptionGroup var global: GlobalOptions

        @Flag(name: .long, help: "Only games that are not on the PS3.")
        var missing = false

        @Flag(name: .long, help: "Do not ask the PS3.")
        var offline = false

        @Flag(name: .long, help: "Print JSON.")
        var json = false

        struct Row: Encodable {
            let game: Game
            let state: MacGameState?
        }

        func run() async throws {
            let asJSON = json || !UI.isTTY
            if !asJSON { UI.progress("Reading the Mac's game folders…") }
            let library = LocalLibrary().scan()
            guard !library.isEmpty else {
                UI.endProgress()
                UI.skip("No games in the Mac's game folders. Link a folder with `ps3 config folder add PS3ISO ~/Games/PS3`.")
                return
            }
            var states: [String: MacGameState] = [:]
            if !offline {
                do {
                    let host = try await Console.host(global, quiet: true)
                    if !asJSON { UI.progress("Comparing with the PS3…") }
                    states = LibraryMatch.states(mac: library, console: try await GameLibraryService(host: host).scan())
                } catch {
                    if !asJSON { UI.endProgress(); UI.warn("The PS3 is not answering, so what is already there cannot be shown.") }
                }
            }
            var rows = library.map { Row(game: $0, state: states[$0.id]) }
            if missing { rows = rows.filter { $0.state != .onConsole } }
            if asJSON { UI.json(rows); return }
            UI.endProgress()
            for platform in Game.Platform.allCases {
                let group = rows.filter { $0.game.platform == platform }
                guard !group.isEmpty else { continue }
                UI.header(platform.label, detail: "\(UI.count(group.count, "game")) · \(Format.bytes(group.compactMap(\.game.size).reduce(0, +)))")
                for row in group {
                    let marker: String
                    switch row.state {
                    case .onConsole?: marker = UI.paint("✓", .green)
                    case .partial?: marker = UI.paint("◐", .yellow)
                    case .notOnConsole?: marker = UI.paint("↑", .cyan)
                    case nil: marker = " "
                    }
                    let title = row.game.title.count > 44 ? String(row.game.title.prefix(43)) + "…" : row.game.title
                    print("  \(marker) \(title.padding(toLength: 46, withPad: " ", startingAt: 0))"
                          + UI.paint((row.game.titleID ?? "").padding(toLength: 12, withPad: " ", startingAt: 0), .gray)
                          + (row.game.size.map(Format.bytes) ?? "folder").padding(toLength: 12, withPad: " ", startingAt: 0)
                          + UI.paint(row.state?.label ?? "", .gray))
                }
                print()
            }
            print("  Send with " + UI.paint("ps3 queue add <name>", .bold) + " and " + UI.paint("ps3 queue start", .bold) + ".")
        }
    }

    // MARK: Shared

    static func renderPatches(_ patches: [GamePatch], for game: Game) {
        let size = Format.bytes(patches.reduce(0) { $0 + $1.size })
        let from = GameUpdateService.currentVersion(of: game) ?? "?"
        let to = patches.last?.version ?? "?"
        let count = "\(UI.count(patches.count, "package")) · \(size)"
        print("  " + UI.paint("↑", .yellow) + " " + game.title.padding(toLength: 40, withPad: " ", startingAt: 0)
              + "\(from) → " + UI.paint(to, .bold, .yellow) + UI.paint("  \(count)", .gray))
    }

    static func requireName(_ name: [String]) throws {
        guard !name.isEmpty else { throw ValidationError("Give a game, e.g. part of the title or a title ID.") }
    }

    /// Reads the games and finds one by title ID, title or path.
    static func find(_ words: [String], host: String, quiet: Bool = false) async throws -> Game {
        if !quiet { UI.progress("Reading the games on the PS3…") }
        let games = try await GameLibraryService(host: host).scan()
        if !quiet { UI.endProgress() }
        return try find(words, in: games)
    }

    static func find(_ words: [String], in games: [Game]) throws -> Game {
        let query = words.joined(separator: " ")
        switch Game.lookup(query, in: games) {
        case .found(let game):
            return game
        case .ambiguous(let matches):
            let list = matches.prefix(8).map { "\($0.title) (\($0.titleID ?? $0.platform.label))" }.joined(separator: ", ")
            throw PS3Error.invalidFile("\(query) could mean several: \(list). Type more of the title, a title ID or the path.")
        case .missing:
            throw PS3Error.invalidFile("No game matches \(query). See `ps3 games`.")
        }
    }

    /// When a game runs: asks whether to quit it first (yes with -y; no when there is nobody to
    /// ask). Returns whether it has to be quit, or nil when the answer was no.
    static func confirmExit(before action: String, host: String, yes: Bool) async throws -> Bool? {
        let webman = WebMAN(host: host)
        guard let process = try await webman.runningProcess() else { return false }
        let running = (try? await webman.snapshot().mountedGameName) ?? process
        if yes { return true }
        guard isatty(STDIN_FILENO) == 1, UI.confirm("\(running) is running. Quit it and \(action)?", defaultYes: true) else {
            UI.skip("\(running) is still running. Nothing was changed (-y quits the game without asking).")
            return nil
        }
        return true
    }

    /// By name: a group per platform. By size or date: one list across platforms, as in the app,
    /// with the platform (and the date) on each line.
    static func render(_ games: [Game], snapshot: ConsoleSnapshot?, order: GameOrder = .name) {
        guard !games.isEmpty else {
            UI.skip("No games found in PS3ISO, GAMES, PS2ISO, PSXISO, PSPISO, BDISO, DVDISO or /dev_hdd0/game.")
            return
        }
        func header(_ title: String, _ rows: [Game]) {
            let total = rows.compactMap(\.size).reduce(0, +)
            UI.header(title, detail: UI.count(rows.count, "game") + (total > 0 ? " · \(Format.bytes(total))" : ""))
        }
        func line(_ game: Game) {
            var marker = " "
            if snapshot?.mountedGamePath == game.path {
                marker = snapshot?.isGameRunning == true ? UI.paint("▶", .green) : UI.paint("◉", .cyan)
            }
            let title = game.title.count > 44 ? String(game.title.prefix(43)) + "…" : game.title
            let id = (game.titleID ?? "").padding(toLength: 12, withPad: " ", startingAt: 0)
            let size = (game.size.map(Format.bytes) ?? (game.isInstalled ? "installed" : "folder"))
                .padding(toLength: 12, withPad: " ", startingAt: 0)
            let detail = [order == .name ? nil : game.platform.label,
                          order == .added ? game.added.map { "added \(Format.day($0))" } : nil,
                          game.region?.label, game.version, game.updateVersion.map { "updated to \($0)" },
                          game.isOnUSB ? "USB" : nil].compactMap { $0 }.joined(separator: " · ")
            print("  \(marker) \(title.padding(toLength: 46, withPad: " ", startingAt: 0))" + UI.paint(id, .gray) + size + UI.paint(detail, .gray))
        }
        if order == .name {
            for platform in Game.Platform.allCases {
                let rows = games.filter { $0.platform == platform }
                guard !rows.isEmpty else { continue }
                header(platform.label, rows)
                rows.forEach(line)
                print()
            }
        } else {
            header(order == .size ? "Largest First" : "Recently Added", games)
            games.forEach(line)
            print()
        }
        if let running = games.first(where: { $0.path == snapshot?.mountedGamePath }) {
            print("  " + (snapshot?.isGameRunning == true ? UI.paint("▶", .green) + " now playing: " : UI.paint("◉", .cyan) + " mounted: ") + running.title)
        }
        let example = games.first.flatMap { $0.title.split(separator: " ").first }.map { String($0).lowercased() } ?? "gran"
        print("  Start with " + UI.paint("ps3 games play <name>", .bold) + ", e.g. " + UI.paint("ps3 games play \(example)", .bold) + ".")
    }
}
