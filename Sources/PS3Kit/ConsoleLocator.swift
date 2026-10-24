import Foundation

/// Decides which console to talk to: an explicit host, PS3_HOST, the saved config, or a scan.
/// If the saved address stops answering, scans once and remembers the new one.
public enum ConsoleLocator {
    public enum Event: Sendable {
        case scanning(previous: String?)
        case found(String)
    }

    public static func resolve(explicit: String? = nil, events: @Sendable (Event) -> Void = { _ in }) async throws -> String {
        if let host = explicit ?? ProcessInfo.processInfo.environment["PS3_HOST"] {
            guard await WebMAN(host: host).isReachable(timeout: 6) else { throw PS3Error.unreachable(host: host) }
            return host
        }
        var config = ConfigStore.load()
        if let saved = config.host, await WebMAN(host: saved).isReachable(timeout: 6) {
            return saved
        }
        events(.scanning(previous: config.host))
        guard let found = await Discovery.scan().first else {
            if let saved = config.host { throw PS3Error.unreachable(host: saved) }
            throw PS3Error.noHost
        }
        config.host = found
        try? ConfigStore.save(config)
        events(.found(found))
        return found
    }
}
