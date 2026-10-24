import AppKit
import PS3Kit
import SwiftUI

/// One game up close, opened from its tile: the XMB background as a banner like the PS
/// Store's, title ID, size and version, and Spela / Montera / Ta bort.
struct GameDetailView: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(GamesStore.self) private var library
    let game: Game
    var scrolls = true

    enum Start { case play, mount }

    @State private var pendingStart: Start = .play
    @State private var confirmingSwitch = false
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            backButton
            if scrolls {
                ScrollView { content }.scrollIndicators(.hidden)
            } else {
                content
            }
        }
        .task(id: game.id) { await library.loadBackground(for: game) }
        .confirmationDialog(switchQuestion, isPresented: $confirmingSwitch, titleVisibility: .visible) {
            Button(pendingStart == .play ? "Avsluta och starta" : "Avsluta och montera") {
                if pendingStart == .play {
                    library.play(game, exitingRunning: true)
                } else {
                    library.mount(game, exitingRunning: true)
                }
            }
            Button("Avbryt", role: .cancel) {}
        }
        .confirmationDialog("Ta bort \(game.title)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Ta bort", role: .destructive) { library.delete(game) }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
    }

    private var backButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { library.selectedID = nil }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                Text("Spel")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            cards
            if let failure = library.failures[game.id] {
                NoteBanner(text: failure)
            }
            if game.isInstalled {
                NoteBanner(text: "Spelet är installerat i XMB:n. Det startas från sin ikon och tas bort i XMB:n (markera det, tryck △ och välj Ta bort).")
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            HeroBackdrop(image: library.backgrounds[game.id], url: nil, tint: GameArtwork.tint(for: game.platform))
            LinearGradient(colors: [Color.black.opacity(0.05), Color.black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
            headerContent.padding(24)
        }
        .frame(height: 290)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.cardStroke))
    }

    private var headerContent: some View {
        HStack(alignment: .bottom, spacing: 22) {
            GameArtwork(image: library.icons[game.id], game: game, size: CGSize(width: 160, height: 88))
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(game.title)
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Chip(text: game.platform.label)
                    if let state = console.playState(of: game) {
                        Chip(text: state.label, color: Theme.good)
                    }
                }
                Text(game.path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 10) { actions }
                    .padding(.top, 4)
            }
            Spacer()
        }
    }

    @ViewBuilder private var actions: some View {
        if let busy = library.busy, busy.id == game.id {
            Spinner()
            Text(busy.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
        } else {
            let state = console.playState(of: game)
            if state == .playing {
                Button("Avsluta spelet") { library.exitGame(game) }
                    .buttonStyle(PillButtonStyle())
            } else {
                Button("Spela") { start(.play) }
                    .buttonStyle(PillButtonStyle())
                    .disabled(library.busy != nil)
                if !game.isInstalled {
                    if state == .mounted {
                        Button("Avmontera") { library.unmount(game) }
                            .buttonStyle(PillButtonStyle(prominent: false))
                    } else {
                        Button("Montera") { start(.mount) }
                            .buttonStyle(PillButtonStyle(prominent: false))
                    }
                }
            }
            if !game.isInstalled, state != .playing {
                Button("Ta bort") { confirmingDelete = true }
                    .buttonStyle(PillButtonStyle(prominent: false))
            }
        }
    }

    /// "Varna och vänta" for starting: a running game is only quit after a question.
    private func start(_ kind: Start) {
        if console.snapshot?.isGameRunning == true {
            pendingStart = kind
            confirmingSwitch = true
        } else if kind == .play {
            library.play(game, exitingRunning: false)
        } else {
            library.mount(game, exitingRunning: false)
        }
    }

    private var switchQuestion: String {
        let running = console.snapshot?.mountedGameName ?? console.snapshot?.runningProcess ?? "Ett spel"
        return "\(running) körs. Avsluta det och \(pendingStart == .play ? "starta" : "montera") \(game.title)?"
    }

    private var deleteMessage: String {
        let freed = game.size.map { "\(Format.bytes($0)) frigörs på PS3:an. " } ?? ""
        return freed + "Det går inte att ångra, men har du spelet kvar på Macen kan du skicka det igen."
    }

    // MARK: Cards

    private var cards: some View {
        HStack(spacing: 14) {
            Card(icon: "number", title: "Title ID", chip: game.region?.label) {
                Text(game.titleID ?? "Okänt")
                    .font(.system(size: 26, weight: .light, design: .monospaced))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                Footnote(text: game.titleID == nil ? "Står inte i filnamnet, och webMAN har inte läst spelet än" : idFootnote)
            }
            Card(icon: "internaldrive", title: "Storlek", chip: game.isOnUSB ? "USB" : "Hårddisk") {
                BigValue(value: sizeParts.value, unit: sizeParts.unit)
                Spacer(minLength: 0)
                Footnote(text: sizeFootnote)
            }
            Card(icon: "shippingbox.fill", title: "Version", chip: game.updateVersion == nil ? nil : "Uppdaterat") {
                BigValue(value: game.updateVersion ?? game.version ?? "–")
                Spacer(minLength: 0)
                Footnote(text: versionFootnote)
            }
        }
        .frame(height: 170)
    }

    private var idFootnote: String {
        game.region.map { "\(game.platform.label)-utgåva för \($0.label)" } ?? "\(game.platform.label)-spel"
    }

    /// "9,64 GB" as a big number and its unit.
    private var sizeParts: (value: String, unit: String?) {
        guard let size = game.size else { return ("–", nil) }
        let parts = Format.bytes(size).split(whereSeparator: \.isWhitespace).map(String.init)
        if parts.count == 2 { return (parts[0], parts[1]) }
        return (Format.bytes(size), nil)
    }

    private var sizeFootnote: String {
        if !game.companions.isEmpty { return "\(game.companions.count + 1) filer" }
        if game.isInstalled { return "Installerat i /dev_hdd0/game" }
        return game.isFolder ? "Spelmapp; storleken räknas inte" : "En fil"
    }

    private var versionFootnote: String {
        if let update = game.updateVersion {
            return "Uppdatering \(update) installerad" + (game.version.map { ", skivan har \($0)" } ?? "")
        }
        if game.version != nil { return "Ingen uppdatering installerad" }
        return game.platform == .ps3 || game.platform == .psn ? "Versionen är inte läst än" : "Versioner finns bara för PS3-spel"
    }
}
