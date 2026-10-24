import Foundation
import Observation
import PS3Kit

/// The game server in the app: on or off (saved as `netServer` in config.json), started with
/// the app when on, and the Mac kept awake while the console plays a game from it.
@MainActor
@Observable
final class NetServerStore {
    private(set) var status = NetServer.Status()
    private(set) var isEnabled = ConfigStore.load().netServer ?? false
    /// The console's address: the only client let in.
    var host: String? {
        didSet { if host != oldValue, isEnabled { restart() } }
    }

    private var server: NetServer?
    private var awake: KeepAwake?
    private var isFixture = false

    var addresses: [String] { NetServer.macAddresses() }

    func loadFixture() {
        isFixture = true
        isEnabled = true
        status = NetServer.Status(isRunning: true, clients: 1, lastFile: "/PS3ISO/Uncharted 2 - Among Thieves (Europe).iso",
                                  bytesServed: 1_284_000_000, error: nil)
    }

    func setEnabled(_ on: Bool) {
        guard !isFixture else { return }
        isEnabled = on
        var config = ConfigStore.load()
        config.netServer = on ? true : nil
        try? ConfigStore.save(config)
        if on { start() } else { stop() }
    }

    func start() {
        // Not before the console is known: only its address is let in.
        guard !isFixture, isEnabled, server == nil, let host, !GameFolders.linked().isEmpty else { return }
        let server = NetServer(allowedHost: host) { status in
            Task { @MainActor [weak self] in self?.status = status }
        }
        do {
            try server.start()
            self.server = server
        } catch {
            status.error = "Spelservern kunde inte starta: \(error.localizedDescription)"
        }
    }

    func stop() {
        server?.stop()
        server = nil
        status = NetServer.Status()
        awake = nil
    }

    /// The linked folders changed: serve the new set.
    func restart() {
        guard server != nil else { return start() }
        stop()
        start()
    }

    /// A game from the server is mounted: keep the Mac awake until it is not.
    func consoleMounted(_ path: String?) {
        let playingFromMac = path?.hasPrefix("/net") == true && server != nil
        if playingFromMac, awake == nil {
            awake = KeepAwake(reason: "PS3:an spelar från Macen")
        } else if !playingFromMac {
            awake = nil
        }
    }
}
