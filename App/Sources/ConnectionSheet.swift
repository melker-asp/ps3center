import AppKit
import PS3Kit
import PS3KitFixtures
import SwiftUI

/// What the connection sheet knows: the consoles the search found, an address typed by hand,
/// and the Mac's own connections. Fixtures when `live` is false (snapshots).
@MainActor
@Observable
final class ConnectionModel {
    enum Search: Equatable {
        case idle
        case searching
        case done
    }

    enum Manual: Equatable {
        case idle
        case checking
        case failed(String)
    }

    private(set) var interfaces: [MacInterface] = []
    private(set) var consoles: [FoundConsole] = []
    private(set) var search: Search = .idle
    /// What `ps3 speedtest` measured per network ("Wi-Fi", "LAN").
    private(set) var speeds: [String: SpeedResult] = [:]
    var manualHost = ""
    private(set) var manual: Manual = .idle
    let live: Bool

    init(live: Bool) {
        self.live = live
        if live {
            refresh()
        } else {
            interfaces = Fixtures.macInterfaces
            consoles = Fixtures.foundConsoles
            speeds = Fixtures.speedsByNetwork
            search = .done
        }
    }

    var subnets: [String] { Discovery.localSubnets(interfaces) }

    /// Read again every few seconds, so a new cable shows its speed while the sheet is open.
    func refresh() {
        guard live else { return }
        let next = MacNetwork.interfaces()
        if next != interfaces { interfaces = next }
        speeds = SpeedTest.byNetwork()
    }

    func searchNow() async {
        guard live, search != .searching else { return }
        refresh()
        consoles = []
        search = .searching
        let found = await Discovery.find(interfaces: interfaces) { console in
            Task { @MainActor [weak self] in
                guard let self, self.search == .searching, !self.consoles.contains(where: { $0.host == console.host }) else { return }
                self.consoles.append(console)
            }
        }
        consoles = found
        search = .done
    }

    /// Checks a typed address before using it, so a typo does not replace an address that works.
    func connect(_ console: ConsoleStore) async {
        let host = manualHost.trimmingCharacters(in: .whitespaces)
        guard MacNetwork.isIPv4(host) else {
            manual = .failed("Enter an address like 192.168.2.2.")
            return
        }
        guard live else { return }
        manual = .checking
        switch await Reachability.probe(host, timeout: 3) {
        case .webMAN:
            console.use(host: host)
            manual = .idle
            manualHost = ""
        case .henOff:
            manual = .failed(Reachability.henOffAdvice(host: host))
        case .unreachable:
            manual = .failed("Nothing answers at \(host). The PS3 shows its address under Settings → Network Settings → Settings and Connection Status List.")
        }
    }
}

/// Every PS3 on the Mac's networks (searched as soon as the sheet opens), an address typed by
/// hand, the Mac's connections with the cable's speed, and what to enter on the PS3 for a cable.
/// Only the Mac's config changes: the PS3's network settings are shown, never written (DESIGN.md).
struct ConnectionSheet: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(\.openURL) private var openURL
    @State private var model: ConnectionModel

    init(live: Bool = true) {
        _model = State(initialValue: ConnectionModel(live: live))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ImageRenderer cannot draw a scroll view, so snapshots get the content as it is.
            if model.live {
                ScrollView { content }.scrollIndicators(.hidden)
            } else {
                content
            }
            HStack {
                Spacer()
                // Outlined: Search Again is the white button here.
                DoneButton(prominent: false)
            }
            .padding(.top, 16)
        }
        .padding(32)
        .frame(width: 620, height: model.live ? 760 : nil, alignment: .topLeading)
        .background(Theme.base)
        .task { await model.searchNow() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                model.refresh()
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Connection")
                .font(.ui(.display, weight: .light))
                .foregroundStyle(Theme.primaryText)
            Text("PS3 Center finds the PS3 by itself when its address changes. Here you see every PS3 on the Mac's networks, can enter an address yourself, and see how to connect a cable.")
                .font(.ui(.body))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            sectionTitle("PS3 on the Network")
            consolesSection
            sectionTitle("This Mac")
            macSection
            sectionTitle("Cable to the PS3")
            cableSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.ui(.caption, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(Theme.secondaryText)
            .padding(.top, 24)
            .padding(.bottom, 10)
    }

    // MARK: Consoles

    private var consolesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.consoles) { consoleRow($0) }
            switch model.search {
            case .searching:
                HStack(spacing: 10) {
                    Spinner(size: 14)
                    Text("Searching \(subnetList)… This takes up to half a minute.")
                        .font(.ui(.body))
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.vertical, 4)
            case .done where model.consoles.isEmpty:
                Text("No PS3 answered on \(subnetList). Is it on, with HEN enabled? webMAN only runs once HEN is.")
                    .font(.ui(.body))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                EmptyView()
            }
            HStack(spacing: 10) {
                Button(model.search == .searching ? "Searching…" : "Search Again") {
                    Task { await model.searchNow() }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(model.search == .searching)
                Spacer(minLength: 16)
                addressField
                Button("Connect") { Task { await model.connect(console) } }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .disabled(model.manualHost.isEmpty || model.manual == .checking)
            }
            .padding(.top, 6)
            if case .failed(let message) = model.manual {
                Text(message)
                    .font(.ui(.footnote))
                    .foregroundStyle(Theme.hotText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func consoleRow(_ found: FoundConsole) -> some View {
        let inUse = found.host == console.host
        let details = [found.firmware, found.via.map { "via \($0)" }].compactMap { $0 }
        return HStack(spacing: 12) {
            Circle()
                .fill(inUse ? Theme.good : Color.white.opacity(0.25))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(found.host)
                        .font(.ui(.headline, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .monospacedDigit()
                    if let network = found.network { Chip(text: network.label) }
                }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.ui(.footnote))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if inUse {
                Chip(text: "In use", color: Theme.good)
            } else {
                Button("Use") { console.use(host: found.host) }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .help("Talk to the PS3 at \(found.host) from now on")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardStroke))
    }

    /// The PS app's dark capsule; drawn as text in snapshots, where an AppKit field cannot render.
    private var addressField: some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .foregroundStyle(Theme.tertiaryText)
            if model.live {
                TextField("IP address", text: $model.manualHost)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .onSubmit { Task { await model.connect(console) } }
            } else {
                Text("IP address")
                    .foregroundStyle(Theme.tertiaryText)
                Spacer(minLength: 0)
            }
            if model.manual == .checking { Spinner(size: 12) }
        }
        .font(.ui(.body))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: 170)
        .background(Capsule().fill(Color.black.opacity(0.45)))
    }

    // MARK: This Mac

    private var macSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.interfaces.isEmpty {
                Text("The Mac has no network connection.")
                    .font(.ui(.body))
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(model.interfaces) { interface in
                HStack(spacing: 10) {
                    Image(systemName: icon(for: interface.kind))
                        .font(.ui(.body))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 20)
                    Text(interface.label)
                        .font(.ui(.body, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(interface.address ?? "No address")
                        .font(.ui(.body))
                        .foregroundStyle(interface.address == nil ? Theme.warm : Theme.secondaryText)
                        .monospacedDigit()
                    if let speed = interface.linkSpeedLabel {
                        Chip(text: speed, color: interface.isSlowLink ? Theme.warm : Theme.good)
                    }
                }
            }
            if let slow = model.interfaces.first(where: \.isSlowLink), let speed = slow.linkSpeed, let label = slow.linkSpeedLabel {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warm)
                    Text("The cable only runs at \(label), at most \(Format.rate(Double(speed) / 8)). The PS3 and the Mac both manage gigabit, which needs all four pairs in the cable: try a Cat5e or Cat6 cable.")
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.ui(.footnote))
                .padding(.top, 2)
            }
        }
    }

    private func icon(for kind: MacInterface.Kind) -> String {
        switch kind {
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector"
        case .sharing: return "point.3.connected.trianglepath.dotted"
        }
    }

    // MARK: Cable

    private var cableSection: some View {
        let setup = WiredSetup.plan(model.interfaces, console: console.host)
        return VStack(alignment: .leading, spacing: 12) {
            Text(setup.advice)
                .font(.ui(.body))
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            switch setup {
            case .direct(_, let ps3):
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
                    valueRow("IP Address", ps3.address)
                    valueRow("Subnet Mask", ps3.subnetMask)
                    if let router = ps3.router { valueRow("Default Router", router) }
                    if let dns = ps3.dns { valueRow("Primary DNS", dns) }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardFill))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardStroke))
                Text(WiredSetup.ps3Remaining)
                    .font(.ui(.footnote))
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            case .needsAddress:
                Button("Open Network Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") { openURL(url) }
                }
                .buttonStyle(PillButtonStyle(prominent: false))
            case .noCable, .router, .sharing:
                EmptyView()
            }
            if let measured = measuredLine {
                Text(measured)
                    .font(.ui(.footnote))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.ui(.body))
                .foregroundStyle(Theme.secondaryText)
            Text(value)
                .font(.ui(.body, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .monospacedDigit()
                .textSelection(.enabled)
        }
    }

    /// "Measured with the speed test: Wi-Fi 1.1 MB/s, cable 5.5 MB/s."
    private var measuredLine: String? {
        let parts = [(NetworkKind.wifi, "Wi-Fi"), (.lan, "cable")].compactMap { network, name in
            SpeedTest.measurement(over: network, in: model.speeds).map { "\(name) \(Format.rate($0.upload))" }
        }
        return parts.isEmpty ? nil : "Measured with the speed test: " + parts.joined(separator: ", ") + "."
    }

    /// "192.168.2.0/24 and 10.0.1.0/24"
    private var subnetList: String {
        let names = model.subnets.map { "\($0).0/24" }
        guard names.count > 1, let last = names.last else { return names.first ?? "the Mac's networks" }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }
}
