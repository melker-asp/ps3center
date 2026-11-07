import AppKit
import PS3Kit
import SwiftUI

/// The menu bar: how the console is, what it plays, the queue and the game server, and the
/// buttons used most. Works with the window closed.
struct MenuBarView: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(TransferStore.self) private var transfers
    @Environment(NetServerStore.self) private var netServer
    @Environment(AppRouter.self) private var router
    @Environment(AppPreferences.self) private var preferences: AppPreferences?
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
                    line("thermometer.medium", "CPU \(s.cpuTemp.map(unit.format) ?? "–") · RSX \(s.rsxTemp.map(unit.format) ?? "–") · fan \(s.fanPercent.map(String.init) ?? "–") %")
                    line("gamecontroller", s.isGameRunning ? (s.mountedGameName ?? s.runningProcess ?? "A game") : "XMB")
                    if let item = transfers.queue.items.first(where: { $0.state == .sending }) {
                        line("arrow.up.circle", "\(item.title) · \(Int(item.fraction * 100)) %")
                    } else if !transfers.pending.isEmpty {
                        line("arrow.up.circle", "\(transfers.pending.count) in the queue")
                    }
                    if netServer.isEnabled {
                        line("server.rack", netServer.status.clients > 0 ? "Game Server: PS3 connected" : "Game Server is on")
                    }
                }
            }
            if let note = console.actionNote {
                Text(note).font(.ui(.caption)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                row("macwindow", "Open PS3 Center") { open() }
                if shows(.sendFiles) {
                    row("square.and.arrow.up", MenuBarAction.sendFiles.title) { chooseFiles() }
                }
                if console.connection == .online {
                    if shows(.refreshGames) {
                        row("arrow.triangle.2.circlepath", MenuBarAction.refreshGames.title) { console.refreshGames() }
                    }
                    if console.snapshot?.isGameRunning == true, shows(.quitGame) {
                        row("xmark.circle", MenuBarAction.quitGame.title) { console.exitGame() }
                    }
                    if shows(.shutDown) {
                        row("power", MenuBarAction.shutDown.title) { confirmShutdown() }
                    }
                }
            }
            .disabled(console.isActing)
            Divider()
            HStack {
                Text("Launch at Login").font(.ui(.body))
                Spacer()
                PillToggle(isOn: startsAtLogin, label: "Launch at Login") { on in
                    loginNote = LoginItem.set(on)
                    startsAtLogin = LoginItem.isEnabled
                }
                .scaleEffect(0.8)
            }
            if let loginNote {
                Text(loginNote).font(.ui(.caption)).foregroundStyle(Theme.warm).fixedSize(horizontal: false, vertical: true)
            }
            row("gearshape", "Settings…") {
                WindowOpener.shared.openWindow = openWindow
                router.openSettings()
            }
            row("xmark.square", "Quit PS3 Center") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 300)
        .background(background)
        .onAppear { WindowOpener.shared.openWindow = openWindow }
    }

    private var unit: TemperatureUnit { preferences?.temperatureUnit ?? .celsius }

    /// Settings → General → Menu Bar; every button without preferences (a snapshot).
    private func shows(_ action: MenuBarAction) -> Bool {
        !(preferences?.hiddenMenuBarActions.contains(action) ?? false)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 9, height: 9)
            Text("PS3 Center").font(.ui(.callout, weight: .semibold))
            Spacer()
            Text(statusText).font(.ui(.footnote)).foregroundStyle(Theme.secondaryText)
        }
    }

    private var statusColor: Color {
        switch console.connection {
        case .online: return Theme.healthColor(console.snapshot?.healthLevel ?? .excellent)
        case .henOff: return Theme.warm
        default: return Theme.tertiaryText
        }
    }

    private var statusText: String {
        switch console.connection {
        case .online: return console.snapshot.map { "Health \($0.health)" } ?? "Connected"
        case .henOff: return "HEN isn't enabled"
        case .offline: return "Can't reach the PS3"
        case .connecting, .scanning: return "Connecting…"
        }
    }

    private func line(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 16).foregroundStyle(Theme.accent)
            Text(text).lineLimit(1).truncationMode(.middle)
        }
        .font(.ui(.footnote))
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
        .font(.ui(.body))
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
        panel.prompt = "Send"
        panel.message = "Choose games, packages or folders to send to the PS3."
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
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { console.shutdown() }
    }
}
