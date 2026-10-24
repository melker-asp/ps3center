import AppKit
import PS3Kit
import SwiftUI

/// The Spel tab: the console's games as a grid of XMB icons like the PS app's library, with a
/// pill per platform and a search field. A click opens the game's page.
struct GamesView: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(GamesStore.self) private var library
    /// Box art (Fodral) or XMB icons (Ikoner); remembered between launches.
    @AppStorage("gamesShowCovers") private var showCovers = true
    /// False when rendered for a snapshot: ImageRenderer cannot draw scroll views or text fields.
    var scrolls = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let selected = library.selected {
                GameDetailView(game: selected, scrolls: scrolls)
                    .transition(.opacity)
            } else {
                toolbar
                content
            }
        }
        .task(id: console.host) {
            guard let host = console.host, library.phase == .idle || library.games.isEmpty else { return }
            await library.load(host: host)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(GamesStore.Filter.allCases) { item in
                    let count = library.count(item)
                    if item == .all || count > 0 {
                        Button {
                            library.filter = item
                        } label: {
                            HStack(spacing: 7) {
                                Text(item.title)
                                Text("\(count)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                            .font(.system(size: 14, weight: library.filter == item ? .bold : .semibold))
                            .foregroundStyle(library.filter == item ? Theme.primaryText : Theme.primaryText.opacity(0.7))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(library.filter == item ? Color.white.opacity(0.14) : .clear))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(4)
            .background(Capsule().fill(Color.black.opacity(0.45)))

            SearchField(text: Bindable(library).search, interactive: scrolls)

            Button {
                guard let host = console.host else { return }
                Task { await library.load(host: host, refresh: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(CircleIconButtonStyle())
            .help("Läs om spelen")
            .disabled(library.isLoading)

            HStack(spacing: 2) {
                modeButton(covers: true, symbol: "rectangle.portrait.fill", help: "Fodral")
                modeButton(covers: false, symbol: "rectangle.fill", help: "XMB-ikoner")
            }
            .padding(3)
            .background(Capsule().fill(Color.black.opacity(0.45)))

            Spacer()

            updatesButton

            if let checked = library.lastChecked {
                Text("Läst \(checked.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }

    private func modeButton(covers: Bool, symbol: String, help: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showCovers = covers }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(showCovers == covers ? Theme.primaryText : Theme.tertiaryText)
                .frame(width: 34, height: 28)
                .background(Capsule().fill(showCovers == covers ? Color.white.opacity(0.14) : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// "Sök uppdateringar" until Sony has been asked; then how many games have newer patches.
    @ViewBuilder private var updatesButton: some View {
        if library.isCheckingUpdates {
            HStack(spacing: 8) {
                Spinner()
                Text("Frågar Sony…").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            }
        } else {
            Button {
                Task { await library.checkUpdates(refresh: library.updatesChecked != nil) }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.down.circle")
                    Text(library.updatesChecked == nil ? "Sök uppdateringar" : library.updateCount == 0 ? "Inga uppdateringar" : "Uppdateringar")
                    if library.updateCount > 0 { CountBadge(count: library.updateCount) }
                }
            }
            .buttonStyle(PillButtonStyle(prominent: false))
            .help("Officiella spelpatchar från Sonys uppdateringsserver. Systemprogramvaran rörs aldrig.")
        }
    }

    @ViewBuilder private var content: some View {
        let firstLoad = library.games.isEmpty && (library.phase == .idle || library.phase == .loading)
        if firstLoad {
            VStack(spacing: 12) {
                Spinner()
                Text("Läser spelen på PS3:an…")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if case .failed(let message) = library.phase, library.games.isEmpty {
            VStack(spacing: 12) {
                Text("Kunde inte läsa spelen").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.primaryText)
                Text(message).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if library.games.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "opticaldisc").font(.system(size: 34, weight: .light)).foregroundStyle(Theme.secondaryText)
                Text("Inga spel på PS3:an än").font(.system(size: 20, weight: .light)).foregroundStyle(Theme.primaryText)
                Text("PS3 Center letar i PS3ISO, GAMES, PS2ISO, PSXISO, PSPISO, BDISO och DVDISO på hårddisken och USB-diskar, och bland installerade spel. Skicka spel med `ps3 send`.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if scrolls {
            ScrollView { grid }.scrollIndicators(.hidden)
        } else {
            grid
        }
    }

    private var grid: some View {
        let visible = library.visible
        return LazyVStack(alignment: .leading, spacing: 4) {
            if visible.isEmpty {
                Text("Inget spel matchar ”\(library.search)”.")
                    .font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
                    .padding(14)
            }
            ForEach(Game.Platform.allCases, id: \.self) { platform in
                let rows = visible.filter { $0.platform == platform }
                if !rows.isEmpty {
                    SectionHeader(title: platform.label, count: rows.count)
                    LazyVGrid(columns: [GridItem(showCovers ? .adaptive(minimum: 160, maximum: 210) : .adaptive(minimum: 200, maximum: 280), spacing: 16)],
                              alignment: .leading, spacing: 16) {
                        ForEach(rows) { GameTile(game: $0, showCover: showCovers) }
                    }
                    .padding(.horizontal, 14)
                }
            }
        }
        .padding(.bottom, 12)
    }
}

/// Whether a game is on the disc icon right now.
enum GamePlayState {
    case playing, mounted

    var label: String { self == .playing ? "Spelar" : "Monterad" }
}

extension ConsoleStore {
    /// Playing while the game runs, mounted while it sits on /dev_bdvd, else nil.
    func playState(of game: Game) -> GamePlayState? {
        guard let snapshot, snapshot.mountedGamePath == game.path else { return nil }
        return snapshot.isGameRunning ? .playing : .mounted
    }
}

/// A tile in the grid: the box art or XMB icon large, the title, platform and region, and a
/// green "Spelar" while it runs.
struct GameTile: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(GamesStore.self) private var library
    let game: Game
    var showCover = true
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear
                .aspectRatio(showCover ? 0.82 : 320.0 / 176.0, contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        if showCover {
                            GameCover(cover: library.covers[game.id], icon: library.icons[game.id], game: game, size: proxy.size)
                        } else {
                            GameArtwork(image: library.icons[game.id], game: game, size: proxy.size)
                        }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if game.isOnUSB { Chip(text: "USB").padding(8) }
                }
            Text(game.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(2, reservesSpace: true)
            HStack(spacing: 6) {
                Chip(text: game.platform.label)
                if let region = game.region { Chip(text: region.label) }
                Spacer(minLength: 4)
                if let state = console.playState(of: game) {
                    Chip(text: state.label, color: Theme.good)
                } else if let latest = library.patches[game.id]?.last {
                    Chip(text: "↑ \(latest.version)", color: Theme.accent)
                } else if let size = game.size {
                    Text(Format.bytes(size))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(hovering ? 0.08 : 0.045)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardStroke))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { library.selectedID = game.id } }
        .onHover { hovering = $0 }
        .help(game.title)
    }
}

/// The game's XMB icon, or a tile in the platform's colour with the title while there is
/// none (PS1, PS2 and PSP images, and ISOs webMAN has not read yet).
struct GameArtwork: View {
    let image: NSImage?
    let game: Game
    var size = CGSize(width: 64, height: 36)

    private var scale: CGFloat { size.height / 36 }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: Self.symbol(for: game.platform))
                        .font(.system(size: min(size.width, size.height) * 0.38, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.28))
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: min(8 * scale, 12), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: min(8 * scale, 12), style: .continuous).strokeBorder(Color.white.opacity(0.08)))
    }

    private var tint: Color { Self.tint(for: game.platform) }

    static func tint(for platform: Game.Platform) -> Color {
        switch platform {
        case .ps3: return Theme.psBlue
        case .psn: return Theme.starlightBlue
        case .ps2: return Theme.galacticPurple
        case .ps1: return Color(white: 0.42)
        case .psp: return Theme.novaPink
        case .bluRay, .dvd: return Theme.cosmicRed
        }
    }

    static func symbol(for platform: Game.Platform) -> String {
        switch platform {
        case .ps3, .psn: return "playstation.logo"
        case .ps2: return "opticaldisc.fill"
        case .ps1: return "opticaldisc"
        case .psp: return "gamecontroller.fill"
        case .bluRay, .dvd: return "film.fill"
        }
    }
}

/// A search field in the PS app's dark capsule. `interactive` false draws the placeholder
/// as text, since ImageRenderer cannot draw an AppKit text field.
struct SearchField: View {
    @Binding var text: String
    var interactive = true

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.tertiaryText)
            if interactive {
                TextField("Sök spel eller title ID", text: $text)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.primaryText)
            } else {
                Text(text.isEmpty ? "Sök spel eller title ID" : text)
                    .foregroundStyle(Theme.tertiaryText)
                Spacer(minLength: 0)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(width: 240)
        .background(Capsule().fill(Color.black.opacity(0.45)))
    }
}

/// Box art for the Fodral grid: the cover fitted on a dark plate, else the XMB icon, else the
/// platform's placeholder.
struct GameCover: View {
    let cover: NSImage?
    let icon: NSImage?
    let game: Game
    let size: CGSize

    var body: some View {
        Group {
            if let picture = cover ?? icon {
                ZStack {
                    Color.black.opacity(0.35)
                    Image(nsImage: picture)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(cover == nil ? 10 : 0)
                }
            } else {
                GameArtwork(image: nil, game: game, size: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
    }
}
