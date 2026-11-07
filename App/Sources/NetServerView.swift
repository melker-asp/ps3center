import PS3Kit
import SwiftUI

/// Spelservern: on/off, what it serves and who reads it, and the one-time setting in webMAN,
/// with a link that opens webMAN's settings in the Mac's browser.
struct NetServerView: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(NetServerStore.self) private var server
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Spelservern")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                PillToggle(isOn: server.isEnabled) { server.setEnabled($0) }
            }
            Text("PS3:an spelar ISO:er direkt från Macens spelmappar, utan att kopiera dem. Macen måste vara på och vaken medan du spelar; PS3 Center håller den vaken.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.bottom, 18)

            Card(icon: "server.rack", title: "Status", chip: statusChip, chipColor: server.status.isRunning ? Theme.good : Theme.secondaryText) {
                VStack(alignment: .leading, spacing: 8) {
                    line("Adress", server.addresses.map { "\($0):\(NetServer.defaultPort)" }.joined(separator: ", "))
                    line("PS3:an", server.status.clients > 0 ? "ansluten" : "inte ansluten än")
                    if let file = server.status.lastFile {
                        line("Läser", (file as NSString).lastPathComponent)
                    }
                    line("Skickat", Format.bytes(server.status.bytesServed))
                    if let error = server.status.error {
                        Text(error).font(.system(size: 12)).foregroundStyle(Theme.hot)
                    }
                }
            }
            .frame(height: 190)

            Text("WEBMAN")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 22)
                .padding(.bottom, 10)
            webMANSection

            Text("PS3-spel bör gå över kabel. PS2-ISO:er kopieras till hårddisken när de startas, och spelmappar (GAMES) går inte över nätet, bara ISO:er. Ge Macen en fast adress i routern, annars hittar webMAN inte servern efter en omstart.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            Spacer(minLength: 16)
            Button { dismiss() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(CircleIconButtonStyle(size: 44, filled: true))
                .keyboardShortcut(.cancelAction)
                .help("Tillbaka")
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
                Text("Läser webMAN:s inställningar…").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
        case .working(let step):
            HStack(spacing: 10) {
                Spinner(size: 14)
                Text(step).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
        case .configured(let slot):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                Text("webMAN hämtar spel från Macen som nätverksserver \(slot + 1) (/net\(slot)). Spelen syns under webMAN:s spel och startar som vanligt.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .notConfigured, .failed:
            VStack(alignment: .leading, spacing: 10) {
                if case .failed(let message) = server.webMAN {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.hot)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("webMAN behöver veta var spelservern finns. PS3 Center fyller i en ledig nätverksserver med \(server.address ?? "Macens adress"):\(NetServer.defaultPort), sparar och uppdaterar spellistan. Dina andra webMAN-inställningar lämnas som de är, och en kopia av dem sparas först (Underhåll → Systemfiler).")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Ställ in webMAN åt mig") { Task { await server.configureWebMAN() } }
                        .buttonStyle(PillButtonStyle())
                        .disabled(console.host == nil)
                    if let host = console.host, let url = URL(string: "http://\(host)/setup.ps3") {
                        Button("Göra det själv") { openURL(url) }
                            .buttonStyle(PillButtonStyle(prominent: false))
                            .help("Öppnar webMAN:s inställningar: nätverksserver 1 = \(server.address ?? "Macens adress") och port \(NetServer.defaultPort)")
                    }
                }
            }
        }
    }

    private var statusChip: String {
        if !server.isEnabled { return "Av" }
        return server.status.isRunning ? "På" : "Startar"
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.secondaryText).frame(width: 70, alignment: .leading)
            Text(value).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.primaryText).lineLimit(1).truncationMode(.middle)
        }
    }
}
