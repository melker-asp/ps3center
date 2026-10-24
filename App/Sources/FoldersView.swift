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
    @State private var linked: [(kind: GameFolders.Kind, url: URL)] = GameFolders.linked()
    @State private var configured: [String: [String]] = ConfigStore.load().folders ?? [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Spelmappar")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.primaryText)
            Text("Koppla mapparna där du har dina spel. Spelen visas under Macen i Spel-fliken, och PS3 Center lägger dem i rätt mapp på PS3:an.")
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
                        if !FileManager.default.fileExists(atPath: url.path) {
                            Chip(text: "Inte ansluten", color: Theme.warm)
                        }
                        Spacer(minLength: 4)
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

    private func reload() {
        linked = GameFolders.linked()
        configured = ConfigStore.load().folders ?? [:]
        onChange()
    }
}
