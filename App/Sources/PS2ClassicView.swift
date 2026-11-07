import AppKit
import PS3Kit
import SwiftUI
import UniformTypeIdentifiers

/// Making a PS2 game on the Mac into a PS2 Classic: the keys (fetched or imported, kept only on
/// this Mac), then the encryption in the background.
@MainActor
@Observable
final class PS2ClassicModel {
    enum Phase: Equatable {
        case ready, working, done(URL), failed(String)
    }

    let game: Game
    private let live: Bool
    private(set) var keys: PS2ClassicKeys?
    /// For the snapshot, which has no keys: whether to show them as there.
    private let fixtureKeys: Bool
    private(set) var fetching = false
    private(set) var keyMessage: String?
    private(set) var phase: Phase = .ready
    private(set) var read: Int64 = 0
    private(set) var total: Int64 = 0
    private var task: Task<Void, Error>?
    /// The PS2 Classic's size, read once: a raw .bin counts 2048 of every 2352 bytes.
    let size: Int64

    init(game: Game, live: Bool = true, fixtureKeys: Bool = false) {
        self.game = game
        self.live = live
        self.fixtureKeys = fixtureKeys
        keys = live ? PS2ClassicKeys.load() : nil
        let image = URL(fileURLWithPath: game.path)
        let imageSize = live ? ((try? PS2ClassicMaker.imageSize(of: image)) ?? FileRouter.fileSize(image)) : (game.size ?? 0)
        size = PS2ClassicMaker.encryptedSize(forImage: imageSize)
    }

    var keysReady: Bool { live ? keys?.isComplete == true : fixtureKeys }
    var image: URL { URL(fileURLWithPath: game.path) }
    var output: URL {
        image.deletingLastPathComponent().appendingPathComponent(PS2ClassicMaker.outputName(for: image, titleID: game.titleID))
    }
    var alreadyMade: Bool { live && FileManager.default.fileExists(atPath: output.path) }

    func fetchKeys() {
        fetching = true
        keyMessage = nil
        Task {
            do {
                keys = try await PS2ClassicKeys.fetch()
            } catch {
                keyMessage = error.localizedDescription
            }
            fetching = false
        }
    }

    func importKeys(_ urls: [URL]) {
        do {
            let read = try PS2ClassicKeys.read(urls)
            let merged = PS2ClassicKeys(values: (keys?.values ?? [:]).merging(read.values) { $1 })
            if !merged.wrong.isEmpty { throw PS3Error.invalidFile(merged.problem ?? "Wrong keys.") }
            try merged.save()
            keys = merged
            keyMessage = merged.problem
        } catch {
            keyMessage = error.localizedDescription
        }
    }

    func removeKeys() {
        try? PS2ClassicKeys.remove()
        keys = nil
    }

    func start() {
        guard keysReady, let keys, phase != .working else { return }
        phase = .working
        read = 0
        total = 0
        let image = self.image, output = self.output
        let work = Task.detached {
            _ = try PS2ClassicMaker.check(image)
            try PS2ClassicMaker.make(from: image, to: output, keys: keys) { read, total in
                Task { @MainActor in
                    self.read = read
                    self.total = total
                }
            }
        }
        task = work
        Task {
            switch await work.result {
            case .success:
                phase = .done(output)
            case .failure(let error):
                phase = error is CancellationError ? .ready : .failed(error.localizedDescription)
            }
            task = nil
        }
    }

    func cancel() {
        task?.cancel()
    }

    /// For the snapshot of a game halfway.
    func showWorking() {
        phase = .working
        read = 1_850_000_000
        total = game.size ?? 0
    }
}

/// "Convert to PS2 Classic": the game and the file it becomes, the keys, what the console needs,
/// and a white button that says what happens.
struct PS2ClassicView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppsStore.self) private var apps
    @Environment(TransferStore.self) private var transfers
    @Environment(GamesStore.self) private var library
    @State private var model: PS2ClassicModel
    @State private var importing = false
    private let live: Bool

    init(game: Game, live: Bool = true, fixtureKeys: Bool = false, working: Bool = false) {
        let model = PS2ClassicModel(game: game, live: live, fixtureKeys: fixtureKeys)
        if working { model.showWorking() }
        _model = State(initialValue: model)
        self.live = live
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Convert to PS2 Classic")
                .font(.ui(.display, weight: .light))
                .foregroundStyle(Theme.primaryText)
            Text("On HEN, PS2 games only start as PS2 Classics. PS3 Center encrypts a copy of the game into a .BIN.ENC next to it, as PS2 Classic GUI does on a PC. The original isn't changed.")
                .font(.ui(.body))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.bottom, 16)

            gameRow

            section("KEYS")
            keysSection

            section("ON THE PS3")
            consoleSection

            Spacer(minLength: 12)
            progress
            buttons.padding(.top, 12)
        }
        .padding(32)
        .frame(width: 580, height: 640, alignment: .topLeading)
        .background(Theme.base)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.importKeys(urls) }
        }
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.ui(.caption, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(Theme.secondaryText)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }

    private var gameRow: some View {
        HStack(spacing: 12) {
            Image(systemName: GameArtwork.symbol(for: .ps2))
                .font(.ui(.title2))
                .foregroundStyle(Theme.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.game.title)
                        .font(.ui(.headline, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    if let id = model.game.titleID { Chip(text: id) }
                }
                Text("→ \(model.output.lastPathComponent)")
                    .font(.ui(.caption, design: .monospaced))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(Format.bytes(model.size))
                .font(.ui(.body))
                .foregroundStyle(Theme.secondaryText)
                .monospacedDigit()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardStroke))
    }

    @ViewBuilder
    private var keysSection: some View {
        if model.keysReady {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.good)
                Text("The keys are on this Mac and check out.")
                    .font(.ui(.body))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Button("Delete") { model.removeKeys() }
                    .buttonStyle(PillButtonStyle(destructive: true))
                    .disabled(model.phase == .working)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("PS2 Classics are encrypted with Sony's keys, and PS3 Center doesn't ship them. Download Keys reads them from webMAN MOD's repo on GitHub, checks them against fingerprints and saves them only here on the Mac (~/.config/ps3center).")
                    .font(.ui(.footnote))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button {
                        model.fetchKeys()
                    } label: {
                        HStack(spacing: 7) {
                            if model.fetching { Spinner() } else { Image(systemName: "arrow.down.circle") }
                            Text(model.fetching ? "Downloading…" : "Download Keys")
                        }
                    }
                    // Outlined: a tint is for buttons inside a coloured banner, and the sheet's one
                    // white button is Convert.
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .disabled(model.fetching)
                    Button("Import…") { importing = true }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .help("ps2classic.c, the placeholder's .rifkey, or the .7z archives, e.g. from PS2 Classic GUI")
                }
                if let message = model.keyMessage {
                    Text(message)
                        .font(.ui(.footnote))
                        .foregroundStyle(Theme.hot)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var consoleSection: some View {
        let launcher = apps.statuses.first { $0.id == "ps2launcher" }
        let text: String
        let ok: Bool
        if let launcher, launcher.installed != nil {
            text = "PS2 Classics Launcher is installed. PS3HEN makes the license itself."
            ok = true
        } else if launcher != nil {
            text = "Install PS2 Classics Launcher under Apps → Browse. It starts PS2 Classics, and PS3HEN makes the license itself."
            ok = false
        } else {
            text = "The PS3 needs PS2 Classics Launcher (Apps → Browse). PS3HEN makes the license itself."
            ok = false
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: ok ? "checkmark.circle.fill" : "info.circle")
                    .foregroundStyle(ok ? Theme.good : Theme.warm)
                Text(text)
                    .font(.ui(.body))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("The Super Slim runs PS2 games in software. Most work; if a game stutters, PS2 CONFIG Database (Apps) may have a fix, which webMAN uses by itself.")
                .font(.ui(.footnote))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var progress: some View {
        switch model.phase {
        case .working:
            let total = max(model.total, max(model.game.size ?? 1, 1))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Encrypting…").font(.ui(.body, weight: .semibold)).foregroundStyle(Theme.primaryText)
                    Spacer()
                    Text("\(Int(Double(model.read) / Double(total) * 100)) %")
                        .font(.ui(.body, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .monospacedDigit()
                }
                PSProgressBar(fraction: Double(model.read) / Double(total))
            }
        case .done(let url):
            Text("Done: \(url.lastPathComponent) is next to the game. Send it to the PS3, and it goes to PS2ISO.")
                .font(.ui(.body, weight: .semibold))
                .foregroundStyle(Theme.good)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            Text(message)
                .font(.ui(.body))
                .foregroundStyle(Theme.hot)
                .fixedSize(horizontal: false, vertical: true)
        case .ready:
            if model.alreadyMade {
                Text("\(model.output.lastPathComponent) is already next to the game.")
                    .font(.ui(.footnote))
                    .foregroundStyle(Theme.warm)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Spacer()
            switch model.phase {
            case .working:
                Button("Cancel") { model.cancel() }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
            case .done(let url):
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(PillButtonStyle(prominent: false))
                Button("Send to PS3") {
                    if let routes = try? FileRouter.routes(for: [url], mirrorRoot: nil) { transfers.add(routes) }
                    Task { await library.loadMac() }
                    dismiss()
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
            case .ready, .failed:
                // Cancel beside the main button, as on every review sheet (DESIGN.md, Sheets).
                Button("Cancel") {
                    if case .failed = model.phase {} else if live { Task { await library.loadMac() } }
                    dismiss()
                }
                .buttonStyle(PillButtonStyle(prominent: false))
                .keyboardShortcut(.cancelAction)
                Button("Convert \(model.game.title)") { model.start() }
                    .buttonStyle(PillButtonStyle())
                    .disabled(!model.keysReady || model.alreadyMade)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
