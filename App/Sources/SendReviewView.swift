import AppKit
import PS3Kit
import SwiftUI

/// What is about to be sent: from the Mac's grid or files dropped on the window.
struct SendReview: Identifiable {
    let id = UUID()
    let routes: [Route]
}

/// The review before sending, as DESIGN.md describes: the games with check boxes and sizes,
/// the console's free space before and after, the expected time, and what the queue does when
/// it is done. The white button says exactly what happens.
struct SendReviewView: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(TransferStore.self) private var transfers
    @Environment(GamesStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let review: SendReview
    @State private var excluded: Set<String> = []

    struct Entry: Identifiable {
        let title: String
        let routes: [Route]
        var id: String { title }
        var size: Int64 { routes.reduce(0) { $0 + $1.size } }
    }

    /// One row per game, grouped as the queue groups them.
    private var groups: [Entry] {
        TransferQueue.games(in: review.routes).map { Entry(title: $0.title, routes: $0.routes) }
    }

    private var chosen: [Entry] { groups.filter { !excluded.contains($0.id) } }
    private var total: Int64 { chosen.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Send to PS3")
                .font(.ui(.display, weight: .light))
                .foregroundStyle(Theme.primaryText)
            Text("The games join the queue and are sent one at a time. If something is interrupted, it resumes where it stopped.")
                .font(.ui(.body))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 6)
                .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(groups) { group in row(group) }
                }
            }
            .frame(maxHeight: 250)

            Divider().overlay(Theme.cardStroke).padding(.vertical, 14)

            VStack(alignment: .leading, spacing: 8) {
                fact("To send", Format.bytes(total))
                if let free = console.snapshot?.freeBytes {
                    let after = free - total
                    fact("Free on the PS3", "\(Format.bytes(free)) → \(Format.bytes(max(after, 0)))", warn: after < 1_000_000_000)
                }
                fact("Time", timeText)
                if sendsPS2ISOToHEN {
                    Text(PlayCheck.Finding.ps2NeedsClassic.message)
                        .font(.ui(.footnote))
                        .foregroundStyle(Theme.warm)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if console.snapshot?.network == .wifi, total > 2_000_000_000 {
                    Text("The PS3 is on Wi-Fi (2.4 GHz only). With a cable it takes \(SpeedTest.cableEstimate(bytes: total))\(cableSource).")
                        .font(.ui(.footnote))
                        .foregroundStyle(Theme.warm)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if KeepAwake.isOnBattery {
                    Text(KeepAwake.batteryTip)
                        .font(.ui(.footnote))
                        .foregroundStyle(Theme.warm)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("WHEN THE QUEUE FINISHES")
                .font(.ui(.caption, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 18)
                .padding(.bottom, 8)
            WhenDonePicker()

            Spacer(minLength: 16)
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                Button(chosen.count == 1 ? "Send \(chosen[0].title)" : "Send \(chosen.count) Games") {
                    transfers.add(chosen.flatMap(\.routes))
                    library.selection.removeAll()
                    dismiss()
                }
                .buttonStyle(PillButtonStyle())
                .disabled(chosen.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 560, height: 640, alignment: .topLeading)
        .background(Theme.base)
    }

    /// A plain PS2 ISO among the chosen games while the console runs HEN, where it will not start.
    private var sendsPS2ISOToHEN: Bool {
        PlayCheck.sendsPS2ISOToHEN(chosen.flatMap(\.routes), console: console.snapshot.map(ConsoleProfile.init))
    }

    private func row(_ group: Entry) -> some View {
        let on = !excluded.contains(group.id)
        return Button {
            if on { excluded.insert(group.id) } else { excluded.remove(group.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.ui(.title3))
                    .foregroundStyle(on ? Theme.accent : Theme.tertiaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                        .font(.ui(.callout, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Text(group.routes.count == 1 ? group.routes[0].remote : "\(group.routes.count) files to \((group.routes[0].remote as NSString).deletingLastPathComponent)")
                        .font(.ui(.caption, design: .monospaced))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(Format.bytes(group.size))
                    .font(.ui(.body))
                    .foregroundStyle(Theme.secondaryText)
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fact(_ label: String, _ value: String, warn: Bool = false) -> some View {
        HStack {
            Text(label).font(.ui(.body)).foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(value)
                .font(.ui(.body, weight: .semibold))
                .foregroundStyle(warn ? Theme.hot : Theme.primaryText)
                .monospacedDigit()
        }
    }

    private var timeText: String {
        guard let speed = transfers.lastSpeed, speed.upload > 0 else {
            return "measure the speed under Transfers"
        }
        let network = speed.network.map { ", \($0.label)" } ?? ""
        return "about \(Format.estimate(Double(total) / speed.upload)) (\(Format.rate(speed.upload))\(network))"
    }

    /// Where the cable time comes from: a measurement over LAN, or what others report.
    private var cableSource: String {
        SpeedTest.measurement(over: .lan) == nil ? ", based on the 10–40 MB/s others have measured" : " from your measurement with a cable"
    }
}

/// "When the queue finishes": the PS app's dark segmented control with the queue's three endings.
struct WhenDonePicker: View {
    @Environment(TransferStore.self) private var transfers

    var body: some View {
        PillPicker(options: TransferQueue.WhenDone.allCases, selection: transfers.queue.whenDone, label: \.label) {
            transfers.setWhenDone($0)
        }
    }
}
