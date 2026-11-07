import Foundation

/// User settings shared by the CLI and the future Mac app.
/// Stored in ~/.config/ps3center/config.json (same layout idea as Mole's ~/.config/mole).
public struct PS3Config: Codable, Equatable, Sendable {
    public var host: String?
    /// The local folder that mirrors the console's file system (contains dev_hdd0/, USB/, _Installed/).
    public var root: String?
    /// The app's colour theme (Appearance). A plain string, so an unknown value from a newer
    /// version cannot make the whole file unreadable.
    public var theme: String?
    /// The Mac's game folders per kind ("PS3ISO", "PS2ISO" …), as linked in the app or with
    /// `ps3 config folder add`. See `GameFolders`.
    public var folders: [String: [String]]?
    /// Whether the app runs its game server (`NetServer`) for webMAN's /net0.
    public var netServer: Bool?
    /// Which of webMAN's network servers points at the game server: 0 for /net0 … 4 for /net4.
    public var netServerSlot: Int?
    /// Linked folders whose new games are queued by themselves (`FolderWatch`), as full paths.
    public var watchedFolders: [String]?
    /// The Mac's folders with .pkg files, as linked in the app (Apps → From Mac) or with
    /// `ps3 config folder add PKG`. See `PackageFolders`.
    public var packageFolders: [String]?
    /// FTP uploads: piece size in KB and pieces in flight (`FTPClient.Tuning`), to compare with
    /// the speed test. Defaults 1024 and 2.
    public var ftpChunkKB: Int?
    public var ftpWindow: Int?
    /// Updates the user chose to skip: catalog id → the release tag they skipped. See `IgnoredUpdates`.
    public var ignoredUpdates: [String: String]?

    public init(host: String? = nil, root: String? = nil, theme: String? = nil, folders: [String: [String]]? = nil) {
        self.host = host
        self.root = root
        self.theme = theme
        self.folders = folders
    }
}

public enum ConfigStore {
    public static var directory: URL { StatePaths.config }

    public static var file: URL { directory.appendingPathComponent("config.json") }

    static var store: JSONFile<PS3Config> { JSONFile(file, empty: PS3Config()) }

    public static func load() -> PS3Config { store.load() }

    /// The only way to change config.json: rereads it under a lock, so a setting another process
    /// saved meanwhile (the app, `ps3`, `ps3 mcp`) is kept. See `JSONFile`.
    @discardableResult
    public static func edit<T>(_ change: (inout PS3Config) throws -> T) throws -> T {
        try store.edit(change)
    }
}

/// Finds the local mirror folder: the configured root, else the nearest parent of the
/// working directory or of the executable that looks like a mirror.
public enum MirrorRoot {
    /// PS3 Center's folder in the mirror; packages are archived in its Packages folder.
    public static let installedFolder = "_Installed"

    public static func resolve(config: PS3Config = ConfigStore.load()) -> URL? {
        if let root = config.root {
            let url = URL(fileURLWithPath: root)
            if looksLikeMirror(url) { return migrated(url) }
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if let found = searchUp(from: cwd) { return migrated(found) }
        if let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            return searchUp(from: exe.deletingLastPathComponent()).map(migrated)
        }
        return nil
    }

    /// A mirror has dev_hdd0/ and _Installed/ (or _Installerat/, its Swedish name from before).
    public static func looksLikeMirror(_ url: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.appendingPathComponent("dev_hdd0").path, isDirectory: &isDir) && isDir.boolValue
            && (fm.fileExists(atPath: url.appendingPathComponent(installedFolder).path)
                || fm.fileExists(atPath: url.appendingPathComponent("_Installerat").path))
    }

    /// The mirror's backup folder, and the one with a known-good boot_plugins.txt for when a
    /// plugin makes the console freeze (the ds45pad advice in `Catalog`). PS3 Center does not
    /// write to either; they are only renamed from their Swedish names.
    public static let backupsFolder = "_Backups"
    public static let emergencyFolder = "_Emergency"

    /// Renames the Swedish names from before: _Installerat/Paket to _Installed/Packages,
    /// _Säkerhetskopior to _Backups and _Nödläge to _Emergency. Each only when the old one exists
    /// and the new one does not; when both exist the new one is used and the old one is left alone.
    static func migrateNames(in root: URL) {
        BackupFolder.migrate("_Installerat", to: installedFolder, in: root)
        BackupFolder.migrate("Paket", to: "Packages", in: root.appendingPathComponent(installedFolder, isDirectory: true))
        BackupFolder.migrate("_Säkerhetskopior", to: backupsFolder, in: root)
        BackupFolder.migrate("_Nödläge", to: emergencyFolder, in: root)
    }

    private static func migrated(_ root: URL) -> URL {
        migrateNames(in: root)
        return root
    }

    static func searchUp(from start: URL) -> URL? {
        var url = start.standardizedFileURL
        while url.path != "/" {
            if looksLikeMirror(url) { return url }
            url.deleteLastPathComponent()
        }
        return nil
    }

    /// Where installed packages are archived: _Installed/Packages in the mirror.
    public static func packageArchive(in root: URL) -> URL {
        migrateNames(in: root)
        return root.appendingPathComponent(installedFolder + "/Packages", isDirectory: true)
    }
}
