import PS3Kit
import SwiftUI

/// Spelservern: on/off, what it serves and who reads it, and the one-time setting in webMAN,
/// with a link that opens webMAN's settings in the Mac's browser.
struct NetServerView: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(NetServerStore.self) private var server
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Game Server")
                    .font(.ui(.display, weight: .light))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                PillToggle(isOn: server.isEnabled, label: "Game Server") { server.setEnabled($0) }
            }
            Text("The PS3 plays ISOs straight from the Mac's game folders, without copying them. The Mac has to be on and awake while you play; PS3 Center keeps it awake.")
                .font(.ui(.body))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.bottom, 18)

            Card(icon: "server.rack", title: "Status", chip: statusChip, chipColor: server.status.isRunning ? Theme.good : Theme.secondaryText) {
                VStack(alignment: .leading, spacing: 8) {
                    line("Address", server.addresses.map { "\($0):\(NetServer.defaultPort)" }.joined(separator: ", "))
                    line("PS3", server.status.clients > 0 ? "connected" : "not connected yet")
                    if let file = server.status.lastFile {
                        line("Reading", (file as NSString).lastPathComponent)
                    }
                    line("Sent", Format.bytes(server.status.bytesServed))
                    if let error = server.status.error {
                        Text(error).font(.ui(.footnote)).foregroundStyle(Theme.hot)
                    }
                }
            }
            .frame(height: 190)

            Text("WEBMAN")
                .font(.ui(.caption, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 22)
                .padding(.bottom, 10)
            webMANSection

            Text("PS3 games should go over a cable. PS2 ISOs are copied to the hard drive when they start, and game folders (GAMES) don't work over the network, only ISOs. Give the Mac a fixed address in the router, or webMAN won't find the server after a restart.")
                .font(.ui(.footnote))
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            Spacer(minLength: 16)
            HStack {
                Spacer()
                // Outlined: Set Up webMAN for Me is the white button here.
                DoneButton(prominent: false)
            }
        }
        .padding(32)
        .frame(width: 580, height: 700, alignment: .topLeading)
        .background(Theme.base)
        .task(id: console.host) { await server.checkWebMAN() }
    }

    @ViewBuilder private var webMANSection: some View {
        switch server.webMAN {
        case .unknown, .checking:
            HStack(spacing: 10) {
                Spinner(size: 14)
                Text("Reading webMAN's settings…").font(.ui(.body)).foregroundStyle(Theme.secondaryText)
            }
        case .working(let step):
            HStack(spacing: 10) {
                Spinner(size: 14)
                Text(step).font(.ui(.body)).foregroundStyle(Theme.secondaryText)
            }
        case .configured(let slot):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                Text("webMAN gets games from the Mac as network server \(slot + 1) (/net\(slot)). The games show up among webMAN's games and start as usual.")
                    .font(.ui(.body))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .notConfigured, .failed:
            VStack(alignment: .leading, spacing: 10) {
                if case .failed(let message) = server.webMAN {
                    Text(message)
                        .font(.ui(.footnote))
                        .foregroundStyle(Theme.hot)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("webMAN needs to know where the game server is. PS3 Center fills in a free network server with \(server.address ?? "the Mac's address"):\(NetServer.defaultPort), saves, and refreshes the game list. Your other webMAN settings stay as they are, and a copy of them is saved first (Maintenance → System Files).")
                    .font(.ui(.body))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Set Up webMAN for Me") { Task { await server.configureWebMAN() } }
                        .buttonStyle(PillButtonStyle())
                        .disabled(console.host == nil)
                    if let host = console.host, let url = URL(string: "http://\(host)/setup.ps3") {
                        Button("Do It Myself") { openURL(url) }
                            .buttonStyle(PillButtonStyle(prominent: false))
                            .help("Opens webMAN's settings: network server 1 = \(server.address ?? "the Mac's address") and port \(NetServer.defaultPort)")
                    }
                }
            }
        }
    }

    private var statusChip: String {
        if !server.isEnabled { return "Off" }
        return server.status.isRunning ? "On" : "Starting"
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.ui(.body)).foregroundStyle(Theme.secondaryText).frame(width: 70, alignment: .leading)
            Text(value).font(.ui(.body, weight: .medium)).foregroundStyle(Theme.primaryText).lineLimit(1).truncationMode(.middle)
        }
    }
}
