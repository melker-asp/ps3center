import PS3Kit
import SwiftUI

/// Mole's Status tab, for a PS3: eight cards and a history table underneath.
struct StatusView: View {
    @Environment(ConsoleStore.self) private var console
    /// False when rendered for a snapshot: ImageRenderer cannot draw scroll views.
    var scrolls = true
    @State private var showsRemote = false
    @State private var confirming: PowerAction?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)

    var body: some View {
        Group {
            if scrolls {
                ScrollView { grid }.scrollIndicators(.hidden)
            } else {
                grid
            }
        }
        .sheet(isPresented: $showsRemote) { RemoteView() }
        .confirmationDialog(confirming?.question ?? "", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            presenting: confirming) { action in
            Button(action.button, role: .destructive) {
                if action == .shutdown { console.shutdown() } else { console.restart() }
            }
        } message: { action in
            Text(action.message(running: console.snapshot?.isGameRunning == true))
        }
    }

    @ViewBuilder private var grid: some View {
        if let s = console.snapshot {
                VStack(spacing: 14) {
                    LazyVGrid(columns: columns, spacing: 14) {
                        healthCard(s)
                        temperatureCard(icon: "cpu", title: "CPU", value: s.cpuTemp, warnAt: 70,
                                        history: console.cpuHistory, footnote: "Cell Broadband Engine")
                        temperatureCard(icon: "square.stack.3d.up", title: "RSX", value: s.rsxTemp, warnAt: 75,
                                        history: console.rsxHistory, footnote: "RSX Reality Synthesizer")
                        fanCard(s)
                        spaceCard(s)
                        networkCard(s)
                        nowPlayingCard(s)
                        systemCard(s)
                    }
                    controls(s)
                    HistoryTable(entries: console.history)
                }
                .padding(.bottom, 8)
        }
    }

    // MARK: Cards

    private func healthCard(_ s: ConsoleSnapshot) -> some View {
        Card(icon: "sun.max", title: "Hälsa", chip: s.network) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(s.health)")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(Theme.primaryText)
                        Text(s.healthLabel)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Footnote(text: s.healthNotes.first ?? "Allt ser bra ut")
                    Spacer(minLength: 0)
                    Footnote(text: "var \(Int(console.interval)):e sekund")
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                HealthOrb(color: Theme.healthColor(s.health))
                    .scaleEffect(0.62)
                    .frame(width: 70, height: 70)
                    .offset(y: 6)
            }
        }
        .frame(height: 210)
    }

    private func temperatureCard(icon: String, title: String, value: Int?, warnAt: Int,
                                 history: [Double], footnote: String) -> some View {
        let color = value.map { Theme.temperatureColor($0, warnAt: warnAt) } ?? Theme.good
        let label = value.map { $0 >= warnAt + 10 ? "Het" : $0 >= warnAt ? "Varm" : "Normal" }
        return Card(icon: icon, title: title, chip: label, chipColor: color) {
            BigValue(value: value.map(String.init) ?? "–", unit: "°C")
            Sparkline(values: history, range: Self.range(for: history, padding: 3), color: color)
                .frame(height: 34)
            Spacer(minLength: 0)
            Footnote(text: footnote)
        }
        .frame(height: 210)
    }

    private func fanCard(_ s: ConsoleSnapshot) -> some View {
        Card(icon: "fan", title: "Fläkt", chip: s.fanTargetMax.map { "max \($0) °C" }) {
            BigValue(value: s.fanPercent.map(String.init) ?? "–", unit: "%")
            Sparkline(values: console.fanHistory, range: Self.range(for: console.fanHistory, padding: 5), color: Theme.cool)
                .frame(height: 34)
            Spacer(minLength: 0)
            if let target = s.fanTargetMax {
                // webMAN's dynamic mode: only the target moves, within FanControl.targets.
                HStack(spacing: 6) {
                    Footnote(text: "Mål \(target) °C")
                    Spacer(minLength: 0)
                    Button { console.setFanTarget(target - 1) } label: { Image(systemName: "minus") }
                        .disabled(target <= FanControl.targets.lowerBound)
                        .help("Sänk målet (fläkten varvar upp tidigare)")
                    Button { console.setFanTarget(target + 1) } label: { Image(systemName: "plus") }
                        .disabled(target >= FanControl.targets.upperBound)
                        .help("Höj målet (tystare, varmare)")
                }
                .buttonStyle(CircleIconButtonStyle(size: 24))
                .disabled(console.isActing)
            } else {
                Footnote(text: "Konsolen styr fläkten själv")
            }
        }
        .frame(height: 210)
    }

    /// The console's own buttons: the remote, quitting the game, the disc, and power.
    private func controls(_ s: ConsoleSnapshot) -> some View {
        HStack(spacing: 10) {
            Button { showsRemote = true } label: { Label("Fjärrkontroll", systemImage: "gamecontroller") }
            if s.isGameRunning {
                Button { console.exitGame() } label: { Label("Avsluta spelet", systemImage: "xmark.circle") }
            }
            Button { console.eject() } label: { Label("Mata ut skivan", systemImage: "eject") }
            if let note = console.actionNote {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, 6)
            }
            Spacer(minLength: 10)
            Button { confirming = .restart } label: { Label("Starta om…", systemImage: "arrow.clockwise") }
            Button { confirming = .shutdown } label: { Label("Stäng av…", systemImage: "power") }
        }
        .buttonStyle(PillButtonStyle(prominent: false))
        .disabled(console.isActing)
    }

    /// The PS app's storage sheet: free space, a white bar of what is used, and the total.
    private func spaceCard(_ s: ConsoleSnapshot) -> some View {
        let parts = s.freeBytes.map { Format.bytes($0).split(separator: " ").map(String.init) } ?? ["–"]
        return Card(icon: "internaldrive", title: "Ledigt", chip: "/dev_hdd0") {
            BigValue(value: parts.first ?? "–", unit: parts.count > 1 ? parts[1] : nil)
            if let free = s.freeBytes, let total = s.totalBytes {
                PSProgressBar(fraction: 1 - Double(free) / Double(total))
            }
            Spacer(minLength: 0)
            if let total = s.totalBytes {
                Footnote(text: "Lagring \(Format.bytes(total))")
            } else {
                Footnote(text: (s.freeBytes ?? 0) < 50_000_000_000 ? "Det börjar bli trångt" : "Gott om plats för fler spel")
            }
        }
        .frame(height: 170)
    }

    private func networkCard(_ s: ConsoleSnapshot) -> some View {
        Card(icon: "network", title: "Nätverk", chip: s.network) {
            Text(s.ip ?? console.host ?? "–")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 0)
            HStack {
                Footnote(text: "webMAN svarar")
                Spacer()
                if let latency = console.latency {
                    Text(latency < 1 ? "\(Int(latency * 1000)) ms" : String(format: "%.1f s", latency))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(latency < 1.5 ? Theme.good : Theme.warm)
                }
            }
        }
        .frame(height: 170)
    }

    /// Like "Vänner som spelar" in the PS app: the game's own art behind it, its icon, and
    /// a green dot while it runs.
    private func nowPlayingCard(_ s: ConsoleSnapshot) -> some View {
        let name = s.isGameRunning ? (s.mountedGameName ?? s.runningProcess ?? "Okänt spel") : (s.mountedGameName ?? "Inget spel")
        return ZStack(alignment: .bottomLeading) {
            nowPlayingBackdrop
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text("SPELAR NU")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(Theme.primaryText.opacity(0.85))
                    Spacer()
                    Chip(text: s.isGameRunning ? "Spelar" : "XMB", color: s.isGameRunning ? Theme.good : Theme.secondaryText)
                }
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 12) {
                    gameThumbnail(name: name)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(s.isGameRunning || s.mountedGameName != nil ? Theme.primaryText : Theme.secondaryText)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            if s.isGameRunning {
                                Circle().fill(Theme.good).frame(width: 8, height: 8)
                                Text(s.playTime.map { "Spelar nu · \($0)" } ?? "Spelar nu")
                            } else {
                                Text(s.mountedGameName == nil ? "Ingen skiva monterad" : "Monterad")
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardStroke))
    }

    @ViewBuilder private var nowPlayingBackdrop: some View {
        if let background = console.gameBackground ?? console.gameIcon {
            // In an overlay, so the picture fills the card without widening its grid column.
            Color.clear
                .overlay(Image(nsImage: background).resizable().aspectRatio(contentMode: .fill))
                .overlay(LinearGradient(colors: [Color.black.opacity(0.35), Color.black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
        } else {
            ZStack {
                Theme.cardFill
                LinearGradient(colors: [Theme.novaPink.opacity(0.22), Theme.psBlue.opacity(0.10), .clear],
                               startPoint: .topTrailing, endPoint: .bottomLeading)
            }
        }
    }

    private func gameThumbnail(name: String) -> some View {
        Group {
            if let icon = console.gameIcon {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [Theme.novaPink.opacity(0.9), Theme.psBlue.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "opticaldisc.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
            }
        }
        .frame(width: 80, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
    }

    private func systemCard(_ s: ConsoleSnapshot) -> some View {
        Card(icon: "shield.lefthalf.filled", title: "System", chip: s.firmwareType) {
            VStack(alignment: .leading, spacing: 8) {
                versionLine("Firmware", s.firmware)
                versionLine("PS3HEN", s.henVersion)
                versionLine("webMAN", s.webmanVersion)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 170)
    }

    /// Follows the recent values so small changes are visible (a fixed 30–90 °C scale looks flat).
    static func range(for values: [Double], padding: Double) -> ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        return (low - padding)...(high + padding)
    }

    private func versionLine(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(value ?? "–").font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.primaryText)
        }
    }
}

/// Like Mole's process table: what PS3 Center changed on the console, newest first.
struct HistoryTable: View {
    let entries: [OperationLog.Entry]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("HISTORIK (\(entries.count))")
                Spacer()
                Text("ÅTGÄRD").frame(width: 90, alignment: .leading)
                Text("TID").frame(width: 130, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider().overlay(Theme.cardStroke)

            if entries.isEmpty {
                Text("Inget ändrat än. Uppladdningar och installationer från appen eller `ps3` visas här.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(20)
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                HStack {
                    Image(systemName: icon(for: entry.action))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 20)
                    Text((entry.detail as NSString).lastPathComponent)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Text(entry.action).frame(width: 90, alignment: .leading)
                        .foregroundStyle(Theme.secondaryText)
                    Text(Self.displayDate(entry.date)).frame(width: 130, alignment: .trailing)
                        .foregroundStyle(Theme.secondaryText)
                        .monospacedDigit()
                }
                .font(.system(size: 13))
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
            }
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardStroke))
    }

    private func icon(for action: String) -> String {
        switch action {
        case "install": return "shippingbox"
        case "send": return "arrow.up.circle"
        case "refresh": return "arrow.clockwise"
        case "play": return "play.circle"
        case "mount": return "opticaldisc"
        case "unmount": return "eject"
        case "exit": return "xmark.circle"
        case "delete": return "trash"
        default: return "circle"
        }
    }

    static func displayDate(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return iso }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "'idag' HH:mm" : "d MMM HH:mm"
        return formatter.string(from: date)
    }
}

/// Shut down or restart, with what the confirmation says.
enum PowerAction: Equatable {
    case shutdown, restart

    var question: String { self == .shutdown ? "Stänga av PS3:an?" : "Starta om PS3:an?" }
    var button: String { self == .shutdown ? "Stäng av" : "Starta om" }

    func message(running: Bool) -> String {
        let game = running ? "Ett spel körs: spara först, annars försvinner det som inte är sparat. " : ""
        switch self {
        case .shutdown: return game + "PS3:an kan inte startas från Macen, bara med knappen eller handkontrollen."
        case .restart: return game + "På HEN måste HEN aktiveras igen efter omstarten innan PS3 Center når konsolen."
        }
    }
}
