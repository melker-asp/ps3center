import AppKit
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
        awake = KeepAwake(reason: "Kopierar spel till en USB-disk")
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
            finishedBytes += route.size
            written = finishedBytes
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

/// "Kopiera till en USB-disk": the drives as pills, the games with where they go and what
/// happens to them (split, made into an ISO), the drive's free space before and after, and a
/// white button that says what happens.
struct USBCopyView: View {
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
            Text("Kopiera till en USB-disk")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.primaryText)
            Text("Snabbast för många spel. PS3:an läser USB-diskar i FAT32, som inte rymmer filer över 4 GB. Större ISO:er delas därför i .iso.0, .iso.1 …, och en spelmapp med en så stor fil blir en ISO. webMAN startar dem direkt från disken.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.bottom, 16)

            drivePicker
                .padding(.bottom, 12)

            if let volume = model.selected, !volume.isFAT32 {
                Text("\(volume.name) är \(volume.format). PS3:an läser bara FAT32: formatera disken som ”MS-DOS (FAT)” i Skivverktyg (det raderar allt på den).")
                    .font(.system(size: 12))
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
        .task {
            guard live else { return }
            for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didMountNotification) {
                model.refreshVolumes()
            }
        }
        .task {
            guard live else { return }
            for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didUnmountNotification) {
                model.refreshVolumes()
            }
        }
    }

    private var drivePicker: some View {
        Group {
            if model.volumes.isEmpty {
                Text("Ingen USB-disk är ansluten. Sätt i en disk som är formaterad som ”MS-DOS (FAT)”.")
                    .font(.system(size: 13))
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
                                Text("\(volume.isFAT32 ? "FAT32" : volume.format) · \(Format.bytes(volume.free)) ledigt")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                            .font(.system(size: 14, weight: chosen ? .bold : .semibold))
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
                    Text("Läser spelen…").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
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
        let done = model.copied.contains(title) || model.alreadyThere.contains(title)
        return HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : GameArtwork.symbol(for: first.game.platform))
                .font(.system(size: 17))
                .foregroundStyle(done ? Theme.good : Theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    if first.kind == .isoFromFolder { Chip(text: "BLIR EN ISO", color: Theme.warm) }
                    if first.parts > 1 { Chip(text: "\(first.parts) DELAR") }
                    if model.alreadyThere.contains(title) { Chip(text: "FINNS REDAN", color: Theme.good) }
                }
                Text(copies.count == 1 ? place : "\(copies.count) filer till \((place as NSString).deletingLastPathComponent)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(Format.bytes(copies.reduce(0) { $0 + $1.size }))
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func skippedRow(_ game: Game, _ reason: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "minus.circle")
                .font(.system(size: 17))
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(game.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Text(reason)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.warm)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text("Hoppar över")
                .font(.system(size: 12))
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
                    Text(model.currentTitle.map { "Kopierar \($0)" } ?? "Kopierar…")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(Double(model.written) / Double(total) * 100)) %")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .monospacedDigit()
                }
                PSProgressBar(fraction: Double(model.written) / Double(total))
                Text(progressText(total: total))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .monospacedDigit()
            case .done:
                Text(model.alreadyThere.isEmpty ? "Klart. Mata ut disken, sätt den i PS3:an och uppdatera spellistan."
                     : "Klart (\(model.alreadyThere.count) fanns redan på disken). Mata ut disken, sätt den i PS3:an och uppdatera spellistan.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.good)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed(let message):
                Text("Kopieringen stannade: \(message) Det som hann bli klart ligger kvar; det som inte blev klart är borttaget.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.hot)
                    .fixedSize(horizontal: false, vertical: true)
            case .review:
                fact("Att kopiera", Format.bytes(model.plan.total))
                if let volume = model.selected {
                    let after = volume.free - model.plan.total
                    fact("Ledigt på \(volume.name)", "\(Format.bytes(volume.free)) → \(Format.bytes(max(after, 0)))", warn: after < 0)
                }
            }
            if let ejectError {
                Text(ejectError).font(.system(size: 12)).foregroundStyle(Theme.hot)
            }
            if model.phase == .copying, KeepAwake.isOnBattery {
                Text(KeepAwake.batteryTip)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.warm)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func progressText(total: Int64) -> String {
        let left = model.rate > 0 ? " · \(Format.duration(Double(total - model.written) / model.rate)) kvar" : ""
        return "\(Format.bytes(model.written)) av \(Format.bytes(total)) · \(Format.rate(model.rate))\(left)"
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Spacer()
            switch model.phase {
            case .copying:
                Button("Avbryt kopieringen") { model.cancel() }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
            case .done:
                if let volume = model.selected {
                    Button("Mata ut \(volume.name)") {
                        Task {
                            do {
                                try await model.eject()
                                onDone()
                                dismiss()
                            } catch {
                                ejectError = "\(volume.name) gick inte att mata ut: \(error.localizedDescription)"
                            }
                        }
                    }
                    .buttonStyle(PillButtonStyle(prominent: false))
                }
                Button("Klar") {
                    onDone()
                    dismiss()
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
            case .review, .failed:
                Button("Avbryt") { dismiss() }
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
        let target = model.selected.map { " till \($0.name)" } ?? ""
        if case .failed = model.phase { return "Försök igen" }
        return count == 1 ? "Kopiera \(model.entries[0].title)\(target)" : "Kopiera \(count) spel\(target)"
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
}
