import PS3Kit
import SwiftUI

/// Transfers: the send queue with progress, Start/Pause, what happens when it is done, the
/// MD5 check and the measured speed. Opened from the arrows in the top bar.
struct TransfersView: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(TransferStore.self) private var transfers
    /// False when rendered for a snapshot: ImageRenderer cannot draw scroll views.
    var scrolls = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let note = transfers.note {
                NoteBanner(text: note).padding(.top, 14)
            }
            Group {
                if transfers.queue.items.isEmpty {
                    Text("The queue is empty. Pick games under Mac in the Games tab, or drag files onto the window.")
                        .font(.ui(.body))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if scrolls {
                    ScrollView { list }.scrollIndicators(.hidden)
                } else {
                    list
                }
            }
            .padding(.top, 16)

            Divider().overlay(Theme.cardStroke).padding(.vertical, 16)
            settings
            Spacer(minLength: 16)
            HStack {
                Spacer()
                // Outlined while Start is the sheet's white button.
                DoneButton(prominent: transfers.isRunning || transfers.pending.isEmpty)
            }
        }
        .padding(32)
        .frame(width: 640, height: 720, alignment: .topLeading)
        .background(Theme.base)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Transfers")
                    .font(.ui(.display, weight: .light))
                    .foregroundStyle(Theme.primaryText)
                Text(summary)
                    .font(.ui(.body))
                    .foregroundStyle(Theme.secondaryText)
                    .monospacedDigit()
            }
            Spacer()
            if transfers.isRunning {
                Button("Pause") { transfers.pause() }
                    .buttonStyle(PillButtonStyle(prominent: false))
            } else if !transfers.pending.isEmpty {
                Button("Start") { transfers.start() }
                    .buttonStyle(PillButtonStyle())
            }
            if transfers.queue.items.contains(where: { $0.state == .done }) {
                Button("Clear Finished") { transfers.clearFinished() }
                    .buttonStyle(PillButtonStyle(prominent: false))
            }
        }
    }

    private var summary: String {
        let pending = transfers.pending.count
        guard pending > 0 else { return "Nothing left to send" }
        var parts = ["\(pending) left", Format.bytes(transfers.remainingBytes)]
        if transfers.isRunning, transfers.rate > 0 { parts.append(Format.rate(transfers.rate)) }
        if let eta = transfers.eta { parts.append("about \(Format.estimate(eta)) left") }
        return parts.joined(separator: " · ")
    }

    private var list: some View {
        VStack(spacing: 8) {
            ForEach(transfers.queue.items) { item in row(item) }
        }
    }

    private func row(_ item: TransferQueue.Item) -> some View {
        HStack(spacing: 14) {
            stateIcon(item)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.title)
                        .font(.ui(.callout, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Text(item.state == .done ? Format.bytes(item.total) : "\(Format.bytes(item.sent)) of \(Format.bytes(item.total))")
                        .font(.ui(.footnote))
                        .foregroundStyle(Theme.secondaryText)
                        .monospacedDigit()
                }
                if item.state == .failed, let message = item.message {
                    Text(message)
                        .font(.ui(.footnote))
                        .foregroundStyle(Theme.hotText)
                        .lineLimit(2)
                } else if item.state != .done {
                    PSProgressBar(fraction: item.fraction)
                }
            }
            if item.state == .failed {
                Button { transfers.retry(item.id) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondaryText)
                    .iconLabel("Try Again")
            }
            if item.id != transfers.current {
                Button { transfers.remove(item.id) } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.tertiaryText)
                    .iconLabel("Remove from the queue (files on the PS3 are not touched)")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardFill))
    }

    @ViewBuilder private func stateIcon(_ item: TransferQueue.Item) -> some View {
        switch item.state {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.hot)
        case .paused: Image(systemName: "pause.circle").foregroundStyle(Theme.warm)
        case .waiting: Image(systemName: "clock").foregroundStyle(Theme.tertiaryText)
        case .sending:
            if transfers.isRunning, transfers.current == item.id {
                Image(systemName: "arrow.up.circle.fill").foregroundStyle(Theme.accent)
            } else {
                Image(systemName: "pause.circle").foregroundStyle(Theme.warm)
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("When the queue finishes").font(.ui(.body)).foregroundStyle(Theme.secondaryText)
                Spacer()
                WhenDonePicker()
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Verify with MD5").font(.ui(.body)).foregroundStyle(Theme.primaryText)
                    Text("The PS3 computes a checksum for each large game; takes a few minutes per game.")
                        .font(.ui(.caption)).foregroundStyle(Theme.tertiaryText)
                }
                Spacer()
                PillToggle(isOn: transfers.queue.verify, label: "Verify with MD5") { transfers.setVerify($0) }
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speed").font(.ui(.body)).foregroundStyle(Theme.primaryText)
                    Text(speedText).font(.ui(.caption)).foregroundStyle(Theme.tertiaryText)
                    if let error = transfers.measureError {
                        Text(error).font(.ui(.caption)).foregroundStyle(Theme.hotText).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if transfers.isMeasuring {
                    HStack(spacing: 8) {
                        Spinner()
                        Text(transfers.measureStep ?? "Measuring…").font(.ui(.footnote)).foregroundStyle(Theme.secondaryText).monospacedDigit()
                    }
                } else {
                    Button("Measure Speed") { Task { await transfers.measureSpeed() } }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .disabled(transfers.isRunning)
                        .help(transfers.isRunning ? "Pause the queue first; the test and the queue share the PS3's FTP" : "Sends to the PS3 for five seconds and reads back what arrived")
                }
            }
            if (transfers.lastSpeed?.network ?? console.snapshot?.network) == .wifi {
                // One line with a mark instead of a paragraph in yellow; the reassurance is in the tooltip.
                tip("wifi", "Wi-Fi only does 2.4 GHz on the PS3. With a cable, 10 GB takes \(SpeedTest.cableEstimate(bytes: 10_000_000_000)).")
                    .help("The Mac stays awake while the queue runs, and the PS3 is never shut down in the middle of a transfer.")
            }
            if KeepAwake.isOnBattery, !transfers.queue.pending.isEmpty {
                tip("battery.50", KeepAwake.batteryTip)
            }
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Theme.warm)
            Text(text)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.ui(.footnote))
    }

    private var speedText: String {
        guard let speed = transfers.lastSpeed else { return "Not measured yet: measure for a time estimate in the queue." }
        // Format.day is always English; `formatted(date:)` followed the system language.
        let network = speed.network.map { " over \($0.label)" } ?? ""
        return "\(Format.rate(speed.upload)) to the PS3\(network) · 10 GB takes about \(Format.estimate(10e9 / speed.upload)) · measured \(Format.day(speed.measuredAt))"
    }
}

/// An on/off switch in the PS app's style; drawn by SwiftUI, so snapshots can render it.
struct PillToggle: View {
    let isOn: Bool
    /// What VoiceOver says; the switch has no visible text of its own.
    var label = ""
    let change: (Bool) -> Void

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { change(!isOn) }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Theme.accent : Color.white.opacity(0.18))
                Circle().fill(Color.white).padding(3)
            }
            .frame(width: 44, height: 26)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}
