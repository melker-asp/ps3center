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

            Text("SÅ STÄLLER DU IN WEBMAN (EN GÅNG)")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 22)
                .padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 8) {
                step(1, "Öppna webMAN:s inställningar, på PS3:an eller här på Macen.")
                if let host = console.host, let url = URL(string: "http://\(host)/setup.ps3") {
                    Button("Öppna webMAN:s inställningar") { openURL(url) }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .padding(.leading, 26)
                }
                step(2, "Slå på nätverksserver 1 och skriv in \(server.addresses.first ?? "Macens adress") och port \(NetServer.defaultPort). Spara.")
                step(3, "Uppdatera spellistan. Spelen syns under webMAN:s spel och startar som vanligt.")
            }
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

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(0.85)))
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
