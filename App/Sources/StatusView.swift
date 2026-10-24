import PS3Kit
import SwiftUI

/// Mole's Status tab, for a PS3: eight cards and a history table underneath.
struct StatusView: View {
    @Environment(ConsoleStore.self) private var console
    /// False when rendered for a snapshot: ImageRenderer cannot draw scroll views.
    var scrolls = true

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)

    var body: some View {
        if scrolls {
            ScrollView { grid }.scrollIndicators(.hidden)
        } else {
            grid
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
            Footnote(text: "webMAN styr fläkten automatiskt")
        }
        .frame(height: 210)
    }

    private func spaceCard(_ s: ConsoleSnapshot) -> some View {
        let parts = s.freeBytes.map { Format.bytes($0).split(separator: " ").map(String.init) } ?? ["–"]
        return Card(icon: "internaldrive", title: "Ledigt", chip: "/dev_hdd0") {
            BigValue(value: parts.first ?? "–", unit: parts.count > 1 ? parts[1] : nil)
            Spacer(minLength: 0)
            Footnote(text: (s.freeBytes ?? 0) < 50_000_000_000 ? "Det börjar bli trångt" : "Gott om plats för fler spel")
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

    private func nowPlayingCard(_ s: ConsoleSnapshot) -> some View {
        Card(icon: "gamecontroller", title: "Spelar nu", chip: s.isGameRunning ? "Spelar" : "XMB",
             chipColor: s.isGameRunning ? Theme.good : Theme.secondaryText) {
            Text(s.isGameRunning ? (s.mountedGameName ?? s.runningProcess ?? "Okänt spel") : "Inget spel")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(s.isGameRunning ? Theme.primaryText : Theme.secondaryText)
                .lineLimit(2)
            Spacer(minLength: 0)
            Footnote(text: s.isGameRunning ? (s.playTime.map { "Spelat \($0)" } ?? "") : (s.mountedGameName.map { "Monterat: \($0)" } ?? "Ingen skiva monterad"))
        }
        .frame(height: 170)
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
