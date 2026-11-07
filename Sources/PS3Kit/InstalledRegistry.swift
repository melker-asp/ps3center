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

    public static func load() -> [String: Record] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: Record].self, from: data)) ?? [:]
    }

    public static func record(_ entryID: String, tag: String, appVersion: String) {
        var records = load()
        records[entryID] = Record(tag: tag, appVersion: appVersion, installedAt: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: ConfigStore.directory, withIntermediateDirectories: true)
        try? encoder.encode(records).write(to: file, options: .atomic)
    }

    /// Forgets an app that was uninstalled.
    public static func forget(_ entryID: String) {
        var records = load()
        guard records.removeValue(forKey: entryID) != nil else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(records).write(to: file, options: .atomic)
    }

    /// The release tag for what is installed now, if PS3 Center installed it and nothing changed since.
    public static func tag(for entryID: String, installedAppVersion: String) -> String? {
        guard let record = load()[entryID], record.appVersion == installedAppVersion else { return nil }
        return record.tag
    }
}
