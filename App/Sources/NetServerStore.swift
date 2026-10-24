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

    /// Whether webMAN has a network server pointing here.
    enum WebMANState: Equatable {
        case unknown
        case checking
        case configured(slot: Int)
        case notConfigured
        case working(String)
        case failed(String)
    }

    private(set) var webMAN: WebMANState = .unknown
    /// webMAN's network server that points here: 0 for /net0 … 4 for /net4.
    private(set) var slot = ConfigStore.load().netServerSlot ?? 0

    private var server: NetServer?
    private var awake: KeepAwake?
    private var isFixture = false

    var addresses: [String] { NetServer.macAddresses() }
    /// The address webMAN should use: the Mac's on the console's network.
    var address: String? { host.flatMap(NetServer.address(facing:)) ?? addresses.first }

    func loadFixture() {
        isFixture = true
        isEnabled = true
        status = NetServer.Status(isRunning: true, clients: 1, lastFile: "/PS3ISO/Uncharted 2 - Among Thieves (Europe).iso",
                                  bytesServed: 1_284_000_000, error: nil)
        webMAN = .notConfigured
    }

    // MARK: webMAN

    /// Reads webMAN's settings: does a network server point here?
    func checkWebMAN() async {
        guard !isFixture, let host, let address else { return }
        if case .working = webMAN { return }
        webMAN = .checking
        do {
            let slots = try await WebMANSetup(host: host).slots()
            if let index = slots.firstIndex(where: { $0.enabled && $0.host == address && $0.port == Int(NetServer.defaultPort) }) {
                remember(index)
                webMAN = .configured(slot: index)
            } else {
                webMAN = .notConfigured
            }
        } catch {
            webMAN = .failed(error.localizedDescription)
        }
    }

    /// Fills in a network server in webMAN's settings (after a copy of them is saved), turns the
    /// game server on and refreshes the game list, so the Mac's games show up on the console.
    func configureWebMAN() async {
        guard !isFixture, let host, let address else { return }
        do {
            webMAN = .working("Sparar en kopia av webMAN:s inställningar…")
            _ = try await SystemFiles.backup(host: host)
            webMAN = .working("Fyller i nätverksservern i webMAN…")
            let index = try await WebMANSetup(host: host).configure(address: address, port: Int(NetServer.defaultPort))
            remember(index)
            if !isEnabled { setEnabled(true) }
            webMAN = .working("Uppdaterar spellistan…")
            let webman = WebMAN(host: host)
            let running = try await webman.isGameRunning()
            if !running {
                try await webman.refreshGames()
                OperationLog.record("refresh", host)
            }
            webMAN = .configured(slot: index)
        } catch {
            webMAN = .failed(error.localizedDescription)
        }
    }

    private func remember(_ index: Int) {
        slot = index
        var config = ConfigStore.load()
        config.netServerSlot = index == 0 ? nil : index
        try? ConfigStore.save(config)
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
