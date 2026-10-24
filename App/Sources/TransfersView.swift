import PS3Kit
import SwiftUI

/// Överföringar: the send queue with progress, Starta/Pausa, what happens when it is done, the
/// MD5 check and the measured speed. Opened from the arrows in the top bar.
struct TransfersView: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(TransferStore.self) private var transfers
    @Environment(\.dismiss) private var dismiss
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
                    Text("Kön är tom. Välj spel under Macen i Spel-fliken, eller dra filer till fönstret.")
                        .font(.system(size: 13))
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
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(CircleIconButtonStyle(size: 44, filled: true))
                    .keyboardShortcut(.cancelAction)
                    .help("Tillbaka")
                Spacer()
            }
        }
        .padding(32)
        .frame(width: 640, height: 720, alignment: .topLeading)
        .background(Theme.base)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Överföringar")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.primaryText)
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .monospacedDigit()
            }
            Spacer()
            if transfers.isRunning {
                Button("Pausa") { transfers.pause() }
                    .buttonStyle(PillButtonStyle(prominent: false))
            } else if !transfers.pending.isEmpty {
                Button("Starta") { transfers.start() }
                    .buttonStyle(PillButtonStyle())
            }
            if transfers.queue.items.contains(where: { $0.state == .done }) {
                Button("Rensa klara") { transfers.clearFinished() }
                    .buttonStyle(PillButtonStyle(prominent: false))
            }
        }
    }

    private var summary: String {
        let pending = transfers.pending.count
        guard pending > 0 else { return "Inget kvar att skicka" }
        var parts = ["\(pending) kvar", Format.bytes(transfers.remainingBytes)]
        if transfers.isRunning, transfers.rate > 0 { parts.append(Format.rate(transfers.rate)) }
        if let eta = transfers.eta { parts.append("ca \(Format.duration(eta)) kvar") }
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Text(item.state == .done ? Format.bytes(item.total) : "\(Format.bytes(item.sent)) av \(Format.bytes(item.total))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .monospacedDigit()
                }
                if item.state == .failed, let message = item.message {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.hot)
                        .lineLimit(2)
                } else if item.state != .done {
                    PSProgressBar(fraction: item.fraction)
                }
            }
            if item.state == .failed {
                Button { transfers.retry(item.id) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondaryText)
                    .help("Försök igen")
            }
            if item.id != transfers.current {
                Button { transfers.remove(item.id) } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.tertiaryText)
                    .help("Ta bort ur kön (filer på PS3:an rörs inte)")
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
                Text("När kön är klar").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                Spacer()
                WhenDonePicker()
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kontrollera med MD5").font(.system(size: 13)).foregroundStyle(Theme.primaryText)
                    Text("PS3:an räknar en kontrollsumma för varje stort spel; tar några minuter per spel.")
                        .font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
                }
                Spacer()
                PillToggle(isOn: transfers.queue.verify) { transfers.setVerify($0) }
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hastighet").font(.system(size: 13)).foregroundStyle(Theme.primaryText)
                    Text(speedText).font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
                    if let error = transfers.measureError {
                        Text(error).font(.system(size: 11)).foregroundStyle(Theme.hot).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if transfers.isMeasuring {
                    HStack(spacing: 8) {
                        Spinner()
                        Text(transfers.measureStep ?? "Mäter…").font(.system(size: 12)).foregroundStyle(Theme.secondaryText).monospacedDigit()
                    }
                } else {
                    Button("Mät hastigheten") { Task { await transfers.measureSpeed() } }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .disabled(transfers.isRunning)
                        .help(transfers.isRunning ? "Pausa kön först; mätningen och kön delar på PS3:ans FTP" : "Skickar till PS3:an i fem sekunder och läser tillbaka det som kom fram")
                }
            }
            if (transfers.lastSpeed?.network ?? console.snapshot?.network) == "Wi-Fi" {
                Text("PS3:an är på Wi-Fi, som bara klarar 2,4 GHz. Med nätverkskabel brukar det gå flera gånger fortare. Macen hålls vaken medan kön går, och PS3:an stängs inte av mitt i en överföring.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.warm)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var speedText: String {
        guard let speed = transfers.lastSpeed else { return "Inte mätt än: mät för en tidsberäkning i kön." }
        let date = speed.measuredAt.formatted(date: .abbreviated, time: .omitted)
        let network = speed.network.map { " över \($0)" } ?? ""
        return "\(Format.rate(speed.upload)) till PS3:an\(network) · 10 GB tar ca \(Format.duration(10e9 / speed.upload)) · mätt \(date)"
    }
}

/// An on/off switch in the PS app's style; drawn by SwiftUI, so snapshots can render it.
struct PillToggle: View {
    let isOn: Bool
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
    }
}
