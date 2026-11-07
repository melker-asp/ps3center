import ArgumentParser
import Foundation
import PS3Kit

/// PS2 Classics on the Mac, as PS2 Classic GUI makes them on Windows. The keys are Sony's and are
/// kept only on this Mac (~/.config/ps3center/ps2classic-keys.json); the code holds their SHA-256.
struct PS2: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ps2",
        abstract: "Turn your own PS2 games into PS2 Classics (.BIN.ENC), the only way they start on HEN.",
        discussion: """
        ps3 ps2 keys --fetch                 Fetch the keys from webMAN MOD (once)
        ps3 ps2 classic "God of War.iso"     Makes God of War [SCES-53133].BIN.ENC
        ps3 send "God of War [SCES-53133].BIN.ENC"
        The PS3 needs PS2 Classics Launcher (ps3 apps install ps2launcher);
        PS3HEN makes the license itself.
        """,
        subcommands: [Keys.self, Classic.self]
    )

    struct Keys: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show, fetch or import the keys for PS2 Classics. They are only stored on the Mac.",
            discussion: """
            --fetch downloads ps2classic_for_multidisc.7z and
            ps2classic_misc.7z from webMAN MOD's repo on GitHub
            (_Projects_/tools), reads the six values and checks them against
            PS3 Center's fingerprints. --import takes ps2classic.c, the
            placeholder's .rifkey or the same .7z archives, e.g. from PS2
            Classic GUI.
            """
        )

        @Flag(name: .long, help: "Fetch the keys from webMAN MOD's repo on GitHub.")
        var fetch = false

        @Option(name: .customLong("import"), parsing: .upToNextOption, help: "ps2classic.c, .rifkey or .7z to read the keys from.")
        var files: [String] = []

        @Flag(name: .long, help: "Remove the keys from the Mac.")
        var remove = false

        func run() async throws {
            if remove {
                try PS2ClassicKeys.remove()
                UI.ok("The keys have been removed from the Mac.")
                return
            }
            if fetch {
                UI.step("Fetching from webMAN MOD's repo on GitHub…")
                _ = try await PS2ClassicKeys.fetch()
                UI.ok("The keys are fetched, checked and saved in ~/.config/ps3center (for you only).")
            } else if !files.isEmpty {
                var keys = PS2ClassicKeys.load() ?? PS2ClassicKeys()
                let read = try PS2ClassicKeys.read(files.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) })
                keys = PS2ClassicKeys(values: keys.values.merging(read.values) { $1 })
                if !keys.wrong.isEmpty { throw PS3Error.invalidFile(keys.problem ?? "Wrong keys.") }
                try keys.save()
                UI.ok("Read \(read.values.count) of 6 values.")
            }
            let keys = PS2ClassicKeys.load()
            UI.header("Keys for PS2 Classics")
            for name in PS2ClassicKeys.Name.allCases {
                if keys?.values[name] == nil {
                    UI.skip("\(name.source): missing")
                } else if keys?.wrong.contains(name) == true {
                    UI.fail("\(name.source): wrong value")
                } else {
                    UI.ok(name.source)
                }
            }
            if keys?.isComplete != true {
                UI.step("Fetch them with `ps3 ps2 keys --fetch`, or import them with `--import`.")
            }
        }
    }

    struct Classic: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Make a PS2 Classic (.BIN.ENC) from a PS2 ISO, or a .cue/.bin, like PS2 Classic GUI.",
            discussion: """
            The ISO is not changed. The file gets the game's title ID in its
            name, so webMAN finds its fix in the PS2 CONFIG Database. Then
            send it with `ps3 send`: it ends up in /dev_hdd0/PS2ISO.
            """
        )

        @Argument(help: "The PS2 game: .iso, .cue or .bin.", completion: .file(extensions: ["iso", "cue", "bin"]))
        var image: String

        @Argument(help: "Folder to put the .BIN.ENC in (otherwise next to the game).", completion: .directory)
        var destination: String?

        @Flag(name: .long, help: "Show what would be done.")
        var dryRun = false

        func run() throws {
            let source = URL(fileURLWithPath: (image as NSString).expandingTildeInPath)
            let titleID = try PS2ClassicMaker.check(source)
            let folder = destination.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? source.deletingLastPathComponent()
            let output = folder.appendingPathComponent(PS2ClassicMaker.outputName(for: source, titleID: titleID))
            let imageSize = FileRouter.fileSize(try PS2ClassicMaker.dataFile(for: source))
            let size = PS2ClassicMaker.encryptedSize(forImage: imageSize)
            UI.header(dryRun ? "Preview" : "PS2 Classic", detail: [titleID, Format.bytes(size)].compactMap { $0 }.joined(separator: " · "))
            guard !FileManager.default.fileExists(atPath: output.path) else {
                throw PS3Error.refused("\(output.lastPathComponent) already exists.")
            }
            guard let keys = PS2ClassicKeys.load(), keys.isComplete else {
                throw PS3Error.refused("The keys for PS2 Classics are not on the Mac. Fetch them with `ps3 ps2 keys --fetch`.")
            }
            if let free = USBDrive.volume(folder)?.free, free < size {
                throw PS3Error.notEnoughSpace(needed: size, free: free)
            }
            UI.step("\(source.lastPathComponent) → \(UI.paint(output.path, .gray))")
            guard !dryRun else { return }
            let progress = FileProgress(source: source, target: output, size: size, title: titleID, announce: false)
            try PS2ClassicMaker.make(from: source, to: output, keys: keys) { progress.update($0, $1) }
            progress.finish()
            UI.step("Send it with `ps3 send \"\(output.path)\"`. The PS3 needs PS2 Classics Launcher (`ps3 apps install ps2launcher`).")
        }
    }
}
