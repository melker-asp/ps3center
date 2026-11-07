import PS3Kit
import SwiftUI

/// Mole's Apps → Updates, for PS3 homebrew: updates first, then what is current, plus a
/// "Browse" list of everything the catalog can install, and "From Mac" with the .pkg files in
/// the Mac's package folders, like the Mac's games in the Games tab.
struct AppsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case updates, get, mac
        var id: String { rawValue }
        var title: String {
            switch self {
            case .updates: return "Updates"
            case .get: return "Browse"
            case .mac: return "From Mac"
            }
        }
    }

    @Environment(ConsoleStore.self) private var console
    @Environment(AppsStore.self) private var apps
    @State private var section: Section
    @State private var showsFolders = false
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
        .task(id: section) {
            guard section == .mac, !apps.packagesLoaded, !apps.isLoadingPackages else { return }
            await apps.loadPackages(host: console.host)
        }
        .sheet(isPresented: $showsFolders) {
            PackageFoldersView {
                Task { await apps.loadPackages(host: console.host) }
            }
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
                        .font(.ui(.callout, weight: section == item ? .bold : .semibold))
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
                if section == .mac {
                    Task { await apps.loadPackages(host: console.host) }
                } else if let host = console.host {
                    Task { await apps.load(host: host, refreshIcons: true) }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(apps.phase == .loading ? 360 : 0))
            }
            .buttonStyle(CircleIconButtonStyle())
            .iconLabel(section == .mac ? "Rescan the Mac's package folders" : "Check Again")
            .disabled(apps.isBusy || apps.isLoadingPackages)

            Spacer()

            if section == .mac {
                Button {
                    showsFolders = true
                } label: {
                    Label("Package Folders", systemImage: "folder")
                }
                .buttonStyle(PillButtonStyle(prominent: false))
            } else if let checked = apps.lastChecked {
                Text("Checked \(Format.time(checked))")
                    .font(.ui(.footnote))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if section == .mac {
            macContent
        } else {
            catalogContent
        }
    }

    /// The Mac's packages do not wait for the catalog: they are listed even when the console
    /// does not answer.
    @ViewBuilder private var macContent: some View {
        if !apps.packagesLoaded {
            VStack(spacing: 12) {
                Spinner()
                Text("Reading the Mac's package folders…").font(.ui(.body)).foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if apps.packages.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "shippingbox").font(.ui(.largeTitle, weight: .light)).foregroundStyle(Theme.secondaryText)
                Text("No packages in the Mac's package folders").font(.ui(.title2, weight: .light)).foregroundStyle(Theme.primaryText)
                Text("Add the folders where you keep .pkg files. The packages show up here and install on the PS3 with one click, and the files stay on the Mac.")
                    .font(.ui(.body)).foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                Button("Add Package Folders…") { showsFolders = true }
                    .buttonStyle(PillButtonStyle())
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if scrolls {
            ScrollView { packageList }.scrollIndicators(.hidden)
        } else {
            packageList
        }
    }

    /// One section per linked folder, in the order they were linked.
    private var packageList: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            let folders = apps.packages.reduce(into: [String]()) { if !$0.contains($1.folder) { $0.append($1.folder) } }
            ForEach(folders, id: \.self) { folder in
                let rows = apps.packages.filter { $0.folder == folder }
                SectionHeader(title: (folder as NSString).lastPathComponent, count: rows.count,
                              detail: (folder as NSString).abbreviatingWithTildeInPath)
                ForEach(rows) { PackageRow(package: $0) }
            }
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder private var catalogContent: some View {
        let firstLoad = apps.statuses.isEmpty && (apps.phase == .idle || apps.phase == .loading)
        switch apps.phase {
        case _ where firstLoad:
            VStack(spacing: 12) {
                Spinner()
                Text("Checking versions on the PS3 and GitHub…")
                    .font(.ui(.body)).foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message) where apps.statuses.isEmpty:
            VStack(spacing: 12) {
                Text("Couldn't load the app list").font(.ui(.headline, weight: .semibold)).foregroundStyle(Theme.primaryText)
                Text(message).font(.ui(.body)).foregroundStyle(Theme.secondaryText)
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
            case .mac: EmptyView()
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
            SectionHeader(title: "Updates", count: 0)
            Text("Everything is up to date.")
                .font(.ui(.callout)).foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 14).padding(.bottom, 12)
        } else {
            // The review comes first; while its queue runs the rows show the progress. The button
            // says how many it installs: HEN and plugins only get advice, so "all" could be wrong.
            let installable = apps.installableUpdates.count
            SectionHeader(title: "Updates", count: apps.updates.count,
                          action: installable == 0 || apps.isUpdatingAll ? nil
                              : (installable == apps.updates.count ? "Update All…" : "Update \(installable)…", { plan = apps.updatePlan() }))
            ForEach(apps.updates, id: \.id) { AppRow(status: $0, mode: .update) }
        }
        SectionHeader(title: "Up to Date", count: apps.current.count)
        ForEach(apps.current, id: \.id) { AppRow(status: $0, mode: .current) }
        if !apps.manual.isEmpty {
            SectionHeader(title: "Check Manually", count: apps.manual.count)
            ForEach(apps.manual, id: \.id) { AppRow(status: $0, mode: .manual) }
        }
        if !apps.ignoredUpdates.isEmpty {
            SectionHeader(title: "Ignored", count: apps.ignoredUpdates.count)
            ForEach(apps.ignoredUpdates, id: \.id) { AppRow(status: $0, mode: .ignored) }
        }
    }

    @ViewBuilder private var getList: some View {
        if !apps.newReleases.isEmpty {
            SectionHeader(title: "New", count: apps.newReleases.count)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 380), spacing: 16)], alignment: .leading, spacing: 16) {
                ForEach(apps.newReleases, id: \.id) { AppTile(status: $0) }
            }
            .padding(.horizontal, 14)
        }
        ForEach(CatalogEntry.Category.allCases, id: \.self) { category in
            let rows = apps.statuses.filter { $0.category == category && $0.isListed }
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
    /// Small text after the count, such as the folder's path.
    var detail: String?
    var action: (String, () -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.ui(.title2, weight: .light)).foregroundStyle(Theme.primaryText)
            Text("\(count)").font(.ui(.callout)).foregroundStyle(Theme.tertiaryText)
            if let detail {
                Text(detail)
                    .font(.ui(.footnote))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 4)
            }
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
                    Text(status.name).font(.ui(.headline, weight: .semibold)).foregroundStyle(Theme.primaryText)
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
                .font(.ui(.footnote, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText.opacity(hovering ? 1 : 0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hovering ? 0.04 : 0)))
        .contentShape(Rectangle())
        // Buttons in the row keep their own action; the rest of the row opens the detail page.
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { apps.selectedID = status.id } }
        .onHover { hovering = $0 }
        .help("More about \(status.name)")
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
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(status.installed ?? "?").foregroundStyle(Theme.secondaryText)
                    Image(systemName: "arrow.right").font(.ui(.caption)).foregroundStyle(Theme.tertiaryText)
                    Text(status.latestForDisplay ?? "?")
                        .foregroundStyle(mode == .ignored ? Theme.secondaryText : Theme.accent)
                        .fontWeight(.semibold)
                    if mode == .ignored {
                        Text("·  shows again when a newer version comes out").foregroundStyle(Theme.tertiaryText).lineLimit(1)
                    }
                }
                .font(.ui(.body, design: .rounded))
                // The advice for HEN and plugins is the reason there is no Update button, so it
                // gets its own lines instead of being cut off after the version.
                if mode == .update, !status.canInstall, let note = status.note {
                    Text(note)
                        .font(.ui(.footnote))
                        .foregroundStyle(Theme.warm)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .current:
            Text([status.installed, status.summary].compactMap { $0 }.joined(separator: "  ·  "))
                .font(.ui(.body)).foregroundStyle(Theme.secondaryText).lineLimit(1)
        case .manual:
            Text([status.installed, status.note].compactMap { $0 }.joined(separator: "  ·  "))
                .font(.ui(.body)).foregroundStyle(Theme.secondaryText).lineLimit(1)
        }
    }

    @ViewBuilder private var trailing: some View {
        if let op = apps.operations[status.id] {
            OperationView(operation: op)
        } else {
            switch mode {
            case .update:
                HStack(spacing: 8) {
                    Button("Ignore") { withAnimation(.easeInOut(duration: 0.2)) { apps.ignore(status) } }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .help("Don't show \(status.latest ?? "this version") as an update. A newer version shows up again.")
                    // Outlined: the white button on this screen is Update All.
                    if status.canInstall {
                        Button("Update") { apps.install(status) }.buttonStyle(PillButtonStyle(prominent: false))
                    } else {
                        Button("Learn More") { apps.selectedID = status.id }
                            .buttonStyle(PillButtonStyle(prominent: false))
                    }
                }
            case .ignored:
                Button("Stop Ignoring") { withAnimation(.easeInOut(duration: 0.2)) { apps.unignore(status) } }
                    .buttonStyle(PillButtonStyle(prominent: false))
            case .manual:
                Button("Open Page") { if let url = URL(string: status.homepage) { openURL(url) } }
                    .buttonStyle(PillButtonStyle(prominent: false))
            case .current:
                EmptyView()
            }
        }
    }
}

/// A tile in Browse, like the PS app's library: the XMB icon large, name, summary and action.
/// Without a real XMB icon the tile is compact: a big tinted letter said nothing and took half
/// the card.
struct AppTile: View {
    @Environment(AppsStore.self) private var apps
    let status: AppStatus
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image = apps.icons[status.id] {
                Color.clear
                    .aspectRatio(320.0 / 176.0, contentMode: .fit)
                    .overlay {
                        GeometryReader { proxy in
                            AppIcon(image: image, name: status.name, category: status.category, size: proxy.size)
                        }
                    }
                titleAndSummary
            } else {
                HStack(alignment: .top, spacing: 12) {
                    AppIcon(image: nil, name: status.name, category: status.category,
                            symbol: AppRow.symbols[status.id], size: CGSize(width: 80, height: 44))
                    titleAndSummary
                }
            }
            HStack(spacing: 8) {
                Chip(text: AppRow.sourceLabel(for: status))
                if status.isNewRelease() {
                    Chip(text: "New", color: Theme.good)
                        .help(status.releasedAt.map { "The latest version came out \(Format.day($0))" } ?? "")
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
        .help("More about \(status.name)")
    }

    private var titleAndSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(status.name)
                .font(.ui(.headline, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
            Text(status.blocked ? status.compatibility.summary : status.summary)
                .font(.ui(.footnote))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(2, reservesSpace: true)
        }
    }

    @ViewBuilder private var action: some View {
        if let op = apps.operations[status.id] {
            OperationView(operation: op)
        } else if status.blocked {
            Label("Doesn't Work", systemImage: "nosign")
                .font(.ui(.footnote, weight: .semibold))
                .foregroundStyle(Theme.hotText)
        } else if let installed = status.installed {
            Label(installed, systemImage: "checkmark")
                .font(.ui(.footnote, weight: .semibold))
                .foregroundStyle(Theme.good)
        } else if status.installable {
            // Outlined: a grid of white buttons left nothing standing out.
            Button("Install") { apps.install(status) }.buttonStyle(PillButtonStyle(prominent: false))
        }
    }
}

/// A .pkg in one of the Mac's package folders: title (the catalog's name when its title ID is
/// known), file, size and whether it is installed. A package from the catalog opens that
/// program's page and is blocked like it on a console that does not meet its requirements.
struct PackageRow: View {
    @Environment(AppsStore.self) private var apps
    let package: LocalPackage
    @State private var hovering = false

    private var status: AppStatus? { apps.catalogStatus(of: package) }
    private var installed: String? { apps.installedVersion(of: package) }

    var body: some View {
        HStack(spacing: 14) {
            AppIcon(image: package.titleID.flatMap { apps.packageIcons[$0] } ?? package.catalogID.flatMap { apps.icons[$0] },
                    name: package.title, category: status?.category ?? .tools,
                    symbol: status == nil ? "shippingbox.fill" : nil)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(package.title)
                        .font(.ui(.headline, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    if let titleID = package.titleID { Chip(text: titleID) }
                    if let badge = status?.compatibility.badge {
                        Chip(text: badge, color: status?.compatibility.blocksInstall == true ? Theme.hot : Theme.warm)
                    }
                }
                Text(subtitle)
                    .font(.ui(.body))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            trailing
            Image(systemName: "chevron.right")
                .font(.ui(.footnote, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText.opacity(hovering ? 1 : 0.5))
                .opacity(status == nil ? 0 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hovering && status != nil ? 0.04 : 0)))
        .contentShape(Rectangle())
        .onTapGesture {
            guard let status else { return }
            withAnimation(.easeInOut(duration: 0.2)) { apps.selectedID = status.id }
        }
        .onHover { hovering = $0 }
        .help(package.path)
    }

    private var subtitle: String {
        var parts = [package.fileName, Format.bytes(package.size)]
        if apps.packagesChecked { parts.append(PackageLibrary.installedLabel(installed)) }
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder private var trailing: some View {
        if let op = apps.operations[package.id] {
            OperationView(operation: op)
        } else if status?.compatibility.blocksInstall == true {
            Label("Doesn't Work", systemImage: "nosign")
                .font(.ui(.footnote, weight: .semibold))
                .foregroundStyle(Theme.hotText)
        } else if installed != nil {
            Button("Reinstall") { apps.install(package) }.buttonStyle(PillButtonStyle(prominent: false))
        } else {
            Button("Install") { apps.install(package) }.buttonStyle(PillButtonStyle(prominent: false))
        }
    }
}

struct OperationView: View {
    let operation: AppsStore.Operation

    var body: some View {
        HStack(spacing: 10) {
            switch operation.stage {
            case .queued:
                Text("Queued").foregroundStyle(Theme.tertiaryText)
            case .downloading:
                Spinner()
                Text("Downloading…").foregroundStyle(Theme.secondaryText)
            case .uploading(let fraction):
                PSProgressBar(fraction: fraction).frame(width: 110)
                Text("\(Int(fraction * 100)) %").foregroundStyle(Theme.secondaryText).monospacedDigit()
            case .waitingForGame:
                Image(systemName: "pause.circle").foregroundStyle(Theme.warm)
                Text("Waiting for the game").foregroundStyle(Theme.warm)
            case .installing:
                Spinner()
                Text("Installing…").foregroundStyle(Theme.secondaryText)
            case .uninstalling:
                Spinner()
                Text("Uninstalling…").foregroundStyle(Theme.secondaryText)
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                Text("Installed").foregroundStyle(Theme.good)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.hot)
                Text(message).foregroundStyle(Theme.hotText).lineLimit(1).frame(maxWidth: 260, alignment: .trailing)
            }
        }
        .font(.ui(.body, weight: .medium))
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
            Text("\(game) is running. The install waits until you quit the game.")
                .font(.ui(.body)).foregroundStyle(Theme.primaryText)
            Spacer()
            Button("Install Anyway", action: force).buttonStyle(PillButtonStyle(tint: Theme.warm))
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
            Text("The app can't find the PS3 folder where packages are archived (_Installed/Packages).")
                .font(.ui(.body)).foregroundStyle(Theme.primaryText)
            Spacer()
            Button("Choose Folder…", action: choose).buttonStyle(PillButtonStyle(tint: Theme.hot))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.hot.opacity(0.1)))
    }
}
