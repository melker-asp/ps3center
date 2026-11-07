import ArgumentParser
import Foundation
import PS3Kit

/// PS3 ISO Tools (aldostools, Windows) and Estwald's makeps3iso, extractps3iso and splitps3iso,
/// on the Mac. Nothing here touches the console.
struct ISO: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "iso",
        abstract: "Make an ISO from a game folder, extract an ISO, split for FAT32 and join (like PS3 ISO Tools).",
        discussion: """
        ps3 iso make ~/Games/GAMES/Game                     Game.iso next to the folder
        ps3 iso make ~/Games/GAMES/Game /Volumes/PS3/PS3ISO   To a FAT32 drive, in 4 GB parts
        ps3 iso split Game.iso                              Game.iso.0, .iso.1 … (FAT32)
        ps3 iso join Game.iso.0                             Back to a Game.iso
        ps3 iso extract Game.iso                            A game folder from the ISO
        None of this touches the PS3. `ps3 usb prepare` does the same by
        itself for games going to a USB drive.
        """,
        subcommands: [Make.self, Split.self, Join.self, Extract.self]
    )

    struct Make: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Make a PS3 ISO from a game folder (PS3_GAME/…), like makeps3iso.",
            discussion: """
            The folder must have PS3_GAME/PARAM.SFO. Files split for FAT32
            (.66600, .66601 …) become one file again. The system update on the
            disc (PS3_UPDATE) is left out. On a FAT32 drive the ISO is split
            into .iso.0, .iso.1 … automatically when it is over 4 GB.
            """
        )

        @Argument(help: "The game folder.", completion: .directory)
        var folder: String

        @Argument(help: "Folder or .iso to write to (otherwise next to the game folder).", completion: .file())
        var destination: String?

        @Flag(name: .long, help: "Split into .iso.0, .iso.1 … if the ISO is over 4 GB, even on a drive that is not FAT32.")
        var split = false

        @Flag(name: .long, help: "Show what would be done.")
        var dryRun = false

        func run() throws {
            let source = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath)
            let builder = try PS3ISOBuilder(folder: source)
            let target = ISOPaths.target(for: source, destination: destination)
            // The drive, also when the destination folder is not made yet (PS3ISO on a new drive).
            let volume = USBDrive.volume(containing: target.deletingLastPathComponent())
            let onFAT32 = volume?.isFAT32 == true
            let splits = builder.size > PS3ISO.partSize && (split || onFAT32)
            let parts = splits ? PS3ISO.partCount(for: builder.size) : 1
            let first = splits ? URL(fileURLWithPath: target.path + ".0") : target

            UI.header(dryRun ? "Preview" : "Making an ISO",
                      detail: "\(builder.title) · \(builder.titleID) · \(UI.count(builder.fileCount, "file")) · \(Format.bytes(builder.size))")
            if !builder.leftOut.isEmpty {
                UI.skip("PS3_UPDATE is left out (the system update on the disc, \(UI.count(builder.leftOut.count, "file")))")
            }
            if builder.size > PS3ISO.partSize, !splits {
                UI.warn("The ISO will be over 4 GB and will not fit on a FAT32 drive. Add --split for 4 GB parts.")
            }
            guard !FileManager.default.fileExists(atPath: first.path) else {
                throw PS3Error.refused("\(first.lastPathComponent) already exists in \(first.deletingLastPathComponent().path).")
            }
            if let volume, volume.free < builder.size {
                throw PS3Error.refused("Not enough space on \(volume.name): needs \(Format.bytes(builder.size)), \(Format.bytes(volume.free)) free.")
            }
            UI.step("\(source.lastPathComponent) → \(UI.paint(first.path, .gray))" + (parts > 1 ? UI.paint("  (\(parts) parts)", .gray) : ""))
            guard !dryRun else { return }

            let progress = FileProgress(source: source, target: first, size: builder.size, title: builder.title, announce: false)
            let files = try builder.write(to: target, split: splits) { progress.update($0, builder.size) }
            progress.finish()
            for file in files where files.count > 1 { UI.skip(file.lastPathComponent) }
        }
    }

    struct Split: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Split an ISO over 4 GB into .iso.0, .iso.1 … for a FAT32 drive, like splitps3iso.",
            discussion: "webMAN starts the parts as one ISO. The original is left in place."
        )

        @Argument(help: "The ISO.", completion: .file(extensions: ["iso"]))
        var iso: String

        @Argument(help: "Folder to put the parts in (otherwise next to the ISO).", completion: .directory)
        var destination: String?

        func run() throws {
            let source = URL(fileURLWithPath: (iso as NSString).expandingTildeInPath)
            let folder = destination.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            let size = FileRouter.fileSize(source)
            let first = (folder ?? source.deletingLastPathComponent()).appendingPathComponent(source.lastPathComponent + ".0")
            UI.header("Splitting", detail: "\(source.lastPathComponent) · \(Format.bytes(size)) · \(UI.count(PS3ISO.partCount(for: size), "part"))")
            let progress = FileProgress(source: source, target: first, size: size, title: nil)
            let parts = try PS3ISO.split(source, into: folder) { progress.update($0, $1) }
            progress.finish()
            for part in parts { UI.skip(part.path) }
            UI.step("\(source.lastPathComponent) is still there. Delete it once the parts are on the drive.")
        }
    }

    struct Join: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Join .iso.0, .iso.1 … into one ISO.")

        @Argument(help: "The first part (.iso.0).", completion: .file())
        var first: String

        @Argument(help: "Folder to put the ISO in (otherwise next to the parts).", completion: .directory)
        var destination: String?

        func run() throws {
            let source = URL(fileURLWithPath: (first as NSString).expandingTildeInPath)
            let folder = destination.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            let parts = PS3ISO.parts(startingAt: source)
            let size = parts.map(FileRouter.fileSize).reduce(0, +)
            let target = (folder ?? source.deletingLastPathComponent()).appendingPathComponent(String(source.lastPathComponent.dropLast(2)))
            UI.header("Joining", detail: "\(UI.count(parts.count, "part")) · \(Format.bytes(size))")
            let progress = FileProgress(source: source, target: target, size: size, title: nil)
            let iso = try PS3ISO.join(source, into: folder) { progress.update($0, $1) }
            progress.finish()
            UI.skip(iso.path)
        }
    }

    struct Extract: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Extract a PS3 ISO to a game folder (GAMES), like extractps3iso.",
            discussion: "The system update on the disc (PS3_UPDATE) is not extracted."
        )

        @Argument(help: "The ISO.", completion: .file(extensions: ["iso"]))
        var iso: String

        @Argument(help: "The game folder to create (otherwise the ISO's name next to it).", completion: .directory)
        var destination: String?

        func run() throws {
            let source = URL(fileURLWithPath: (iso as NSString).expandingTildeInPath)
            let folder = destination.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            let target = folder ?? source.deletingPathExtension()
            let image = try ISOImage(url: source, joliet: true)
            let files = try image.allFiles()
            if let big = files.map(\.size).max(), big > UInt64(PS3ISO.partSize),
               USBDrive.volume(containing: target.deletingLastPathComponent())?.isFAT32 == true {
                throw PS3Error.refused("The ISO has a file over 4 GB, which FAT32 cannot hold. Keep the ISO as an ISO, or split it with `ps3 iso split`.")
            }
            let size = Int64(files.reduce(0) { $0 + $1.size })
            UI.header("Extracting", detail: "\(source.lastPathComponent) · \(UI.count(files.count, "file")) · \(Format.bytes(size))")
            let progress = FileProgress(source: source, target: target, size: size, title: nil)
            let result = try PS3ISO.extract(source, into: folder) { progress.update($0, $1) }
            progress.finish()
            if !result.leftOut.isEmpty {
                UI.skip("PS3_UPDATE was not extracted (the system update on the disc)")
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
    let printer = TransferPrinter(dryRun: false, done: "done")
    let start = Date()
    private var last = Date.distantPast
    /// "source → target", printed with the first bytes, so a refusal comes before it.
    private var announcement: Route?

    /// `announce` prints "source → target"; leave it out when the command already has.
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
