import Foundation

/// Remembers which release tag produced which PARAM.SFO version when PS3 Center installed an app.
/// Projects number tags and APP_VER differently; with this mapping an app installed by the tool
/// never has to be guessed. Stored next to the config in ~/.config/ps3center/installed.json.
public enum InstalledRegistry {
    public struct Record: Codable, Equatable, Sendable {
        public let tag: String
        public let appVersion: String
        public let installedAt: Date
    }

    static var file: URL { ConfigStore.directory.appendingPathComponent("installed.json") }

    static var store: JSONFile<[String: Record]> { JSONFile(file, empty: [:]) }

    public static func load() -> [String: Record] { store.load() }

    public static func record(_ entryID: String, tag: String, appVersion: String) throws {
        try store.edit { $0[entryID] = Record(tag: tag, appVersion: appVersion, installedAt: Date()) }
    }

    /// Forgets an app that was uninstalled.
    public static func forget(_ entryID: String) throws {
        guard load()[entryID] != nil else { return }
        try store.edit { $0[entryID] = nil }
    }

    /// The release tag for what is installed now, if PS3 Center installed it and nothing changed since.
    public static func tag(for entryID: String, installedAppVersion: String) -> String? {
        guard let record = load()[entryID], record.appVersion == installedAppVersion else { return nil }
        return record.tag
    }
}
