import ArgumentParser
import Foundation
import PS3Kit

/// PS3 ISO Tools (aldostools, Windows) and Estwald's makeps3iso, extractps3iso and splitps3iso,
/// on the Mac. Nothing here touches the console.
struct ISO: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "iso",
        abstract: "Gör en ISO av en spelmapp, packa upp en ISO, dela för FAT32 och foga ihop (som PS3 ISO Tools).",
        discussion: """
        ps3 iso make ~/Spel/GAMES/Spel                    Spel.iso bredvid mappen
        ps3 iso make ~/Spel/GAMES/Spel /Volumes/PS3/PS3ISO  Direkt till en FAT32-disk, i delar om 4 GB
        ps3 iso split Spel.iso                            Spel.iso.0, .iso.1 … för FAT32
        ps3 iso join Spel.iso.0                           Tillbaka till en Spel.iso
        ps3 iso extract Spel.iso                          En spelmapp (GAMES) av ISO:n
        Inget av det här rör PS3:an. `ps3 usb prepare` gör det samma av sig själv för spel som ska till en USB-disk.
        """,
        subcommands: [Make.self, Split.self, Join.self, Extract.self]
    )

    struct Make: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Gör en PS3-ISO av en spelmapp (PS3_GAME/…), som makeps3iso.",
            discussion: """
            Mappen ska ha PS3_GAME/PARAM.SFO. Filer som delats för FAT32 (.66600, .66601 …) blir en fil
            igen. Systemuppdateringen på skivan (PS3_UPDATE) tas inte med. På en FAT32-disk delas ISO:n
            i .iso.0, .iso.1 … av sig själv när den är över 4 GB.
            """
        )

        @Argument(help: "Spelmappen.", completion: .directory)
        var folder: String

        @Argument(help: "Mapp eller .iso att skriva till (annars bredvid spelmappen).", completion: .file())
        var destination: String?

        @Flag(name: .long, help: "Dela i .iso.0, .iso.1 … om ISO:n är över 4 GB, även på en disk som inte är FAT32.")
        var split = false

        @Flag(name: .long, help: "Visa vad som skulle göras.")
        var dryRun = false

        func run() throws {
            let source = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath)
            let builder = try PS3ISOBuilder(folder: source)
            let target = ISOPaths.target(for: source, destination: destination)
            let onFAT32 = USBDrive.volume(target.deletingLastPathComponent())?.isFAT32 == true
            let splits = builder.size > PS3ISO.partSize && (split || onFAT32)
            let parts = splits ? PS3ISO.partCount(for: builder.size) : 1
            let first = splits ? URL(fileURLWithPath: target.path + ".0") : target

            UI.header(dryRun ? "Förhandsvisning" : "Gör en ISO",
                      detail: "\(builder.title) · \(builder.titleID) · \(builder.fileCount) filer · \(Format.bytes(builder.size))")
            if !builder.leftOut.isEmpty {
                UI.skip("PS3_UPDATE tas inte med (systemuppdateringen på skivan, \(builder.leftOut.count) filer)")
            }
            if builder.size > PS3ISO.partSize, !splits {
                UI.warn("ISO:n blir över 4 GB och får inte plats på en FAT32-disk. Lägg till --split för delar om 4 GB.")
            }
            guard !FileManager.default.fileExists(atPath: first.path) else {
                throw PS3Error.refused("\(first.lastPathComponent) finns redan i \(first.deletingLastPathComponent().path).")
            }
            if let free = USBDrive.volume(target.deletingLastPathComponent())?.free, free < builder.size {
                throw PS3Error.notEnoughSpace(needed: builder.size, free: free)
            }
            UI.step("\(source.lastPathComponent) → \(UI.paint(first.path, .gray))" + (parts > 1 ? UI.paint("  (\(parts) delar)", .gray) : ""))
            guard !dryRun else { return }

            let progress = FileProgress(source: source, target: first, size: builder.size, title: builder.title, announce: false)
            let files = try builder.write(to: target, split: splits) { progress.update($0, builder.size) }
            progress.finish()
            for file in files where files.count > 1 { UI.skip(file.lastPathComponent) }
        }
    }

    struct Split: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Dela en ISO över 4 GB i .iso.0, .iso.1 … för en FAT32-disk, som splitps3iso.",
            discussion: "webMAN startar delarna som en ISO. Originalet lämnas kvar."
        )

        @Argument(help: "ISO:n.", completion: .file(extensions: ["iso"]))
        var iso: String

        @Argument(help: "Mapp att lägga delarna i (annars bredvid ISO:n).", completion: .directory)
        var destination: String?

        func run() throws {
            let source = URL(fileURLWithPath: (iso as NSString).expandingTildeInPath)
            let folder = destination.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            let size = FileRouter.fileSize(source)
            let first = (folder ?? source.deletingLastPathComponent()).appendingPathComponent(source.lastPathComponent + ".0")
            UI.header("Delar", detail: "\(source.lastPathComponent) · \(Format.bytes(size)) · \(PS3ISO.partCount(for: size)) delar")
            let progress = FileProgress(source: source, target: first, size: size, title: nil)
            let parts = try PS3ISO.split(source, into: folder) { progress.update($0, $1) }
            progress.finish()
            for part in parts { UI.skip(part.path) }
            UI.step("\(source.lastPathComponent) finns kvar. Ta bort den när delarna ligger på disken.")
        }
    }

    struct Join: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Foga ihop .iso.0, .iso.1 … till en ISO.")

        @Argument(help: "Den första delen (.iso.0).", completion: .file())
        var first: String

        @Argument(help: "Mapp att lägga ISO:n i (annars bredvid delarna).", completion: .directory)
        var destination: String?

        func run() throws {
            let source = URL(fileURLWithPath: (first as NSString).expandingTildeInPath)
            let folder = destination.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            let parts = PS3ISO.parts(startingAt: source)
            let size = parts.map(FileRouter.fileSize).reduce(0, +)
            let target = (folder ?? source.deletingLastPathComponent()).appendingPathComponent(String(source.lastPathComponent.dropLast(2)))
            UI.header("Fogar ihop", detail: "\(parts.count) delar · \(Format.bytes(size))")
            let progress = FileProgress(source: source, target: target, size: size, title: nil)
            let iso = try PS3ISO.join(source, into: folder) { progress.update($0, $1) }
            progress.finish()
            UI.skip(iso.path)
        }
    }

    struct Extract: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Packa upp en PS3-ISO till en spelmapp (GAMES), som extractps3iso.",
            discussion: "Systemuppdateringen på skivan (PS3_UPDATE) packas inte upp."
        )

        @Argument(help: "ISO:n.", completion: .file(extensions: ["iso"]))
        var iso: String

        @Argument(help: "Spelmappen som skapas (annars ISO:ns namn bredvid den).", completion: .directory)
        var destination: String?

        func run() throws {
            let source = URL(fileURLWithPath: (iso as NSString).expandingTildeInPath)
            let folder = destination.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            let target = folder ?? source.deletingPathExtension()
            let image = try ISOImage(url: source, joliet: true)
            let files = try image.allFiles()
            if let big = files.map(\.size).max(), big > UInt64(PS3ISO.partSize),
               USBDrive.volume(target.deletingLastPathComponent())?.isFAT32 == true {
                throw PS3Error.refused("ISO:n har en fil över 4 GB, som FAT32 inte rymmer. Låt ISO:n vara en ISO, eller dela den med `ps3 iso split`.")
            }
            let size = Int64(files.reduce(0) { $0 + $1.size })
            UI.header("Packar upp", detail: "\(source.lastPathComponent) · \(files.count) filer · \(Format.bytes(size))")
            let progress = FileProgress(source: source, target: target, size: size, title: nil)
            let result = try PS3ISO.extract(source, into: folder) { progress.update($0, $1) }
            progress.finish()
            if !result.leftOut.isEmpty {
                UI.skip("PS3_UPDATE packades inte upp (systemuppdateringen på skivan)")
            }
            UI.skip(result.folder.path)
        }
    }
}

enum ISOPaths {
    /// Game.iso for a game folder: the destination as given when it ends in .iso, else the
    /// folder's name (FAT32-safe) in the destination folder or beside the game folder.
    static func target(for folder: URL, destination: String?) -> URL {
        let name = PS3ISO.fatName(folder.lastPathComponent) + ".iso"
        guard let destination else { return folder.deletingLastPathComponent().appendingPathComponent(name) }
        let url = URL(fileURLWithPath: (destination as NSString).expandingTildeInPath)
        return url.pathExtension.lowercased() == "iso" ? url : url.appendingPathComponent(name)
    }
}

/// Bytes written on the Mac as TransferPrinter's progress line, a few times a second.
final class FileProgress {
    let route: Route
    let printer = TransferPrinter(dryRun: false, done: "klar")
    let start = Date()
    private var last = Date.distantPast
    /// "källa → mål", printed with the first bytes, so a refusal comes before it.
    private var announcement: Route?

    /// `announce` prints "källa → mål"; leave it out when the command already has.
    init(source: URL, target: URL, size: Int64, title: String?, announce: Bool = true) {
        route = Route(local: target, remote: target.path, kind: .other, size: size, title: title)
        if announce {
            announcement = Route(local: source, remote: target.path, kind: .other, size: size, title: title)
        }
    }

    func update(_ written: Int64, _ total: Int64) {
        if let announcement {
            printer.handle(.started(announcement, resumingFrom: 0))
            self.announcement = nil
        }
        let now = Date()
        guard now.timeIntervalSince(last) >= 0.25 else { return }
        last = now
        printer.handle(.progress(route, sent: written, total: total, bytesPerSecond: Double(written) / max(now.timeIntervalSince(start), 0.001)))
    }

    func finish() {
        printer.handle(.finished(route, seconds: Date().timeIntervalSince(start)))
    }
}
