import ArgumentParser
import Foundation
import PS3Kit

struct Record: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start or stop recording the running game (webMAN, 720p MP4).",
        discussion: "The video ends up in /dev_hdd0/VIDEO on the PS3. Fetch it to the Mac with `ps3 media pull`."
    )

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        let host = try await Console.host(global)
        let recording = try await WebMAN(host: host).toggleRecording()
        if recording {
            UI.ok("Recording. Run `ps3 record` again to stop.")
        } else {
            UI.ok("The recording is done and is in /dev_hdd0/VIDEO.")
        }
    }
}

struct Media: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Videos and screenshots from the PS3 to the Mac.",
        discussion: """
        ps3 media                    What is new on the PS3 since last time
        ps3 media pull               Copy it to ~/Pictures/PS3 Center
        ps3 media screenshots        Allow screenshots in all games (until restart)
        Nothing is deleted from the PS3.
        """,
        subcommands: [List.self, Pull.self, Screenshots.self],
        defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show videos and photos that have not been copied yet.")

        @OptionGroup var global: GlobalOptions

        func run() async throws {
            let host = try await Console.host(global)
            let items = try await MediaImport(host: host).newItems()
            UI.header("New on the PS3", detail: UI.count(items.count, "file"))
            for item in items { UI.row(item.isVideo ? "Video" : "Photo", "\(item.remotePath) · \(Format.bytes(item.size))") }
            if !items.isEmpty { print("\n  " + UI.paint("ps3 media pull", .bold) + " copies them to the Mac.") }
        }
    }

    struct Pull: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Copy new videos and photos to the Mac.")

        @OptionGroup var global: GlobalOptions

        @Option(name: .long, help: "Folder on the Mac (default: ~/Pictures/PS3 Center).", completion: .directory)
        var to: String?

        func run() async throws {
            let host = try await Console.host(global)
            let service = MediaImport(host: host)
            let items = try await service.newItems()
            guard !items.isEmpty else { UI.skip("Nothing new to copy."); return }
            let folder = to.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) } ?? MediaImport.defaultFolder
            let written = try await service.copy(items, to: folder) { done, total in UI.progress("Copying \(min(done + 1, total)) of \(total)…") }
            UI.endProgress()
            UI.ok("\(UI.count(written.count, "file")) in \(folder.path)")
        }
    }

    struct Screenshots: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Allow the XMB's screenshots in all games (until the next restart).",
            discussion: "Take the picture with the PS button → Save Screenshot during the game. It ends up among the photos in the XMB."
        )

        @OptionGroup var global: GlobalOptions

        @Flag(name: .long, help: "Show what would happen.")
        var dryRun = false

        func run() async throws {
            let host = try await Console.host(global)
            if dryRun { UI.step("Would turn on screenshots in games (/xmb.ps3$ingame_screenshot)"); return }
            try await WebMAN(host: host).enableGameScreenshots()
            UI.ok("Screenshots are allowed in games until the next restart.")
        }
    }
}

struct Beep: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Make the PS3 beep, to find it or see that it is listening.")

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Number of beeps, 1–3.")
    var count: Int = 3

    func run() async throws {
        let host = try await Console.host(global)
        try await WebMAN(host: host).beep(count)
        UI.ok("Beep!")
    }
}

struct Music: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Let music from the XMB play during games, or turn it off (until the next restart).",
        discussion: "webMAN cannot read the setting, only set it."
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "on or off.")
    var state: String

    @Flag(name: .long, help: "Show what would happen.")
    var dryRun = false

    func validate() throws {
        guard ["on", "off", "på", "av"].contains(state.lowercased()) else { throw ValidationError("Give on or off.") }
    }

    func run() async throws {
        let on = ["on", "på"].contains(state.lowercased())
        let host = try await Console.host(global)
        if dryRun { UI.step("Would turn \(on ? "on" : "off") music in games"); return }
        try await WebMAN(host: host).setGameMusic(on)
        UI.ok(on ? "Music from the XMB plays during games" : "Music during games is turned off")
    }
}

struct Verify: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check a copy of a PS3 disc against the original (IRD).",
        discussion: """
        ps3 verify ~/Games/PS3/Game.dec.iso    A decrypted ISO on the Mac
        ps3 verify ~/Games/GAMES/BLES01234     A game folder on the Mac
        ps3 verify gran                        A game folder on the PS3 (from ps3 rip)
        The IRD file is fetched from FlexBy420's database on GitHub, or given
        with --ird. Each file's MD5 is compared with the original disc's.
        Encrypted ISOs (redump, 3k3y) cannot be checked. Nothing is changed.
        """
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "An ISO or folder on the Mac, or a game on the PS3.")
    var target: [String]

    @Option(name: .long, help: "Your own .ird file.", completion: .file(extensions: ["ird"]))
    var ird: String?

    @Flag(name: .long, help: "Print JSON.")
    var json = false

    func validate() throws {
        guard !target.isEmpty else { throw ValidationError("Give an ISO, a folder or a game.") }
    }

    func run() async throws {
        let joined = target.joined(separator: " ")
        let url = URL(fileURLWithPath: (joined as NSString).expandingTildeInPath)
        var host: String?
        let checked: DiscVerifier.Target
        if FileManager.default.fileExists(atPath: url.path) {
            guard let local = DiscVerifier.Target.local(url) else {
                throw PS3Error.invalidFile("\(url.lastPathComponent) is neither an ISO nor a game folder with PS3_GAME.")
            }
            checked = local
        } else {
            let console = try await Console.host(global)
            host = console
            let game = try await Games.find(target, host: console)
            guard game.canVerifyWithIRD else {
                throw PS3Error.refused("\(game.title) is not a game folder. Check an ISO on the Mac instead, or a folder from ps3 rip.")
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
        UI.header("IRD Check", detail: report.title)
        if report.isIntact { UI.ok(report.summary) } else { UI.warn(report.summary) }
        for path in report.mismatched.prefix(20) { UI.row("Differs", path) }
        for path in report.missing.prefix(20) { UI.row("Missing", path) }
        if !report.extra.isEmpty { UI.row("Extra", "\(UI.count(report.extra.count, "file")) that were not on the disc") }
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
        abstract: "Explain an error code from the PS3, e.g. 80010006."
    )

    @Argument(help: "The error code.")
    var code: String

    func run() throws {
        guard let value = ConsoleErrorCode.parse(code) else { throw ValidationError("\(code) does not look like an error code (eight hex digits).") }
        guard let info = ConsoleErrorCode.info(value) else {
            UI.warn("\(code) is not in the list. PS3 Center only knows the system's 8001xxxx codes.")
            return
        }
        UI.ok(ConsoleErrorCode.describe(info))
    }
}
