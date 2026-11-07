import Foundation

// MARK: XMB

extension WebMAN {
    /// Reads the game list again and reloads the XMB, so new icons show and removed ones go
    /// (`/refresh.ps3?xmb`, include/cmd/refresh.h). Only on the XMB: webMAN skips the reload
    /// during a game. With one user on the console and Reload XMB installed webMAN starts that
    /// app; otherwise it logs the user out and in with virtual pad presses (reload_xmb in
    /// include/init/vsh.h). Logged.
    public func reloadXMB() async throws {
        OperationLog.record(.reloadXMB, host)
        try await long("/refresh.ps3?xmb", timeout: 90)
    }

    /// True when webMAN reloads the XMB by starting Reload XMB, without pad presses: the app is
    /// installed and the console has a single user.
    public func reloadsXMBQuietly() async throws -> Bool {
        try await TransferService(host: host).withFTP { ftp in
            guard try await ftp.size("/dev_hdd0/game/RELOADXMB/PARAM.SFO") != nil else { return false }
            let users = try await ftp.list("/dev_hdd0/home").filter(\.isDirectory)
            return users.count == 1
        }
    }
}

/// After an app or installed game is removed: reload the XMB when webMAN can do it with Reload
/// XMB (one user), so the icon goes; otherwise say how. Returns the sentence for the user.
enum XMBReload {
    static func afterRemoval(host: String) async -> String {
        let webman = WebMAN(host: host)
        if (try? await webman.reloadsXMBQuietly()) == true, (try? await webman.reloadXMB()) != nil {
            return "The XMB was reloaded, so the icon is gone."
        }
        return "The icon stays in the XMB until it is reloaded: Reload XMB in the Status tab, or ps3 refresh --xmb."
    }
}

// MARK: Recording and screenshots

/// webMAN's game recorder (`/videorec.ps3`, include/feat/video_rec.h): only during a game, as
/// 720p MP4 in /dev_hdd0/VIDEO named "<title ID>_<date>.mp4". The answer says whether it records.
extension WebMAN {
    public static let videoFolder = "/dev_hdd0/VIDEO"
    /// Where the XMB keeps photos, screenshots from games included.
    public static let photoFolder = "/dev_hdd0/photo"

    /// Starts or stops recording the running game and returns whether it now records. Logged.
    @discardableResult
    public func toggleRecording() async throws -> Bool {
        guard try await runningProcess() != nil else {
            throw PS3Error.refused("No game is running. webMAN only records while a game is running.")
        }
        let page = try await get("/videorec.ps3", timeout: 30)
        let recording = Self.isRecording(page)
        OperationLog.record(.record, recording ? "start" : "stop")
        return recording
    }

    /// "Video recording: Enabled" (STR_ENABLED) on the answer page.
    static func isRecording(_ page: String) -> Bool {
        guard let range = page.range(of: "Video recording:") else { return false }
        let rest = page[range.upperBound...].prefix(120)
        let text = rest.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("enabled")
    }

    /// Lets the XMB's own "save screenshot" work in every game (`/xmb.ps3$ingame_screenshot`,
    /// include/feat/ingame_screenshot.h). It lasts until the console restarts. Logged.
    public func enableGameScreenshots() async throws {
        OperationLog.record(.screenshots, "on in games")
        try await get("/xmb.ps3$ingame_screenshot", timeout: 15)
    }
}

/// Copies recordings and photos from the console to the Mac, once each. Nothing on the console
/// is changed or removed.
public struct MediaImport: Sendable {
    public struct Item: Equatable, Sendable, Identifiable {
        public let remotePath: String
        public let size: Int64
        public var id: String { remotePath }
        public var name: String { (remotePath as NSString).lastPathComponent }
        public var isVideo: Bool { name.lowercased().hasSuffix(".mp4") }

        package init(remotePath: String, size: Int64) {
            self.remotePath = remotePath
            self.size = size
        }
    }

    public let host: String
    public init(host: String) { self.host = host }

    public static let mediaExtensions = ["mp4", "jpg", "jpeg", "png", "bmp"]

    /// The default folder on the Mac: ~/Pictures/PS3 Center.
    public static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/PS3 Center", isDirectory: true)
    }

    /// What has been copied before, by console path and size.
    static var memoryFile: URL { StatePaths.support.appendingPathComponent("imported.json") }
    static var memory: JSONFile<[String]> { JSONFile(memoryFile, empty: []) }

    static func loadMemory() -> Set<String> { Set(memory.load()) }

    /// Remembers one more copied item. Throws when imported.json cannot be written, rather than
    /// letting the next import copy the same file again without a word.
    static func remember(_ key: String) throws {
        try memory.edit { keys in
            guard !keys.contains(key) else { return }
            keys.append(key)
            keys.sort()
        }
    }

    static func key(_ item: Item) -> String { "\(item.remotePath)|\(item.size)" }

    /// Recordings and photos on the console that have not been copied yet.
    public func newItems() async throws -> [Item] {
        let known = Self.loadMemory()
        return try await TransferService(host: host).withFTP { ftp in
            var items: [Item] = []
            for folder in [WebMAN.videoFolder, WebMAN.photoFolder] {
                try await collect(folder, ftp: ftp, depth: 0, into: &items)
            }
            return items.filter { !known.contains(Self.key($0)) }
        }
    }

    private func collect(_ path: String, ftp: FTPClient, depth: Int, into items: inout [Item]) async throws {
        guard depth < 4 else { return }
        for entry in try await ftp.list(path) {
            let child = path + "/" + entry.name
            if entry.isDirectory {
                try await collect(child, ftp: ftp, depth: depth + 1, into: &items)
            } else if Self.mediaExtensions.contains((entry.name as NSString).pathExtension.lowercased()), entry.size > 0 {
                items.append(Item(remotePath: child, size: entry.size))
            }
        }
    }

    /// The subfolders of the import folder for recordings and for photos.
    public static let videoFolderName = "Videos"
    public static let photoFolderName = "Photos"

    /// Renames the subfolders from their Swedish names (Filmer, Bilder) when only the old one
    /// exists; when both exist the new one is used and the old one is left alone.
    static func migrateNames(in folder: URL) {
        BackupFolder.migrate("Filmer", to: videoFolderName, in: folder)
        BackupFolder.migrate("Bilder", to: photoFolderName, in: folder)
    }

    /// Copies `items` into `folder` (videos and photos in their own subfolders) and remembers
    /// them. Returns the files written. A name already taken gets a number.
    public func copy(_ items: [Item], to folder: URL = MediaImport.defaultFolder,
                     progress: @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> [URL] {
        var written: [URL] = []
        let fm = FileManager.default
        Self.migrateNames(in: folder)
        for (index, item) in items.enumerated() {
            progress(index, items.count)
            let target = folder.appendingPathComponent(item.isVideo ? Self.videoFolderName : Self.photoFolderName, isDirectory: true)
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            let destination = Self.freeName(item.name, in: target)
            let partial = destination.appendingPathExtension("part")
            try await TransferService(host: host).withFTP { ftp in
                try await ftp.download(item.remotePath, to: partial, expectedSize: item.size)
            }
            try fm.moveItem(at: partial, to: destination)
            written.append(destination)
            try Self.remember(Self.key(item))
        }
        progress(items.count, items.count)
        return written
    }

    static func freeName(_ name: String, in folder: URL) -> URL {
        var candidate = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(number)" + (ext.isEmpty ? "" : ".\(ext)"))
            number += 1
        }
        return candidate
    }
}

// MARK: Sounds and music

extension WebMAN {
    /// The console's beeper, to find it or check that it listens (`/beep.ps3?<n>`,
    /// play_sound_id in include/notify/vsh_notify.h: 1–3 are buzzer beeps). Changes nothing.
    public func beep(_ count: Int = 3) async throws {
        try await get("/beep.ps3?\(min(max(count, 1), 3))", timeout: 8)
    }

    /// Lets music from the XMB keep playing during games, or stops it (`/sysbgm.ps3?1` or `?0`,
    /// include/cmd/sysbgm.h). webMAN cannot report the current setting: its "?" query changes it.
    /// Lasts until the console restarts. Logged.
    public func setGameMusic(_ on: Bool) async throws {
        OperationLog.record(.gameMusic, on ? "on" : "off")
        try await get("/sysbgm.ps3?\(on ? 1 : 0)", timeout: 15)
    }
}

// MARK: System updates

/// Keeps the console from downloading a system update by mistake. When
/// /dev_hdd0/ps3-updatelist.txt exists, webMAN points the XMB's update check at it on every
/// start (include/www/www_start.h), and the file sends every region's update to 127.0.0.1. The
/// file is webMAN MOD's own (_Projects_/updater/pkgfiles/USRDIR/ps3-updatelist.txt). Nothing in
/// dev_flash is touched; removing the file undoes it after a restart.
public enum UpdateBlock {
    public static let remotePath = "/dev_hdd0/ps3-updatelist.txt"

    /// webMAN MOD's ps3-updatelist.txt, byte for byte: two lines per region, blank lines between.
    public static let contents: Data = {
        let regions = ["83", "84", "85", "86", "87", "88", "89", "8A", "8B", "8C", "8D", "8F"]
        let blocks = regions.map {
            "Dest=\($0);CompatibleSystemSoftwareVersion=1.0000-;\n"
                + "Dest=\($0);ImageVersion=000108dd;SystemSoftwareVersion=5.0000;CDN=http://127.0.0.1/PS3UPDAT.PUP;CDN_Timeout=30;\n"
        }
        return Data(blocks.joined(separator: "\n").utf8)
    }()

    public static func isInstalled(host: String) async throws -> Bool {
        try await TransferService(host: host).withFTP { try await $0.size(remotePath) != nil }
    }

    /// Puts the file in place (or removes it with `on == false`). Takes effect at the next start.
    public static func set(_ on: Bool, host: String, dryRun: Bool = false, events: @Sendable (String) -> Void = { _ in }) async throws {
        if dryRun {
            events(on ? "Would write \(remotePath) (\(contents.count) bytes)" : "Would delete \(remotePath)")
            return
        }
        try await TransferService(host: host).withFTP { ftp in
            if on {
                try await ftp.upload(contents: contents, to: remotePath)
                guard try await ftp.size(remotePath) == Int64(contents.count) else {
                    throw PS3Error.ftpProtocol("\(remotePath) did not come out right on the PS3.")
                }
            } else if try await ftp.size(remotePath) != nil {
                try await ftp.delete(remotePath)
            }
        }
        OperationLog.record(.updateBlock, on ? "on" : "off")
        events(on ? "System updates are blocked from the next start." : "System updates are no longer blocked from the next start.")
    }
}
