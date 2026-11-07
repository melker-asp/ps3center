import AppKit
import PS3Kit
import SwiftUI

/// What Help shows: a guide, the whole glossary, or the glossary at one term (from an ⓘ).
enum HelpItem: Hashable {
    case guide(GuideID)
    case glossary
    case term(Glossary.TermID)
}

/// Help (⌘?, the ? at the top right, Settings → Help and the How? links): the guides on the left
/// with a search field and the glossary last, the text on the right, drawn by the same `ReadmeView`
/// as the READMEs on an app's page. The CLI prints the same texts with `ps3 guide`.
struct HelpView: View {
    @State private var item: HelpItem
    @State private var query = ""
    /// False when rendered for a snapshot: no text field, no scroll view.
    private let live: Bool

    init(item: HelpItem = .guide(.gettingStarted), live: Bool = true) {
        _item = State(initialValue: item)
        self.live = live
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Help")
                .font(.ui(.display, weight: .light))
                .foregroundStyle(Theme.primaryText)
                .padding(.bottom, 20)
            HStack(alignment: .top, spacing: 28) {
                sidebar
                    .frame(width: 280, alignment: .topLeading)
                Group {
                    if live {
                        ScrollViewReader { proxy in
                            ScrollView {
                                content.padding(.bottom, 12).padding(.trailing, 8)
                            }
                            .scrollIndicators(.hidden)
                            .onChange(of: item, initial: true) { _, item in
                                if case .term(let id) = item {
                                    withAnimation { proxy.scrollTo(id, anchor: .top) }
                                } else {
                                    proxy.scrollTo("top", anchor: .top)
                                }
                            }
                        }
                    } else {
                        content
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: live ? .infinity : nil, alignment: .topLeading)
            }
            Spacer(minLength: 20)
            HStack {
                Spacer()
                DoneButton()
            }
        }
        .padding(32)
        .frame(width: 940, height: live ? 700 : nil, alignment: .topLeading)
        .background(Theme.base)
        // Links between guides (ps3center://guide/<id>) open here; the rest in the browser.
        .environment(\.openURL, OpenURLAction { url in
            guard let id = Guide.id(from: url) else { return .systemAction }
            withAnimation(.easeInOut(duration: 0.2)) { item = .guide(id) }
            return .handled
        })
    }

    // MARK: The list

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            SearchField(text: $query, interactive: live, placeholder: "Search the guides")
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 2) {
                let guides = Guides.search(query)
                ForEach(guides) { guide in
                    row(title: guide.title, symbol: guide.symbol, selected: item == .guide(guide.id)) { item = .guide(guide.id) }
                }
                if guides.isEmpty {
                    Text("No guide mentions \u{201C}\(query)\u{201D}.")
                        .font(.ui(.footnote))
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.vertical, 8)
                row(title: "Glossary", symbol: "character.book.closed", selected: isGlossary) { item = .glossary }
            }
        }
    }

    private var isGlossary: Bool {
        switch item {
        case .glossary, .term: return true
        case .guide: return false
        }
    }

    private func row(title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.ui(.callout, weight: .semibold))
                    .foregroundStyle(selected ? Theme.primaryText : Theme.accent)
                    .frame(width: 20)
                Text(title)
                    .font(.ui(.callout, weight: selected ? .bold : .semibold))
                    .foregroundStyle(selected ? Theme.primaryText : Theme.primaryText.opacity(0.75))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(selected ? Color.white.opacity(0.14) : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: The text

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 0).id("top")
            switch item {
            case .guide(let id):
                if let guide = Guides.guide(id) {
                    guideView(guide)
                }
            case .glossary, .term:
                glossary
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func guideView(_ guide: Guide) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(guide.title)
                    .font(.ui(.title, weight: .light))
                    .foregroundStyle(Theme.primaryText)
                Text(guide.summary)
                    .font(.ui(.callout))
                    .foregroundStyle(Theme.secondaryText)
            }
            ReadmeView(readme: guide.readme)
            nextGuide(after: guide)
        }
    }

    /// The next guide in the list, so the guides can be read in order.
    @ViewBuilder private func nextGuide(after guide: Guide) -> some View {
        let all = Guides.all
        if let index = all.firstIndex(of: guide), index + 1 < all.count {
            let next = all[index + 1]
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { item = .guide(next.id) }
            } label: {
                HStack(spacing: 8) {
                    Text("Next: \(next.title)")
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(PillButtonStyle(prominent: false))
            .padding(.top, 12)
        }
    }

    private var glossary: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Glossary")
                    .font(.ui(.title, weight: .light))
                    .foregroundStyle(Theme.primaryText)
                Text("The words PS3 Center uses, in a few sentences each.")
                    .font(.ui(.callout))
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(Glossary.terms) { term in
                termView(term)
                    .id(term.id)
            }
        }
    }

    private func termView(_ term: Glossary.Term) -> some View {
        let highlighted = item == .term(term.id)
        return VStack(alignment: .leading, spacing: 6) {
            Text(term.term)
                .font(.ui(.headline, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
            Text(term.definition)
                .font(.ui(.callout))
                .foregroundStyle(Theme.primaryText.opacity(0.8))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if let guide = term.guide.flatMap(Guides.guide) {
                Button("Read \u{201C}\(guide.title)\u{201D}") {
                    withAnimation(.easeInOut(duration: 0.2)) { item = .guide(guide.id) }
                }
                .buttonStyle(.plain)
                .font(.ui(.footnote, weight: .semibold))
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(highlighted ? Theme.accent.opacity(0.12) : Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(highlighted ? Theme.accent.opacity(0.5) : Theme.cardStroke))
    }
}

/// "How?" under an empty view or an error: opens the guide that explains it.
struct HelpLink: View {
    @Environment(\.openHelp) private var openHelp
    let title: String
    let guide: GuideID
    /// White on the blue splash, where PlayStation blue doesn't read.
    var tint: Color = Theme.accent

    var body: some View {
        Button {
            openHelp(guide)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                Text(title)
            }
        }
        .buttonStyle(.plain)
        .font(.ui(.body, weight: .semibold))
        .foregroundStyle(tint)
        .help("Opens the guide in Help")
    }
}
