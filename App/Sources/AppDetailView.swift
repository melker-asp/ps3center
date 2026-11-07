import AppKit
import PS3Kit
import SwiftUI

/// One program up close, opened by clicking its row: versions, whether it runs on this
/// console (HEN/CFW, CEX/DEX, firmware) and its README with images from GitHub.
struct AppDetailView: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(AppsStore.self) private var apps
    @Environment(\.openURL) private var openURL
    let status: AppStatus
    var scrolls = true
    @State private var confirmingUninstall = false

    private var entry: CatalogEntry? { AppsStore.entry(for: status) }

    private var profile: ConsoleProfile {
        console.snapshot.map(ConsoleProfile.init(snapshot:)) ?? ConsoleProfile()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            backButton
            if scrolls {
                ScrollView { content }.scrollIndicators(.hidden)
            } else {
                content
            }
        }
        .task(id: status.id) {
            guard let entry else { return }
            await apps.loadReadme(for: entry)
            await apps.loadBackground(for: entry)
        }
    }

    private var backButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { apps.selectedID = nil }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                Text("Apps")
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
            cards
            if let note = status.note, !status.noteIsCompatibility {
                NoteBanner(text: note)
            }
            readmeSection
        }
        .padding(.bottom, 16)
    }

    // MARK: Header

    /// A banner like the PS Store's: the app's own XMB background (PIC1.PNG) when it is
    /// installed, else the README's first picture, else the category colour.
    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            HeroBackdrop(image: apps.backgrounds[status.id], url: firstReadmeImage, tint: AppIcon.tint(for: status.category))
            LinearGradient(colors: [Color.black.opacity(0.05), Color.black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
            headerContent.padding(24)
        }
        .frame(height: 290)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.cardStroke))
    }

    private var firstReadmeImage: URL? {
        guard case .some(.loaded(let readme)) = readmeState else { return nil }
        for block in readme.blocks { if case .image(let image) = block { return image.url } }
        return nil
    }

    private var headerContent: some View {
        HStack(alignment: .bottom, spacing: 22) {
            AppIcon(image: apps.icons[status.id], name: status.name, category: status.category,
                    symbol: AppRow.symbols[status.id], size: CGSize(width: 160, height: 88))
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(status.name)
                        .font(.ui(.display, weight: .light))
                        .foregroundStyle(Theme.primaryText)
                    Chip(text: status.category.label)
                    if let badge = status.compatibility.badge {
                        Chip(text: badge, color: compatibilityColor)
                    }
                }
                Text(status.summary)
                    .font(.ui(.callout))
                    .foregroundStyle(Color.white.opacity(0.75))
                HStack(spacing: 10) {
                    action
                    if status.state == .updateAvailable, apps.operations[status.id] == nil {
                        Button(status.ignored ? "Stop Ignoring" : "Ignore") {
                            if status.ignored { apps.unignore(status) } else { apps.ignore(status) }
                        }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .help(status.ignored ? "Show the update again" : "Skip \(status.latestForDisplay ?? "this version"). A newer version shows up again.")
                    }
                    if let url = sourceURL {
                        Button(entry?.repository == nil ? "Open Page" : "Open on GitHub") { openURL(url) }
                            .buttonStyle(PillButtonStyle(prominent: false))
                    }
                    if canUninstall {
                        // Apart from the other buttons, and red.
                        Spacer(minLength: 24)
                        Button("Uninstall…") { confirmingUninstall = true }
                            .buttonStyle(PillButtonStyle(destructive: true))
                    }
                }
                .padding(.top, 4)
                .confirmationDialog("Uninstall \(status.name)?", isPresented: $confirmingUninstall, titleVisibility: .visible) {
                    Button("Uninstall", role: .destructive) { apps.uninstall(status) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The app is removed from the PS3's hard drive (/dev_hdd0/game/\(entry?.titleID ?? "")). Its saves stay, and you can install it again from here. The icon may stay in the XMB until the PS3 restarts.")
                }
            }
            Spacer()
        }
    }

    @ViewBuilder private var action: some View {
        if let op = apps.operations[status.id] {
            OperationView(operation: op)
        } else if status.canInstall {
            Button("Update to \(status.latestForDisplay ?? "Latest")") { apps.install(status) }
                .buttonStyle(PillButtonStyle())
        } else if status.installed == nil, status.installable {
            Button("Install") { apps.install(status) }
                .buttonStyle(PillButtonStyle())
        } else if status.blocked {
            Label("Doesn't work on your PS3", systemImage: "nosign")
                .font(.ui(.body, weight: .semibold))
                .foregroundStyle(Theme.hotText)
        } else if let installed = status.installed {
            Label("Installed \(installed)", systemImage: "checkmark")
                .font(.ui(.body, weight: .semibold))
                .foregroundStyle(Theme.good)
        }
    }

    /// Apps installed from a package; HEN, webMAN and plugins are not removed from here.
    private var canUninstall: Bool {
        guard status.installed != nil, status.category != .system, entry?.titleID != nil else { return false }
        if let op = apps.operations[status.id], !op.isFailed { return false }
        return true
    }

    private var sourceURL: URL? {
        URL(string: entry?.repository.map { "https://github.com/\($0)" } ?? status.homepage)
    }

    // MARK: Cards

    private var cards: some View {
        HStack(spacing: 14) {
            Card(icon: "shippingbox.fill", title: "Version", chip: stateLabel) {
                BigValue(value: status.installed ?? "–")
                Footnote(text: versionFootnote)
            }
            Card(icon: "checkmark.shield.fill", title: "Your PS3", chip: profile.exploit?.label, chipColor: compatibilityColor) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: compatibilitySymbol).foregroundStyle(compatibilityColor)
                    Text(compatibilityTitle)
                        .font(.ui(.title2, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                }
                Text(compatibilityDetail)
                    .font(.ui(.body))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Footnote(text: profile.label)
            }
            Card(icon: "chevron.left.forwardslash.chevron.right", title: "Source", chip: entry?.repository == nil ? "Link" : "GitHub") {
                Text(entry?.repository ?? "Brewology")
                    .font(.ui(.title3, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Footnote(text: sourceFootnote)
            }
        }
        .frame(height: 192)
    }

    private var stateLabel: String {
        if status.ignored { return "Ignored" }
        switch status.state {
        case .updateAvailable: return "Update"
        case .upToDate: return "Up to Date"
        case .notInstalled: return "Not Installed"
        case .manual: return "Manual"
        case .error: return "Error"
        }
    }

    private var versionFootnote: String {
        if let latest = status.latest {
            // "Latest: 02.41 (v2.4.1)": the console's form first, the release tag after it.
            let shown = status.latestForDisplay ?? latest
            let tag = shown == latest ? "" : " (\(latest))"
            return "Latest: \(shown)\(tag)" + (status.ignored ? ", ignored" : "")
        }
        if entry?.tracksUpdates == false { return "Comes with webMAN MOD's release" }
        return status.state == .manual ? "Check the version on its page" : "No version info"
    }

    private var sourceFootnote: String {
        guard let entry else { return "" }
        if entry.category == .webmanAddons { return "Part of webMAN MOD's package" }
        switch entry.source {
        case .github: return "Downloaded from GitHub releases"
        case .henSource: return "Version from HEN's source code"
        case .manual: return "Link only, not downloaded automatically"
        }
    }

    private var compatibilityColor: Color {
        switch status.compatibility.verdict {
        case .compatible: return Theme.good
        case .untested, .unknown: return Theme.warm
        case .incompatible: return Theme.hot
        }
    }

    private var compatibilitySymbol: String {
        switch status.compatibility.verdict {
        case .compatible: return "checkmark.circle.fill"
        case .untested: return "exclamationmark.triangle.fill"
        case .incompatible: return "nosign"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private var compatibilityTitle: String {
        switch status.compatibility.verdict {
        case .compatible: return "Works"
        case .untested: return "Untested"
        case .incompatible: return "Doesn't Work"
        case .unknown: return "Unknown"
        }
    }

    private var compatibilityDetail: String {
        status.compatibility.verdict == .compatible
            ? entry?.requirements.summary ?? ""
            : status.compatibility.summary
    }

    // MARK: README

    private var readmeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.ui(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("README")
                    .font(.ui(.caption, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(Theme.primaryText.opacity(0.85))
                if let repo = entry?.repository {
                    Text(repo).font(.ui(.footnote)).foregroundStyle(Theme.tertiaryText)
                }
                Spacer()
                if case .loaded(let readme) = readmeState, let url = readme.htmlURL {
                    Button("View on GitHub") { openURL(url) }
                        .buttonStyle(.plain)
                        .font(.ui(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            if entry?.category == .webmanAddons {
                Text("The add-on is part of webMAN MOD, so the README describes the whole project.")
                    .font(.ui(.footnote))
                    .foregroundStyle(Theme.tertiaryText)
            }
            switch readmeState {
            case nil where entry?.repository == nil:
                Text("The app isn't on GitHub, so there is no README to show.")
                    .font(.ui(.body))
                    .foregroundStyle(Theme.secondaryText)
            case nil, .some(.loading):
                // nil with a repo: the fetch starts when the page appears.
                HStack(spacing: 10) {
                    Spinner()
                    Text("Loading the README from GitHub…").font(.ui(.body)).foregroundStyle(Theme.secondaryText)
                }
            case .some(.failed(let message)):
                HStack(spacing: 12) {
                    Text(message).font(.ui(.body)).foregroundStyle(Theme.secondaryText)
                    Button("Try Again") {
                        if let entry { Task { await apps.loadReadme(for: entry) } }
                    }
                    .buttonStyle(PillButtonStyle(prominent: false))
                }
            case .some(.loaded(let readme)):
                ReadmeView(readme: readme)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardStroke))
    }

    private var readmeState: AppsStore.ReadmeState? {
        entry?.repository.flatMap { apps.readmes[$0] }
    }
}

/// The banner picture, filling its frame; the category colour while nothing has loaded.
struct HeroBackdrop: View {
    let image: NSImage?
    let url: URL?
    let tint: Color
    @State private var remote: NSImage?

    var body: some View {
        Group {
            if let picture = image ?? remote {
                Color.clear.overlay(Image(nsImage: picture).resizable().aspectRatio(contentMode: .fill))
            } else {
                FacetBackground(tint: tint, intensity: 1)
            }
        }
        .task(id: url) {
            guard image == nil, let url, let response = try? await URLSession.shared.data(from: url) else { return }
            remote = NSImage(data: response.0)
        }
    }
}

struct NoteBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill").foregroundStyle(Theme.warm)
            Text(text)
                .font(.ui(.body))
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.warm.opacity(0.1)))
    }
}

/// Draws a parsed README: headings, text with links, lists, quotes, code, tables and images.
struct ReadmeView: View {
    let readme: Readme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(readme.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
        .tint(Theme.cool)
    }

    @ViewBuilder private func blockView(_ block: Readme.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.inline(text))
                .font(.system(size: Self.headingSize(level), weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .padding(.top, level <= 2 ? 10 : 4)
        case .paragraph(let text):
            Text(Self.inline(text))
                .font(.ui(.callout))
                .foregroundStyle(Theme.primaryText.opacity(0.8))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered && item.depth == 0 ? "\(index + 1)." : "•")
                            .foregroundStyle(Theme.tertiaryText)
                            .monospacedDigit()
                        Text(Self.inline(item.text))
                            .foregroundStyle(Theme.primaryText.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.depth) * 18)
                }
            }
            .font(.ui(.callout))
        case .quote(let text):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.accent.opacity(0.8)).frame(width: 3)
                Text(Self.inline(text))
                    .font(.ui(.callout))
                    .foregroundStyle(Theme.primaryText.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent.opacity(0.08)))
        case .code(let code):
            // Wraps instead of scrolling sideways: a nested scroll view fights the page's, and
            // ImageRenderer cannot draw one.
            Text(code)
                .font(.ui(.footnote, design: .monospaced))
                .foregroundStyle(Theme.primaryText.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.25)))
        case .image(let image):
            ReadmeImage(image: image)
        case .table(let rows):
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(Self.inline(cell))
                                .font(.ui(.body, weight: index == 0 ? .semibold : .regular))
                                .foregroundStyle(index == 0 ? Theme.primaryText : Theme.primaryText.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if index == 0 {
                        Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.03)))
        case .rule:
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    static func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 22
        case 2: return 18
        case 3: return 16
        default: return 15
        }
    }

    /// The parser keeps inline Markdown (bold, code, links), which AttributedString renders.
    static func inline(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }
}

/// A README image at its own size (never scaled up), shrunk to fit; clicking follows its link.
struct ReadmeImage: View {
    let image: Readme.Image
    @Environment(\.openURL) private var openURL
    @State private var loaded: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let loaded {
                Image(nsImage: loaded)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: min(loaded.size.width, 720), maxHeight: min(loaded.size.height, 420), alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .help(image.alt)
                    .onTapGesture { if let link = image.link { openURL(link) } }
            } else if !failed {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 320, height: 180)
                    .overlay(Spinner())
            }
        }
        .task(id: image.url) {
            guard let response = try? await URLSession.shared.data(from: image.url), let picture = NSImage(data: response.0) else {
                failed = true
                return
            }
            loaded = picture
        }
    }
}
