import AppKit
import PS3Kit
import SwiftUI

/// Maintenance: backups of the saves and system files, the check that finds leftovers, the
/// storage map and copying the disc, as cards in Mole's style.
struct MaintenanceView: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(MaintenanceStore.self) private var store
    /// False when rendered for a snapshot: ImageRenderer cannot draw scroll views.
    var scrolls = true
    @State private var showsSaves = false
    @State private var confirmsFix = false
    @State private var confirmsRip = false
    @State private var confirmsBlock = false

    var body: some View {
        Group {
            if scrolls {
                ScrollView { content }.scrollIndicators(.hidden)
            } else {
                content
            }
        }
        .sheet(isPresented: $showsSaves) { SavesView() }
        .confirmationDialog("Delete \(store.fixable.count) files from the PS3?", isPresented: $confirmsFix) {
            Button("Delete", role: .destructive) { store.fix() }
        } message: {
            Text(store.fixable.map(\.title).joined(separator: ", "))
        }
        .confirmationDialog("Copy the disc to the PS3's hard drive?", isPresented: $confirmsRip) {
            Button("Copy") { store.rip() }
        } message: {
            Text(store.disc.map { "\($0.title) (\(Format.bytes($0.bytes))) goes to \($0.destination)." } ?? "")
        }
        .confirmationDialog("Block system updates?", isPresented: $confirmsBlock) {
            Button("Block") { store.blockUpdates() }
        } message: {
            Text("PS3 Center puts webMAN MOD's ps3-updatelist.txt in /dev_hdd0. From the next start, webMAN points the XMB's update check at it, so no system update can be downloaded by mistake. Nothing in the system flash changes, and the file can be removed again.")
        }
        .task(id: console.host) {
            store.host = console.host
            store.loadDisc()
            store.loadMedia()
        }
    }

    private var content: some View {
        VStack(spacing: 14) {
            if store.busy != nil || store.note != nil { statusLine }
            HStack(spacing: 14) {
                savesCard
                systemCard
                discCard
                mediaCard
            }
            .frame(height: 236)
            cleanupCard
            storageCard
        }
        .padding(.bottom, 8)
    }

    private var statusLine: some View {
        HStack(spacing: 10) {
            if let busy = store.busy {
                Spinner(size: 14)
                Text(busy)
            } else if let note = store.note {
                Image(systemName: "checkmark.circle").foregroundStyle(Theme.good)
                Text(note)
            }
            Spacer()
        }
        .font(.ui(.body))
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 4)
    }

    // MARK: Backups

    private var savesCard: some View {
        Card(icon: "externaldrive.badge.checkmark", title: "Saves") {
            BigValue(value: "\(store.localSaves.count)", unit: "backed up")
            // The weekly switch has its label next to it (it used to be a bare switch and a chip).
            HStack(spacing: 8) {
                Footnote(text: store.lastSaveBackup.map { "Last \(Format.day($0))" } ?? "Not backed up yet")
                Spacer(minLength: 4)
                Text("Weekly").font(.ui(.footnote)).foregroundStyle(Theme.secondaryText)
                PillToggle(isOn: store.autoBackup, label: "Back up weekly") { store.setAutoBackup($0) }
                    .scaleEffect(0.8)
                    .frame(width: 36, height: 22)
                    .help("Back up the saves once a week while the PS3 is on and no game is running")
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button("Back Up Now") { store.backupSaves() }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .fixedSize()
                Button("Show…") { showsSaves = true }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .fixedSize()
            }
            .disabled(store.busy != nil)
        }
    }

    private var systemCard: some View {
        Card(icon: "gearshape.2", title: "System Files", chip: "Read Only") {
            BigValue(value: "\(store.systemBackups.count)", unit: store.systemBackups.count == 1 ? "copy" : "copies")
            Footnote(text: store.systemBackups.first.map { "Last \(Format.day($0))" } ?? "No copies yet")
            Spacer(minLength: 0)
            Text("System settings, webMAN's settings and boot_plugins.")
                .font(.ui(.footnote))
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Back Up Now") { store.backupSystem() }
                .buttonStyle(PillButtonStyle(prominent: false))
                .fixedSize()
                .disabled(store.busy != nil)
        }
    }

    private var discCard: some View {
        Card(icon: "opticaldisc", title: "Disc", chip: store.disc?.titleID) {
            if let disc = store.disc {
                Text(disc.title)
                    .font(.ui(.title2, weight: .light))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
                Footnote(text: Format.bytes(disc.bytes))
                Spacer(minLength: 0)
                if let ripped = store.ripped, store.isRipping {
                    PSProgressBar(fraction: disc.bytes > 0 ? Double(ripped) / Double(disc.bytes) : 0)
                        .frame(height: 6)
                    HStack {
                        Footnote(text: "\(Format.bytes(ripped)) of \(Format.bytes(disc.bytes))")
                        Spacer()
                        Button("Stop") { store.abortRip() }
                            .buttonStyle(PillButtonStyle(prominent: false))
                    }
                } else {
                    Button("Copy to Hard Drive") { confirmsRip = true }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .disabled(store.busy != nil)
                }
            } else {
                Text(store.discNote ?? "No PS3 disc in the drive.")
                    .font(.ui(.body))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Look Again") { store.loadDisc() }
                    .buttonStyle(PillButtonStyle(prominent: false))
            }
        }
    }

    // MARK: Videos and photos

    private var mediaCard: some View {
        let items = store.media ?? []
        let videos = items.filter(\.isVideo).count
        // Two lines of text at most: a third made this card taller than the row, so it sat
        // higher than the three beside it.
        return Card(icon: "film.stack", title: "Videos & Photos", chip: items.isEmpty ? nil : "\(items.count) new", chipColor: Theme.good) {
            BigValue(value: "\(videos)", unit: videos == 1 ? "video" : "videos")
            Footnote(text: "\(items.count - videos) \(items.count - videos == 1 ? "photo" : "photos") · \(Format.bytes(items.reduce(0) { $0 + $1.size }))")
            Spacer(minLength: 0)
            Text("Recordings and in-game screenshots. Nothing is deleted from the PS3.")
                .font(.ui(.footnote))
                .foregroundStyle(Theme.tertiaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Import to Mac") { store.importMedia() }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .fixedSize()
                    .disabled(items.isEmpty || store.busy != nil)
                Button { NSWorkspace.shared.open(MediaImport.defaultFolder) } label: { Image(systemName: "folder") }
                    .buttonStyle(CircleIconButtonStyle(size: 30))
                    .iconLabel("Show the folder in Finder")
            }
        }
    }

    // MARK: Cleanup

    private var cleanupCard: some View {
        Card(icon: "sparkles", title: "Cleanup", chip: store.report.map { $0.findings.isEmpty ? "All good" : "\($0.findings.count) to look at" },
             chipColor: store.report?.findings.isEmpty == false ? Theme.warm : Theme.good) {
            if let report = store.report {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(report.passed, id: \.self) { passed in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                            Text(passed).foregroundStyle(Theme.secondaryText)
                        }
                        .font(.ui(.body))
                    }
                    ForEach(report.findings) { finding in findingRow(finding) }
                }
            } else {
                Text("Looks for leftover packages, interrupted transfers, games that are there twice, a large cache and missing plugins. Only reads, until you choose to delete.")
                    .font(.ui(.body))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button(store.report == nil ? "Check" : "Check Again") { store.check() }
                    .buttonStyle(PillButtonStyle(prominent: store.report == nil))
                if !store.fixable.isEmpty {
                    // Red, and apart on the right (DESIGN.md, Buttons): it deletes from the
                    // console, even if only leftovers, so it never sits where Check Again is.
                    Spacer()
                    Button("Delete \(store.fixable.count) \(store.fixable.count == 1 ? "File" : "Files") · \(Format.bytes(store.fixable.compactMap(\.size).reduce(0, +)))…") { confirmsFix = true }
                        .buttonStyle(PillButtonStyle(destructive: true))
                }
            }
            .disabled(store.busy != nil)
        }
    }

    private func findingRow(_ finding: MaintenanceFinding) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: finding.canFix ? "trash.circle.fill" : "info.circle")
                .foregroundStyle(finding.canFix ? Theme.warm : Theme.secondaryText)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(finding.title).font(.ui(.body, weight: .semibold)).foregroundStyle(Theme.primaryText)
                    if let size = finding.size { Chip(text: Format.bytes(size)) }
                }
                Text(finding.detail)
                    .font(.ui(.footnote))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if finding.kind == .updates {
                Spacer()
                Button("Block…") { confirmsBlock = true }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .disabled(store.busy != nil)
            }
        }
    }

    // MARK: Storage

    private var storageCard: some View {
        Card(icon: "chart.bar.xaxis", title: "Storage", chip: storageChip) {
            if let map = store.storage {
                StorageBar(map: map).frame(height: 26)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    ForEach(map.areas.indices, id: \.self) { index in
                        legend(StorageBar.color(index), map.areas[index].name, map.areas[index].bytes)
                    }
                    if let other = map.other, other > 0 { legend(Color.white.opacity(0.25), "Other and system", other) }
                }
                if !map.largest.isEmpty {
                    Text("LARGEST FILES")
                        .font(.ui(.caption, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, 4)
                    ForEach(map.largest.prefix(5)) { file in
                        HStack {
                            Text(file.name).font(.ui(.footnote)).foregroundStyle(Theme.primaryText).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Format.bytes(file.bytes)).font(.ui(.footnote, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            } else {
                Text("Counts how much each folder on /dev_hdd0 takes, on the console with webMAN. Takes a while for large folders.")
                    .font(.ui(.body))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(store.storage == nil ? "Count" : "Recount") { store.analyze() }
                .buttonStyle(PillButtonStyle(prominent: false))
                .disabled(store.busy != nil)
        }
    }

    private var storageChip: String? {
        guard let free = store.storage?.free else { return nil }
        return "\(Format.bytes(free)) free"
    }

    private func legend(_ color: Color, _ name: String, _ bytes: Int64) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(name).font(.ui(.footnote)).foregroundStyle(Theme.primaryText).lineLimit(1)
            Spacer(minLength: 4)
            Text(Format.bytes(bytes)).font(.ui(.footnote, weight: .semibold)).foregroundStyle(Theme.secondaryText)
        }
    }
}

/// The disk as one bar: each area its share of the total, then the rest, then free space.
struct StorageBar: View {
    let map: StorageMap

    static let palette: [Color] = [Theme.cosmicRed, Theme.novaPink, Theme.galacticPurple, Theme.psBlue, Theme.starlightBlue, Theme.good, Theme.warm]

    static func color(_ index: Int) -> Color { palette[index % palette.count] }

    var body: some View {
        GeometryReader { proxy in
            let total = Double(map.total ?? max(1, map.areas.reduce(0) { $0 + $1.bytes }))
            HStack(spacing: 2) {
                ForEach(map.areas.indices, id: \.self) { index in
                    Self.color(index).frame(width: max(2, proxy.size.width * Double(map.areas[index].bytes) / total))
                }
                if let other = map.other, other > 0 {
                    Color.white.opacity(0.25).frame(width: proxy.size.width * Double(other) / total)
                }
                Color.white.opacity(0.06)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// The saves in the backup, each with a button to put it back on the console.
struct SavesView: View {
    @Environment(MaintenanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var onConsole = true
    @State private var restoring: SaveGame?
    @State private var deleting: SaveGame?
    /// False when rendered for a snapshot.
    var live = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Saves")
                    .font(.ui(.display, weight: .light))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                HStack(spacing: 6) {
                    sourcePill("On PS3", selected: onConsole) { onConsole = true }
                    sourcePill("On Mac", selected: !onConsole) { onConsole = false }
                }
            }
            Text(onConsole
                 ? "The saves on the PS3. A save you delete is copied to the Mac first, so it can be restored."
                 : "The backup on the Mac. What is on the PS3 is backed up first when you restore a save, and restoring doesn't work while a game is running.")
                .font(.ui(.body))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.bottom, 14)
            if live {
                ScrollView { list }
            } else {
                list
                Spacer(minLength: 0)
            }
            HStack {
                if let busy = store.busy {
                    Text(busy).font(.ui(.footnote)).foregroundStyle(Theme.secondaryText)
                } else if let note = store.note {
                    Text(note).font(.ui(.footnote)).foregroundStyle(Theme.secondaryText).lineLimit(2)
                }
                Spacer()
                DoneButton()
            }
            .padding(.top, 16)
        }
        .padding(32)
        .frame(width: 640, height: 640, alignment: .topLeading)
        .background(Theme.base)
        .task {
            guard live, store.consoleSaves == nil else { return }
            store.loadConsoleSaves()
        }
        .confirmationDialog("Restore \(restoring?.title ?? "")?", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
                            presenting: restoring) { save in
            Button("Overwrite on PS3", role: .destructive) { store.restore(save) }
        } message: { save in
            Text("The save in \(save.folder) on the PS3 is replaced with the copy from \(save.modified.map(Format.day) ?? "the backup").")
        }
        .confirmationDialog("Delete \(deleting?.title ?? "") from the PS3?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { save in
            Button("Delete", role: .destructive) { store.deleteSave(save) }
        } message: { save in
            Text("\(save.folder) is deleted from the PS3. A copy is saved on the Mac first, so you can restore it under On Mac.")
        }
    }

    @ViewBuilder private var list: some View {
        let saves = onConsole ? (store.consoleSaves ?? []) : store.localSaves
        VStack(spacing: 0) {
            if onConsole, store.consoleSaves == nil {
                Text(store.busy ?? "The saves on the PS3 haven't been read yet.")
                    .font(.ui(.body))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.vertical, 10)
            } else if saves.isEmpty {
                Text(onConsole ? "No saves on the PS3." : "No backup yet.")
                    .font(.ui(.body))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.vertical, 10)
            }
            ForEach(saves) { save in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(save.title).font(.ui(.callout, weight: .semibold)).foregroundStyle(Theme.primaryText)
                        Text([save.subtitle, save.folder, save.modified.map(Format.day)].compactMap { $0 }.joined(separator: " · "))
                            .font(.ui(.footnote))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(Format.bytes(save.size)).font(.ui(.footnote)).foregroundStyle(Theme.secondaryText)
                    if onConsole {
                        Button("Delete…") { deleting = save }
                            .buttonStyle(PillButtonStyle(destructive: true))
                            .disabled(store.busy != nil)
                    } else {
                        Button("Restore…") { restoring = save }
                            .buttonStyle(PillButtonStyle(prominent: false))
                            .disabled(store.busy != nil)
                    }
                }
                .padding(.vertical, 10)
                Divider().overlay(Theme.cardStroke)
            }
        }
    }

    private func sourcePill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.ui(.footnote, weight: .semibold))
                .foregroundStyle(selected ? Color.black : Theme.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}
