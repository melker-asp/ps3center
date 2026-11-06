import AppKit
import PS3Kit
import SwiftUI

/// Spelmappar: one row per kind (PS3ISO, PS2ISO …) with the Mac folders linked to it, saved as
/// `folders` in config.json like `ps3 config folder add`. The mirror folder's dev_hdd0/<KIND>
/// counts too and is shown, but is not removed from here.
struct FoldersView: View {
    @Environment(\.dismiss) private var dismiss
    /// Called after a change, so the Mac's library is read again.
    let onChange: () -> Void
    /// False when rendered for a snapshot: the folders in Fixtures, and no disk is looked at.
    private let live: Bool
    @State private var linked: [(kind: GameFolders.Kind, url: URL)]
    @State private var configured: [String: [String]]
    @State private var watched: Set<String>

    init(live: Bool = true, onChange: @escaping () -> Void = {}) {
        let config = live ? ConfigStore.load() : Fixtures.folderConfig
        self.live = live
        self.onChange = onChange
        _linked = State(initialValue: live ? GameFolders.linked(config: config) : GameFolders.linked(config: config, mirrorRoot: nil))
        _configured = State(initialValue: config.folders ?? [:])
        _watched = State(initialValue: Set(config.watchedFolders ?? []))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Spelmappar")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.primaryText)
            Text("Koppla mapparna där du har dina spel. Spelen visas under Macen i Spel-fliken, och PS3 Center lägger dem i rätt mapp på PS3:an. Bevakar du en mapp skickas nya spel i den av sig själva när de har kopierats klart.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(GameFolders.kinds) { kind in
                        row(kind)
                        Divider().overlay(Theme.cardStroke)
                    }
                }
            }

            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(CircleIconButtonStyle(size: 44, filled: true))
                    .keyboardShortcut(.cancelAction)
                    .help("Tillbaka")
                Spacer()
            }
            .padding(.top, 16)
        }
        .padding(32)
        .frame(width: 620, height: 660, alignment: .topLeading)
        .background(Theme.base)
    }

    private func row(_ kind: GameFolders.Kind) -> some View {
        let folders = linked.filter { $0.kind == kind }.map { $0.url }
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.primaryText)
                Text(kind.name).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Theme.tertiaryText)
            }
            .frame(width: 160, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(folders, id: \.path) { url in
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                        Text((url.path as NSString).abbreviatingWithTildeInPath)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if !isPluggedIn(url) {
                            Chip(text: "Inte ansluten", color: Theme.warm)
                        }
                        Spacer(minLength: 4)
                        HStack(spacing: 4) {
                            Text("Bevaka").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                            PillToggle(isOn: watched.contains(url.path)) { setWatched(url, $0) }
                                .scaleEffect(0.7)
                                .frame(width: 34)
                        }
                        .help("Nya spel i mappen läggs i kön och skickas när de har slutat växa. Det som redan finns i mappen räknas inte som nytt.")
                        if isConfigured(url, kind) {
                            Button { remove(url, kind) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain)
                                .foregroundStyle(Theme.secondaryText)
                                .help("Koppla bort (filerna rörs inte)")
                        } else {
                            Chip(text: "Spegelmappen")
                        }
                    }
                }
                Button { add(kind) } label: { Label("Lägg till…", systemImage: "plus") }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 12)
    }

    private func isPluggedIn(_ url: URL) -> Bool {
        live ? FileManager.default.fileExists(atPath: url.path) : !Fixtures.unpluggedFolders.contains(url.path)
    }

    private func isConfigured(_ url: URL, _ kind: GameFolders.Kind) -> Bool {
        (configured[kind.name] ?? []).contains {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL.path == url.path
        }
    }

    private func add(_ kind: GameFolders.Kind) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Koppla"
        panel.message = "Välj mappar med \(kind.label.lowercased())."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { try? GameFolders.add(url, as: kind) }
        reload()
    }

    private func remove(_ url: URL, _ kind: GameFolders.Kind) {
        try? GameFolders.remove(url, from: kind)
        reload()
    }

    private func setWatched(_ url: URL, _ on: Bool) {
        try? FolderWatch.setWatched(url, on)
        watched = Set(ConfigStore.load().watchedFolders ?? [])
    }

    private func reload() {
        linked = GameFolders.linked()
        configured = ConfigStore.load().folders ?? [:]
        onChange()
    }
}

/// Paketmappar: the Mac folders with .pkg files, saved as `packageFolders` in config.json like
/// `ps3 config folder add PKG`. Their packages are listed under Från Macen in the Apps tab.
struct PackageFoldersView: View {
    @Environment(\.dismiss) private var dismiss
    /// Called after a change, so the packages are read again.
    let onChange: () -> Void
    /// False when rendered for a snapshot: the folders in Fixtures, and no disk is looked at.
    private let live: Bool
    @State private var folders: [URL]

    init(live: Bool = true, onChange: @escaping () -> Void = {}) {
        self.live = live
        self.onChange = onChange
        _folders = State(initialValue: PackageFolders.linked(config: live ? ConfigStore.load() : Fixtures.folderConfig))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Paketmappar")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.primaryText)
            Text("Koppla mapparna där du har .pkg-filer, till exempel program du har laddat ner själv. PS3 Center letar i mappen och mapparna direkt under den. Paketen visas under Från Macen i Appar-fliken och installeras på PS3:an med ett klick. Filerna ligger kvar på Macen.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.bottom, 14)

            // ImageRenderer cannot draw a scroll view.
            if live {
                ScrollView { list }
            } else {
                list
                Spacer(minLength: 0)
            }

            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(CircleIconButtonStyle(size: 44, filled: true))
                    .keyboardShortcut(.cancelAction)
                    .help("Tillbaka")
                Spacer()
            }
            .padding(.top, 16)
        }
        .padding(32)
        .frame(width: 620, height: 440, alignment: .topLeading)
        .background(Theme.base)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            if folders.isEmpty {
                Text("Inga mappar är kopplade än.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.vertical, 12)
            }
            ForEach(folders, id: \.path) { url in
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                    Text((url.path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !isPluggedIn(url) {
                        Chip(text: "Inte ansluten", color: Theme.warm)
                    }
                    Spacer(minLength: 4)
                    Button { remove(url) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.secondaryText)
                        .help("Koppla bort (filerna rörs inte)")
                }
                .padding(.vertical, 10)
                Divider().overlay(Theme.cardStroke)
            }
            Button { add() } label: { Label("Lägg till…", systemImage: "plus") }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.top, 12)
        }
    }

    private func isPluggedIn(_ url: URL) -> Bool {
        live ? FileManager.default.fileExists(atPath: url.path) : !Fixtures.unpluggedFolders.contains(url.path)
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Koppla"
        panel.message = "Välj mappar med .pkg-filer."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { try? PackageFolders.add(url) }
        reload()
    }

    private func remove(_ url: URL) {
        try? PackageFolders.remove(url)
        reload()
    }

    private func reload() {
        folders = PackageFolders.linked()
        onChange()
    }
}
