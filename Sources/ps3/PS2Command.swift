import ArgumentParser
import Foundation
import PS3Kit

/// PS2 Classics on the Mac, as PS2 Classic GUI makes them on Windows. The keys are Sony's and are
/// kept only on this Mac (~/.config/ps3center/ps2classic-keys.json); the code holds their SHA-256.
struct PS2: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ps2",
        abstract: "Gör egna PS2-spel till PS2 Classics (.BIN.ENC), det enda sätt de startar på HEN.",
        discussion: """
        ps3 ps2 keys --fetch                 Hämta nycklarna ur webMAN MOD:s repo (en gång)
        ps3 ps2 classic "God of War.iso"     God of War [SCES-53133].BIN.ENC bredvid ISO:n
        ps3 send "God of War [SCES-53133].BIN.ENC"
        PS3:an behöver PS2 Classics Launcher (ps3 apps install ps2launcher); PS3HEN gör licensen själv.
        """,
        subcommands: [Keys.self, Classic.self]
    )

    struct Keys: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Visa, hämta eller importera nycklarna för PS2 Classics. De sparas bara på Macen.",
            discussion: """
            --fetch hämtar ps2classic_for_multidisc.7z och ps2classic_misc.7z ur webMAN MOD:s repo på GitHub
            (_Projects_/tools), läser de sex värdena och kontrollerar dem mot PS3 Centers fingeravtryck.
            --import tar ps2classic.c, platshållarens .rifkey eller samma .7z-arkiv, t.ex. från PS2 Classic GUI.
            """
        )

        @Flag(name: .long, help: "Hämta nycklarna ur webMAN MOD:s repo på GitHub.")
        var fetch = false

        @Option(name: .customLong("import"), parsing: .upToNextOption, help: "ps2classic.c, .rifkey eller .7z att läsa nycklarna ur.")
        var files: [String] = []

        @Flag(name: .long, help: "Ta bort nycklarna från Macen.")
        var remove = false

        func run() async throws {
            if remove {
                try PS2ClassicKeys.remove()
                UI.ok("Nycklarna är borttagna från Macen.")
                return
            }
            if fetch {
                UI.step("Hämtar ur webMAN MOD:s repo på GitHub…")
                _ = try await PS2ClassicKeys.fetch()
                UI.ok("Nycklarna är hämtade, kontrollerade och sparade i ~/.config/ps3center (bara för dig).")
            } else if !files.isEmpty {
                var keys = PS2ClassicKeys.load() ?? PS2ClassicKeys()
                let read = try PS2ClassicKeys.read(files.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) })
                keys = PS2ClassicKeys(values: keys.values.merging(read.values) { $1 })
                if !keys.wrong.isEmpty { throw PS3Error.invalidFile(keys.problem ?? "Fel nycklar.") }
                try keys.save()
                UI.ok("Läste \(read.values.count) av 6 värden.")
            }
            let keys = PS2ClassicKeys.load()
            UI.header("Nycklar för PS2 Classics")
            for name in PS2ClassicKeys.Name.allCases {
                if keys?.values[name] == nil {
                    UI.skip("\(name.source): saknas")
                } else if keys?.wrong.contains(name) == true {
                    UI.fail("\(name.source): fel värde")
                } else {
                    UI.ok(name.source)
                }
            }
            if keys?.isComplete != true {
                UI.step("Hämta dem med `ps3 ps2 keys --fetch`, eller importera dem med `--import`.")
            }
        }
    }

    struct Classic: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Gör en PS2 Classic (.BIN.ENC) av en PS2-ISO, eller en .cue/.bin, som PS2 Classic GUI.",
            discussion: """
            ISO:n ändras inte. Filen får spelets title ID i namnet, så att webMAN hittar dess rättning i
            PS2 CONFIG Database. Skicka den sedan med `ps3 send`: den hamnar i /dev_hdd0/PS2ISO.
            """
        )

        @Argument(help: "PS2-spelet: .iso, .cue eller .bin.", completion: .file(extensions: ["iso", "cue", "bin"]))
        var image: String

        @Argument(help: "Mapp att lägga .BIN.ENC i (annars bredvid spelet).", completion: .directory)
        var destination: String?

        @Flag(name: .long, help: "Visa vad som skulle göras.")
        var dryRun = false

        func run() throws {
            let source = URL(fileURLWithPath: (image as NSString).expandingTildeInPath)
            let titleID = try PS2ClassicMaker.check(source)
            let folder = destination.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? source.deletingLastPathComponent()
            let output = folder.appendingPathComponent(PS2ClassicMaker.outputName(for: source, titleID: titleID))
            let imageSize = FileRouter.fileSize(try PS2ClassicMaker.dataFile(for: source))
            let size = PS2ClassicMaker.encryptedSize(forImage: imageSize)
            UI.header(dryRun ? "Förhandsvisning" : "PS2 Classic", detail: [titleID, Format.bytes(size)].compactMap { $0 }.joined(separator: " · "))
            guard !FileManager.default.fileExists(atPath: output.path) else {
                throw PS3Error.refused("\(output.lastPathComponent) finns redan.")
            }
            guard let keys = PS2ClassicKeys.load(), keys.isComplete else {
                throw PS3Error.refused("Nycklarna för PS2 Classics finns inte på Macen. Hämta dem med `ps3 ps2 keys --fetch`.")
            }
            if let free = USBDrive.volume(folder)?.free, free < size {
                throw PS3Error.notEnoughSpace(needed: size, free: free)
            }
            UI.step("\(source.lastPathComponent) → \(UI.paint(output.path, .gray))")
            guard !dryRun else { return }
            let progress = FileProgress(source: source, target: output, size: size, title: titleID, announce: false)
            try PS2ClassicMaker.make(from: source, to: output, keys: keys) { progress.update($0, $1) }
            progress.finish()
            UI.step("Skicka den med `ps3 send \"\(output.path)\"`. PS3:an behöver PS2 Classics Launcher (`ps3 apps install ps2launcher`).")
        }
    }
}
