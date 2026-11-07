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
            if let index = WebMANSettings.readySlot(slots, address: address, port: Int(NetServer.defaultPort)) {
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
            webMAN = .working("Saving a copy of webMAN's settings…")
            _ = try await SystemFiles.backup(host: host)
            webMAN = .working("Filling in the network server in webMAN…")
            let index = try await WebMANSetup(host: host).configure(address: address, port: Int(NetServer.defaultPort))
            remember(index)
            if !isEnabled { setEnabled(true) }
            webMAN = .working("Refreshing the game list…")
            // A running game keeps its list until later: the setup itself is done.
            try await TransferService(host: host).refreshGameList(whenGameRuns: .skip)
            webMAN = .configured(slot: index)
        } catch {
            webMAN = .failed(error.localizedDescription)
        }
    }

    private func remember(_ index: Int) {
        slot = index
        // Remembered for next time; the slot in webMAN is what counts now.
        try? ConfigStore.edit { $0.netServerSlot = index == 0 ? nil : index }
    }

    func setEnabled(_ on: Bool) {
        guard !isFixture else { return }
        isEnabled = on
        // Remembered for next launch; the server starts or stops either way.
        try? ConfigStore.edit { $0.netServer = on ? true : nil }
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
            status.error = "The game server couldn't start: \(error.localizedDescription)"
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
        let playingFromMac = path.map(NetServer.isNetMount) == true && server != nil
        if playingFromMac, awake == nil {
            awake = KeepAwake(reason: "The PS3 is playing from the Mac")
        } else if !playingFromMac {
            awake = nil
        }
    }
}
