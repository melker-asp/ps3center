import AppKit
import PS3Kit
import SwiftUI

/// The Games tab: the console's games (or the Mac's game folders) as a grid of box art or XMB
/// icons like the PS app's library, with a pill per platform and a search field. A click opens
/// a console game's page, or picks a Mac game for sending.
struct GamesView: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(GamesStore.self) private var library
    @Environment(NetServerStore.self) private var netServer
    /// Box art (Covers) or XMB icons (Icons); remembered between launches.
    @AppStorage("gamesShowCovers") private var showCovers = true
    /// Name (per platform, as the console lists them), Size or Recently Added.
    @AppStorage("gamesOrder") private var order: GameOrder = .name
    /// False when rendered for a snapshot: ImageRenderer cannot draw scroll views or text fields.
    var scrolls = true
    @State private var showsFolders = false
    @State private var showsServer = false
    @State private var review: SendReview?
    @State private var usbCopy: USBCopyRequest?

    private var onMac: Bool { library.source == .mac }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let selected = library.selected, !onMac {
                GameDetailView(game: selected, scrolls: scrolls)
                    .transition(.opacity)
            } else {
                toolbar
                if onMac, let failure = library.macFailure {
                    NoteBanner(text: failure)
                }
                content
                if onMac, !library.selection.isEmpty {
                    selectionBar
                }
            }
        }
        .task(id: console.host) {
            guard let host = console.host, library.phase == .idle || library.games.isEmpty else { return }
            await library.load(host: host)
        }
        .task(id: library.source) {
            guard onMac, !library.macLoaded, !library.isLoadingMac else { return }
            await library.loadMac()
        }
        .sheet(isPresented: $showsFolders) {
            FoldersView {
                netServer.restart()
                Task { await library.loadMac() }
            }
        }
        .sheet(item: $review) { SendReviewView(review: $0) }
        .sheet(item: $usbCopy) { request in
            USBCopyView(games: request.games) { library.selection.removeAll() }
        }
        .sheet(isPresented: $showsServer) { NetServerView() }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                sourceButton(.console, title: "PS3")
                sourceButton(.mac, title: "Mac")
            }
            .padding(4)
            .background(Capsule().fill(Color.black.opacity(0.45)))
            .fixedSize()

            HStack(spacing: 2) {
                ForEach(GamesStore.Filter.allCases) { item in
                    let count = library.count(item)
                    if item == .all || count > 0 {
                        Button {
                            library.filter = item
                        } label: {
                            HStack(spacing: 6) {
                                Text(item.title)
                                Text("\(count)")
                                    .font(.ui(.footnote, weight: .semibold))
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                            .font(.ui(.callout, weight: library.filter == item ? .bold : .semibold))
                            .foregroundStyle(library.filter == item ? Theme.primaryText : Theme.primaryText.opacity(0.7))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(library.filter == item ? Color.white.opacity(0.14) : .clear))
                            .contentShape(Capsule())
                            .fixedSize()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(4)
            .background(Capsule().fill(Color.black.opacity(0.45)))

            // The search field gives way when the row gets tight, never the pills.
            SearchField(text: Bindable(library).search, interactive: scrolls)

            Button {
                if onMac {
                    Task { await library.loadMac() }
                } else if let host = console.host {
                    Task { await library.load(host: host, refresh: true) }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(CircleIconButtonStyle())
            .iconLabel(onMac ? "Rescan the Mac's game folders" : "Rescan Games")
            .disabled(library.isLoading || library.isLoadingMac)

            HStack(spacing: 2) {
                modeButton(covers: true, symbol: "rectangle.portrait.fill", help: "Covers")
                modeButton(covers: false, symbol: "rectangle.fill", help: "XMB Icons")
                Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 16).padding(.horizontal, 2)
                orderMenu
            }
            .padding(3)
            .background(Capsule().fill(Color.black.opacity(0.45)))
            .fixedSize()

            Spacer(minLength: 0)

            if onMac {
                Button {
                    showsServer = true
                } label: {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(netServer.status.isRunning ? Theme.good : Theme.tertiaryText)
                            .frame(width: 8, height: 8)
                        Text("Game Server")
                    }
                }
                .buttonStyle(PillButtonStyle(prominent: false))
                .help("Play ISOs straight from the Mac without copying them")
                Button {
                    showsFolders = true
                } label: {
                    Label("Game Folders", systemImage: "folder")
                }
                .buttonStyle(PillButtonStyle(prominent: false))
            } else {
                updatesButton
            }
        }
    }

    private func sourceButton(_ source: Game.Source, title: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                library.source = source
                library.filter = .all
            }
        } label: {
            Text(title)
                .font(.ui(.callout, weight: library.source == source ? .bold : .semibold))
                .foregroundStyle(library.source == source ? Theme.primaryText : Theme.primaryText.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(library.source == source ? Color.white.opacity(0.14) : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func modeButton(covers: Bool, symbol: String, help: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showCovers = covers }
        } label: {
            Image(systemName: symbol)
                .font(.ui(.footnote, weight: .semibold))
                .foregroundStyle(showCovers == covers ? Theme.primaryText : Theme.tertiaryText)
                .frame(width: 34, height: 28)
                .background(Capsule().fill(showCovers == covers ? Color.white.opacity(0.14) : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .iconLabel(help)
        .accessibilityAddTraits(showCovers == covers ? .isSelected : [])
    }

    /// The sort order, beside Covers and Icons, as a button that opens a menu. Lit while it is
    /// not by name.
    @ViewBuilder private var orderMenu: some View {
        let label = Image(systemName: "arrow.up.arrow.down")
            .font(.ui(.footnote, weight: .semibold))
            .foregroundStyle(order == .name ? Theme.tertiaryText : Theme.primaryText)
            .frame(width: 34, height: 28)
            .background(Capsule().fill(order == .name ? .clear : Color.white.opacity(0.14)))
            .contentShape(Capsule())
        if scrolls {
            Menu {
                Picker("Sort By", selection: $order) {
                    ForEach(GameOrder.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                label
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .iconLabel("Sort by \(order.label.lowercased())")
        } else {
            label
        }
    }

    /// "Check for Updates" until Sony has been asked; then how many games have newer patches.
    @ViewBuilder private var updatesButton: some View {
        if library.isCheckingUpdates {
            HStack(spacing: 8) {
                Spinner()
                Text("Asking Sony…").font(.ui(.footnote)).foregroundStyle(Theme.secondaryText)
            }
        } else {
            Button {
                Task { await library.checkUpdates(refresh: library.updatesChecked != nil) }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.down.circle")
                    Text(library.updatesChecked == nil ? "Check for Updates" : library.updateCount == 0 ? "No Updates" : "Updates")
                    if library.updateCount > 0 { CountBadge(count: library.updateCount) }
                }
            }
            .buttonStyle(PillButtonStyle(prominent: false))
            .help("Official game patches from Sony's update server. The system software is never touched.")
        }
    }

    @ViewBuilder private var content: some View {
        if onMac {
            macContent
        } else {
            consoleContent
        }
    }

    @ViewBuilder private var consoleContent: some View {
        let firstLoad = library.games.isEmpty && (library.phase == .idle || library.phase == .loading)
        if firstLoad {
            centered(spinner: "Reading the games on the PS3…")
        } else if case .failed(let message) = library.phase, library.games.isEmpty {
            VStack(spacing: 12) {
                Text("Couldn't read the games").font(.ui(.headline, weight: .semibold)).foregroundStyle(Theme.primaryText)
                Text(message).font(.ui(.body)).foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if library.games.isEmpty {
            emptyState(symbol: "opticaldisc", title: "No games on the PS3 yet",
                       detail: "PS3 Center looks in PS3ISO, GAMES, PS2ISO, PSXISO, PSPISO, BDISO and DVDISO on the hard drive and USB drives, and among installed games. Choose Mac above to send games.")
        } else {
            scrolling
        }
    }

    @ViewBuilder private var macContent: some View {
        if !library.macLoaded {
            centered(spinner: "Reading the Mac's game folders…")
        } else if library.macGames.isEmpty {
            VStack(spacing: 14) {
                emptyState(symbol: "folder.badge.plus", title: "No games in the Mac's game folders",
                           detail: "Add the folders where you keep your games, one or more per type: PS3ISO, PS2ISO, PSXISO and so on. The games show up here and go to the PS3 with one click.")
                    .frame(maxHeight: 220)
                Button("Add Game Folders…") { showsFolders = true }
                    .buttonStyle(PillButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            scrolling
        }
    }

    @ViewBuilder private var scrolling: some View {
        if scrolls {
            ScrollView { grid }.scrollIndicators(.hidden)
        } else {
            grid
        }
    }

    private func centered(spinner text: String) -> some View {
        VStack(spacing: 12) {
            Spinner()
            Text(text).font(.ui(.body)).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.ui(.largeTitle, weight: .light)).foregroundStyle(Theme.secondaryText)
            Text(title).font(.ui(.title2, weight: .light)).foregroundStyle(Theme.primaryText)
            Text(detail)
                .font(.ui(.body)).foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// By name: a section per platform. By size or date: one list across platforms, like the PS
    /// app's library, since the point is what is largest or newest of all.
    private var grid: some View {
        let visible = order.sorted(library.visible)
        return LazyVStack(alignment: .leading, spacing: 4) {
            if visible.isEmpty {
                Text("No game matches “\(library.search)”.")
                    .font(.ui(.callout)).foregroundStyle(Theme.secondaryText)
                    .padding(14)
            }
            if order == .name {
                // Platforms with a few games share a row instead of leaving most of one empty;
                // a platform with more keeps its own full-width grid.
                ForEach(PlatformRun.runs(of: visible)) { run in
                    if let big = run.big {
                        SectionHeader(title: big.platform.label, count: big.games.count)
                        tiles(big.games)
                    } else {
                        FlowLayout(spacing: 12) {
                            ForEach(run.sections, id: \.platform) { compactSection($0) }
                        }
                    }
                }
            } else if !visible.isEmpty {
                SectionHeader(title: order == .size ? "Largest First" : "Recently Added", count: visible.count)
                tiles(visible)
            }
        }
        .padding(.bottom, 12)
    }

    /// A platform with few games: its header and tiles of a fixed width, sized to fit them.
    private func compactSection(_ section: PlatformRun.Section) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: section.platform.label, count: section.games.count)
            HStack(alignment: .top, spacing: 16) {
                ForEach(section.games) {
                    GameTile(game: $0, showCover: showCovers, showsAdded: false, showsPlatform: false)
                        // The grid's minimum column width, so these tiles match the full-width grids.
                        .frame(width: showCovers ? 170 : 200)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func tiles(_ rows: [Game]) -> some View {
        LazyVGrid(columns: [GridItem(showCovers ? .adaptive(minimum: 170, maximum: 220) : .adaptive(minimum: 200, maximum: 280), spacing: 16)],
                  alignment: .leading, spacing: 16) {
            // Grouped by platform, the section header already names it; sorted lists mix platforms.
            ForEach(rows) { GameTile(game: $0, showCover: showCovers, showsAdded: order == .added, showsPlatform: order != .name) }
        }
        .padding(.horizontal, 14)
    }

    /// "3 selected · 24.1 GB" and the white Send button, under the Mac's grid. Games the console
    /// already has are counted, since sending them again only resumes or skips them.
    private var selectionBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
            Text(selectionSummary)
                .font(.ui(.callout, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
            Spacer()
            Button("Deselect") { library.selection.removeAll() }
                .buttonStyle(PillButtonStyle(prominent: false))
            Button {
                usbCopy = USBCopyRequest(games: library.selectedMacGames)
            } label: {
                Label("Copy to USB Drive…", systemImage: "externaldrive")
            }
            .buttonStyle(PillButtonStyle(prominent: false))
            .help("Copy to a FAT32 drive for the PS3. ISOs over 4 GB are split, and a game folder with a file that large becomes an ISO.")
            Button("Send to PS3") {
                let routes = library.selectedMacGames.flatMap { (try? $0.routes()) ?? [] }
                review = SendReview(routes: routes)
            }
            .buttonStyle(PillButtonStyle())
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cardStroke))
    }

    private var selectionSummary: String {
        let already = library.selectedMacGames.filter { library.macStates[$0.id] == .onConsole }.count
        let base = "\(library.selection.count) selected · \(Format.bytes(library.selectedSize))"
        return already == 0 ? base : base + " · \(already) already on the PS3"
    }
}

/// Whether a game is on the disc icon right now.
enum GamePlayState {
    case playing, mounted

    var label: String { self == .playing ? "Playing" : "Mounted" }
}

extension ConsoleStore {
    /// Playing while the game runs, mounted while it sits on /dev_bdvd, else nil.
    func playState(of game: Game) -> GamePlayState? {
        guard let snapshot, snapshot.mountedGamePath == game.path else { return nil }
        return snapshot.isGameRunning ? .playing : .mounted
    }
}

/// A tile in the grid: the box art or XMB icon large, the title, platform and region, and a
/// green "Playing" while it runs. A Mac game shows whether the console has it, and a click
/// picks it for sending instead of opening a page.
struct GameTile: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(GamesStore.self) private var library
    @Environment(NetServerStore.self) private var netServer
    let game: Game
    var showCover = true
    /// The date it was added under the title instead of its size (sorted by Recently Added).
    var showsAdded = false
    /// The platform chip; off when the grid is grouped by platform.
    var showsPlatform = true
    @State private var hovering = false
    @State private var confirmingSwitch = false
    @State private var makingClassic = false

    private var isSelected: Bool { library.selection.contains(game.id) }

    /// "13.5 GB", or "Folder"/"Installed" when the size is not known; the date when sorted by it.
    private var footnote: String {
        if showsAdded, let added = game.added { return Format.day(added) }
        return game.size.map(Format.bytes) ?? (game.isInstalled ? "Installed" : "Folder")
    }

    /// "Warn and wait" for starting: a running game is only quit after a question.
    private func playFromMac() {
        if console.snapshot?.isGameRunning == true {
            confirmingSwitch = true
        } else {
            library.playFromMac(game, slot: netServer.slot, exitingRunning: false)
        }
    }

    private var switchQuestion: String {
        let running = console.snapshot?.mountedGameName ?? console.snapshot?.runningProcess ?? "A game"
        return "\(running) is running. Quit it and start \(game.title)?"
    }

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
                // On the cover, so the size underneath is never cut short by it.
                .overlay(alignment: .topTrailing) {
                    if !game.isOnMac, console.playState(of: game) == nil, let latest = library.patches[game.id]?.last {
                        Chip(text: "Update \(latest.version)", color: Theme.accent).padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if game.isOnMac {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.ui(.title2, weight: .semibold))
                            .foregroundStyle(isSelected ? Theme.accent : Color.white.opacity(0.7))
                            .background(Circle().fill(Color.black.opacity(0.35)).padding(2))
                            .padding(8)
                    }
                }
            Text(game.title)
                .font(.ui(.callout, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(2, reservesSpace: true)
            HStack(spacing: 6) {
                if showsPlatform { Chip(text: game.platform.label) }
                if let region = game.region { Chip(text: region.label) }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Text(footnote)
                    .font(.ui(.footnote))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                status
            }
            .frame(height: 20)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(background))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(isSelected ? Theme.accent.opacity(0.7) : Theme.cardStroke,
                                                                               lineWidth: isSelected ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                if game.isOnMac { library.toggleSelection(game) } else { library.selectedID = game.id }
            }
        }
        .onHover { hovering = $0 }
        .help(game.title)
        .contextMenu {
            if game.isOnMac {
                Button("Play from Mac") { playFromMac() }
                    .disabled(!netServer.status.isRunning || game.netPath == nil || game.isFolder)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: game.path)]) }
                if game.platform == .ps2, !PS2Classic.isClassic(game.path) {
                    Button("Convert to PS2 Classic…") { makingClassic = true }
                }
            }
        }
        .sheet(isPresented: $makingClassic) { PS2ClassicView(game: game) }
        .confirmationDialog(switchQuestion, isPresented: $confirmingSwitch, titleVisibility: .visible) {
            Button("Quit and Start") { library.playFromMac(game, slot: netServer.slot, exitingRunning: true) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var background: Color {
        if isSelected { return Theme.accent.opacity(0.12) }
        return Color.white.opacity(hovering ? 0.08 : 0.045)
    }

    @ViewBuilder private var status: some View {
        if game.isOnMac {
            switch library.macStates[game.id] {
            case .onConsole?: Chip(text: "On PS3", color: Theme.good)
            case .partial?: Chip(text: "Partial", color: Theme.warm)
            default: EmptyView()
            }
        } else if let state = console.playState(of: game) {
            Chip(text: state.label, color: Theme.good)
        }
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
                TextField("Search games or title ID", text: $text)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.primaryText)
            } else {
                Text(text.isEmpty ? "Search games or title ID" : text)
                    .foregroundStyle(Theme.tertiaryText)
                Spacer(minLength: 0)
            }
        }
        .font(.ui(.body))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minWidth: 140, maxWidth: 240)
        .background(Capsule().fill(Color.black.opacity(0.45)))
    }
}

/// Box art for the Covers grid: the cover fitted on a dark plate, else the XMB icon, else the
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

/// Consecutive platforms with few games, grouped so they can share a row, or one platform with
/// more games on its own.
struct PlatformRun: Identifiable {
    struct Section { let platform: Game.Platform; let games: [Game] }

    /// Up to this many games, a platform is small enough to share a row.
    static let compactLimit = 3

    let sections: [Section]
    var id: Game.Platform { sections[0].platform }
    var big: Section? { sections.count == 1 && sections[0].games.count > Self.compactLimit ? sections[0] : nil }

    static func runs(of games: [Game]) -> [PlatformRun] {
        var runs: [PlatformRun] = []
        var small: [Section] = []
        for platform in Game.Platform.allCases {
            let rows = games.filter { $0.platform == platform }
            guard !rows.isEmpty else { continue }
            if rows.count > compactLimit {
                if !small.isEmpty { runs.append(PlatformRun(sections: small)); small = [] }
                runs.append(PlatformRun(sections: [Section(platform: platform, games: rows)]))
            } else {
                small.append(Section(platform: platform, games: rows))
            }
        }
        if !small.isEmpty { runs.append(PlatformRun(sections: small)) }
        return runs
    }
}

/// Lays its blocks out left to right and wraps to a new line when the next one does not fit,
/// like words in a paragraph. Each block keeps its ideal size.
struct FlowLayout: Layout {
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = lines.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? lines.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for line in arrange(width: bounds.width, subviews: subviews) {
            for item in line.items {
                subviews[item.index].place(at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + line.y),
                                           proposal: ProposedViewSize(item.size))
            }
        }
    }

    private struct Line {
        var items: [(index: Int, x: CGFloat, size: CGSize)] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Line] {
        var lines = [Line()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            var line = lines[lines.count - 1]
            let x = line.items.isEmpty ? 0 : line.width + spacing
            if !line.items.isEmpty, x + size.width > width {
                lines.append(Line(items: [(index, 0, size)], y: line.y + line.height + lineSpacing, width: size.width, height: size.height))
            } else {
                line.items.append((index, x, size))
                line.width = x + size.width
                line.height = max(line.height, size.height)
                lines[lines.count - 1] = line
            }
        }
        return lines
    }
}
