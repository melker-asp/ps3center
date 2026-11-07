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
                        temperatureCard(icon: "cpu", title: "CPU", value: s.cpuTemp, sensor: .cpu,
                                        history: console.cpuHistory)
                        temperatureCard(icon: "square.stack.3d.up", title: "RSX", value: s.rsxTemp, sensor: .rsx,
                                        history: console.rsxHistory)
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
        // No chip: the network type is on the Network card.
        Card(icon: "sun.max", title: "Health") {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(s.health)")
                            .font(.ui(.hero, weight: .light))
                            .foregroundStyle(Theme.primaryText)
                        Text(s.healthLabel)
                            .font(.ui(.title3, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    // Up to two notes; the polling interval was developer detail.
                    Text(s.healthNotes.isEmpty ? "Everything looks good" : s.healthNotes.prefix(2).joined(separator: "\n"))
                        .font(.ui(.body))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                HealthOrb(color: Theme.healthColor(s.healthLevel))
                    .scaleEffect(0.62)
                    .frame(width: 70, height: 70)
                    .offset(y: 6)
            }
        }
        .frame(height: 210)
    }

    private func temperatureCard(icon: String, title: String, value: Int?, sensor: Thermal,
                                 history: [Double]) -> some View {
        let level = value.map(sensor.level)
        let color = level.map(Theme.temperatureColor) ?? Theme.good
        let label = level?.label
        let warnAt = sensor.warnAt
        return Card(icon: icon, title: title, chip: label, chipColor: color) {
            BigValue(value: value.map(String.init) ?? "–", unit: "°C")
            Sparkline(values: history, range: Self.range(for: history, padding: 3), color: color)
                .frame(height: 34)
            Spacer(minLength: 0)
            Footnote(text: peakNote(history, warnAt: warnAt))
        }
        .frame(height: 210)
    }

    /// "Peak 64 °C in 5 min · warns at 70 °C": what the sparkline shows, in numbers.
    private func peakNote(_ history: [Double], warnAt: Int) -> String {
        guard let peak = history.max(), history.count > 1 else { return "Warns at \(warnAt) °C" }
        let minutes = max(1, Int((Double(history.count) * console.interval / 60).rounded()))
        return "Peak \(Int(peak)) °C in \(minutes) min · warns at \(warnAt) °C"
    }

    private func fanCard(_ s: ConsoleSnapshot) -> some View {
        // The chip says the mode; the target itself is in the footnote, next to − and +.
        Card(icon: "fan", title: "Fan", chip: s.fanTargetMax == nil ? "Auto" : "Dynamic") {
            BigValue(value: s.fanPercent.map(String.init) ?? "–", unit: "%")
            Sparkline(values: console.fanHistory, range: Self.range(for: console.fanHistory, padding: 5), color: Theme.cool)
                .frame(height: 34)
            Spacer(minLength: 0)
            if let target = s.fanTargetMax {
                // webMAN's dynamic mode: only the target moves, within FanControl.targets.
                HStack(spacing: 6) {
                    Footnote(text: "Target \(target) °C")
                    Spacer(minLength: 0)
                    Button { console.setFanTarget(target - 1) } label: { Image(systemName: "minus") }
                        .disabled(target <= FanControl.targets.lowerBound)
                        .iconLabel("Lower the target (the fan speeds up sooner)")
                    Button { console.setFanTarget(target + 1) } label: { Image(systemName: "plus") }
                        .disabled(target >= FanControl.targets.upperBound)
                        .iconLabel("Raise the target (quieter, warmer)")
                }
                // 28 pt: WCAG 2.2 asks for at least 24.
                .buttonStyle(CircleIconButtonStyle(size: 28))
                .disabled(console.isActing)
            } else {
                Footnote(text: "The console controls the fan")
            }
        }
        .frame(height: 210)
    }

    /// The console's own buttons: the remote, quitting the game, the disc, and power.
    private func controls(_ s: ConsoleSnapshot) -> some View {
        HStack(spacing: 10) {
            Button { showsRemote = true } label: { Label("Remote", systemImage: "gamecontroller") }
            if s.isGameRunning {
                Button { console.exitGame() } label: { Label("Quit Game", systemImage: "xmark.circle") }
                Button { console.toggleRecording() } label: {
                    Label(console.isRecording ? "Stop Recording" : "Record", systemImage: console.isRecording ? "stop.circle" : "record.circle")
                }
                .help("webMAN records the game as 720p MP4 in /dev_hdd0/VIDEO")
            }
            Button { console.eject() } label: { Label("Eject Disc", systemImage: "eject") }
            if let note = console.actionNote {
                Text(note)
                    .font(.ui(.footnote))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, 6)
            }
            Spacer(minLength: 10)
            Button { confirming = .restart } label: { Label("Restart…", systemImage: "arrow.clockwise") }
            Button { confirming = .shutdown } label: { Label("Shut Down…", systemImage: "power") }
        }
        .buttonStyle(PillButtonStyle(prominent: false))
        .disabled(console.isActing)
    }

    /// The PS app's storage sheet: free space, a white bar of what is used, and the total.
    /// The footnote says what the bar is, since the big number is the free space.
    private func spaceCard(_ s: ConsoleSnapshot) -> some View {
        let parts = s.freeBytes.map { Format.bytes($0).split(separator: " ").map(String.init) } ?? ["–"]
        return Card(icon: "internaldrive", title: "Free", chip: "/dev_hdd0") {
            BigValue(value: parts.first ?? "–", unit: parts.count > 1 ? parts[1] : nil)
            if let free = s.freeBytes, let total = s.totalBytes {
                PSProgressBar(fraction: 1 - Double(free) / Double(total))
            }
            Spacer(minLength: 0)
            if let free = s.freeBytes, let total = s.totalBytes {
                Footnote(text: "\(Format.bytes(max(total - free, 0))) used of \(Format.bytes(total))")
            } else {
                Footnote(text: (s.freeBytes ?? 0) < 50_000_000_000 ? "Running low on space" : "Plenty of room for more games")
            }
        }
        .frame(height: 170)
    }

    private func networkCard(_ s: ConsoleSnapshot) -> some View {
        Card(icon: "network", title: "Network", chip: s.network?.label) {
            Text(s.ip ?? console.host ?? "–")
                .font(.ui(.title, weight: .light))
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 0)
            HStack {
                Footnote(text: "webMAN response time")
                Spacer()
                if let latency = console.latency {
                    Text(latency < 1 ? "\(Int(latency * 1000)) ms" : String(format: "%.1f s", latency))
                        .font(.ui(.body, weight: .medium))
                        .foregroundStyle(latency < 1.5 ? Theme.good : Theme.warm)
                }
            }
        }
        .frame(height: 170)
    }

    /// Like "Friends Playing" in the PS app: the game's own art behind it, its icon, and
    /// a green dot while it runs.
    private func nowPlayingCard(_ s: ConsoleSnapshot) -> some View {
        let name = s.isGameRunning ? (s.mountedGameName ?? s.runningProcess ?? "Unknown game") : (s.mountedGameName ?? "No game")
        return ZStack(alignment: .bottomLeading) {
            nowPlayingBackdrop
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "gamecontroller")
                        .font(.ui(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text("NOW PLAYING")
                        .font(.ui(.caption, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(Theme.primaryText.opacity(0.85))
                    Spacer()
                    // While a game runs, the green dot and "Playing" below already say so.
                    if !s.isGameRunning { Chip(text: "XMB", color: Theme.secondaryText) }
                }
                .frame(minHeight: Chip.height)
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 12) {
                    gameThumbnail(name: name)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .font(.ui(.title3, weight: .semibold))
                            .foregroundStyle(s.isGameRunning || s.mountedGameName != nil ? Theme.primaryText : Theme.secondaryText)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            if s.isGameRunning {
                                Circle().fill(Theme.good).frame(width: 8, height: 8)
                                Text(s.playTime.map { "Playing · \($0)" } ?? "Playing")
                            } else {
                                Text(s.mountedGameName == nil ? "No disc mounted" : "Mounted")
                            }
                        }
                        .font(.ui(.footnote))
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
                        .font(.ui(.title3, weight: .semibold))
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
            Text(label).font(.ui(.body)).foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(value ?? "–").font(.ui(.body, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.primaryText)
        }
    }
}

/// Like Mole's process table: what PS3 Center changed on the console, newest first.
struct HistoryTable: View {
    let entries: [OperationLog.Entry]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("HISTORY (\(entries.count))")
                Spacer()
                Text("ACTION").frame(width: 150, alignment: .leading)
                Text("TIME").frame(width: 130, alignment: .trailing)
            }
            .font(.ui(.caption, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider().overlay(Theme.cardStroke)

            if entries.isEmpty {
                Text("Nothing changed yet. Uploads and installs from the app or `ps3` show up here.")
                    .font(.ui(.body))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(20)
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                let described = Self.describe(entry)
                HStack {
                    Image(systemName: entry.kind.map(Self.icon) ?? "circle")
                        .foregroundStyle(Theme.accent)
                        .frame(width: 20)
                    Text(described.subject)
                        .font(.ui(.callout, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Text(described.action).frame(width: 150, alignment: .leading)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                    Text(Self.displayDate(entry.date)).frame(width: 130, alignment: .trailing)
                        .foregroundStyle(Theme.secondaryText)
                        .monospacedDigit()
                }
                .font(.ui(.body))
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
            }
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardStroke))
    }

    /// Exhaustive on purpose: a new `OperationKind` doesn't build until it has an icon and words.
    static func icon(_ kind: OperationKind) -> String {
        switch kind {
        case .install, .installTheme: return "shippingbox"
        case .send, .covers, .libcrypt: return "arrow.up.circle"
        case .refresh, .reloadXMB: return "arrow.clockwise"
        case .play: return "play.circle"
        case .mount, .rip, .ripAbort: return "opticaldisc"
        case .unmount, .eject, .insert: return "eject"
        case .exit: return "xmark.circle"
        case .delete, .uninstall, .deleteSave: return "trash"
        case .update: return "arrow.down.circle"
        case .restart: return "arrow.clockwise.circle"
        case .shutdown: return "power"
        case .record: return "record.circle"
        case .gameMusic: return "music.note"
        case .screenshots: return "camera"
        case .updateBlock: return "hand.raised"
        case .fan: return "fan"
        case .restore: return "arrow.uturn.backward.circle"
        case .webmanSetup: return "gearshape"
        }
    }

    /// What the row says: the thing that changed, and the action in words. The log keeps the
    /// short action names that `ps3 history` and scripts read; this is only how they look here.
    static func describe(_ entry: OperationLog.Entry) -> (subject: String, action: String) {
        let file = (entry.detail as NSString).lastPathComponent
        let onOff = entry.switchedOn == true ? "On" : "Off"
        guard let kind = entry.kind else {
            return (file, entry.action.replacingOccurrences(of: "-", with: " ").capitalized)
        }
        switch kind {
        case .install: return (file, "Installed")
        case .installTheme: return (file, "Theme installed")
        case .send: return (file, "Sent")
        case .update: return (entry.detail, "Updated")
        case .uninstall: return (file, "Uninstalled")
        case .delete: return (file, "Deleted")
        case .deleteSave: return (entry.detail, "Save deleted")
        case .restore: return (entry.detail, "Save restored")
        case .play: return (file, "Started")
        case .mount: return (file, "Mounted")
        case .unmount: return ("Disc", "Unmounted")
        case .exit: return (file, "Quit")
        case .refresh: return ("Game list", "Refreshed")
        case .reloadXMB: return ("XMB", "Reloaded")
        case .eject: return ("Disc", "Ejected")
        case .insert: return ("Disc", "Inserted")
        case .restart: return ("PS3", "Restarted")
        case .shutdown: return ("PS3", "Shut down")
        case .record: return ("Recording", entry.switchedOn == true ? "Started" : "Stopped")
        case .gameMusic: return ("In-game music", onOff)
        case .screenshots: return ("In-game screenshots", "On")
        case .updateBlock: return ("System update block", onOff)
        case .fan: return ("Fan", "Target changed")
        case .covers: return (entry.detail, "Covers sent")
        case .libcrypt: return (file, "LibCrypt file sent")
        case .rip: return (entry.detail, "Disc copied")
        case .ripAbort: return ("Disc copy", "Stopped")
        case .webmanSetup: return ("webMAN settings", "Changed")
        }
    }

    static func displayDate(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return iso }
        let formatter = DateFormatter()
        formatter.locale = Theme.locale
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "'Today' HH:mm" : "MMM d, HH:mm"
        return formatter.string(from: date)
    }
}

/// Shut down or restart, with what the confirmation says.
enum PowerAction: Equatable {
    case shutdown, restart

    var question: String { self == .shutdown ? "Shut down the PS3?" : "Restart the PS3?" }
    var button: String { self == .shutdown ? "Shut Down" : "Restart" }

    func message(running: Bool) -> String {
        let game = running ? "A game is running: save first, or anything unsaved is lost. " : ""
        switch self {
        case .shutdown: return game + "The PS3 can't be turned on from the Mac, only with its button or the controller."
        case .restart: return game + "On HEN, HEN has to be enabled again after the restart before PS3 Center can reach the console."
        }
    }
}
