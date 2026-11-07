import Foundation

/// The how-to guides, as Markdown: the app's Help (⌘?) draws them with `ReadmeView`, and
/// `ps3 guide` prints them. The texts are in Guides/GuideTexts.swift. A link between guides is
/// `ps3center://guide/<id>`.
public enum GuideID: String, CaseIterable, Sendable, Identifiable, Codable {
    case gettingStarted = "getting-started"
    case sendGames = "send-games"
    case playFromMac = "play-from-mac"
    case homebrew
    case ownPackages = "own-packages"
    case saves
    case usbDrive = "usb-drive"
    case ps2Classic = "ps2-classic"
    case gameUpdates = "game-updates"
    case troubleshooting
    case cliAndClaude = "cli-and-claude"

    public var id: String { rawValue }
}

public struct Guide: Sendable, Identifiable, Equatable {
    public let id: GuideID
    public let title: String
    /// One line for the list in Help and `ps3 guide`.
    public let summary: String
    /// An SF Symbol for the list in Help.
    public let symbol: String
    public let markdown: String

    public init(id: GuideID, title: String, summary: String, symbol: String, markdown: String) {
        self.id = id
        self.title = title
        self.summary = summary
        self.symbol = symbol
        self.markdown = markdown
    }

    /// The blocks the app draws and the CLI prints, by the README parser.
    public var readme: Readme {
        Readme(markdown: markdown, repo: "guide/\(id.rawValue)", rawBase: nil, htmlBase: nil)
    }

    public static let scheme = "ps3center"

    public var link: URL { URL(string: "\(Self.scheme)://guide/\(id.rawValue)")! }

    /// The guide a `ps3center://guide/<id>` link points to.
    public static func id(from url: URL) -> GuideID? {
        guard url.scheme == scheme, url.host == "guide" else { return nil }
        return GuideID(rawValue: url.lastPathComponent)
    }
}

public enum Guides {
    /// In the order Help lists them.
    public static var all: [Guide] {
        GuideID.allCases.compactMap { id in GuideTexts.all.first { $0.id == id } }
    }

    public static func guide(_ id: GuideID) -> Guide? {
        GuideTexts.all.first { $0.id == id }
    }

    /// For `ps3 guide <name>`: the id ("send-games"), or a title or a word in it ("send").
    public static func named(_ name: String) -> Guide? {
        let wanted = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return nil }
        if let exact = all.first(where: { $0.id.rawValue == wanted || $0.title.lowercased() == wanted }) { return exact }
        return all.first { $0.id.rawValue.hasPrefix(wanted) || $0.title.lowercased().contains(wanted) }
    }

    /// Help's search field: guides whose title, summary or text has every word, best first.
    public static func search(_ query: String) -> [Guide] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return all }
        return all.filter { guide in
            let text = (guide.title + " " + guide.summary + " " + guide.markdown).lowercased()
            return words.allSatisfy(text.contains)
        }
        .sorted { a, b in
            let inTitleA = words.filter(a.title.lowercased().contains).count
            let inTitleB = words.filter(b.title.lowercased().contains).count
            return inTitleA > inTitleB
        }
    }
}

/// Words a new user meets in PS3 Center, explained: the ⓘ buttons in the app, Help's glossary and
/// `ps3 guide glossary`.
public enum Glossary {
    public enum TermID: String, CaseIterable, Sendable, Codable {
        case hen, cfw, webman, xmb
        case titleID = "title-id"
        case gameFolders = "game-folders"
        case pkg
        case appVer = "app-ver"
        case cexDex = "cex-dex"
        case ps2Classic = "ps2-classic"
        case libCrypt = "libcrypt"
        case ird
        case gameServer = "game-server"
        case dynamicFan = "dynamic-fan"
        case ps3Folder = "ps3-folder"
        case rsx, firmware
    }

    public struct Term: Sendable, Identifiable, Equatable {
        public let id: TermID
        public let term: String
        public let definition: String
        /// The guide that says more, if any.
        public let guide: GuideID?

        public init(id: TermID, term: String, definition: String, guide: GuideID?) {
            self.id = id
            self.term = term
            self.definition = definition
            self.guide = guide
        }
    }

    /// In the order of `TermID`.
    public static var terms: [Term] {
        TermID.allCases.compactMap { id in GuideTexts.glossary.first { $0.id == id } }
    }

    public static func term(_ id: TermID) -> Term? {
        GuideTexts.glossary.first { $0.id == id }
    }
}
