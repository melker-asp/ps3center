import ArgumentParser
import Foundation
import PS3Kit

struct Queue: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Kön av spel att skicka, delad med appen. Tål avbrott och fortsätter där den slutade.",
        discussion: """
        ps3 queue                        Visa kön
        ps3 queue add Spel.iso           Lägg filer eller spel från Macens spelmappar i kön
        ps3 queue start                  Skicka allt i kön, ett spel i taget
        ps3 queue start --when-done shutdown   Stäng av PS3:an när kön är klar (aldrig mitt i ett spel)
        ps3 queue clear                  Ta bort det som är klart
        Ctrl-C stoppar rent: filen på PS3:an ligger kvar och nästa start fortsätter där.
        Macen hålls vaken så länge kön går.
        """,
        subcommands: [List.self, Add.self, Start.self, Remove.self, Clear.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "Visa kön (standard).")

        @Flag(name: .long, help: "Skriv ut JSON.")
        var json = false

        func run() throws {
            let queue = TransferQueue.load()
            if json || !UI.isTTY { UI.json(queue); return }
            guard !queue.items.isEmpty else {
                UI.skip("Kön är tom. Lägg till med `ps3 queue add <filer eller spel>`.")
                return
            }
            UI.header("Kön", detail: "\(queue.pending.count) kvar · \(Format.bytes(queue.remainingBytes))"
                      + (SpeedTest.estimate(bytes: queue.remainingBytes).map { " · ca \(Format.duration($0))" } ?? ""))
            for (index, item) in queue.items.enumerated() {
                let number = UI.paint(String(format: "%2d", index + 1), .gray)
                let marker: String
                switch item.state {
                case .done: marker = UI.paint("✓", .green)
                case .failed: marker = UI.paint("✗", .red)
                case .paused, .sending: marker = UI.paint("‖", .yellow)
                case .waiting: marker = UI.paint("·", .gray)
                }
                let progress = item.state == .done ? "" : "  " + UI.bar(item.fraction, width: 12) + " \(Int(item.fraction * 100)) %"
                print("  \(number) \(marker) \(item.title.padding(toLength: 40, withPad: " ", startingAt: 0))\(Format.bytes(item.total))\(progress)")
                if let message = item.message, item.state == .failed { print("        " + UI.paint(message, .gray)) }
            }
            print("\n  När kön är klar: " + queue.whenDone.label + (queue.verify ? " · MD5-kontroll" : ""))
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Lägg filer, mappar eller spel från Macens spelmappar i kön.",
            discussion: "En sökväg skickas som med `ps3 send`; annars söks namnet bland spelen i `ps3 games mac`."
        )

        @Argument(help: "Filer, mappar eller namn på spel i Macens spelmappar.", completion: .file())
        var items: [String] = []

        @Option(name: .long, help: "Skicka till en egen mapp på PS3:an, t.ex. /dev_hdd0/PS3ISO.")
        var to: String?

        func validate() throws {
            guard !items.isEmpty else { throw ValidationError("Ange filer eller spel att lägga i kön.") }
        }

        func run() throws {
            var routes: [Route] = []
            var names: [String] = []
            for item in items {
                let url = URL(fileURLWithPath: (item as NSString).expandingTildeInPath)
                if FileManager.default.fileExists(atPath: url.path) {
                    routes += try FileRouter.routes(for: [url], mirrorRoot: MirrorRoot.resolve(), remoteFolder: to)
                } else {
                    names.append(item)
                }
            }
            if !names.isEmpty {
                let games = LocalLibrary().scan()
                switch Game.lookup(names.joined(separator: " "), in: games) {
                case .found(let game): routes += try game.routes()
                case .ambiguous(let matches):
                    throw PS3Error.invalidFile("\(names.joined(separator: " ")) kan betyda flera: \(matches.prefix(8).map(\.title).joined(separator: ", ")).")
                case .missing:
                    throw PS3Error.invalidFile("Hittar varken filen eller spelet \(names.joined(separator: " ")) i Macens spelmappar (se `ps3 games mac`).")
                }
            }
            var queue = TransferQueue.load()
            let added = queue.add(routes)
            queue.save()
            guard !added.isEmpty else {
                UI.skip("Det ligger redan i kön.")
                return
            }
            for item in added { UI.ok("\(item.title) (\(Format.bytes(item.total))) ligger i kön") }
            print("\n  Skicka med " + UI.paint("ps3 queue start", .bold) + ".")
        }
    }

    struct Start: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Skicka allt i kön, ett spel i taget.")

        @OptionGroup var global: GlobalOptions

        @Option(name: .long, help: "När kön är klar: nothing, popup eller shutdown. Sparas till nästa gång.")
        var whenDone: String?

        @Flag(name: .long, inversion: .prefixedNo, help: "Jämför MD5 på PS3:an med Macens efter varje stor fil. Sparas till nästa gång.")
        var verify: Bool?

        func run() async throws {
            guard let lock = QueueLock() else {
                throw PS3Error.refused("Kön skickas redan, från appen eller ett annat `ps3 queue start`.")
            }
            var queue = TransferQueue.load()
            if let whenDone {
                guard let choice = TransferQueue.WhenDone(rawValue: whenDone) else {
                    throw ValidationError("--when-done tar nothing, popup eller shutdown.")
                }
                queue.whenDone = choice
            }
            if let verify { queue.verify = verify }
            queue.save()
            guard !queue.pending.isEmpty else {
                UI.skip("Inget i kön att skicka.")
                return
            }
            let host = try await Console.host(global)
            let awake = KeepAwake(reason: "Skickar spel till PS3:an")
            defer { withExtendedLifetime(awake) {} }
            UI.header("Skickar kön", detail: "\(queue.pending.count) st · \(Format.bytes(queue.remainingBytes))")
            let runner = QueueRunner(host: host)
            let printer = TransferPrinter(dryRun: false)
            var sentTitles: [String] = []
            var refreshes = false
            for item in queue.pending {
                queue.update(item.id) { $0.state = .sending }
                queue.save()
                UI.step(item.title)
                do {
                    try await runner.send(item, verify: queue.verify) { printer.handle($0) }
                    queue.update(item.id) {
                        $0.state = .done
                        $0.sent = $0.total
                        $0.finishedAt = Date()
                        $0.message = nil
                    }
                    sentTitles.append(item.title)
                    refreshes = refreshes || item.routes.contains(where: \.refreshesGameList)
                } catch {
                    queue.update(item.id) {
                        $0.state = .failed
                        $0.message = error.localizedDescription
                    }
                    UI.fail("\(item.title): \(error.localizedDescription)")
                }
                queue.save()
            }
            try await runner.finish(sent: sentTitles, refresh: refreshes, whenDone: queue.whenDone) { printer.handle($0) }
            withExtendedLifetime(lock) {}
            UI.ok("Kön är klar: \(sentTitles.count) skickade")
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Ta bort en rad ur kön (numret från `ps3 queue`). Filer på PS3:an rörs inte.")

        @Argument(help: "Radens nummer.")
        var number: Int

        func run() throws {
            var queue = TransferQueue.load()
            guard queue.items.indices.contains(number - 1) else { throw ValidationError("Kön har ingen rad \(number).") }
            let item = queue.items.remove(at: number - 1)
            queue.save()
            UI.ok("\(item.title) är borttaget ur kön")
        }
    }

    struct Clear: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Ta bort det som är klart ur kön, eller allt med --all.")

        @Flag(name: .long, help: "Töm hela kön.")
        var all = false

        func run() throws {
            var queue = TransferQueue.load()
            if all { queue.items.removeAll() } else { queue.removeFinished() }
            queue.save()
            UI.ok(all ? "Kön är tömd" : "Klara rader är borttagna")
        }
    }
}

struct Speedtest: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "speedtest",
        abstract: "Mät hur fort filer går till och från PS3:an. Resultatet ger tidsberäkningar i kön och appen."
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Megabyte att skicka.")
    var mb = 256

    func run() async throws {
        let host = try await Console.host(global)
        UI.header("Hastighetstest", detail: "\(mb) MB till /dev_hdd0/tmp och tillbaka")
        let printer = TransferPrinter(dryRun: false)
        let result = try await SpeedTest.run(host: host, megabytes: mb) { printer.handle($0) }
        UI.row("Till PS3:an", Format.rate(result.upload))
        if let down = result.download { UI.row("Från PS3:an", Format.rate(down)) }
        if let network = result.network { UI.row("Nätverk", network) }
        let tenGB: Int64 = 10_000_000_000
        UI.row("10 GB tar", Format.duration(Double(tenGB) / result.upload))
        if result.network == "Wi-Fi" {
            print()
            UI.warn("PS3:an är på Wi-Fi (bara 2,4 GHz). Med nätverkskabel brukar det gå flera gånger fortare.")
        }
    }
}

struct Power: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stäng av eller starta om PS3:an.",
        discussion: "På HEN måste HEN aktiveras igen efter en omstart, och PS3:an kan inte startas från Macen.",
        subcommands: [Off.self, Restart.self]
    )

    struct Off: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Stäng av PS3:an (väntar inte på spel; avsluta först om du vill spara).")

        @OptionGroup var global: GlobalOptions

        @Flag(name: [.short, .long], help: "Fråga inte.")
        var yes = false

        @Flag(name: .long, help: "Visa vad som skulle hända.")
        var dryRun = false

        func run() async throws {
            let host = try await Console.host(global)
            if let running = try await WebMAN(host: host).snapshot().mountedGameName, try await WebMAN(host: host).isGameRunning() {
                UI.warn("\(running) körs. Spara först, osparade framsteg försvinner.")
            }
            if dryRun { UI.step("Skulle stänga av PS3:an på \(host)"); return }
            guard yes || UI.confirm("Stänga av PS3:an?") else { return }
            try await WebMAN(host: host).shutdown()
            UI.ok("PS3:an stängs av")
        }
    }

    struct Restart: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Starta om PS3:an. På HEN måste HEN aktiveras igen efteråt.")

        @OptionGroup var global: GlobalOptions

        @Flag(name: [.short, .long], help: "Fråga inte.")
        var yes = false

        @Flag(name: .long, help: "Visa vad som skulle hända.")
        var dryRun = false

        func run() async throws {
            let host = try await Console.host(global)
            let profile = ConsoleProfile(snapshot: try await WebMAN(host: host).snapshot())
            if profile.exploit == .hen { UI.warn("PS3:an kör HEN: efter omstarten måste HEN aktiveras igen innan PS3 Center når den.") }
            if dryRun { UI.step("Skulle starta om PS3:an på \(host)"); return }
            guard yes || UI.confirm("Starta om PS3:an?") else { return }
            try await WebMAN(host: host).restart()
            UI.ok("PS3:an startar om")
        }
    }
}

struct USB: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "usb",
        abstract: "Förbered en USB-disk med spel från Macens spelmappar (snabbast för många spel).",
        subcommands: [Prepare.self]
    )

    struct Prepare: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Kopiera spel till en FAT32-disk i webMAN:s mappar. PS3-ISO:er över 4 GB delas i .iso.0, .iso.1 …",
            discussion: """
            ps3 usb prepare /Volumes/PS3 gran demon     Två spel från Macens spelmappar
            ps3 usb prepare /Volumes/PS3 --missing      Alla som inte finns på PS3:an
            Formatera disken som "MS-DOS (FAT)" i Skivverktyg först; macOS kan inte skriva NTFS.
            Sätt sedan disken i PS3:an: spelen syns under webMAN:s spel efter en uppdatering av spellistan.
            """
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Diskens mapp, t.ex. /Volumes/PS3.", completion: .directory)
        var volume: String

        @Argument(help: "Spel (del av titeln eller title ID) från Macens spelmappar.")
        var names: [String] = []

        @Flag(name: .long, help: "Alla spel i Macens spelmappar som inte finns på PS3:an.")
        var missing = false

        @Flag(name: .long, help: "Visa vad som skulle kopieras.")
        var dryRun = false

        func validate() throws {
            guard missing || !names.isEmpty else { throw ValidationError("Ange spel, eller --missing för alla som inte finns på PS3:an.") }
        }

        func run() async throws {
            let root = URL(fileURLWithPath: (volume as NSString).expandingTildeInPath)
            guard let info = USBDrive.volume(root) else { throw ValidationError("Hittar ingen disk på \(root.path).") }
            guard info.isFAT32 else {
                throw PS3Error.refused("\(root.path) är \(info.format), inte FAT32. Formatera den som \"MS-DOS (FAT)\" i Skivverktyg (det raderar disken).")
            }
            let library = LocalLibrary().scan()
            var games: [Game]
            if missing {
                let host = try await Console.host(global)
                let console = try await GameLibraryService(host: host).scan()
                let states = LibraryMatch.states(mac: library, console: console)
                games = library.filter { states[$0.id] != .onConsole }
            } else {
                games = try names.map { name in
                    switch Game.lookup(name, in: library) {
                    case .found(let game): return game
                    case .ambiguous(let matches): throw PS3Error.invalidFile("\(name) kan betyda flera: \(matches.prefix(8).map(\.title).joined(separator: ", ")).")
                    case .missing: throw PS3Error.invalidFile("Hittar inget spel som matchar \(name) i Macens spelmappar.")
                    }
                }
            }
            let plan = USBDrive.plan(games, on: root)
            for (game, reason) in plan.skipped { UI.skip("\(game.title): \(reason)") }
            let total = plan.copies.reduce(0) { $0 + $1.size }
            UI.header(dryRun ? "Förhandsvisning" : "Kopierar", detail: "\(plan.copies.count) filer · \(Format.bytes(total)) · ledigt \(Format.bytes(info.free))")
            guard total < info.free else { throw PS3Error.notEnoughSpace(needed: total, free: info.free) }
            for copy in plan.copies {
                UI.step("\(copy.game.title) → \(copy.destination.path)" + (copy.parts > 1 ? UI.paint("  (\(copy.parts) delar)", .gray) : ""))
            }
            guard !dryRun else { return }
            let printer = TransferPrinter(dryRun: false)
            try await USBDrive.copy(plan.copies) { printer.handle($0) }
            UI.ok("Klart. Mata ut disken, sätt den i PS3:an och kör `ps3 refresh`.")
        }
    }
}

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Kör spelservern: PS3:an spelar ISO:er direkt från Macens spelmappar via webMAN (/net0).",
        discussion: """
        En egen ps3netsrv som bara läser, på port 38008. Ställ in den en gång i webMAN:
        Inställningar (http://<ps3>/setup.ps3) → nätverksserver 1 = Macens adress och 38008.
        Spelen syns sedan under webMAN:s spel och startas som vanligt, eller med
        `ps3 games play` på /net0-sökvägen. Ctrl-C stoppar servern.
        PS3-spel bör gå över kabel. PS2-ISO:er kopieras till hårddisken när de startas, och
        spelmappar (GAMES) går inte över nätet, bara ISO:er.
        """
    )

    @OptionGroup var global: GlobalOptions

    @Flag(name: .long, help: "Släpp in alla på nätverket, inte bara PS3:an.")
    var anyClient = false

    func run() async throws {
        let folders = GameFolders.linked()
        guard !folders.isEmpty else {
            throw PS3Error.refused("Inga spelmappar är kopplade. Koppla en med `ps3 config folder add PS3ISO ~/Spel/PS3`.")
        }
        let console = anyClient ? nil : (try? await Console.host(global, quiet: true))
        let server = NetServer(folders: folders, allowedHost: console) { status in
            if let error = status.error { UI.fail(error) }
        }
        try server.start()
        let awake = KeepAwake(reason: "Spelservern för PS3:an")
        defer { withExtendedLifetime(awake) {}; server.stop() }
        UI.header("Spelservern", detail: "port \(NetServer.defaultPort)" + (console.map { " · bara \($0)" } ?? ""))
        for address in NetServer.macAddresses() { UI.row("Adress", "\(address):\(NetServer.defaultPort)") }
        for (kind, url) in folders { UI.row(kind.name, url.path) }
        print("\n  Ctrl-C stoppar. Macen hålls vaken så länge servern går.")
        // Polled, so the output stays calm: one line per game file the console opens.
        var last: String?
        while true {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            if let file = server.currentStatus.lastFile, file != last {
                last = file
                UI.step("PS3:an läser \(file)")
            }
        }
    }
}
