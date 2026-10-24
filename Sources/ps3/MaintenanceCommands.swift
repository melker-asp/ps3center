import ArgumentParser
import Foundation
import PS3Kit

struct Saves: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Sparfilerna på PS3:an och i säkerhetskopian på Macen.",
        discussion: """
        ps3 saves                    Sparfilerna på PS3:an
        ps3 saves backup             Kopiera det som ändrats till Macen (läser bara konsolen)
        ps3 saves local              Vad som finns i säkerhetskopian
        ps3 saves restore gran       Lägg tillbaka en sparfil från säkerhetskopian
        Säkerhetskopian ligger i ~/Library/Application Support/ps3center/Sparfiler.
        """,
        subcommands: [List.self, Backup.self, Local.self, Restore.self],
        defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "Sparfilerna på PS3:an (standard).")

        @OptionGroup var global: GlobalOptions

        @Flag(name: .long, help: "Skriv ut JSON.")
        var json = false

        func run() async throws {
            let asJSON = json || !UI.isTTY
            let host = try await Console.host(global, quiet: asJSON)
            let saves = try await SaveBackupService(host: host).list()
            if asJSON { UI.json(saves); return }
            Saves.render(saves, header: "Sparfiler på PS3:an")
        }
    }

    struct Backup: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Kopiera sparfiler som ändrats till Macen. Läser bara konsolen.")

        @OptionGroup var global: GlobalOptions

        func run() async throws {
            let host = try await Console.host(global)
            try await Saves.backup(host: host)
        }
    }

    struct Local: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Sparfilerna i säkerhetskopian på Macen.")

        func run() throws {
            let saves = SaveBackupService.local()
            guard !saves.isEmpty else {
                UI.skip("Ingen säkerhetskopia än. Kör `ps3 saves backup`.")
                return
            }
            Saves.render(saves, header: "Sparfiler på Macen")
            if let last = SaveBackupService.lastBackup() { print("\n  Senast kopierat \(Format.day(last)).") }
        }
    }

    struct Restore: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Lägg tillbaka en sparfil från säkerhetskopian (samma användare). Inte medan ett spel körs."
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Del av titeln, ett title ID eller mappens namn.")
        var name: [String] = []

        @Flag(name: [.short, .long], help: "Fråga inte.")
        var yes = false

        @Flag(name: .long, help: "Visa vad som skulle hända.")
        var dryRun = false

        func validate() throws {
            guard !name.isEmpty else { throw ValidationError("Ange vilken sparfil, t.ex. `ps3 saves restore gran`.") }
        }

        func run() async throws {
            let query = name.joined(separator: " ")
            let matches = SaveBackupService.local().filter {
                $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    || $0.folder.range(of: query, options: .caseInsensitive) != nil
            }
            guard let save = matches.first else { throw PS3Error.refused("Ingen sparfil i säkerhetskopian passar \"\(query)\".") }
            guard matches.count == 1 else {
                Saves.render(matches, header: "Flera sparfiler passar")
                throw PS3Error.refused("Skriv mappens namn för att välja en.")
            }
            let host = try await Console.host(global)
            UI.header(save.title, detail: save.subtitle ?? save.folder)
            UI.row("Mapp", "/dev_hdd0/home/\(save.user)/savedata/\(save.folder)")
            UI.row("Storlek", Format.bytes(save.size))
            if let modified = save.modified { UI.row("Sparad", Format.day(modified)) }
            if dryRun { UI.step("Skulle lägga tillbaka sparfilen på \(host)"); return }
            guard yes || UI.confirm("Skriva över sparfilen på PS3:an med den här? Den som ligger där nu sparas först.") else { return }
            try await SaveBackupService(host: host).restore(save) { UI.step($0) }
            UI.ok("Sparfilen är tillbaka på PS3:an")
        }
    }

    static func backup(host: String) async throws {
        let report = try await SaveBackupService(host: host).backup { UI.progress($0) }
        UI.endProgress()
        for save in report.copied { UI.ok("\(save.title) (\(Format.bytes(save.size)))") }
        for failure in report.failed { UI.fail(failure) }
        UI.ok("Sparfiler: \(report.copied.count) kopierade, \(report.unchanged) oförändrade")
    }

    static func render(_ saves: [SaveGame], header: String) {
        UI.header(header, detail: "\(saves.count) st · \(Format.bytes(saves.reduce(0) { $0 + $1.size }))")
        for save in saves {
            let date = save.modified.map { UI.paint(Format.day($0), .gray) } ?? ""
            print("  " + save.title + (save.subtitle.map { UI.paint(" · " + $0, .gray) } ?? "")
                  + "  " + UI.paint(save.folder, .gray) + "  " + Format.bytes(save.size) + "  " + date)
        }
    }
}

struct Backup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Säkerhetskopiera sparfiler och systemfiler till Macen. Läser bara konsolen.",
        discussion: """
        Systemfilerna är systeminställningarna (xRegistry.sys), webMAN:s inställningar och
        boot_plugins-listorna. De sparas i en mapp per tillfälle i
        ~/Library/Application Support/ps3center/Systemfiler och visas aldrig.
        """
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Bara saves eller system.")
    var only: String?

    func validate() throws {
        if let only, !["saves", "system"].contains(only) { throw ValidationError("--only tar saves eller system.") }
    }

    func run() async throws {
        let host = try await Console.host(global)
        if only != "saves" {
            let result = try await SystemFiles.backup(host: host)
            for path in result.saved { UI.ok(path) }
            UI.ok("Systemfiler i \(result.folder.path)")
        }
        if only != "system" { try await Saves.backup(host: host) }
    }
}

struct Maintain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Leta efter sådant som tar plats eller kan ställa till det, och städa.",
        discussion: """
        Kontrollerar kvarglömda paket, avbrutna överföringar, spel som finns två gånger,
        webMAN:s cache, boot_plugins som pekar på filer som saknas, HEN:s inställningar och
        ledigt utrymme. Med --fix tas paket och avbrutna överföringar bort efter en fråga;
        resten är råd. boot_plugins.txt ändras aldrig.
        """
    )

    @OptionGroup var global: GlobalOptions

    @Flag(name: .long, help: "Ta bort det som kan tas bort.")
    var fix = false

    @Flag(name: [.short, .long], help: "Fråga inte.")
    var yes = false

    @Flag(name: .long, help: "Visa vad som skulle tas bort.")
    var dryRun = false

    @Flag(name: .long, help: "Skriv ut JSON.")
    var json = false

    func run() async throws {
        let host = try await Console.host(global, quiet: json)
        let service = MaintenanceService(host: host)
        let report = try await service.check { if !json { UI.progress($0) } }
        if !json { UI.endProgress() }
        if json { UI.json(report); return }
        UI.header("Underhåll", detail: host)
        for passed in report.passed { UI.ok(passed) }
        for finding in report.findings {
            let size = finding.size.map { " · " + Format.bytes($0) } ?? ""
            print("  " + UI.paint(finding.canFix ? "●" : "○", finding.canFix ? .yellow : .gray) + " " + finding.title + UI.paint(size, .gray))
            print("    " + UI.paint(finding.detail, .gray))
        }
        let fixable = report.findings.filter(\.canFix)
        guard !fixable.isEmpty else { return }
        let total = fixable.compactMap(\.size).reduce(0, +)
        guard fix || dryRun else {
            print("\n  " + UI.paint("ps3 maintain --fix", .bold) + " tar bort \(fixable.count) filer (\(Format.bytes(total))).")
            return
        }
        if dryRun {
            for finding in fixable { UI.step("Skulle ta bort \(finding.path ?? finding.title)") }
            return
        }
        guard yes || UI.confirm("Ta bort \(fixable.count) filer (\(Format.bytes(total))) från PS3:an?") else { return }
        for result in try await service.fix(fixable) {
            if let skipped = result.skipped { UI.skip("\(result.finding.title): \(skipped)") } else { UI.ok("Borttaget: \(result.finding.title)") }
        }
    }
}

struct Analyze: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Vad som tar plats på /dev_hdd0, mapp för mapp (räknas på konsolen med webMAN:s /stat.ps3)."
    )

    @OptionGroup var global: GlobalOptions

    @Flag(name: .long, help: "Skriv ut JSON.")
    var json = false

    func run() async throws {
        let host = try await Console.host(global, quiet: json)
        let map = try await StorageAnalyzer(host: host).analyze { if !json { UI.progress("Räknar \($0)") } }
        if !json { UI.endProgress() }
        if json { UI.json(map); return }
        let total = Double(map.total ?? max(1, map.areas.reduce(0) { $0 + $1.bytes }))
        UI.header("Lagring", detail: map.free.map { "\(Format.bytes($0)) ledigt" + (map.total.map { " av \(Format.bytes($0))" } ?? "") })
        for area in map.areas {
            UI.row(area.name, "\(UI.bar(Double(area.bytes) / total, width: 20, color: .blue)) \(Format.bytes(area.bytes))", width: 30)
        }
        if let other = map.other, other > 0 { UI.row("Övrigt och systemet", "\(UI.bar(Double(other) / total, width: 20, color: .gray)) \(Format.bytes(other))", width: 30) }
        if !map.largest.isEmpty {
            print("\n  " + UI.paint("Största filerna", .bold))
            for file in map.largest { UI.row(Format.bytes(file.bytes), file.path) }
        }
    }
}

struct Rip: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Kopiera PS3-skivan i spelaren till /dev_hdd0/GAMES (webMAN gör jobbet på konsolen).",
        discussion: "Bara dina egna skivor. Ctrl-C slutar följa förloppet; `ps3 rip --abort` stoppar kopieringen."
    )

    @OptionGroup var global: GlobalOptions

    @Flag(name: .long, help: "Stoppa en kopiering som pågår.")
    var abort = false

    @Flag(name: [.short, .long], help: "Fråga inte.")
    var yes = false

    @Flag(name: .long, help: "Visa vad som skulle hända.")
    var dryRun = false

    func run() async throws {
        let host = try await Console.host(global)
        let ripper = DiscRipper(host: host)
        if abort {
            try await ripper.abort()
            UI.ok("Kopieringen stoppas")
            return
        }
        guard let disc = try await ripper.disc() else {
            throw PS3Error.refused("Ingen PS3-skiva i spelaren.")
        }
        UI.header(disc.title, detail: disc.titleID)
        UI.row("Storlek", Format.bytes(disc.bytes))
        UI.row("Till", disc.destination)
        if dryRun { UI.step("Skulle kopiera skivan till \(disc.destination)"); return }
        guard yes || UI.confirm("Kopiera skivan till PS3:ans hårddisk?") else { return }
        let started = Date()
        try await ripper.rip(disc) { copied in
            let fraction = disc.bytes > 0 ? Double(copied) / Double(disc.bytes) : 0
            UI.progress("\(UI.bar(fraction, width: 24)) \(Format.bytes(copied)) av \(Format.bytes(disc.bytes))")
        }
        UI.endProgress()
        UI.ok("Klart på \(Format.duration(Date().timeIntervalSince(started))). Uppdatera spellistan med `ps3 refresh`.")
    }
}
