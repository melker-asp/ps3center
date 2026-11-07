import Foundation

/// Updates the user has chosen to skip ("Ignorera" in the app, `ps3 apps ignore` in the CLI).
/// What is skipped is one release: when a newer tag comes out, the update shows again. Kept as
/// `ignoredUpdates` in config.json, so the app and the CLI agree. Only the Mac's settings change,
/// never the console.
public enum IgnoredUpdates {
    /// Catalog id → the release tag that is skipped.
    public static func load(config: PS3Config = ConfigStore.load()) -> [String: String] {
        config.ignoredUpdates ?? [:]
    }

    /// Skips `version` (a release tag, as in `AppStatus.latest`) of the app with catalog id `id`.
    public static func ignore(_ id: String, version: String) throws {
        var config = ConfigStore.load()
        var ignored = config.ignoredUpdates ?? [:]
        ignored[id] = version
        config.ignoredUpdates = ignored
        try ConfigStore.save(config)
    }

    /// Shows the app's updates again. False when nothing was ignored for it.
    @discardableResult
    public static func unignore(_ id: String) throws -> Bool {
        var config = ConfigStore.load()
        guard config.ignoredUpdates?.removeValue(forKey: id) != nil else { return false }
        if config.ignoredUpdates?.isEmpty == true { config.ignoredUpdates = nil }
        try ConfigStore.save(config)
        return true
    }

    /// True when the update to `latest` is the very release that was skipped.
    public static func skips(_ id: String, latest: String?, in ignored: [String: String]) -> Bool {
        guard let latest, let skipped = ignored[id] else { return false }
        return skipped == latest
    }
}
