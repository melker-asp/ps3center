import PS3Kit
import SwiftUI

/// Mole's Apps → Updates, for PS3 homebrew: updates first, then what is current, plus a
/// "Hämta" list of everything the catalog can install.
struct AppsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case updates, get
        var id: String { rawValue }
        var title: String { self == .updates ? "Uppdateringar" : "Hämta" }
    }

    @Environment(ConsoleStore.self) private var console
    @Environment(AppsStore.self) private var apps
    @State private var section: Section
    @State private var plan: AppsStore.UpdatePlan?
    var scrolls = true

    init(section: Section = .updates, scrolls: Bool = true) {
        _section = State(initialValue: section)
        self.scrolls = scrolls
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if apps.selected == nil { toolbar }
            if let game = apps.waitingGame {
                WaitingBanner(game: game) { apps.forceWaiting() }
            }
            if apps.archiveMissing {
                MissingFolderBanner { apps.chooseMirrorFolder() }
            }
            if let selected = apps.selected {
                AppDetailView(status: selected, scrolls: scrolls)
                    .transition(.opacity)
            } else {
                content
            }
        }
        .task(id: console.host) {
            guard let host = console.host, apps.phase == .idle || apps.statuses.isEmpty else { return }
            await apps.load(host: host)
        }
        .sheet(item: $plan) { UpdateReviewView(plan: $0) }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(Section.allCases) { item in
                    Button {
                        section = item
                    } label: {
                        HStack(spacing: 7) {
                            Text(item.title)
                            if item == .updates, !apps.updates.isEmpty {
                                CountBadge(count: apps.updates.count)
                            }
                        }
                        .font(.system(size: 14, weight: section == item ? .bold : .semibold))
                        .foregroundStyle(section == item ? Theme.primaryText : Theme.primaryText.opacity(0.7))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(section == item ? Color.white.opacity(0.14) : .clear))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Capsule().fill(Color.black.opacity(0.45)))

            Button {
                guard let host = console.host else { return }
                Task { await apps.load(host: host, refreshIcons: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(apps.phase == .loading ? 360 : 0))
            }
            .buttonStyle(CircleIconButtonStyle())
            .help("Kolla igen")
            .disabled(apps.isBusy)

            Spacer()

            if let checked = apps.lastChecked {
                Text("Kollat \(checked.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }

    @ViewBuilder private var content: some View {
        let firstLoad = apps.statuses.isEmpty && (apps.phase == .idle || apps.phase == .loading)
        switch apps.phase {
        case _ where firstLoad:
            VStack(spacing: 12) {
                Spinner()
                Text("Kollar versioner på PS3:an och GitHub…")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message) where apps.statuses.isEmpty:
            VStack(spacing: 12) {
                Text("Kunde inte hämta programlistan").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.primaryText)
                Text(message).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            if scrolls {
                ScrollView { list }.scrollIndicators(.hidden)
            } else {
                list
            }
        }
    }

    private var list: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            switch section {
            case .updates: updatesList
            case .get: getList
            }
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder private var updatesList: some View {
        if let report = apps.report {
            UpdateReportCard(report: report) { withAnimation(.easeInOut(duration: 0.2)) { apps.dismissReport() } }
                .padding(.horizontal, 14)
                .padding(.top, 10)
        }
        if apps.updates.isEmpty {
            SectionHeader(title: "Uppdateringar", count: 0)
            Text("Allt är aktuellt.")
                .font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 14).padding(.bottom, 12)
        } else {
            // The review comes first; while its queue runs the rows show the progress.
            SectionHeader(title: "Uppdateringar", count: apps.updates.count,
                          action: apps.installableUpdates.isEmpty || apps.isUpdatingAll ? nil : ("Uppdatera alla…", { plan = apps.updatePlan() }))
            ForEach(apps.updates, id: \.id) { AppRow(status: $0, mode: .update) }
        }
        SectionHeader(title: "Aktuella", count: apps.current.count)
        ForEach(apps.current, id: \.id) { AppRow(status: $0, mode: .current) }
        if !apps.manual.isEmpty {
            SectionHeader(title: "Kolla manuellt", count: apps.manual.count)
            ForEach(apps.manual, id: \.id) { AppRow(status: $0, mode: .manual) }
        }
        if !apps.ignoredUpdates.isEmpty {
            SectionHeader(title: "Ignorerade", count: apps.ignoredUpdates.count)
            ForEach(apps.ignoredUpdates, id: \.id) { AppRow(status: $0, mode: .ignored) }
        }
    }

    @ViewBuilder private var getList: some View {
        if !apps.newReleases.isEmpty {
            SectionHeader(title: "Nytt", count: apps.newReleases.count)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 380), spacing: 16)], alignment: .leading, spacing: 16) {
                ForEach(apps.newReleases, id: \.id) { AppTile(status: $0) }
            }
            .padding(.horizontal, 14)
        }
        ForEach(CatalogEntry.Category.allCases, id: \.self) { category in
            let rows = apps.statuses.filter { $0.category == category && ($0.installable || $0.installed != nil || $0.blocked) }
            if !rows.isEmpty {
                SectionHeader(title: category.label, count: rows.count)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 380), spacing: 16)], alignment: .leading, spacing: 16) {
                    ForEach(rows, id: \.id) { AppTile(status: $0) }
                }
                .padding(.horizontal, 14)
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    let count: Int
    var action: (String, () -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 20, weight: .light)).foregroundStyle(Theme.primaryText)
            Text("\(count)").font(.system(size: 14)).foregroundStyle(Theme.tertiaryText)
            Spacer()
            if let action {
                Button(action.0, action: action.1).buttonStyle(PillButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }
}

struct AppRow: View {
    enum Mode { case update, current, manual, ignored }

    @Environment(AppsStore.self) private var apps
    @Environment(\.openURL) private var openURL
    let status: AppStatus
    let mode: Mode
    @State private var hovering = false

    /// For entries without an XMB icon on the console (HEN, webMAN, plugins).
    static let symbols = ["hen": "lock.open.fill", "webman": "server.rack", "ds45pad": "gamecontroller.fill"]

    var body: some View {
        HStack(spacing: 14) {
            AppIcon(image: apps.icons[status.id], name: status.name, category: status.category, symbol: Self.symbols[status.id])
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(status.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.primaryText)
                    Chip(text: sourceLabel)
                    if let badge = status.compatibility.badge {
                        Chip(text: badge, color: status.compatibility.blocksInstall ? Theme.hot : Theme.warm)
                    }
                }
                subtitle
            }
            Spacer()
            trailing
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText.opacity(hovering ? 1 : 0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hovering ? 0.04 : 0)))
        .contentShape(Rectangle())
        // Buttons in the row keep their own action; the rest of the row opens the detail page.
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { apps.selectedID = status.id } }
        .onHover { hovering = $0 }
        .help("Visa mer om \(status.name)")
    }

    private var sourceLabel: String { Self.sourceLabel(for: status) }

    static func sourceLabel(for status: AppStatus) -> String {
        guard let entry = AppsStore.entry(for: status) else { return "" }
        switch entry.source {
        case .github(let repo, _, _):
            if entry.category == .webmanAddons { return "webMAN" }
            return repo.split(separator: "/").first.map(String.init) ?? "GitHub"
        case .henSource: return "PS3Xploit"
        case .manual: return "Brewology"
        }
    }

    @ViewBuilder private var subtitle: some View {
        switch mode {
        case .update, .ignored:
            HStack(spacing: 6) {
                Text(status.installed ?? "?").foregroundStyle(Theme.secondaryText)
                Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Theme.tertiaryText)
                Text(status.latest ?? "?")
                    .foregroundStyle(mode == .ignored ? Theme.secondaryText : Theme.accent)
                    .fontWeight(.semibold)
                if mode == .ignored {
                    Text("·  visas igen när en nyare version kommer").foregroundStyle(Theme.tertiaryText).lineLimit(1)
                } else if !status.canInstall, let note = status.note {
                    Text("·  \(note)").foregroundStyle(Theme.tertiaryText).lineLimit(1)
                }
            }
            .font(.system(size: 13, design: .rounded))
        case .current:
            Text([status.installed, status.summary].compactMap { $0 }.joined(separator: "  ·  "))
                .font(.system(size: 13)).foregroundStyle(Theme.secondaryText).lineLimit(1)
        case .manual:
            Text([status.installed, status.note].compactMap { $0 }.joined(separator: "  ·  "))
                .font(.system(size: 13)).foregroundStyle(Theme.secondaryText).lineLimit(1)
        }
    }

    @ViewBuilder private var trailing: some View {
        if let op = apps.operations[status.id] {
            OperationView(operation: op)
        } else {
            switch mode {
            case .update:
                HStack(spacing: 8) {
                    Button("Ignorera") { withAnimation(.easeInOut(duration: 0.2)) { apps.ignore(status) } }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .help("Visa inte \(status.latest ?? "den här versionen") som en uppdatering. Kommer en nyare version visas den igen.")
                    if status.canInstall {
                        Button("Uppdatera") { apps.install(status) }.buttonStyle(PillButtonStyle())
                    } else {
                        Button("Läs mer") { apps.selectedID = status.id }
                            .buttonStyle(PillButtonStyle(prominent: false))
                    }
                }
            case .ignored:
                Button("Sluta ignorera") { withAnimation(.easeInOut(duration: 0.2)) { apps.unignore(status) } }
                    .buttonStyle(PillButtonStyle(prominent: false))
            case .manual:
                Button("Öppna sidan") { if let url = URL(string: status.homepage) { openURL(url) } }
                    .buttonStyle(PillButtonStyle(prominent: false))
            case .current:
                EmptyView()
            }
        }
    }
}

/// A tile in Hämta, like the PS app's library: the XMB icon large, name, summary and action.
struct AppTile: View {
    @Environment(AppsStore.self) private var apps
    let status: AppStatus
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear
                .aspectRatio(320.0 / 176.0, contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        AppIcon(image: apps.icons[status.id], name: status.name, category: status.category,
                                symbol: AppRow.symbols[status.id], size: proxy.size)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(status.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(status.blocked ? status.compatibility.summary : status.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2, reservesSpace: true)
            }
            HStack(spacing: 8) {
                Chip(text: AppRow.sourceLabel(for: status))
                if status.isNewRelease() {
                    Chip(text: "NYTT", color: Theme.good)
                        .help(status.releasedAt.map { "Senaste versionen kom \($0.formatted(date: .long, time: .omitted))" } ?? "")
                }
                if let badge = status.compatibility.badge {
                    Chip(text: badge, color: status.compatibility.blocksInstall ? Theme.hot : Theme.warm)
                }
                Spacer()
                action
            }
            .frame(height: 30)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(hovering ? 0.08 : 0.045)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardStroke))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { apps.selectedID = status.id } }
        .onHover { hovering = $0 }
        .help("Visa mer om \(status.name)")
    }

    @ViewBuilder private var action: some View {
        if let op = apps.operations[status.id] {
            OperationView(operation: op)
        } else if status.blocked {
            Label("Fungerar inte", systemImage: "nosign")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.hot)
        } else if let installed = status.installed {
            Label(installed, systemImage: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.good)
        } else if status.installable {
            Button("Installera") { apps.install(status) }.buttonStyle(PillButtonStyle())
        }
    }
}

struct OperationView: View {
    let operation: AppsStore.Operation

    var body: some View {
        HStack(spacing: 10) {
            switch operation.stage {
            case .queued:
                Text("I kö").foregroundStyle(Theme.tertiaryText)
            case .downloading:
                Spinner()
                Text("Laddar ner…").foregroundStyle(Theme.secondaryText)
            case .uploading(let fraction):
                PSProgressBar(fraction: fraction).frame(width: 110)
                Text("\(Int(fraction * 100)) %").foregroundStyle(Theme.secondaryText).monospacedDigit()
            case .waitingForGame:
                Image(systemName: "pause.circle").foregroundStyle(Theme.warm)
                Text("Väntar på spelet").foregroundStyle(Theme.warm)
            case .installing:
                Spinner()
                Text("Installerar…").foregroundStyle(Theme.secondaryText)
            case .uninstalling:
                Spinner()
                Text("Avinstallerar…").foregroundStyle(Theme.secondaryText)
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                Text("Installerat").foregroundStyle(Theme.good)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.hot)
                Text(message).foregroundStyle(Theme.hot).lineLimit(1).frame(maxWidth: 260, alignment: .trailing)
            }
        }
        .font(.system(size: 13, weight: .medium))
    }
}

/// The console's own XMB icon when the app is installed, else a tinted initial.
struct AppIcon: View {
    let image: NSImage?
    let name: String
    let category: CatalogEntry.Category
    var symbol: String?
    // ICON0.PNG is 320×176, so a wide tile shows it without cropping too much.
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
                    LinearGradient(colors: [tint.opacity(0.9), tint.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 16 * scale, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.9))
                    } else {
                        Text(String(name.prefix(1)))
                            .font(.system(size: 18 * scale, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.9))
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
    }

    private var tint: Color { Self.tint(for: category) }

    static func tint(for category: CatalogEntry.Category) -> Color {
        switch category {
        case .system: return Theme.psBlue
        case .tools: return Theme.galacticPurple
        case .webmanAddons: return Theme.cosmicRed
        }
    }
}

struct WaitingBanner: View {
    let game: String
    let force: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "gamecontroller.fill").foregroundStyle(Theme.warm)
            Text("\(game) körs. Installationen väntar tills du har avslutat spelet.")
                .font(.system(size: 13)).foregroundStyle(Theme.primaryText)
            Spacer()
            Button("Installera ändå", action: force).buttonStyle(PillButtonStyle(tint: Theme.warm))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.warm.opacity(0.1)))
    }
}

struct MissingFolderBanner: View {
    let choose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark").foregroundStyle(Theme.hot)
            Text("Appen hittar inte PS3-mappen där paketen arkiveras (_Installerat/Paket).")
                .font(.system(size: 13)).foregroundStyle(Theme.primaryText)
            Spacer()
            Button("Välj mapp…", action: choose).buttonStyle(PillButtonStyle(tint: Theme.hot))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.hot.opacity(0.1)))
    }
}
