import ArgumentParser
import Foundation
import PS3Kit

struct Saves: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Saves on the PS3 and in the backup on the Mac.",
        discussion: """
        ps3 saves                    Saves on the PS3
        ps3 saves backup             Copy what changed to the Mac (read-only)
        ps3 saves local              What is in the backup
        ps3 saves restore gran       Put a save back from the backup
        ps3 saves delete gran        Delete a save from the PS3 (copied first)
        The backup is in ~/Library/Application Support/ps3center/Saves.
        """,
        subcommands: [List.self, Backup.self, Local.self, Restore.self, Delete.self],
        defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "Saves on the PS3.")

        @OptionGroup var global: GlobalOptions

        @Flag(name: .long, help: "Print JSON.")
        var json = false

        func run() async throws {
            let asJSON = json || !UI.isTTY
            let host = try await Console.host(global, quiet: asJSON)
            let saves = try await SaveBackupService(host: host).list()
            if asJSON { UI.json(saves); return }
            Saves.render(saves, header: "Saves on the PS3")
        }
    }

    struct Backup: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Copy saves that have changed to the Mac. Only reads the console.")

        @OptionGroup var global: GlobalOptions

        func run() async throws {
            let host = try await Console.host(global)
            try await Saves.backup(host: host)
        }
    }

    struct Local: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Saves in the backup on the Mac.")

        func run() throws {
            let saves = SaveBackupService.local()
            guard !saves.isEmpty else {
                UI.skip("No backup yet. Run `ps3 saves backup`.")
                return
            }
            Saves.render(saves, header: "Saves on the Mac")
            if let last = SaveBackupService.lastBackup() { print("\n  Last copied \(Format.day(last)).") }
        }
    }

    struct Restore: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Put a save back from the backup (same user). Not while a game is running."
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Part of the title, a title ID or the folder name.")
        var name: [String] = []

        @Flag(name: [.short, .long], help: "Do not ask.")
        var yes = false

        @Flag(name: .long, help: "Show what would happen.")
        var dryRun = false

        func validate() throws {
            guard !name.isEmpty else { throw ValidationError("Say which save, e.g. `ps3 saves restore gran`.") }
        }

        func run() async throws {
            let query = name.joined(separator: " ")
            let matches = SaveBackupService.local().filter {
                $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    || $0.folder.range(of: query, options: .caseInsensitive) != nil
            }
            guard let save = matches.first else { throw PS3Error.refused("No save in the backup matches \"\(query)\".") }
            guard matches.count == 1 else {
                Saves.render(matches, header: "Several saves match")
                throw PS3Error.refused("Type the folder name to pick one.")
            }
            let host = try await Console.host(global)
            UI.header(save.title, detail: save.subtitle ?? save.folder)
            UI.row("Folder", "/dev_hdd0/home/\(save.user)/savedata/\(save.folder)")
            UI.row("Size", Format.bytes(save.size))
            if let modified = save.modified { UI.row("Saved", Format.day(modified)) }
            if dryRun { UI.step("Would put the save back on \(host)"); return }
            guard yes || UI.confirm("Overwrite the save on the PS3 with this one? The one there now is backed up first.") else { return }
            try await SaveBackupService(host: host).restore(save) { UI.step($0) }
            UI.ok("The save is back on the PS3")
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete a save from the PS3. It is copied to the Mac first, so it can be put back."
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Part of the title, a title ID or the folder name.")
        var name: [String] = []

        @Flag(name: [.short, .long], help: "Do not ask.")
        var yes = false

        @Flag(name: .long, help: "Show what would happen.")
        var dryRun = false

        func validate() throws {
            guard !name.isEmpty else { throw ValidationError("Say which save, e.g. `ps3 saves delete gran`.") }
        }

        func run() async throws {
            let query = name.joined(separator: " ")
            let host = try await Console.host(global)
            let matches = try await SaveBackupService(host: host).list().filter {
                $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    || $0.folder.range(of: query, options: .caseInsensitive) != nil
            }
            guard let save = matches.first else { throw PS3Error.refused("No save on the PS3 matches \"\(query)\".") }
            guard matches.count == 1 else {
                Saves.render(matches, header: "Several saves match")
                throw PS3Error.refused("Type the folder name to pick one.")
            }
            UI.header(save.title, detail: save.subtitle ?? save.folder)
            UI.row("Folder", "/dev_hdd0/home/\(save.user)/savedata/\(save.folder)")
            UI.row("Size", Format.bytes(save.size))
            if dryRun { UI.step("Would copy the save to the Mac and delete it from the PS3"); return }
            guard yes || UI.confirm("Delete the save from the PS3? A copy is saved on the Mac first.") else { return }
            try await SaveBackupService(host: host).delete(save) { UI.step($0) }
            UI.ok("The save is deleted. `ps3 saves restore \(save.folder)` puts it back.")
        }
    }

    static func backup(host: String) async throws {
        let report = try await SaveBackupService(host: host).backup { UI.progress($0) }
        UI.endProgress()
        for save in report.copied { UI.ok("\(save.title) (\(Format.bytes(save.size)))") }
        for failure in report.failed { UI.fail(failure) }
        UI.ok("Saves: \(report.copied.count) copied, \(report.unchanged) unchanged")
    }

    static func render(_ saves: [SaveGame], header: String) {
        UI.header(header, detail: "\(UI.count(saves.count, "save")) · \(Format.bytes(saves.reduce(0) { $0 + $1.size }))")
        for save in saves {
            let date = save.modified.map { UI.paint(Format.day($0), .gray) } ?? ""
            print("  " + save.title + (save.subtitle.map { UI.paint(" · " + $0, .gray) } ?? "")
                  + "  " + UI.paint(save.folder, .gray) + "  " + Format.bytes(save.size) + "  " + date)
        }
    }
}

struct Backup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Back up saves and system files to the Mac. Only reads the console.",
        discussion: """
        The system files are the system settings (xRegistry.sys), webMAN's
        settings and the boot_plugins lists. They are saved in one folder per
        run in ~/Library/Application Support/ps3center/System Files and are
        never displayed.
        """
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Only saves or system.")
    var only: String?

    func validate() throws {
        if let only, !["saves", "system"].contains(only) { throw ValidationError("--only takes saves or system.") }
    }

    func run() async throws {
        let host = try await Console.host(global)
        if only != "saves" {
            let result = try await SystemFiles.backup(host: host)
            for path in result.saved { UI.ok(path) }
            UI.ok("System files in \(result.folder.path)")
        }
        if only != "system" { try await Saves.backup(host: host) }
    }
}

struct Maintain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Look for things that take up space or could cause trouble, and clean up.",
        subcommands: [Check.self, BlockUpdates.self],
        defaultSubcommand: Check.self
    )

    struct Check: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Look for things that take up space or could cause trouble, and clean up.",
            discussion: """
            Checks for leftover packages, interrupted transfers, games that
            exist twice, webMAN's cache, boot_plugins entries that point to
            missing files, HEN's settings and free space. With --fix, packages
            and interrupted transfers are removed after a question; the rest
            is advice. boot_plugins.txt is never changed.
            """
        )

        @OptionGroup var global: GlobalOptions

        @Flag(name: .long, help: "Remove what can be removed.")
        var fix = false

        @Flag(name: [.short, .long], help: "Do not ask.")
        var yes = false

        @Flag(name: .long, help: "Show what would be removed.")
        var dryRun = false

        @Flag(name: .long, help: "Print JSON.")
        var json = false

        func run() async throws {
            let host = try await Console.host(global, quiet: json)
            let service = MaintenanceService(host: host)
            let report = try await service.check { if !json { UI.progress($0) } }
            if !json { UI.endProgress() }
            if json { UI.json(report); return }
            UI.header("Maintenance", detail: host)
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
                print("\n  " + UI.paint("ps3 maintain --fix", .bold) + " removes \(UI.count(fixable.count, "file")) (\(Format.bytes(total))).")
                return
            }
            if dryRun {
                for finding in fixable { UI.step("Would remove \(finding.path ?? finding.title)") }
                return
            }
            guard yes || UI.confirm("Remove \(UI.count(fixable.count, "file")) (\(Format.bytes(total))) from the PS3?") else { return }
            for result in try await service.fix(fixable) {
                if let skipped = result.skipped { UI.skip("\(result.finding.title): \(skipped)") } else { UI.ok("Removed: \(result.finding.title)") }
            }
        }
    }

    struct BlockUpdates: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "block-updates",
            abstract: "Keep the PS3 from downloading a system update by mistake.",
            discussion: """
            Puts webMAN MOD's own /dev_hdd0/ps3-updatelist.txt on the PS3.
            webMAN then points the XMB's update check at it on every start,
            and it sends the update to 127.0.0.1. Nothing in dev_flash is
            touched. Takes effect from the next start; --off removes the file.
            """
        )

        @OptionGroup var global: GlobalOptions

        @Flag(name: .long, help: "Stop blocking (remove the file).")
        var off = false

        @Flag(name: .long, help: "Show what would happen.")
        var dryRun = false

        func run() async throws {
            let host = try await Console.host(global)
            let installed = try await UpdateBlock.isInstalled(host: host)
            if installed != off {
                UI.skip(off ? "System updates are not blocked." : "System updates are already blocked.")
                return
            }
            try await UpdateBlock.set(!off, host: host, dryRun: dryRun) { UI.ok($0) }
        }
    }
}

struct Analyze: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "What takes up space on /dev_hdd0, folder by folder (counted on the console with webMAN's /stat.ps3)."
    )

    @OptionGroup var global: GlobalOptions

    @Flag(name: .long, help: "Print JSON.")
    var json = false

    func run() async throws {
        let host = try await Console.host(global, quiet: json)
        let map = try await StorageAnalyzer(host: host).analyze { if !json { UI.progress("Counting \($0)") } }
        if !json { UI.endProgress() }
        if json { UI.json(map); return }
        let total = Double(map.total ?? max(1, map.areas.reduce(0) { $0 + $1.bytes }))
        UI.header("Storage", detail: map.free.map { "\(Format.bytes($0)) free" + (map.total.map { " of \(Format.bytes($0))" } ?? "") })
        for area in map.areas {
            UI.row(area.name, "\(UI.bar(Double(area.bytes) / total, width: 20, color: .blue)) \(Format.bytes(area.bytes))", width: 30)
        }
        if let other = map.other, other > 0 { UI.row("Other and system", "\(UI.bar(Double(other) / total, width: 20, color: .gray)) \(Format.bytes(other))", width: 30) }
        if !map.largest.isEmpty {
            print("\n  " + UI.paint("Largest Files", .bold))
            for file in map.largest { UI.row(Format.bytes(file.bytes), file.path) }
        }
    }
}

struct Rip: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Copy the PS3 disc in the drive to /dev_hdd0/GAMES (webMAN does the work on the console).",
        discussion: "Your own discs only. Ctrl-C stops following the progress; `ps3 rip --abort` stops the copy."
    )

    @OptionGroup var global: GlobalOptions

    @Flag(name: .long, help: "Stop a copy in progress.")
    var abort = false

    @Flag(name: [.short, .long], help: "Do not ask.")
    var yes = false

    @Flag(name: .long, help: "Show what would happen.")
    var dryRun = false

    func run() async throws {
        let host = try await Console.host(global)
        let ripper = DiscRipper(host: host)
        if abort {
            try await ripper.abort()
            UI.ok("The copy is stopping")
            return
        }
        guard let disc = try await ripper.disc() else {
            throw PS3Error.refused("No PS3 disc in the drive.")
        }
        UI.header(disc.title, detail: disc.titleID)
        UI.row("Size", Format.bytes(disc.bytes))
        UI.row("To", disc.destination)
        if dryRun { UI.step("Would copy the disc to \(disc.destination)"); return }
        guard yes || UI.confirm("Copy the disc to the PS3's hard drive?") else { return }
        let started = Date()
        try await ripper.rip(disc) { copied in
            let fraction = disc.bytes > 0 ? Double(copied) / Double(disc.bytes) : 0
            UI.progress("\(UI.bar(fraction, width: 24)) \(Format.bytes(copied)) of \(Format.bytes(disc.bytes))")
        }
        UI.endProgress()
        UI.ok("Done in \(Format.duration(Date().timeIntervalSince(started))). Refresh the game list with `ps3 refresh`.")
    }
}
