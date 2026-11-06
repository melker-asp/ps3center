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

    init(game: Game, live: Bool = true, fixtureKeys: Bool = false) {
        self.game = game
        self.live = live
        self.fixtureKeys = fixtureKeys
        keys = live ? PS2ClassicKeys.load() : nil
    }

    var keysReady: Bool { live ? keys?.isComplete == true : fixtureKeys }
    var image: URL { URL(fileURLWithPath: game.path) }
    var output: URL {
        image.deletingLastPathComponent().appendingPathComponent(PS2ClassicMaker.outputName(for: image, titleID: game.titleID))
    }
    var size: Int64 {
        let imageSize = live ? FileRouter.fileSize((try? PS2ClassicMaker.dataFile(for: image)) ?? image) : (game.size ?? 0)
        return PS2ClassicMaker.encryptedSize(forImage: imageSize)
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
            if !merged.wrong.isEmpty { throw PS3Error.invalidFile(merged.problem ?? "Fel nycklar.") }
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

/// "Gör om till PS2 Classic": the game and the file it becomes, the keys, what the console needs,
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
            Text("Gör om till PS2 Classic")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.primaryText)
            Text("På HEN startar PS2-spel bara som PS2 Classics. PS3 Center krypterar en kopia av spelet till en .BIN.ENC bredvid det, som PS2 Classic GUI gör på en PC. Originalet ändras inte.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.bottom, 16)

            gameRow

            section("NYCKLAR")
            keysSection

            section("PÅ PS3:AN")
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
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(Theme.secondaryText)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }

    private var gameRow: some View {
        HStack(spacing: 12) {
            Image(systemName: GameArtwork.symbol(for: .ps2))
                .font(.system(size: 20))
                .foregroundStyle(Theme.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.game.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    if let id = model.game.titleID { Chip(text: id) }
                }
                Text("→ \(model.output.lastPathComponent)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(Format.bytes(model.size))
                .font(.system(size: 13))
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
                Text("Nycklarna finns på den här Macen och stämmer.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Button("Ta bort") { model.removeKeys() }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .disabled(model.phase == .working)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("PS2 Classics krypteras med Sonys nycklar, och PS3 Center har dem inte med sig. Hämta läser dem ur webMAN MOD:s repo på GitHub, kontrollerar dem mot fingeravtryck och sparar dem bara här på Macen (~/.config/ps3center).")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button {
                        model.fetchKeys()
                    } label: {
                        HStack(spacing: 7) {
                            if model.fetching { Spinner() } else { Image(systemName: "arrow.down.circle") }
                            Text(model.fetching ? "Hämtar…" : "Hämta nycklarna")
                        }
                    }
                    .buttonStyle(PillButtonStyle(tint: Theme.accent))
                    .disabled(model.fetching)
                    Button("Importera…") { importing = true }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .help("ps2classic.c, platshållarens .rifkey eller .7z-arkiven, t.ex. från PS2 Classic GUI")
                }
                if let message = model.keyMessage {
                    Text(message)
                        .font(.system(size: 12))
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
            text = "PS2 Classics Launcher är installerad. PS3HEN gör licensen själv."
            ok = true
        } else if launcher != nil {
            text = "Installera PS2 Classics Launcher under Appar → Hämta. Den startar PS2 Classics, och PS3HEN gör licensen själv."
            ok = false
        } else {
            text = "PS3:an behöver PS2 Classics Launcher (Appar → Hämta). PS3HEN gör licensen själv."
            ok = false
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: ok ? "checkmark.circle.fill" : "info.circle")
                    .foregroundStyle(ok ? Theme.good : Theme.warm)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Super Slim kör PS2-spel i mjukvara. De flesta fungerar; hackar ett spel kan PS2 CONFIG Database (Appar) ha en rättning, som webMAN använder av sig själv.")
                .font(.system(size: 12))
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
                    Text("Krypterar…").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primaryText)
                    Spacer()
                    Text("\(Int(Double(model.read) / Double(total) * 100)) %")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .monospacedDigit()
                }
                PSProgressBar(fraction: Double(model.read) / Double(total))
            }
        case .done(let url):
            Text("Klart: \(url.lastPathComponent) ligger bredvid spelet. Skicka den till PS3:an, så hamnar den i PS2ISO.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.good)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.hot)
                .fixedSize(horizontal: false, vertical: true)
        case .ready:
            if model.alreadyMade {
                Text("\(model.output.lastPathComponent) finns redan bredvid spelet.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.warm)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Spacer()
            switch model.phase {
            case .working:
                Button("Avbryt") { model.cancel() }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
            case .done(let url):
                Button("Visa i Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(PillButtonStyle(prominent: false))
                Button("Skicka till PS3:an") {
                    if let routes = try? FileRouter.routes(for: [url], mirrorRoot: nil) { transfers.add(routes) }
                    Task { await library.loadMac() }
                    dismiss()
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
            case .ready, .failed:
                Button("Stäng") {
                    if case .failed = model.phase {} else if live { Task { await library.loadMac() } }
                    dismiss()
                }
                .buttonStyle(PillButtonStyle(prominent: false))
                .keyboardShortcut(.cancelAction)
                Button("Gör om \(model.game.title)") { model.start() }
                    .buttonStyle(PillButtonStyle())
                    .disabled(!model.keysReady || model.alreadyMade)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
