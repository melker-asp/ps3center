import Foundation

/// User settings shared by the CLI and the future Mac app.
/// Stored in ~/.config/ps3center/config.json (same layout idea as Mole's ~/.config/mole).
public struct PS3Config: Codable, Equatable, Sendable {
    public var host: String?
    /// The local folder that mirrors the console's file system (contains dev_hdd0/, USB/, _Installerat/).
    public var root: String?
    /// The app's colour theme (Utseende). A plain string, so an unknown value from a newer
    /// version cannot make the whole file unreadable.
    public var theme: String?
    /// The Mac's game folders per kind ("PS3ISO", "PS2ISO" …), as linked in the app or with
    /// `ps3 config folder add`. See `GameFolders`.
    public var folders: [String: [String]]?

    public init(host: String? = nil, root: String? = nil, theme: String? = nil, folders: [String: [String]]? = nil) {
        self.host = host
        self.root = root
        self.theme = theme
        self.folders = folders
    }
}

public enum ConfigStore {
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ps3center", isDirectory: true)
    }

    public static var file: URL { directory.appendingPathComponent("config.json") }

    public static func load() -> PS3Config {
        guard let data = try? Data(contentsOf: file),
              let config = try? JSONDecoder().decode(PS3Config.self, from: data)
        else { return PS3Config() }
        return config
    }

    public static func save(_ config: PS3Config) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: file, options: .atomic)
    }
}

/// Finds the local mirror folder: the configured root, else the nearest parent of the
/// working directory or of the executable that looks like a mirror.
public enum MirrorRoot {
    public static func resolve(config: PS3Config = ConfigStore.load()) -> URL? {
        if let root = config.root {
            let url = URL(fileURLWithPath: root)
            if looksLikeMirror(url) { return url }
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if let found = searchUp(from: cwd) { return found }
        if let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            return searchUp(from: exe.deletingLastPathComponent())
        }
        return nil
    }

    public static func looksLikeMirror(_ url: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.appendingPathComponent("dev_hdd0").path, isDirectory: &isDir) && isDir.boolValue
            && fm.fileExists(atPath: url.appendingPathComponent("_Installerat").path)
    }

    static func searchUp(from start: URL) -> URL? {
        var url = start.standardizedFileURL
        while url.path != "/" {
            if looksLikeMirror(url) { return url }
            url.deleteLastPathComponent()
        }
        return nil
    }

    /// Where installed packages are archived (README: "_Installerat/Paket").
    public static func packageArchive(in root: URL) -> URL {
        root.appendingPathComponent("_Installerat/Paket", isDirectory: true)
    }
}
