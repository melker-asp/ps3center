import Foundation

/// A game on the console, as `ps3 games` and the Spel tab show it.
public struct Game: Codable, Equatable, Sendable, Identifiable {
    public enum Platform: String, Codable, Sendable, CaseIterable {
        case ps3, psn, ps2, ps1, psp, bluRay, dvd

        public var label: String {
            switch self {
            case .ps3: return "PS3"
            case .psn: return "PSN"
            case .ps2: return "PS2"
            case .ps1: return "PS1"
            case .psp: return "PSP"
            case .bluRay: return "Blu-ray"
            case .dvd: return "DVD"
            }
        }

        /// The order games are listed in: PS3 first, films last.
        public var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    }

    /// Where it is on the console: an ISO, a .cue, a game folder or /dev_hdd0/game/<titleID>.
    public var path: String
    public var title: String
    /// "BLES01234" for PS3 games, "SLES-12345" for PS1, PS2 and PSP.
    public var titleID: String?
    public var platform: Platform
    /// Bytes on the console, split parts and .bin tracks included. Nil for folders, whose size
    /// would need a listing of every file in them.
    public var size: Int64?
    public var isFolder: Bool
    /// APP_VER (or VERSION) from PARAM.SFO.
    public var version: String?
    /// An installed update for a disc game: APP_VER in /dev_hdd0/game/<titleID> (CATEGORY GD).
    public var updateVersion: String?
    /// The XMB icon (ICON0, 320×176) and background (PIC1) on the console, when known.
    public var iconPath: String?
    public var backgroundPath: String?
    /// Files that belong to the game besides `path`: split ISO parts (.iso.1 …) and .bin tracks.
    public var companions: [String]

    init(path: String, title: String, titleID: String? = nil, platform: Platform, size: Int64? = nil,
         isFolder: Bool = false, version: String? = nil, iconPath: String? = nil, backgroundPath: String? = nil,
         companions: [String] = []) {
        self.path = path
        self.title = title
        self.titleID = titleID
        self.platform = platform
        self.size = size
        self.isFolder = isFolder
        self.version = version
        self.iconPath = iconPath
        self.backgroundPath = backgroundPath
        self.companions = companions
    }

    public var id: String { path }

    public var region: Region? { titleID.flatMap(Region.init(titleID:)) }

    /// Installed in the XMB (PSN games, PS1/PS2 Classics, minis): started from its icon by title
    /// ID and removed in the XMB, never mounted or deleted by PS3 Center.
    public var isInstalled: Bool { path.hasPrefix("/dev_hdd0/game/") }

    public var isOnUSB: Bool { path.hasPrefix("/dev_usb") }
}

public enum Region: String, Codable, Sendable {
    case europe, usa, japan, asia

    public var label: String {
        switch self {
        case .europe: return "Europa"
        case .usa: return "USA"
        case .japan: return "Japan"
        case .asia: return "Asien"
        }
    }

    /// The third letter of a title ID or serial: BLES, NPEB, SLES and ULES are European, BLUS and
    /// SLUS American, BLJM, SLPS and ULJM Japanese, BLAS, SLKA and NPHB Asian.
    public init?(titleID: String) {
        let id = Array(titleID.uppercased())
        guard id.count >= 5, id[0...3].allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        switch id[2] {
        case "E": self = .europe
        case "U": self = .usa
        case "J", "P": self = .japan
        case "A", "H", "K": self = .asia
        default: return nil
        }
    }
}

public enum TitleID {
    /// "BLES01234" (disc) and "NPUB31234" (PSN). Homebrew IDs such as NP0APOLLO or IRISMAN00 do not match.
    public static func isOfficial(_ id: String) -> Bool {
        ConsoleSnapshot.firstMatch(#"^[BN][A-Z]{3}\d{5}$"#, in: id) != nil
    }

    /// The title ID in a file or folder name, written as the console writes it: "BLES01234" for
    /// PS3 games, "SLES-12345" for the others. Finds "[SLUS-20946]", "SLUS_209.46.Game.iso" and
    /// multiMAN's "BLES01234-[Game]".
    public static func find(in name: String, platform: Game.Platform) -> String? {
        guard let m = ConsoleSnapshot.firstMatch(#"(?:^|[^A-Za-z])([A-Z]{4})[-_ ]?(\d{3})\.?(\d{2})(?!\d)"#, in: name)
        else { return nil }
        let separator = platform == .ps3 || platform == .psn ? "" : "-"
        return m[1] + separator + m[2] + m[3]
    }

    /// "sles_123.45" and "SLES-12345" compare equal.
    static func normalized(_ id: String) -> String {
        id.uppercased().filter { $0.isLetter || $0.isNumber }
    }
}

public enum GameLookup {
    case found(Game)
    case ambiguous([Game])
    case missing
}

extension Game {
    /// Title ID, exact title or path first; then a part of the title ("gran" → Gran Turismo 5).
    public static func lookup(_ query: String, in games: [Game]) -> GameLookup {
        let q = query.trimmingCharacters(in: .whitespaces)
        let id = TitleID.normalized(q)
        let exact = games.filter { game in
            game.titleID.map(TitleID.normalized) == id || game.title.caseInsensitiveCompare(q) == .orderedSame || game.path == q
        }
        let matches = exact.isEmpty
            ? games.filter { $0.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            : exact
        switch matches.count {
        case 0: return .missing
        case 1: return .found(matches[0])
        default: return .ambiguous(matches)
        }
    }
}
