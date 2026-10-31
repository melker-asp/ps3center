import Foundation

/// The games on the console: webMAN's game folders on the internal disk and USB drives, and
/// games installed in /dev_hdd0/game. Titles and title IDs come from PARAM.SFO (in game folders,
/// or the copy webMAN keeps of each ISO's in /dev_hdd0/tmp/wmtmp), cached on the Mac by path,
/// size and date, so a second scan is only listings.
public struct GameLibraryService: Sendable {
    public let host: String
    public var webman: WebMAN { WebMAN(host: host) }

    public init(host: String) { self.host = host }

    static let wmtmp = "/dev_hdd0/tmp/wmtmp"

    // MARK: Scan

    /// All games, sorted by platform and title. `events` gets each folder as it is read;
    /// `refresh` reads every PARAM.SFO again instead of using the cache.
    public func scan(refresh: Bool = false, events: @Sendable (String) -> Void = { _ in }) async throws -> [Game] {
        let cached = refresh ? [:] : GameCache.load()
        var fresh: [String: GameCache.Info] = [:]
        let games = try await TransferService(host: host).withFTP { ftp -> [Game] in
            let root = (try? await ftp.list("/")) ?? []
            let usb = root.filter { $0.isDirectory && $0.name.hasPrefix("dev_usb") }.map { "/" + $0.name }.sorted()
            let wmtmp = GameListing.names((try? await ftp.list(Self.wmtmp)) ?? [])

            var candidates: [GameListing.Candidate] = []
            for device in ["/dev_hdd0"] + usb {
                for folder in GameListing.folders {
                    let dir = device + "/" + folder.name
                    let entries = try await ftp.list(dir)
                    guard !entries.isEmpty else { continue }
                    events(dir)
                    var nested: [String: [FTPClient.Entry]] = [:]
                    if !folder.holdsFolders {
                        for sub in entries where sub.isDirectory {
                            nested[sub.name] = try await ftp.list(dir + "/" + sub.name)
                        }
                    }
                    candidates += GameListing.candidates(in: dir, folder: folder, entries: entries, nested: nested, wmtmp: wmtmp)
                }
            }
            events("/dev_hdd0/game")
            candidates += try await ftp.list("/dev_hdd0/game")
                .filter { $0.isDirectory && GameListing.isGame(titleID: $0.name) }
                .map(GameListing.installedCandidate)

            var games: [Game] = []
            var updates: [String: String] = [:]
            for candidate in candidates {
                var info = cached[candidate.cacheKey]
                if info == nil, let sfoPath = candidate.sfoPath {
                    let sfo = try await ftp.download(sfoPath, limit: 64 << 10).flatMap(ParamSFO.init(data:))
                    info = GameCache.Info(sfo: sfo)
                }
                if let info { fresh[candidate.cacheKey] = info }
                if let game = GameListing.resolve(candidate, info: info, updates: &updates) { games.append(game) }
            }
            return GameListing.attach(updates, to: games)
        }
        GameCache.save(fresh)
        // A game whose PARAM.SFO could not be read is named by its title ID; aldostools' title
        // list usually knows it.
        guard games.contains(where: TitleDatabase.needsName) else { return games }
        return await TitleDatabase.load().named(games)
    }

    // MARK: Pictures

    /// XMB icons by game id, cached on disk like the apps' icons. A game whose icon turned out
    /// not to exist gets an empty file, so it is not asked for again; `refresh` asks anyway.
    public func icons(for games: [Game], refresh: Bool = false) async -> [String: Data] {
        let cache = Self.cacheDirectory("game-icons")
        var result: [String: Data] = [:]
        var missing: [(id: String, remote: String, file: URL)] = []
        for game in games {
            guard let remote = game.iconPath else { continue }
            let file = cache.appendingPathComponent(AppsService.md5(Data(remote.utf8)) + ".png")
            if !refresh, let data = try? Data(contentsOf: file) {
                if !data.isEmpty { result[game.id] = data }
            } else {
                missing.append((game.id, remote, file))
            }
        }
        guard !missing.isEmpty else { return result }
        _ = try? await TransferService(host: host).withFTP { ftp in
            for item in missing {
                let data = try await ftp.download(item.remote, limit: 2 << 20)
                try? (data ?? Data()).write(to: item.file)
                if let data { result[item.id] = data }
            }
        }
        return result
    }

    /// The XMB background (PIC1.PNG, 1920×1080), cached on disk like the icons.
    public func background(for game: Game) async -> Data? {
        guard let remote = game.backgroundPath else { return nil }
        let file = Self.cacheDirectory("game-backgrounds").appendingPathComponent(AppsService.md5(Data(remote.utf8)) + ".png")
        if let data = try? Data(contentsOf: file) { return data.isEmpty ? nil : data }
        do {
            let data = try await TransferService(host: host).withFTP { ftp in try await ftp.download(remote, limit: 8 << 20) }
            try? (data ?? Data()).write(to: file)
            return data
        } catch {
            return nil  // not reachable now; try again next time
        }
    }

    static func cacheDirectory(_ name: String) -> URL {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/ps3center/\(name)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Start, mount, quit

    /// Starts a game. ISOs and game folders are mounted and started like the disc icon
    /// (/play.ps3/<path>); installed games start from their XMB icon (/play.ps3?<titleID>).
    /// A running game is quit first when `exitingRunning`, otherwise it is an error.
    public func play(_ game: Game, exitingRunning: Bool = false) async throws {
        try await quitRunningGame(allowed: exitingRunning)
        if game.isInstalled, let titleID = game.titleID {
            try await webman.get("/play.ps3?" + titleID, timeout: 30)
        } else {
            try await webman.get("/play.ps3" + game.path, timeout: 30)
        }
        OperationLog.record("play", game.path)
    }

    /// Mounts a game as /dev_bdvd without starting it, so it can be started from the XMB.
    public func mount(_ game: Game, exitingRunning: Bool = false) async throws {
        guard !game.isInstalled else {
            throw PS3Error.refused("\(game.title) är installerat i XMB:n och monteras inte. Starta det i stället.")
        }
        try await quitRunningGame(allowed: exitingRunning)
        try await webman.get("/mount.ps3" + game.path, timeout: 30)
        OperationLog.record("mount", game.path)
    }

    public func unmount() async throws {
        try await webman.get("/mount.ps3/unmount", timeout: 30)
        OperationLog.record("unmount", "/dev_bdvd")
    }

    /// Quits the running game or app to the XMB and waits until it is gone.
    /// Returns its name, or nil when only the XMB was running.
    @discardableResult
    public func exitGame() async throws -> String? {
        guard let process = try await webman.runningProcess() else { return nil }
        let name = (try? await webman.snapshot().mountedGameName) ?? process
        try await webman.get("/xmb.ps3$exit", timeout: 30)
        try await waitForXMB()
        OperationLog.record("exit", name)
        return name
    }

    private func quitRunningGame(allowed: Bool) async throws {
        guard try await webman.runningProcess() != nil else { return }
        guard allowed else { throw PS3Error.gameRunning }
        try await exitGame()
    }

    /// Polls until only the XMB runs, then gives the XMB a moment before it takes a new game.
    private func waitForXMB(timeout: TimeInterval = 40) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while try await webman.runningProcess() != nil {
            guard Date() < deadline else { throw PS3Error.timeout("spelet avslutades inte inom \(Int(timeout)) sekunder") }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        try await Task.sleep(nanoseconds: 3_000_000_000)
    }

    // MARK: Delete

    /// Removes a game's files (an ISO with its split parts or tracks, or a game folder), then
    /// refreshes the game list. An installed game is uninstalled: its folder in /dev_hdd0/game
    /// goes, its saves stay. A game that is running is never touched, and nothing HEN needs.
    public func delete(_ game: Game, options: TransferOptions, events: TransferHandler) async throws {
        if game.isInstalled, let refusal = UninstallGuard.refusal(titleID: game.titleID, title: game.title, path: game.path) {
            throw PS3Error.refused(refusal)
        }
        let snapshot = try await webman.snapshot()
        let mounted = snapshot.mountedGamePath == game.path
        if mounted, snapshot.isGameRunning {
            throw PS3Error.refused("\(game.title) körs. Avsluta spelet först.")
        }
        // An installed game runs from its folder without being mounted, so nothing may run.
        if game.isInstalled, snapshot.isGameRunning {
            throw PS3Error.refused("Ett spel körs. Avsluta det först, så att \(game.title) inte används medan det tas bort.")
        }
        let files = game.isFolder ? [game.path] : [game.path] + game.companions
        if options.dryRun {
            for file in files { events(.note("Skulle ta bort \(file)")) }
            return
        }
        if mounted { try await webman.get("/mount.ps3/unmount", timeout: 30) }
        try await TransferService(host: host).withFTP { ftp in
            if game.isFolder {
                try await ftp.removeTree(game.path)
            } else {
                for file in files { try await ftp.delete(file) }
            }
        }
        OperationLog.record(game.isInstalled ? "uninstall" : "delete", game.path + (game.size.map { " (\(Format.bytes($0)))" } ?? ""))
        if game.isInstalled {
            let reload = await XMBReload.afterRemoval(host: host)
            events(.note("\(game.title) är avinstallerat. Sparfilerna ligger kvar. \(reload)"))
        } else {
            events(.note("\(game.title) är borttaget från PS3:an"))
        }
        guard options.refresh else { return }
        try await TransferService(host: host).waitUntilIdle(force: options.force, events: events)
        try await webman.refreshGames()
        events(.refreshed)
    }
}

/// What PS3 Center will not uninstall: anything but a folder directly in /dev_hdd0/game, and
/// what HEN needs to be enabled (without HEN, webMAN does not start and PS3 Center cannot reach
/// the console).
public enum UninstallGuard {
    public static func refusal(titleID: String?, title: String, path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.count == 3, parts[0] == "dev_hdd0", parts[1] == "game" else {
            return "\(title) ligger inte direkt i /dev_hdd0/game och avinstalleras inte härifrån."
        }
        let name = title.uppercased()
        if name.contains("PS3HEN") || name.range(of: #"\bHEN\b"#, options: .regularExpression) != nil || titleID == "PS3XPLOIT" {
            return "\(title) behövs för att aktivera HEN, och utan HEN startar inte webMAN. PS3 Center tar inte bort det."
        }
        return nil
    }
}

/// Turns listings of webMAN's game folders into games. No network, so tests can feed it listings.
enum GameListing {
    struct Folder {
        let name: String
        let platform: Game.Platform
        /// GAMES and GAMEZ hold one folder per game (PS3_GAME/…); the others hold image files,
        /// flat or one subfolder deep, as webMAN reads them.
        var holdsFolders = false
        var extensions: [String] = []
    }

    static let folders: [Folder] = [
        Folder(name: "PS3ISO", platform: .ps3, extensions: [".iso", ".iso.0"]),
        Folder(name: "GAMES", platform: .ps3, holdsFolders: true),
        Folder(name: "GAMEZ", platform: .ps3, holdsFolders: true),
        Folder(name: "PS2ISO", platform: .ps2, extensions: [".iso", ".bin.enc", ".cue", ".bin", ".img", ".mdf"]),
        Folder(name: "PSXISO", platform: .ps1, extensions: [".cue", ".bin", ".iso", ".img", ".mdf"]),
        Folder(name: "PSPISO", platform: .psp, extensions: [".iso", ".cso"]),
        Folder(name: "BDISO", platform: .bluRay, extensions: [".iso"]),
        Folder(name: "DVDISO", platform: .dvd, extensions: [".iso"]),
    ]

    /// multiMAN borrows an official-looking title ID.
    static let homebrewIDs: Set<String> = ["BLES80608"]

    struct Candidate {
        var game: Game
        /// PARAM.SFO with the title and title ID: in the game's folder, or webMAN's copy of an ISO's.
        var sfoPath: String?
        /// Path, size and listing date: while they match, the cached PARAM.SFO details still hold.
        var cacheKey: String
    }

    /// File names in a folder by their lowercase form (paths on the console are case-sensitive).
    static func names(_ entries: [FTPClient.Entry]) -> [String: String] {
        Dictionary(entries.map { ($0.name.lowercased(), $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    static func candidates(in dir: String, folder: Folder, entries: [FTPClient.Entry],
                           nested: [String: [FTPClient.Entry]], wmtmp: [String: String]) -> [Candidate] {
        if folder.holdsFolders {
            return entries.filter(\.isDirectory).sorted { $0.name < $1.name }.map { entry in
                let path = dir + "/" + entry.name
                let game = Game(path: path, title: GameName.clean(entry.name), titleID: TitleID.find(in: entry.name, platform: .ps3),
                                platform: .ps3, isFolder: true, iconPath: path + "/PS3_GAME/ICON0.PNG",
                                backgroundPath: path + "/PS3_GAME/PIC1.PNG")
                return Candidate(game: game, sfoPath: path + "/PS3_GAME/PARAM.SFO", cacheKey: path + "|" + entry.modified)
            }
        }
        var result = images(in: dir, files: entries.filter { !$0.isDirectory }, folder: folder, wmtmp: wmtmp)
        for (name, files) in nested.sorted(by: { $0.key < $1.key }) {
            result += images(in: dir + "/" + name, files: files.filter { !$0.isDirectory }, folder: folder, wmtmp: wmtmp)
        }
        return result
    }

    /// Image files in one folder. Split parts (.iso.1 …) and the .bin tracks of a .cue join the
    /// file that starts them, so each game is listed once.
    static func images(in dir: String, files: [FTPClient.Entry], folder: Folder, wmtmp: [String: String]) -> [Candidate] {
        let beside = names(files)
        let cues = files.map { $0.name.lowercased() }.filter { $0.hasSuffix(".cue") }.map { String($0.dropLast(4)) }
        var result: [Candidate] = []
        for file in files.sorted(by: { $0.name < $1.name }) {
            let lower = file.name.lowercased()
            guard let ext = folder.extensions.first(where: { lower.hasSuffix($0) }) else { continue }
            if ext == ".bin", cues.contains(where: { isTrack(lower, ofCue: $0) }) { continue }

            var size = file.size
            var companions: [String] = []
            if ext == ".iso.0" {
                let stem = String(file.name.dropLast())  // "Game.iso."
                for part in files where part.name != file.name && part.name.hasPrefix(stem) && Int(part.name.dropFirst(stem.count)) != nil {
                    companions.append(dir + "/" + part.name)
                    size += part.size
                }
            } else if ext == ".cue" {
                let base = String(lower.dropLast(4))
                for track in files where isTrack(track.name.lowercased(), ofCue: base) {
                    companions.append(dir + "/" + track.name)
                    size += track.size
                }
            }

            let path = dir + "/" + file.name
            var game = Game(path: path, title: GameName.clean(file.name), titleID: TitleID.find(in: file.name, platform: folder.platform),
                            platform: folder.platform, size: size, companions: companions.sorted())
            // webMAN names its copies after the file without its extension; a picture can also lie beside the file.
            let stems = Self.stems(of: lower)
            if let icon = stems.lazy.compactMap({ wmtmp[$0 + ".png"] }).first {
                game.iconPath = GameLibraryService.wmtmp + "/" + icon
            } else if let icon = stems.lazy.compactMap({ beside[$0 + ".png"] ?? beside[$0 + ".jpg"] }).first {
                game.iconPath = dir + "/" + icon
            }
            let sfo = folder.platform == .ps3 ? stems.lazy.compactMap({ wmtmp[$0 + ".sfo"] }).first : nil
            result.append(Candidate(game: game, sfoPath: sfo.map { GameLibraryService.wmtmp + "/" + $0 },
                                    cacheKey: "\(path)|\(size)|\(file.modified)"))
        }
        return result
    }

    /// Whether a lowercase .bin name is a track of the .cue with this lowercase stem: "game.bin" or
    /// "game (track 2).bin". "game 2.bin" is another game: tracks are deleted with their game, so
    /// a name that is not clearly a track never counts as one.
    static func isTrack(_ bin: String, ofCue cue: String) -> Bool {
        guard bin.hasSuffix(".bin"), bin.hasPrefix(cue) else { return false }
        let rest = String(bin.dropFirst(cue.count).dropLast(4))
        return rest.isEmpty || rest.range(of: #"^[ ._-]*\(?track[ ._-]*\d+\)?$"#, options: .regularExpression) != nil
    }

    /// "game.dec.iso" → ["game.dec.iso", "game.dec", "game"]: the names webMAN and covers use.
    static func stems(of lowercasedName: String) -> [String] {
        var stems = [lowercasedName, (lowercasedName as NSString).deletingPathExtension]
        for ext in [".dec.iso", ".iso.0", ".bin.enc", ".iso", ".cso", ".cue", ".bin", ".img", ".mdf"] where lowercasedName.hasSuffix(ext) {
            stems.append(String(lowercasedName.dropLast(ext.count)))
            break
        }
        var seen = Set<String>()
        return stems.filter { seen.insert($0).inserted }
    }

    /// Official title IDs, minus the homebrew in the catalog and multiMAN.
    static func isGame(titleID: String) -> Bool {
        TitleID.isOfficial(titleID) && Catalog.entry(titleID: titleID) == nil && !homebrewIDs.contains(titleID)
    }

    /// A folder in /dev_hdd0/game: its PARAM.SFO says whether it is a game or an update.
    static func installedCandidate(_ entry: FTPClient.Entry) -> Candidate {
        let path = "/dev_hdd0/game/" + entry.name
        let game = Game(path: path, title: entry.name, titleID: entry.name, platform: .psn, isFolder: true,
                        iconPath: path + "/ICON0.PNG", backgroundPath: path + "/PIC1.PNG")
        return Candidate(game: game, sfoPath: path + "/PARAM.SFO", cacheKey: path + "|" + entry.modified)
    }

    /// The game with its PARAM.SFO details, or nil for folders in /dev_hdd0/game that are not
    /// games: updates (noted in `updates` by title ID), game data and apps.
    static func resolve(_ candidate: Candidate, info: GameCache.Info?, updates: inout [String: String]) -> Game? {
        var game = candidate.game
        if let info {
            if let title = info.title { game.title = title }
            if let titleID = info.titleID { game.titleID = titleID }
            game.version = info.version
        }
        // A folder in GAMES without PS3_GAME/PARAM.SFO (such as covers/) is not a game.
        if game.isFolder, !game.isInstalled, info?.titleID == nil { return nil }
        guard game.isInstalled else { return game }
        switch info?.category {
        case "HG"?: game.platform = .psn
        case "1P"?: game.platform = .ps1
        case "2P"?: game.platform = .ps2
        case "MN"?, "PE"?, "PP"?: game.platform = .psp
        case "GD"?:
            if let titleID = game.titleID, let version = info?.version { updates[titleID] = version }
            return nil
        default:
            return nil
        }
        return game
    }

    /// Disc games get the version of their installed update; then everything is sorted.
    static func attach(_ updates: [String: String], to games: [Game]) -> [Game] {
        games.map { game in
            var game = game
            if !game.isInstalled, let titleID = game.titleID { game.updateVersion = updates[titleID] }
            return game
        }
        .sorted { ($0.platform.order, $0.title.lowercased(), $0.path) < ($1.platform.order, $1.title.lowercased(), $1.path) }
    }
}

/// PARAM.SFO details per game in ~/Library/Caches/ps3center/games.json, keyed by
/// `GameListing.Candidate.cacheKey`. Each scan writes only what it saw, so old keys drop out.
enum GameCache {
    struct Info: Codable, Equatable {
        var title: String?
        var titleID: String?
        var version: String?
        var category: String?

        init(sfo: ParamSFO?) {
            title = sfo?.title
            titleID = sfo?.titleID
            version = sfo?.appVersion
            category = sfo?.category
        }
    }

    static var file: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/ps3center/games.json")
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
