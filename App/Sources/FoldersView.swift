import AppKit
import PS3Kit
import SwiftUI

/// Spelmappar: one row per kind (PS3ISO, PS2ISO …) with the Mac folders linked to it, saved as
/// `folders` in config.json like `ps3 config folder add`. The mirror folder's dev_hdd0/<KIND>
/// counts too and is shown, but is not removed from here.
struct FoldersView: View {
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
            Text("Game Folders")
                .font(.ui(.display, weight: .light))
                .foregroundStyle(Theme.primaryText)
            Text("Add the folders where you keep your games. The games show up under Mac in the Games tab, and PS3 Center puts them in the right folder on the PS3. If you watch a folder, new games in it are sent by themselves once they have finished copying.")
                .font(.ui(.body))
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
                Spacer()
                DoneButton()
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
                Text(kind.label).font(.ui(.headline, weight: .semibold)).foregroundStyle(Theme.primaryText)
                Text(kind.name).font(.ui(.caption, weight: .bold, design: .monospaced)).foregroundStyle(Theme.tertiaryText)
            }
            .frame(width: 160, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(folders, id: \.path) { url in
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                        Text((url.path as NSString).abbreviatingWithTildeInPath)
                            .font(.ui(.footnote))
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if !isPluggedIn(url) {
                            Chip(text: "Not Connected", color: Theme.warm)
                        }
                        Spacer(minLength: 4)
                        HStack(spacing: 4) {
                            Text("Watch").font(.ui(.caption)).foregroundStyle(Theme.secondaryText)
                            PillToggle(isOn: watched.contains(url.path), label: "Watch \(url.lastPathComponent)") { setWatched(url, $0) }
                                .scaleEffect(0.7)
                                .frame(width: 34)
                        }
                        .help("New games in the folder join the queue and are sent once they stop growing. What is already in the folder doesn't count as new.")
                        if isConfigured(url, kind) {
                            Button { remove(url, kind) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain)
                                .foregroundStyle(Theme.secondaryText)
                                .iconLabel("Remove (the files are not touched)")
                        } else {
                            Chip(text: "Mirror Folder")
                        }
                    }
                }
                Button { add(kind) } label: { Label("Add…", systemImage: "plus") }
                    .buttonStyle(.plain)
                    .font(.ui(.footnote, weight: .semibold))
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
        panel.prompt = "Add"
        panel.message = "Choose folders with \(kind.label.lowercased())."
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
/// `ps3 config folder add PKG`. Their packages are listed under From Mac in the Apps tab.
struct PackageFoldersView: View {
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
            Text("Package Folders")
                .font(.ui(.display, weight: .light))
                .foregroundStyle(Theme.primaryText)
            Text("Add the folders where you keep .pkg files, such as apps you downloaded yourself. PS3 Center looks in the folder and the folders directly inside it. The packages show up under From Mac in the Apps tab and install on the PS3 with one click. The files stay on the Mac.")
                .font(.ui(.body))
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
                Spacer()
                DoneButton()
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
                Text("No folders added yet.")
                    .font(.ui(.body))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.vertical, 12)
            }
            ForEach(folders, id: \.path) { url in
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                    Text((url.path as NSString).abbreviatingWithTildeInPath)
                        .font(.ui(.footnote))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !isPluggedIn(url) {
                        Chip(text: "Not Connected", color: Theme.warm)
                    }
                    Spacer(minLength: 4)
                    Button { remove(url) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.secondaryText)
                        .iconLabel("Remove (the files are not touched)")
                }
                .padding(.vertical, 10)
                Divider().overlay(Theme.cardStroke)
            }
            Button { add() } label: { Label("Add…", systemImage: "plus") }
                .buttonStyle(.plain)
                .font(.ui(.footnote, weight: .semibold))
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
        panel.prompt = "Add"
        panel.message = "Choose folders with .pkg files."
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
