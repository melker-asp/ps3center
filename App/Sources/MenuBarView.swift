import AppKit
import PS3Kit
import SwiftUI

/// The menu bar: how the console is, what it plays, the queue and the game server, and the
/// buttons used most. Works with the window closed.
struct MenuBarView: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(TransferStore.self) private var transfers
    @Environment(NetServerStore.self) private var netServer
    @Environment(\.openWindow) private var openWindow
    @State private var startsAtLogin = LoginItem.isEnabled
    /// The panel's own background; the menu bar draws one, a snapshot needs it.
    var background: Color = .clear
    @State private var loginNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let s = console.snapshot, console.connection == .online {
                VStack(alignment: .leading, spacing: 6) {
                    line("thermometer.medium", "CPU \(s.cpuTemp.map(String.init) ?? "–") °C · RSX \(s.rsxTemp.map(String.init) ?? "–") °C · fläkt \(s.fanPercent.map(String.init) ?? "–") %")
                    line("gamecontroller", s.isGameRunning ? (s.mountedGameName ?? s.runningProcess ?? "Ett spel") : "XMB")
                    if let item = transfers.queue.items.first(where: { $0.state == .sending }) {
                        line("arrow.up.circle", "\(item.title) · \(Int(item.fraction * 100)) %")
                    } else if !transfers.pending.isEmpty {
                        line("arrow.up.circle", "\(transfers.pending.count) i kön")
                    }
                    if netServer.isEnabled {
                        line("server.rack", netServer.status.clients > 0 ? "Spelservern: PS3:an ansluten" : "Spelservern är på")
                    }
                }
            }
            if let note = console.actionNote {
                Text(note).font(.system(size: 11)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                row("macwindow", "Öppna PS3 Center") { open() }
                row("square.and.arrow.up", "Skicka filer…") { chooseFiles() }
                if console.connection == .online {
                    row("arrow.triangle.2.circlepath", "Uppdatera spellistan") { console.refreshGames() }
                    if console.snapshot?.isGameRunning == true {
                        row("xmark.circle", "Avsluta spelet") { console.exitGame() }
                    }
                    row("power", "Stäng av PS3:an…") { confirmShutdown() }
                }
            }
            .disabled(console.isActing)
            Divider()
            HStack {
                Text("Starta vid inloggning").font(.system(size: 13))
                Spacer()
                PillToggle(isOn: startsAtLogin) { on in
                    loginNote = LoginItem.set(on)
                    startsAtLogin = LoginItem.isEnabled
                }
                .scaleEffect(0.8)
            }
            if let loginNote {
                Text(loginNote).font(.system(size: 11)).foregroundStyle(Theme.warm).fixedSize(horizontal: false, vertical: true)
            }
            row("xmark.square", "Avsluta PS3 Center") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 300)
        .background(background)
        .onAppear { WindowOpener.shared.openWindow = openWindow }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 9, height: 9)
            Text("PS3 Center").font(.system(size: 14, weight: .semibold))
            Spacer()
            Text(statusText).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
        }
    }

    private var statusColor: Color {
        switch console.connection {
        case .online: return Theme.healthColor(console.snapshot?.health ?? 100)
        case .henOff: return Theme.warm
        default: return Theme.tertiaryText
        }
    }

    private var statusText: String {
        switch console.connection {
        case .online: return console.snapshot.map { "Hälsa \($0.health)" } ?? "Ansluten"
        case .henOff: return "HEN är inte aktiverat"
        case .offline: return "Ingen kontakt"
        case .connecting, .scanning: return "Ansluter…"
        }
    }

    private func line(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 16).foregroundStyle(Theme.accent)
            Text(text).lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 12))
    }

    private func row(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 16)
                Text(title)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .font(.system(size: 13))
    }

    private func open() {
        WindowOpener.shared.openWindow = openWindow
        WindowOpener.shared.showMain()
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Skicka"
        panel.message = "Välj spel, paket eller mappar att skicka till PS3:an."
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        WindowOpener.shared.openWindow = openWindow
        Inbox.shared.receive(panel.urls)
    }

    private func confirmShutdown() {
        let alert = NSAlert()
        alert.messageText = PowerAction.shutdown.question
        alert.informativeText = PowerAction.shutdown.message(running: console.snapshot?.isGameRunning == true)
        alert.addButton(withTitle: PowerAction.shutdown.button)
        alert.addButton(withTitle: "Avbryt")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { console.shutdown() }
    }
}
