import Foundation

/// The Mac's game folders, one or more per kind: linked in the app or with
/// `ps3 config folder add PS3ISO ~/Games/PS3`, plus the mirror folder's dev_hdd0/<KIND>.
public enum GameFolders {
    public struct Kind: Sendable, Identifiable, Equatable {
        /// The folder's name on the console, also the key in config.json: "PS3ISO", "GAMES" …
        public let name: String
        public let label: String
        public let content: ContentKind

        public var id: String { name }
    }

    public static let kinds: [Kind] = [
        Kind(name: "PS3ISO", label: "PS3 Games (ISO)", content: .ps3ISO),
        Kind(name: "GAMES", label: "PS3 Games (Folders)", content: .ps3Folder),
        Kind(name: "PS2ISO", label: "PS2 Games", content: .ps2ISO),
        Kind(name: "PSXISO", label: "PS1 Games", content: .psxISO),
        Kind(name: "PSPISO", label: "PSP Games", content: .pspISO),
        Kind(name: "BDISO", label: "Blu-ray Movies", content: .bluRayISO),
        Kind(name: "DVDISO", label: "DVD Movies", content: .dvdISO),
    ]

    public static func kind(named name: String) -> Kind? {
        kinds.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Every linked folder with its kind, the mirror's included. A folder on a drive that is not
    /// plugged in stays in the list; `LocalLibrary` skips what it cannot read.
    public static func linked(config: PS3Config = ConfigStore.load(), mirrorRoot: URL? = MirrorRoot.resolve()) -> [(kind: Kind, url: URL)] {
        var result: [(kind: Kind, url: URL)] = []
        var seen = Set<String>()
        for kind in kinds {
            var paths = config.folders?[kind.name] ?? []
            if let mirrorRoot { paths.append(mirrorRoot.appendingPathComponent("dev_hdd0/\(kind.name)").path) }
            for path in paths {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
                guard seen.insert(url.path).inserted else { continue }
                if config.folders?[kind.name]?.contains(path) == true || FileManager.default.fileExists(atPath: url.path) {
                    result.append((kind, url))
                }
            }
        }
        return result
    }

    /// Links `folder` as a source of `kind` games in config.json.
    public static func add(_ folder: URL, as kind: Kind) throws {
        var config = ConfigStore.load()
        var folders = config.folders ?? [:]
        let path = folder.standardizedFileURL.path
        if !(folders[kind.name] ?? []).contains(path) { folders[kind.name, default: []].append(path) }
        config.folders = folders
        try ConfigStore.save(config)
    }

    public static func remove(_ folder: URL, from kind: Kind) throws {
        var config = ConfigStore.load()
        let path = folder.standardizedFileURL.path
        config.folders?[kind.name]?.removeAll { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL.path == path }
        if config.folders?[kind.name]?.isEmpty == true { config.folders?[kind.name] = nil }
        try ConfigStore.save(config)
    }
}

/// The games in the Mac's game folders, read like the console's: the same folder rules
/// (`GameListing`), and titles, title IDs and icons from inside the images.
public struct LocalLibrary: Sendable {
    public init() {}

    public func scan(folders: [(kind: GameFolders.Kind, url: URL)] = GameFolders.linked()) -> [Game] {
        var cache = LocalGameReader.Cache.load()
        var fresh: [String: LocalGameReader.Info] = [:]
        var games: [Game] = []
        for (kind, url) in folders {
            guard let folder = GameListing.folders.first(where: { $0.name == kind.name }),
                  let entries = Self.entries(in: url) else { continue }
            var nested: [String: [FTPClient.Entry]] = [:]
            if !folder.holdsFolders {
                for sub in entries where sub.isDirectory {
                    nested[sub.name] = Self.entries(in: url.appendingPathComponent(sub.name)) ?? []
                }
            }
            let remoteFolder = kind.content.remoteFolder ?? "/dev_hdd0/\(kind.name)"
            for candidate in GameListing.candidates(in: url.path, folder: folder, entries: entries, nested: nested, wmtmp: [:]) {
                var game = candidate.game
                game.source = .mac
                game.remotePath = remoteFolder + "/" + (game.path as NSString).lastPathComponent
                game.netPath = "/" + kind.name + String(game.path.dropFirst(url.path.count))
                game.added = Self.addedDate(of: URL(fileURLWithPath: game.path)) ?? game.added
                let info = cache[candidate.cacheKey] ?? LocalGameReader.read(game)
                fresh[candidate.cacheKey] = info
                if let title = info.title { game.title = title }
                if let titleID = info.titleID { game.titleID = titleID }
                game.version = info.version ?? game.version
                if let icon = info.iconFile { game.iconPath = icon }
                // A folder in GAMES without PS3_GAME/PARAM.SFO is not a game.
                if game.isFolder, info.titleID == nil { continue }
                games.append(game)
            }
        }
        cache = fresh
        LocalGameReader.Cache.save(cache)
        return GameListing.attach([:], to: games)
    }

    /// When the file was put in its folder (Finder's Date Added), else when it was created. A
    /// copy keeps the original's modification date, which would say when the image was made.
    static func addedDate(of url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        return values?.addedToDirectoryDate ?? values?.creationDate
    }

    /// A local folder listed like webMAN's FTP lists one; nil when it cannot be read.
    static func entries(in folder: URL) -> [FTPClient.Entry]? {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                       options: [.skipsHiddenFiles]) else { return nil }
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let modified = values?.contentModificationDate.map { String(Int($0.timeIntervalSince1970)) } ?? ""
            return FTPClient.Entry(name: url.lastPathComponent, size: Int64(values?.fileSize ?? 0),
                                   isDirectory: values?.isDirectory ?? false, modified: modified)
        }
    }
}

/// Titles, title IDs, versions and icons from inside the Mac's images: PARAM.SFO and ICON0 for
/// PS3 and PSP, SYSTEM.CNF for PS2 and PS1 (also in raw .bin images, through a .cue).
enum LocalGameReader {
    struct Info: Codable, Equatable {
        var title: String?
        var titleID: String?
        var version: String?
        /// ICON0 copied out of the image to the Mac's cache.
        var iconFile: String?
    }

    static func read(_ game: Game) -> Info {
        let url = URL(fileURLWithPath: game.path)
        var info = Info()
        var icon: Data?
        if game.isFolder {
            let sfo = (try? Data(contentsOf: url.appendingPathComponent("PS3_GAME/PARAM.SFO"))).flatMap(ParamSFO.init(data:))
            info.title = sfo?.title
            info.titleID = sfo?.titleID
            info.version = sfo?.appVersion
            return info  // ICON0 is read from the folder itself (`iconPath`).
        }
        guard let image = try? ISOImage(url: imageFile(for: url)) else { return info }
        switch game.platform {
        case .ps3, .psn:
            let sfo = (try? image.readFile("PS3_GAME/PARAM.SFO")).flatMap(ParamSFO.init(data:))
            info.title = sfo?.title
            info.titleID = sfo?.titleID
            info.version = sfo?.appVersion
            icon = try? image.readFile("PS3_GAME/ICON0.PNG")
        case .psp:
            let sfo = (try? image.readFile("PSP_GAME/PARAM.SFO")).flatMap(ParamSFO.init(data:))
            info.title = sfo?.title
            let umd = (try? image.readFile("UMD_DATA.BIN")).flatMap { String(data: $0.prefix(10), encoding: .ascii) }
            if let disc = sfo?.string("DISC_ID") ?? umd {
                info.titleID = serial(from: disc)
            }
            icon = try? image.readFile("PSP_GAME/ICON0.PNG")
        case .ps2, .ps1:
            let cnf = (try? image.readFile("SYSTEM.CNF")).map { String(decoding: $0, as: UTF8.self) } ?? ""
            info.titleID = serial(from: cnf)
        case .bluRay, .dvd:
            break
        }
        if let icon, !icon.isEmpty {
            let file = GameLibraryService.cacheDirectory("mac-icons").appendingPathComponent(AppsService.md5(Data(game.path.utf8)) + ".png")
            if (try? icon.write(to: file, options: .atomic)) != nil { info.iconFile = file.path }
        }
        return info
    }

    /// The file that holds the image: a .cue points at its first .bin.
    static func imageFile(for url: URL) -> URL {
        guard url.pathExtension.lowercased() == "cue", let text = try? String(contentsOf: url, encoding: .utf8),
              let name = ConsoleSnapshot.firstMatch(#"FILE\s+"([^"]+)""#, in: text)?[1] else { return url }
        return url.deletingLastPathComponent().appendingPathComponent(name)
    }

    /// "cdrom0:\SLES_533.26;1" or "ULES00995" -> "SLES-53326", "ULES-00995".
    static func serial(from text: String) -> String? {
        guard let m = ConsoleSnapshot.firstMatch(#"([A-Z]{4})[_-]?(\d{3})\.?(\d{2})"#, in: text.uppercased()) else { return nil }
        return "\(m[1])-\(m[2])\(m[3])"
    }

    /// Read details per file (path, size and date), in ~/Library/Caches/ps3center/mac-games.json.
    enum Cache {
        static var file: URL {
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/ps3center/mac-games.json")
        }

        static func load() -> [String: Info] {
            guard let data = try? Data(contentsOf: file) else { return [:] }
            return (try? JSONDecoder().decode([String: Info].self, from: data)) ?? [:]
        }

        static func save(_ cache: [String: Info]) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(cache).write(to: file, options: .atomic)
        }
    }
}

/// Whether the Mac's games are on the console.
public enum MacGameState: String, Codable, Sendable {
    case notOnConsole, onConsole, partial

    public var label: String {
        switch self {
        case .notOnConsole: return "Only on Mac"
        case .onConsole: return "On PS3"
        case .partial: return "Partly Sent"
        }
    }
}

public enum LibraryMatch {
    /// For each Mac game by id: on the console when a game there has the same title ID (PS3 and
    /// PSN counting as one), or a file with the same name; partly when that file is smaller.
    public static func states(mac: [Game], console: [Game]) -> [String: MacGameState] {
        var byID: [String: Game] = [:]
        var byName: [String: Game] = [:]
        for game in console {
            if let id = game.titleID { byID["\(game.platform.family.rawValue)-\(TitleID.normalized(id))"] = game }
            byName[(game.path as NSString).lastPathComponent.lowercased()] = game
        }
        var result: [String: MacGameState] = [:]
        for game in mac {
            let name = (game.path as NSString).lastPathComponent.lowercased()
            if let id = game.titleID, byID["\(game.platform.family.rawValue)-\(TitleID.normalized(id))"] != nil {
                result[game.id] = .onConsole
            } else if let remote = byName[name] {
                result[game.id] = (remote.size ?? 0) < (game.size ?? 0) ? .partial : .onConsole
            } else {
                result[game.id] = .notOnConsole
            }
        }
        return result
    }
}

extension Game {
    /// The uploads that put a game from the Mac on the console: the image with its split parts
    /// or tracks, or the whole game folder, in the folder of its kind.
    public func routes() throws -> [Route] {
        guard source == .mac, let remotePath else { throw PS3Error.refused("\(title) is not on the Mac.") }
        let folder = (remotePath as NSString).deletingLastPathComponent
        let files = ([path] + companions).map { URL(fileURLWithPath: $0) }
        return try FileRouter.routes(for: files, mirrorRoot: nil, remoteFolder: folder).map { route in
            Route(local: route.local, remote: route.remote, kind: route.kind, size: route.size, title: title)
        }
    }
}
