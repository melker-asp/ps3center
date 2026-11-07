import AppKit
import PS3Kit
import SwiftUI

/// Underhåll: backups of the saves and system files, the check that finds leftovers, the
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
        .confirmationDialog("Ta bort \(store.fixable.count) filer från PS3:an?", isPresented: $confirmsFix) {
            Button("Ta bort", role: .destructive) { store.fix() }
        } message: {
            Text(store.fixable.map(\.title).joined(separator: ", "))
        }
        .confirmationDialog("Kopiera skivan till PS3:ans hårddisk?", isPresented: $confirmsRip) {
            Button("Kopiera") { store.rip() }
        } message: {
            Text(store.disc.map { "\($0.title) (\(Format.bytes($0.bytes))) hamnar i \($0.destination)." } ?? "")
        }
        .confirmationDialog("Blockera systemuppdateringar?", isPresented: $confirmsBlock) {
            Button("Blockera") { store.blockUpdates() }
        } message: {
            Text("PS3 Center lägger webMAN MOD:s ps3-updatelist.txt i /dev_hdd0. Från nästa start pekar webMAN XMB:ns uppdateringskoll på den, så ingen systemuppdatering kan hämtas av misstag. Inget i systemflashen ändras, och filen kan tas bort igen.")
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
        .font(.system(size: 13))
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 4)
    }

    // MARK: Backups

    private var savesCard: some View {
        Card(icon: "externaldrive.badge.checkmark", title: "Sparfiler", chip: store.autoBackup ? "Varje vecka" : nil, chipColor: Theme.good) {
            BigValue(value: "\(store.localSaves.count)", unit: "säkerhetskopierade")
            Footnote(text: store.lastSaveBackup.map { "Senast \(Format.day($0))" } ?? "Inte kopierade än")
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button("Kopiera nu") { store.backupSaves() }
                    .buttonStyle(PillButtonStyle())
                Button("Visa…") { showsSaves = true }
                    .buttonStyle(PillButtonStyle(prominent: false))
                Spacer(minLength: 0)
                PillToggle(isOn: store.autoBackup) { store.setAutoBackup($0) }
                    .scaleEffect(0.8)
                    .help("Kopiera sparfilerna en gång i veckan när PS3:an är på och inget spel körs")
            }
            .disabled(store.busy != nil)
        }
    }

    private var systemCard: some View {
        Card(icon: "gearshape.2", title: "Systemfiler", chip: "Bara läsning") {
            BigValue(value: "\(store.systemBackups.count)", unit: store.systemBackups.count == 1 ? "kopia" : "kopior")
            Footnote(text: store.systemBackups.first.map { "Senast \(Format.day($0))" } ?? "Inga kopior än")
            Spacer(minLength: 0)
            Text("Systeminställningarna, webMAN:s inställningar och boot_plugins.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Kopiera nu") { store.backupSystem() }
                .buttonStyle(PillButtonStyle(prominent: false))
                .disabled(store.busy != nil)
        }
    }

    private var discCard: some View {
        Card(icon: "opticaldisc", title: "Skivan", chip: store.disc?.titleID) {
            if let disc = store.disc {
                Text(disc.title)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
                Footnote(text: Format.bytes(disc.bytes))
                Spacer(minLength: 0)
                if let ripped = store.ripped, store.busy == "Kopierar skivan" {
                    PSProgressBar(fraction: disc.bytes > 0 ? Double(ripped) / Double(disc.bytes) : 0)
                        .frame(height: 6)
                    HStack {
                        Footnote(text: "\(Format.bytes(ripped)) av \(Format.bytes(disc.bytes))")
                        Spacer()
                        Button("Stoppa") { store.abortRip() }
                            .buttonStyle(PillButtonStyle(prominent: false))
                    }
                } else {
                    Button("Kopiera till hårddisken") { confirmsRip = true }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .disabled(store.busy != nil)
                }
            } else {
                Text(store.discNote ?? "Ingen PS3-skiva i spelaren.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Titta igen") { store.loadDisc() }
                    .buttonStyle(PillButtonStyle(prominent: false))
            }
        }
    }

    // MARK: Films and pictures

    private var mediaCard: some View {
        let items = store.media ?? []
        let videos = items.filter(\.isVideo).count
        return Card(icon: "film.stack", title: "Filmer och bilder", chip: items.isEmpty ? nil : "\(items.count) nya", chipColor: Theme.good) {
            BigValue(value: "\(videos)", unit: videos == 1 ? "film" : "filmer")
            Footnote(text: "\(items.count - videos) bilder · \(Format.bytes(items.reduce(0) { $0 + $1.size }))")
            Spacer(minLength: 0)
            Text("Inspelningar från webMAN och skärmbilder från spel. Inget tas bort från PS3:an.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Hämta till Macen") { store.importMedia() }
                    .buttonStyle(PillButtonStyle())
                    .disabled(items.isEmpty || store.busy != nil)
                Button { NSWorkspace.shared.open(MediaImport.defaultFolder) } label: { Image(systemName: "folder") }
                    .buttonStyle(CircleIconButtonStyle(size: 30))
                    .help("Visa mappen Bilder/PS3 Center")
            }
        }
    }

    // MARK: Cleaning up

    private var cleanupCard: some View {
        Card(icon: "sparkles", title: "Städning", chip: store.report.map { $0.findings.isEmpty ? "Allt bra" : "\($0.findings.count) att titta på" },
             chipColor: store.report?.findings.isEmpty == false ? Theme.warm : Theme.good) {
            if let report = store.report {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(report.passed, id: \.self) { passed in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                            Text(passed).foregroundStyle(Theme.secondaryText)
                        }
                        .font(.system(size: 13))
                    }
                    ForEach(report.findings) { finding in findingRow(finding) }
                }
            } else {
                Text("Letar efter kvarglömda paket, avbrutna överföringar, spel som finns två gånger, en stor cache och plugins som saknas. Läser bara, tills du väljer att ta bort.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button(store.report == nil ? "Kontrollera" : "Kontrollera igen") { store.check() }
                    .buttonStyle(PillButtonStyle(prominent: store.report == nil))
                if !store.fixable.isEmpty {
                    Button("Ta bort \(store.fixable.count) filer · \(Format.bytes(store.fixable.compactMap(\.size).reduce(0, +)))") { confirmsFix = true }
                        .buttonStyle(PillButtonStyle())
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
                    Text(finding.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primaryText)
                    if let size = finding.size { Chip(text: Format.bytes(size)) }
                }
                Text(finding.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if finding.kind == .updates {
                Spacer()
                Button("Blockera") { confirmsBlock = true }
                    .buttonStyle(PillButtonStyle())
                    .disabled(store.busy != nil)
            }
        }
    }

    // MARK: Storage

    private var storageCard: some View {
        Card(icon: "chart.bar.xaxis", title: "Lagring", chip: storageChip) {
            if let map = store.storage {
                StorageBar(map: map).frame(height: 26)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    ForEach(map.areas.indices, id: \.self) { index in
                        legend(StorageBar.color(index), map.areas[index].name, map.areas[index].bytes)
                    }
                    if let other = map.other, other > 0 { legend(Color.white.opacity(0.25), "Övrigt och systemet", other) }
                }
                if !map.largest.isEmpty {
                    Text("STÖRSTA FILERNA")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, 4)
                    ForEach(map.largest.prefix(5)) { file in
                        HStack {
                            Text(file.name).font(.system(size: 12)).foregroundStyle(Theme.primaryText).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Format.bytes(file.bytes)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            } else {
                Text("Räknar hur mycket varje mapp på /dev_hdd0 tar, på konsolen med webMAN. Tar en stund för stora mappar.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(store.storage == nil ? "Räkna" : "Räkna igen") { store.analyze() }
                .buttonStyle(PillButtonStyle(prominent: false))
                .disabled(store.busy != nil)
        }
    }

    private var storageChip: String? {
        guard let free = store.storage?.free else { return nil }
        return "\(Format.bytes(free)) ledigt"
    }

    private func legend(_ color: Color, _ name: String, _ bytes: Int64) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(name).font(.system(size: 12)).foregroundStyle(Theme.primaryText).lineLimit(1)
            Spacer(minLength: 4)
            Text(Format.bytes(bytes)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondaryText)
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
                Text("Sparfiler")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                HStack(spacing: 6) {
                    sourcePill("På PS3:an", selected: onConsole) { onConsole = true }
                    sourcePill("På Macen", selected: !onConsole) { onConsole = false }
                }
            }
            Text(onConsole
                 ? "Sparfilerna på PS3:an. En sparfil som tas bort kopieras till Macen först, så den går att lägga tillbaka."
                 : "Säkerhetskopian på Macen. Det som ligger på PS3:an sparas först när du lägger tillbaka en sparfil, och det går inte medan ett spel körs.")
                .font(.system(size: 13))
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
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(CircleIconButtonStyle(size: 44, filled: true))
                    .keyboardShortcut(.cancelAction)
                    .help("Tillbaka")
                Spacer()
                if let busy = store.busy {
                    Text(busy).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                } else if let note = store.note {
                    Text(note).font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(2)
                }
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
        .confirmationDialog("Lägga tillbaka \(restoring?.title ?? "")?", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
                            presenting: restoring) { save in
            Button("Skriv över på PS3:an", role: .destructive) { store.restore(save) }
        } message: { save in
            Text("Sparfilen i \(save.folder) på PS3:an ersätts med kopian från \(save.modified.map(Format.day) ?? "säkerhetskopian").")
        }
        .confirmationDialog("Ta bort \(deleting?.title ?? "") från PS3:an?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { save in
            Button("Ta bort", role: .destructive) { store.deleteSave(save) }
        } message: { save in
            Text("\(save.folder) tas bort från PS3:an. En kopia sparas på Macen först, så du kan lägga tillbaka den under På Macen.")
        }
    }

    @ViewBuilder private var list: some View {
        let saves = onConsole ? (store.consoleSaves ?? []) : store.localSaves
        VStack(spacing: 0) {
            if onConsole, store.consoleSaves == nil {
                Text(store.busy ?? "Sparfilerna på PS3:an har inte lästs än.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.vertical, 10)
            } else if saves.isEmpty {
                Text(onConsole ? "Inga sparfiler på PS3:an." : "Ingen säkerhetskopia än.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.vertical, 10)
            }
            ForEach(saves) { save in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(save.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.primaryText)
                        Text([save.subtitle, save.folder, save.modified.map(Format.day)].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(Format.bytes(save.size)).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                    if onConsole {
                        Button("Ta bort") { deleting = save }
                            .buttonStyle(PillButtonStyle(prominent: false))
                            .disabled(store.busy != nil)
                    } else {
                        Button("Lägg tillbaka") { restoring = save }
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? Color.black : Theme.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}
