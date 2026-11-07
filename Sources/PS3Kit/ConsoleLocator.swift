import Foundation

/// Decides which console to talk to: an explicit host, PS3_HOST, the saved config, or a scan.
/// If the saved address stops answering, scans once and remembers the new one.
public enum ConsoleLocator {
    public enum Event: Sendable {
        case scanning(previous: String?)
        case found(String)
    }

    /// When the console can't be found but the address it should have answers on the network,
    /// throws `PS3Error.henOff`, for the CLI, the app and `ps3 mcp` alike.
    public static func resolve(explicit: String? = nil, events: @Sendable (Event) -> Void = { _ in }) async throws -> String {
        do {
            return try await find(explicit: explicit, events: events)
        } catch {
            let known = explicit ?? ProcessInfo.processInfo.environment["PS3_HOST"] ?? ConfigStore.load().host
            if let known, await Reachability.probe(known) == .henOff { throw PS3Error.henOff(host: known) }
            throw error
        }
    }

    static func find(explicit: String?, events: @Sendable (Event) -> Void) async throws -> String {
        if let host = explicit ?? ProcessInfo.processInfo.environment["PS3_HOST"] {
            guard await WebMAN(host: host).isReachable(timeout: 6) else { throw PS3Error.unreachable(host: host) }
            return host
        }
        let config = ConfigStore.load()
        if let saved = config.host, await WebMAN(host: saved).isReachable(timeout: 6) {
            return saved
        }
        events(.scanning(previous: config.host))
        guard let found = await Discovery.scan().first else {
            if let saved = config.host { throw PS3Error.unreachable(host: saved) }
            throw PS3Error.noHost
        }
        // Remembering the address is a convenience: the console was found either way.
        try? ConfigStore.edit { $0.host = found }
        events(.found(found))
        return found
    }
}
