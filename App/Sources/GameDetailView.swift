import AppKit
import PS3Kit
import SwiftUI

/// One game up close, opened from its tile: the XMB background as a banner like the PS
/// Store's, title ID, size and version, and Play / Mount / Delete.
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
        .task(id: game.id) {
            await library.checkCompatibility(of: game, console: console.snapshot.map(ConsoleProfile.init(snapshot:)))
            await library.loadBackground(for: game)
        }
        .confirmationDialog(switchQuestion, isPresented: $confirmingSwitch, titleVisibility: .visible) {
            Button(pendingStart == .play ? "Quit and Start" : "Quit and Mount") {
                if pendingStart == .play {
                    library.play(game, exitingRunning: true)
                } else {
                    library.mount(game, exitingRunning: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(game.isInstalled ? "Uninstall \(game.title)?" : "Delete \(game.title)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(game.isInstalled ? "Uninstall" : "Delete", role: .destructive) { library.delete(game) }
            Button("Cancel", role: .cancel) {}
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
                Text("Games")
            }
            .font(.ui(.callout, weight: .semibold))
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
            if let pending = library.patches[game.id], !pending.isEmpty {
                UpdateBanner(game: game, patches: pending)
            }
            cards
            ForEach(Array((library.findings[game.id] ?? []).enumerated()), id: \.offset) { _, finding in
                findingBanner(finding)
            }
            if let report = library.verifications[game.id] {
                verificationBanner(report)
            }
            if let failure = library.failures[game.id] {
                NoteBanner(text: failure)
            }
            if game.isInstalled {
                NoteBanner(text: "The game is installed in the XMB and starts from its icon. Uninstall removes it from the hard drive; the saves stay.")
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
        // A picture dropped on the banner becomes the game's cover.
        .droppingFile(scrolls) { library.setCustomCover(from: $0, for: game) }
        .help(game.titleID == nil ? "" : "Drop a picture here to use it as the cover")
    }

    private var headerContent: some View {
        HStack(alignment: .bottom, spacing: 22) {
            artwork
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(game.title)
                        .font(.ui(.display, weight: .light))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Chip(text: game.platform.label)
                    if let state = console.playState(of: game) {
                        Chip(text: state.label, color: Theme.good)
                    }
                }
                Text(game.path)
                    .font(.ui(.footnote, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let played = console.playLog.record(for: game) {
                    Text("Played \(Format.playTime(played.seconds)) · last \(Format.day(played.lastPlayed))")
                        .font(.ui(.footnote))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                HStack(spacing: 10) { actions }
                    .padding(.top, 4)
            }
            Spacer()
        }
    }

    /// The box art when there is one, else the XMB icon.
    @ViewBuilder private var artwork: some View {
        if let cover = library.covers[game.id] {
            GameCover(cover: cover, icon: nil, game: game, size: CGSize(width: 150, height: 180))
        } else {
            GameArtwork(image: library.icons[game.id], game: game, size: CGSize(width: 160, height: 88))
        }
    }

    @ViewBuilder private var actions: some View {
        if let busy = library.busy, busy.id == game.id {
            if let progress = busy.progress {
                PSProgressBar(fraction: progress).frame(width: 140)
            } else {
                Spinner()
            }
            Text(busy.label)
                .font(.ui(.body, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .monospacedDigit()
        } else {
            let state = console.playState(of: game)
            if state == .playing {
                Button("Quit Game") { library.exitGame(game) }
                    .buttonStyle(PillButtonStyle())
            } else {
                Button("Play") { start(.play) }
                    .buttonStyle(PillButtonStyle())
                    .disabled(library.busy != nil)
                if !game.isInstalled {
                    if state == .mounted {
                        Button("Unmount") { library.unmount(game) }
                            .buttonStyle(PillButtonStyle(prominent: false))
                    } else {
                        Button("Mount") { start(.mount) }
                            .buttonStyle(PillButtonStyle(prominent: false))
                    }
                }
            }
            if canVerify {
                Button("Verify Against IRD") { library.verify(game) }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .help("Compares every file with the original disc (IRD from FlexBy420's database). The PS3 computes the MD5s, so it takes a while.")
            }
            if state != .playing {
                // Apart from Play and Mount, and red, so it never reads as one of them.
                Spacer(minLength: 24)
                Button(game.isInstalled ? "Uninstall…" : "Delete…") { confirmingDelete = true }
                    .buttonStyle(PillButtonStyle(destructive: true))
            }
        }
    }

    /// A copied PS3 disc in a game folder (from ps3 rip, say), not an installed game.
    private var canVerify: Bool {
        game.platform == .ps3 && game.isFolder && !game.isInstalled && game.source == .console
    }

    // MARK: Compatibility

    @ViewBuilder private func findingBanner(_ finding: PlayCheck.Finding) -> some View {
        HStack(spacing: 12) {
            Image(systemName: finding.blocksPlay ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .foregroundStyle(finding.blocksPlay ? Theme.warm : Theme.good)
            Text(finding.message)
                .font(.ui(.body))
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if finding == .libCrypt(exe: LibCrypt.exe(for: game) ?? "", installed: false) {
                Button("Copy the Data to the PS3") {
                    library.installLibCrypt(for: game, console: console.snapshot.map(ConsoleProfile.init(snapshot:)))
                }
                .buttonStyle(PillButtonStyle(tint: Theme.warm))
                .disabled(library.busy != nil)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill((finding.blocksPlay ? Theme.warm : Theme.good).opacity(0.1)))
    }

    private func verificationBanner(_ report: DiscVerifier.Report) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: report.isIntact ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(report.isIntact ? Theme.good : Theme.warm)
            VStack(alignment: .leading, spacing: 4) {
                Text(report.summary)
                    .font(.ui(.body))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(report.mismatched.prefix(5)) + Array(report.missing.prefix(5)), id: \.self) { path in
                    Text(path)
                        .font(.ui(.caption, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill((report.isIntact ? Theme.good : Theme.warm).opacity(0.1)))
    }

    /// "Warn and wait" for starting: a running game is only quit after a question.
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
        let running = console.snapshot?.mountedGameName ?? console.snapshot?.runningProcess ?? "A game"
        return "\(running) is running. Quit it and \(pendingStart == .play ? "start" : "mount") \(game.title)?"
    }

    private var deleteMessage: String {
        let freed = game.size.map { "This frees \(Format.bytes($0)) on the PS3. " } ?? ""
        if game.isInstalled {
            return freed + "The game is removed from the hard drive, but the saves stay. With Reload XMB installed, the XMB reloads so the icon goes away."
        }
        return freed + "This can't be undone, but if the game is still on the Mac you can send it again."
    }

    // MARK: Cards

    private var cards: some View {
        HStack(spacing: 14) {
            Card(icon: "number", title: "Title ID", chip: game.region?.label) {
                Text(game.titleID ?? "Unknown")
                    .font(.ui(.title, weight: .light, design: .monospaced))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                Footnote(text: game.titleID == nil ? "Not in the file name, and webMAN hasn't read the game yet" : idFootnote)
            }
            // Only with a size: an installed game or a game folder on the console has none, and a
            // card with just "–" would repeat the path the banner shows (DESIGN.md, Cards).
            if game.size != nil {
                Card(icon: "internaldrive", title: "Size", chip: game.isOnUSB ? "USB" : "Hard Drive") {
                    BigValue(value: sizeParts.value, unit: sizeParts.unit)
                    Spacer(minLength: 0)
                    Footnote(text: sizeFootnote)
                }
            }
            Card(icon: "shippingbox.fill", title: "Version", chip: versionChip) {
                BigValue(value: game.updateVersion ?? game.version ?? "–")
                Spacer(minLength: 0)
                Footnote(text: versionFootnote)
            }
        }
        .frame(height: 170)
    }

    private var versionChip: String? {
        // A pending update has its own banner above the cards; no chip repeats it.
        if library.patches[game.id]?.isEmpty == false { return nil }
        return game.updateVersion == nil ? nil : "Updated"
    }

    private var idFootnote: String {
        game.region.map { "\(game.platform.label) release for \($0.label)" } ?? "\(game.platform.label) game"
    }

    /// "9.64 GB" as a big number and its unit.
    private var sizeParts: (value: String, unit: String?) {
        guard let size = game.size else { return ("–", nil) }
        let parts = Format.bytes(size).split(whereSeparator: \.isWhitespace).map(String.init)
        if parts.count == 2 { return (parts[0], parts[1]) }
        return (Format.bytes(size), nil)
    }

    private var sizeFootnote: String {
        if !game.companions.isEmpty { return "\(game.companions.count + 1) files" }
        return game.isFolder ? "Game folder" : "One file"
    }

    private var versionFootnote: String {
        if let update = game.updateVersion {
            return "Update \(update) installed" + (game.version.map { ", the disc has \($0)" } ?? "")
        }
        if game.version != nil { return "No update installed" }
        return game.platform == .ps3 || game.platform == .psn ? "The version hasn't been read yet" : "Only PS3 games have versions"
    }
}

/// Sony has newer patches: from what is installed to the latest, how many packages and how
/// much, and an Install button tinted like the banner (Play is the page's white button). Says
/// plainly that system software is never touched.
struct UpdateBanner: View {
    @Environment(GamesStore.self) private var library
    let game: Game
    let patches: [GamePatch]

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.ui(.title2))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Update \(GameUpdateService.currentVersion(of: game) ?? "?") → \(patches.last?.version ?? "?")")
                    .font(.ui(.headline, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("\(patches.count) \(patches.count == 1 ? "package" : "packages") from Sony · \(Format.bytes(patches.reduce(0) { $0 + $1.size })). Only the game is updated, never the system software.")
                    .font(.ui(.footnote))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            if library.busy?.id != game.id {
                Button("Install") { library.installUpdates(for: game) }
                    .buttonStyle(PillButtonStyle(tint: Theme.accent))
                    .disabled(library.busy != nil)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.accent.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.accent.opacity(0.25)))
    }
}

extension View {
    /// A drop target for one file. Off in snapshots, where ImageRenderer draws drop targets as yellow boxes.
    @ViewBuilder func droppingFile(_ enabled: Bool, perform: @escaping (URL) -> Void) -> some View {
        if enabled {
            dropDestination(for: URL.self) { urls, _ in
                guard let file = urls.first else { return false }
                perform(file)
                return true
            }
        } else {
            self
        }
    }
}
