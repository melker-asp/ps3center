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

    private var groups: [Entry] {
        var order: [String] = []
        var byTitle: [String: [Route]] = [:]
        for route in review.routes {
            let title = route.title ?? GameName.clean(route.local.lastPathComponent)
            if byTitle[title] == nil { order.append(title) }
            byTitle[title, default: []].append(route)
        }
        return order.map { Entry(title: $0, routes: byTitle[$0] ?? []) }
    }

    private var chosen: [Entry] { groups.filter { !excluded.contains($0.id) } }
    private var total: Int64 { chosen.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Skicka till PS3:an")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.primaryText)
            Text("Spelen läggs i kön och skickas ett i taget. Avbryts något fortsätter det där det slutade.")
                .font(.system(size: 13))
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
                fact("Att skicka", Format.bytes(total))
                if let free = console.snapshot?.freeBytes {
                    let after = free - total
                    fact("Ledigt på PS3:an", "\(Format.bytes(free)) → \(Format.bytes(max(after, 0)))", warn: after < 1_000_000_000)
                }
                fact("Tid", timeText)
                if sendsPS2ISOToHEN {
                    Text(PlayCheck.Finding.ps2NeedsClassic.message)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.warm)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if console.snapshot?.network == "Wi-Fi", total > 2_000_000_000 {
                    Text("PS3:an är på Wi-Fi (bara 2,4 GHz). Med nätverkskabel brukar det gå flera gånger fortare.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.warm)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("NÄR KÖN ÄR KLAR")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 18)
                .padding(.bottom, 8)
            WhenDonePicker()

            Spacer(minLength: 16)
            HStack(spacing: 10) {
                Spacer()
                Button("Avbryt") { dismiss() }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                Button(chosen.count == 1 ? "Skicka \(chosen[0].title)" : "Skicka \(chosen.count) spel") {
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
        guard let snapshot = console.snapshot, ConsoleProfile(snapshot: snapshot).exploit == .hen else { return false }
        return chosen.flatMap(\.routes).contains { $0.kind == .ps2ISO && !PS2Classic.isClassic($0.remote) }
    }

    private func row(_ group: Entry) -> some View {
        let on = !excluded.contains(group.id)
        return Button {
            if on { excluded.insert(group.id) } else { excluded.remove(group.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17))
                    .foregroundStyle(on ? Theme.accent : Theme.tertiaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Text(group.routes.count == 1 ? group.routes[0].remote : "\(group.routes.count) filer till \((group.routes[0].remote as NSString).deletingLastPathComponent)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(Format.bytes(group.size))
                    .font(.system(size: 13))
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
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(warn ? Theme.hot : Theme.primaryText)
                .monospacedDigit()
        }
    }

    private var timeText: String {
        guard let speed = transfers.lastSpeed, speed.upload > 0 else {
            return "mät hastigheten under Överföringar"
        }
        return "ca \(Format.duration(Double(total) / speed.upload)) (\(Format.rate(speed.upload)))"
    }
}

/// "När kön är klar": the PS app's dark segmented control with the queue's three endings.
struct WhenDonePicker: View {
    @Environment(TransferStore.self) private var transfers

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TransferQueue.WhenDone.allCases, id: \.self) { choice in
                Button {
                    transfers.setWhenDone(choice)
                } label: {
                    Text(choice.label)
                        .font(.system(size: 13, weight: transfers.queue.whenDone == choice ? .bold : .semibold))
                        .foregroundStyle(transfers.queue.whenDone == choice ? Theme.primaryText : Theme.primaryText.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(transfers.queue.whenDone == choice ? Color.white.opacity(0.14) : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.black.opacity(0.45)))
    }
}
