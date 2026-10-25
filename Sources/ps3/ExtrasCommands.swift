import ArgumentParser
import Foundation
import PS3Kit

struct Record: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Starta eller stoppa inspelning av spelet som körs (webMAN, 720p MP4).",
        discussion: "Filmen hamnar i /dev_hdd0/VIDEO på PS3:an. Hämta den till Macen med `ps3 media pull`."
    )

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        let host = try await Console.host(global)
        let recording = try await WebMAN(host: host).toggleRecording()
        if recording {
            UI.ok("Spelar in. Kör `ps3 record` igen för att sluta.")
        } else {
            UI.ok("Inspelningen är klar och ligger i /dev_hdd0/VIDEO.")
        }
    }
}

struct Media: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Filmer och skärmbilder från PS3:an till Macen.",
        discussion: """
        ps3 media                    Vad som är nytt på PS3:an sedan förra gången
        ps3 media pull               Kopiera det till ~/Pictures/PS3 Center
        ps3 media screenshots        Tillåt skärmbilder i alla spel (till nästa omstart)
        Inget tas bort från PS3:an.
        """,
        subcommands: [List.self, Pull.self, Screenshots.self],
        defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Visa filmer och bilder som inte har kopierats än.")

        @OptionGroup var global: GlobalOptions

        func run() async throws {
            let host = try await Console.host(global)
            let items = try await MediaImport(host: host).newItems()
            UI.header("Nytt på PS3:an", detail: "\(items.count) filer")
            for item in items { UI.row(item.isVideo ? "Film" : "Bild", "\(item.remotePath) · \(Format.bytes(item.size))") }
            if !items.isEmpty { print("\n  " + UI.paint("ps3 media pull", .bold) + " kopierar dem till Macen.") }
        }
    }

    struct Pull: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Kopiera nya filmer och bilder till Macen.")

        @OptionGroup var global: GlobalOptions

        @Option(name: .long, help: "Mapp på Macen (standard: ~/Pictures/PS3 Center).", completion: .directory)
        var to: String?

        func run() async throws {
            let host = try await Console.host(global)
            let service = MediaImport(host: host)
            let items = try await service.newItems()
            guard !items.isEmpty else { UI.skip("Inget nytt att kopiera."); return }
            let folder = to.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) } ?? MediaImport.defaultFolder
            let written = try await service.copy(items, to: folder) { done, total in UI.progress("Kopierar \(min(done + 1, total)) av \(total)…") }
            UI.endProgress()
            UI.ok("\(written.count) filer i \(folder.path)")
        }
    }

    struct Screenshots: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Tillåt XMB:ns skärmbilder i alla spel (gäller till nästa omstart).",
            discussion: "Ta bilden med PS-knappen → Spara skärmbild under spelet. Den hamnar bland foton i XMB:n."
        )

        @OptionGroup var global: GlobalOptions

        @Flag(name: .long, help: "Visa vad som skulle hända.")
        var dryRun = false

        func run() async throws {
            let host = try await Console.host(global)
            if dryRun { UI.step("Skulle slå på skärmbilder i spel (/xmb.ps3$ingame_screenshot)"); return }
            try await WebMAN(host: host).enableGameScreenshots()
            UI.ok("Skärmbilder är tillåtna i spel till nästa omstart.")
        }
    }
}

struct Beep: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Låt PS3:an pipa, för att hitta den eller se att den lyssnar.")

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Antal pip, 1–3.")
    var count: Int = 3

    func run() async throws {
        let host = try await Console.host(global)
        try await WebMAN(host: host).beep(count)
        UI.ok("Pip!")
    }
}

struct Music: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Låt musik från XMB:n spela under spel, eller stäng av den (till nästa omstart).",
        discussion: "webMAN kan inte läsa av inställningen, bara sätta den."
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "on eller off (på eller av).")
    var state: String

    @Flag(name: .long, help: "Visa vad som skulle hända.")
    var dryRun = false

    func validate() throws {
        guard ["on", "off", "på", "av"].contains(state.lowercased()) else { throw ValidationError("Ange on eller off.") }
    }

    func run() async throws {
        let on = ["on", "på"].contains(state.lowercased())
        let host = try await Console.host(global)
        if dryRun { UI.step("Skulle slå \(on ? "på" : "av") musik i spel"); return }
        try await WebMAN(host: host).setGameMusic(on)
        UI.ok(on ? "Musik från XMB:n spelar under spel" : "Musik under spel är avstängd")
    }
}

struct Verify: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Kontrollera en kopia av en PS3-skiva mot originalet (IRD).",
        discussion: """
        ps3 verify ~/Spel/PS3/Spel.dec.iso     En dekrypterad ISO på Macen
        ps3 verify ~/Spel/GAMES/BLES01234      En spelmapp på Macen
        ps3 verify gran                        En spelmapp på PS3:an (t.ex. från ps3 rip)
        IRD-filen hämtas från FlexBy420:s databas på GitHub, eller anges med --ird. Varje fils
        MD5 jämförs med originalskivans. Krypterade ISO:er (redump, 3k3y) går inte att kontrollera.
        Inget ändras.
        """
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "En ISO eller mapp på Macen, eller ett spel på PS3:an.")
    var target: [String]

    @Option(name: .long, help: "En egen .ird-fil.", completion: .file(extensions: ["ird"]))
    var ird: String?

    @Flag(name: .long, help: "Skriv ut JSON.")
    var json = false

    func validate() throws {
        guard !target.isEmpty else { throw ValidationError("Ange en ISO, en mapp eller ett spel.") }
    }

    func run() async throws {
        let joined = target.joined(separator: " ")
        let url = URL(fileURLWithPath: (joined as NSString).expandingTildeInPath)
        var host: String?
        let checked: DiscVerifier.Target
        if FileManager.default.fileExists(atPath: url.path) {
            guard let local = DiscVerifier.Target.local(url) else {
                throw PS3Error.invalidFile("\(url.lastPathComponent) är varken en ISO eller en spelmapp med PS3_GAME.")
            }
            checked = local
        } else {
            let console = try await Console.host(global)
            host = console
            let game = try await Games.find(target, host: console)
            guard game.isFolder, game.platform == .ps3 else {
                throw PS3Error.refused("\(game.title) är ingen spelmapp. Kontrollera en ISO på Macen i stället, eller en mapp från ps3 rip.")
            }
            checked = .console(game.path)
        }
        let file = try ird.map { try IRD.parse(Data(contentsOf: URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath))) }
        let report = try await DiscVerifier.verify(checked, host: host, ird: file, events: { UI.progress($0) }) { done, total, name in
            UI.progress("\(done)/\(total) \(name)")
        }
        UI.endProgress()
        if json {
            UI.json(VerifyJSON(report))
            return
        }
        UI.header("Kontroll mot IRD", detail: report.title)
        if report.isIntact { UI.ok(report.summary) } else { UI.warn(report.summary) }
        for path in report.mismatched.prefix(20) { UI.row("Skiljer sig", path) }
        for path in report.missing.prefix(20) { UI.row("Saknas", path) }
        if !report.extra.isEmpty { UI.row("Extra", "\(report.extra.count) filer som inte fanns på skivan") }
    }

    struct VerifyJSON: Encodable {
        let title: String
        let checked: Int
        let matched: Int
        let mismatched: [String]
        let missing: [String]
        let extra: [String]
        let intact: Bool

        init(_ report: DiscVerifier.Report) {
            title = report.title
            checked = report.checked
            matched = report.matched
            mismatched = report.mismatched
            missing = report.missing
            extra = report.extra
            intact = report.isIntact
        }
    }
}

struct ErrorCode: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "error",
        abstract: "Förklara en felkod från PS3:an, t.ex. 80010006."
    )

    @Argument(help: "Felkoden.")
    var code: String

    func run() throws {
        guard let value = ConsoleErrorCode.parse(code) else { throw ValidationError("\(code) ser inte ut som en felkod (åtta hexsiffror).") }
        guard let info = ConsoleErrorCode.info(value) else {
            UI.warn("\(code) finns inte i listan. PS3 Center känner bara till systemets 8001xxxx-koder.")
            return
        }
        UI.ok(ConsoleErrorCode.describe(info))
    }
}
