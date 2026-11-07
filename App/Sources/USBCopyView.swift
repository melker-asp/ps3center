import AppKit
import Combine
import PS3Kit
import SwiftUI

/// The Mac's picked games on their way to a USB drive, as `ps3 usb prepare` does it.
struct USBCopyRequest: Identifiable {
    let id = UUID()
    let games: [Game]
}

/// Copies games to a FAT32 drive for the console: picks a drive, plans what goes where
/// (`USBDrive.plan`: ISOs over 4 GB split, game folders with such a file made into an ISO) and
/// copies in the background, keeping the Mac awake meanwhile.
@MainActor
@Observable
final class USBCopyModel {
    enum Phase: Equatable {
        case review, copying, done, failed(String)
    }

    let games: [Game]
    private let live: Bool
    private(set) var volumes: [USBDrive.Volume] = []
    var selectedID: String? {
        didSet { if oldValue != selectedID { replan() } }
    }
    private(set) var plan = USBDrive.Plan()
    private(set) var isPlanning = false
    private(set) var phase: Phase = .review
    private(set) var currentTitle: String?
    /// Bytes done of the whole plan, and the speed of the current file.
    private(set) var written: Int64 = 0
    private(set) var rate: Double = 0
    /// Titles finished, and titles that were already on the drive.
    private(set) var copied: [String] = []
    private(set) var alreadyThere: [String] = []
    private var finishedBytes: Int64 = 0
    private var copyTask: Task<Void, Error>?
    private var awake: KeepAwake?

    init(games: [Game], live: Bool = true) {
        self.games = games
        self.live = live
        if live {
            refreshVolumes()
        } else {
            volumes = Fixtures.usbVolumes
            selectedID = volumes.first?.id
            plan = Fixtures.usbPlan
        }
    }

    var selected: USBDrive.Volume? { volumes.first { $0.id == selectedID } }
    var canCopy: Bool {
        guard let selected, selected.isFAT32, !isPlanning, !plan.copies.isEmpty else { return false }
        return plan.total < selected.free
    }

    struct Entry: Identifiable {
        let title: String
        let copies: [USBDrive.Copy]
        let id: String
    }

    /// The games in the plan, in order, with all their files (a .cue and its .bin are one game).
    var entries: [Entry] {
        var order: [String] = []
        var byGame: [String: [USBDrive.Copy]] = [:]
        for copy in plan.copies {
            if byGame[copy.game.id] == nil { order.append(copy.game.id) }
            byGame[copy.game.id, default: []].append(copy)
        }
        return order.compactMap { id in byGame[id].map { Entry(title: $0[0].game.title, copies: $0, id: id) } }
    }

    /// Reads the plugged-in drives again, after one is mounted or ejected.
    func refreshVolumes() {
        guard live else { return }
        volumes = USBDrive.volumes()
        if selected == nil {
            selectedID = volumes.first(where: \.isFAT32)?.id ?? volumes.first?.id
        }
    }

    private func replan() {
        guard live else { return }
        guard let volume = selected, volume.isFAT32 else {
            plan = USBDrive.Plan()
            // A plan still being made for the drive picked before is dropped when it is done.
            isPlanning = false
            return
        }
        isPlanning = true
        let games = self.games
        Task { [weak self] in
            // Planning reads every game folder, so it stays off the main thread.
            let plan = await Task.detached { USBDrive.plan(games, on: volume.url) }.value
            guard let self, self.selectedID == volume.id else { return }
            self.plan = plan
            self.isPlanning = false
        }
    }

    func start() {
        guard canCopy, phase != .copying else { return }
        phase = .copying
        written = 0
        finishedBytes = 0
        copied = []
        alreadyThere = []
        awake = KeepAwake(reason: "Copying games to a USB drive")
        let copies = plan.copies
        // Off the main thread: the copy reads and writes for minutes. The store is MainActor
        // (and so Sendable); events hop back to it.
        let task = Task.detached {
            try await USBDrive.copy(copies) { event in
                Task { @MainActor in self.handle(event) }
            }
        }
        copyTask = task
        Task { [weak self] in
            let result = await task.result
            guard let self else { return }
            self.awake = nil
            self.copyTask = nil
            self.currentTitle = nil
            switch result {
            case .success:
                self.phase = .done
            case .failure(let error):
                self.phase = error is CancellationError ? .review : .failed(error.localizedDescription)
            }
            self.volumes = USBDrive.volumes()
            // What made it to the drive no longer needs room, so Try Again sees the space it has.
            if self.phase != .done { self.replan() }
        }
    }

    func cancel() {
        copyTask?.cancel()
    }

    func eject() async throws {
        guard let volume = selected else { return }
        try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
    }

    private func handle(_ event: TransferEvent) {
        switch event {
        case .started(let route, _):
            currentTitle = route.title
        case .progress(_, let sent, _, let bytesPerSecond):
            written = finishedBytes + sent
            rate = bytesPerSecond
        case .finished(let route, _):
            finishedBytes += route.size
            written = finishedBytes
            if let title = route.title, !copied.contains(title) { copied.append(title) }
        case .skipped(let route, _):
            // Already on the drive: the plan's total leaves it out, so it adds no bytes.
            if let title = route.title, !alreadyThere.contains(title) { alreadyThere.append(title) }
        default:
            break
        }
    }

    /// For the snapshot of a copy under way.
    func showCopying() {
        phase = .copying
        currentTitle = plan.copies.first?.game.title
        written = 9_870_000_000
        rate = 31_400_000
        copied = []
    }
}

/// "Copy to a USB Drive": the drives as pills, the games with where they go and what
/// happens to them (split, made into an ISO), the drive's free space before and after, and a
/// white button that says what happens.
struct USBCopyView: View {
    /// A drive was mounted or unmounted, delivered on the main queue. Computed, so there is no
    /// shared stored publisher to make Sendable.
    private static var volumeChanges: AnyPublisher<Notification, Never> {
        let center = NSWorkspace.shared.notificationCenter
        return center.publisher(for: NSWorkspace.didMountNotification)
            .merge(with: center.publisher(for: NSWorkspace.didUnmountNotification))
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    @Environment(\.dismiss) private var dismiss
    @State private var model: USBCopyModel
    @State private var ejectError: String?
    /// False when rendered for a snapshot: the drives and plan in Fixtures, no scroll view.
    private let live: Bool
    /// Called when the copy is done, so the grid lets go of the picked games.
    private let onDone: () -> Void

    init(games: [Game], live: Bool = true, copying: Bool = false, onDone: @escaping () -> Void = {}) {
        let model = USBCopyModel(games: games, live: live)
        if copying { model.showCopying() }
        _model = State(initialValue: model)
        self.live = live
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Copy to a USB Drive")
                .font(.ui(.display, weight: .light))
                .foregroundStyle(Theme.primaryText)
            Text("Fastest for many games. The PS3 reads USB drives in FAT32, which can't hold files over 4 GB. Larger ISOs are split into .iso.0, .iso.1 …, and a game folder with a file that large becomes an ISO. webMAN starts them straight from the drive.")
                .font(.ui(.body))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.bottom, 16)

            drivePicker
                .padding(.bottom, 12)

            if let volume = model.selected, !volume.isFAT32 {
                Text("\(volume.name) is \(volume.format). The PS3 only reads FAT32: format the drive as “MS-DOS (FAT)” in Disk Utility (that erases everything on it).")
                    .font(.ui(.footnote))
                    .foregroundStyle(Theme.warm)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
            }

            if live {
                ScrollView { rows }.frame(maxHeight: 300)
            } else {
                rows.frame(maxHeight: 300, alignment: .top).clipped()
            }

            Divider().overlay(Theme.cardStroke).padding(.vertical, 14)

            facts

            Spacer(minLength: 16)
            buttons
        }
        .padding(32)
        .frame(width: 580, height: 720, alignment: .topLeading)
        .background(Theme.base)
        // A publisher, not `for await` over notifications(named:): an older SDK's Notification
        // is not Sendable, so the async loop does not compile under strict concurrency there.
        .onReceive(Self.volumeChanges) { _ in
            if live { model.refreshVolumes() }
        }
    }

    private var drivePicker: some View {
        Group {
            if model.volumes.isEmpty {
                Text("No USB drive is connected. Plug in a drive formatted as “MS-DOS (FAT)”.")
                    .font(.ui(.body))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                HStack(spacing: 2) {
                    ForEach(model.volumes) { volume in
                        let chosen = model.selectedID == volume.id
                        Button {
                            model.selectedID = volume.id
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "externaldrive.fill")
                                    .foregroundStyle(volume.isFAT32 ? Theme.accent : Theme.tertiaryText)
                                Text(volume.name)
                                Text("\(volume.isFAT32 ? "FAT32" : volume.format) · \(Format.bytes(volume.free)) free")
                                    .font(.ui(.footnote, weight: .semibold))
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                            .font(.ui(.callout, weight: chosen ? .bold : .semibold))
                            .foregroundStyle(chosen ? Theme.primaryText : Theme.primaryText.opacity(0.7))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(chosen ? Color.white.opacity(0.14) : .clear))
                            .contentShape(Capsule())
                            .fixedSize()
                        }
                        .buttonStyle(.plain)
                        .disabled(model.phase == .copying)
                    }
                }
                .padding(4)
                .background(Capsule().fill(Color.black.opacity(0.45)))
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 2) {
            if model.isPlanning {
                HStack(spacing: 10) {
                    Spinner()
                    Text("Reading the games…").font(.ui(.body)).foregroundStyle(Theme.secondaryText)
                }
                .padding(10)
            }
            ForEach(model.entries) { entry in row(entry.title, entry.copies) }
            ForEach(Array(model.plan.skipped.enumerated()), id: \.offset) { _, skipped in skippedRow(skipped.game, skipped.reason) }
        }
    }

    private func row(_ title: String, _ copies: [USBDrive.Copy]) -> some View {
        let first = copies[0]
        let root = model.selected?.url.path ?? ""
        let place = String(first.destination.path.dropFirst(root.count + 1))
        let onDrive = model.alreadyThere.contains(title) || copies.allSatisfy(\.isOnDrive)
        let done = model.copied.contains(title) || onDrive
        return HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : GameArtwork.symbol(for: first.game.platform))
                .font(.ui(.title3))
                .foregroundStyle(done ? Theme.good : Theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.ui(.callout, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    if first.kind == .isoFromFolder { Chip(text: "Becomes an ISO", color: Theme.warm) }
                    if first.parts > 1 { Chip(text: "\(first.parts) parts") }
                    if onDrive { Chip(text: "Already there", color: Theme.good) }
                }
                Text(copies.count == 1 ? place : "\(copies.count) files to \((place as NSString).deletingLastPathComponent)")
                    .font(.ui(.caption, design: .monospaced))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(Format.bytes(copies.reduce(0) { $0 + $1.size }))
                .font(.ui(.body))
                .foregroundStyle(Theme.secondaryText)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func skippedRow(_ game: Game, _ reason: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "minus.circle")
                .font(.ui(.title3))
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(game.title)
                    .font(.ui(.callout, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Text(reason)
                    .font(.ui(.caption))
                    .foregroundStyle(Theme.warm)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text("Skipped")
                .font(.ui(.footnote))
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var facts: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.phase {
            case .copying:
                let total = max(model.plan.total, 1)
                HStack {
                    Text(model.currentTitle.map { "Copying \($0)" } ?? "Copying…")
                        .font(.ui(.body, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(Double(model.written) / Double(total) * 100)) %")
                        .font(.ui(.body, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .monospacedDigit()
                }
                PSProgressBar(fraction: Double(model.written) / Double(total))
                Text(progressText(total: total))
                    .font(.ui(.footnote))
                    .foregroundStyle(Theme.secondaryText)
                    .monospacedDigit()
            case .done:
                Text(model.alreadyThere.isEmpty ? "Done. Eject the drive, plug it into the PS3 and refresh the game list."
                     : "Done (\(model.alreadyThere.count) were already on the drive). Eject the drive, plug it into the PS3 and refresh the game list.")
                    .font(.ui(.body, weight: .semibold))
                    .foregroundStyle(Theme.good)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed(let message):
                Text("The copy stopped: \(message) What was finished stays; what wasn't is removed.")
                    .font(.ui(.body))
                    .foregroundStyle(Theme.hot)
                    .fixedSize(horizontal: false, vertical: true)
            case .review:
                fact("To copy", Format.bytes(model.plan.total))
                if let volume = model.selected {
                    let after = volume.free - model.plan.total
                    fact("Free on “\(volume.name)”", "\(Format.bytes(volume.free)) → \(Format.bytes(max(after, 0)))", warn: after < 0)
                }
            }
            if let ejectError {
                Text(ejectError).font(.ui(.footnote)).foregroundStyle(Theme.hot)
            }
            if model.phase == .copying, KeepAwake.isOnBattery {
                Text(KeepAwake.batteryTip)
                    .font(.ui(.footnote))
                    .foregroundStyle(Theme.warm)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func progressText(total: Int64) -> String {
        let left = model.rate > 0 ? " · \(Format.estimate(Double(total - model.written) / model.rate)) left" : ""
        return "\(Format.bytes(model.written)) of \(Format.bytes(total)) · \(Format.rate(model.rate))\(left)"
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Spacer()
            switch model.phase {
            case .copying:
                Button("Stop Copying") { model.cancel() }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
            case .done:
                if let volume = model.selected {
                    Button("Eject “\(volume.name)”") {
                        Task {
                            do {
                                try await model.eject()
                                onDone()
                                dismiss()
                            } catch {
                                ejectError = "“\(volume.name)” couldn't be ejected: \(error.localizedDescription)"
                            }
                        }
                    }
                    .buttonStyle(PillButtonStyle(prominent: false))
                }
                Button("Done") {
                    onDone()
                    dismiss()
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
            case .review, .failed:
                Button("Cancel") { dismiss() }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                Button(primaryTitle) { model.start() }
                    .buttonStyle(PillButtonStyle())
                    .disabled(!model.canCopy)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var primaryTitle: String {
        let count = model.entries.count
        // The drive is quoted and called a drive, so one named "PS3" is never read as the console.
        let target = model.selected.map { " to “\($0.name)”" } ?? ""
        if case .failed = model.phase { return "Try Again" }
        return count == 1 ? "Copy \(model.entries[0].title)\(target)" : "Copy \(count) Games\(target)"
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
}
