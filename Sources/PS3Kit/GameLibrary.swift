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
    /// `refresh` reads every PARAM.SFO again instead of using the cache. What `send` saved about
    /// a game that has no PARAM.SFO on the console (a PS2 ISO, say) is kept, since there is
    /// nothing to read again.
    public func scan(refresh: Bool = false, events: @Sendable (String) -> Void = { _ in }) async throws -> [Game] {
        let cached = GameCache.load()
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
                var info = refresh && candidate.sfoPath != nil ? nil : cached[candidate.cacheKey]
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
            guard let remote = game.iconPath else {
                // Sent from the Mac, before webMAN has made its copy: ICON0 from the image there.
                if let data = try? Data(contentsOf: SentGames.iconFile(for: game.path)), !data.isEmpty { result[game.id] = data }
                continue
            }
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
        let url = StatePaths.caches.appendingPathComponent(name, isDirectory: true)
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
        OperationLog.record(.play, game.path)
    }

    /// Mounts a game as /dev_bdvd without starting it, so it can be started from the XMB.
    public func mount(_ game: Game, exitingRunning: Bool = false) async throws {
        guard !game.isInstalled else {
            throw PS3Error.refused("\(game.title) is installed in the XMB and is not mounted. Start it instead.")
        }
        try await quitRunningGame(allowed: exitingRunning)
        try await webman.get("/mount.ps3" + game.path, timeout: 30)
        OperationLog.record(.mount, game.path)
    }

    /// Unmounts the disc (/dev_bdvd). Refused while a game runs: it runs from that disc. The app
    /// only hides its button from a status up to 3 seconds old, so the check is made here.
    public func unmount() async throws {
        if let process = try await webman.runningProcess() {
            let name = (try? await webman.snapshot().mountedGameName) ?? nil
            throw PS3Error.refused("\(name ?? process) is running. Quit the game first.")
        }
        try await webman.get("/mount.ps3/unmount", timeout: 30)
        OperationLog.record(.unmount, "/dev_bdvd")
    }

    /// Quits the running game or app to the XMB and waits until it is gone.
    /// Returns its name, or nil when only the XMB was running.
    @discardableResult
    public func exitGame() async throws -> String? {
        guard let process = try await webman.runningProcess() else { return nil }
        let name = (try? await webman.snapshot().mountedGameName) ?? process
        try await webman.get("/xmb.ps3$exit", timeout: 30)
        try await waitForXMB()
        OperationLog.record(.exit, name)
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
            guard Date() < deadline else { throw PS3Error.timeout("the game did not quit within \(Int(timeout)) seconds") }
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
            throw PS3Error.refused("\(game.title) is running. Quit the game first.")
        }
        // An installed game runs from its folder without being mounted, so nothing may run.
        if game.isInstalled, snapshot.isGameRunning {
            throw PS3Error.refused("A game is running. Quit it first, so that \(game.title) is not in use while it is deleted.")
        }
        let files = game.isFolder ? [game.path] : [game.path] + game.companions
        if options.dryRun {
            for file in files { events(.note("Would delete \(file)")) }
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
        OperationLog.record(game.isInstalled ? .uninstall : .delete, game.path + (game.size.map { " (\(Format.bytes($0)))" } ?? ""))
        if game.isInstalled {
            let reload = await XMBReload.afterRemoval(host: host)
            events(.note("\(game.title) is uninstalled. Its saves are kept. \(reload)"))
        } else {
            events(.note("\(game.title) is deleted from the PS3"))
        }
        guard options.refresh else { return }
        try await TransferService(host: host).refreshGameList(whenGameRuns: .wait, force: options.force, events: events)
    }
}

/// What PS3 Center will not uninstall: anything but a folder directly in /dev_hdd0/game, and
/// what HEN needs to be enabled (without HEN, webMAN does not start and PS3 Center cannot reach
/// the console).
public enum UninstallGuard {
    public static func refusal(titleID: String?, title: String, path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.count == 3, parts[0] == "dev_hdd0", parts[1] == "game" else {
            return "\(title) is not directly in /dev_hdd0/game and is not uninstalled from here."
        }
        let name = title.uppercased()
        if name.contains("PS3HEN") || name.range(of: #"\bHEN\b"#, options: .regularExpression) != nil || titleID == "PS3XPLOIT" {
            return "\(title) is needed to enable HEN, and without HEN webMAN does not start. PS3 Center does not delete it."
        }
        return nil
    }
}

/// Turns listings of webMAN's game folders into games. No network, so tests can feed it listings.
package enum GameListing {
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
        Folder(name: "BDISO", platform: .bluRay, extensions: [".iso", ".iso.0"]),
        Folder(name: "DVDISO", platform: .dvd, extensions: [".iso", ".iso.0"]),
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
                                backgroundPath: path + "/PS3_GAME/PIC1.PNG", added: listedDate(entry.modified))
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
                            platform: folder.platform, size: size, companions: companions.sorted(),
                            added: listedDate(file.modified))
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
                        iconPath: path + "/ICON0.PNG", backgroundPath: path + "/PIC1.PNG", added: listedDate(entry.modified))
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
    package static func attach(_ updates: [String: String], to games: [Game]) -> [Game] {
        games.map { game in
            var game = game
            if !game.isInstalled, let titleID = game.titleID { game.updateVersion = updates[titleID] }
            return game
        }
        .sorted(by: byName)
    }

    /// The console's order: platform, then title, then path.
    static func byName(_ a: Game, _ b: Game) -> Bool {
        (a.platform.order, a.title.lowercased(), a.path) < (b.platform.order, b.title.lowercased(), b.path)
    }

    /// The date in a listing line: "Jun 05 18:33" (the year left out, so the latest such date
    /// that is not in the future), "Jun 05 2025", or seconds since 1970 from a Mac folder.
    static func listedDate(_ text: String, now: Date = Date()) -> Date? {
        if let seconds = TimeInterval(text), !text.isEmpty { return Date(timeIntervalSince1970: seconds) }
        let parts = text.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        if parts[2].contains(":") {
            let year = Calendar.current.component(.year, from: now)
            formatter.dateFormat = "MMM d HH:mm yyyy"
            for candidate in [year, year - 1] {
                if let date = formatter.date(from: "\(parts[0]) \(parts[1]) \(parts[2]) \(candidate)"),
                   date <= now.addingTimeInterval(86_400) {
                    return date
                }
            }
            return nil
        }
        formatter.dateFormat = "MMM d yyyy"
        return formatter.date(from: parts.joined(separator: " "))
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

        init(title: String?, titleID: String?, version: String?, category: String? = nil) {
            self.title = title
            self.titleID = titleID
            self.version = version
            self.category = category
        }
    }

    static var file: URL { StatePaths.caches.appendingPathComponent("games.json") }

    static func load() -> [String: Info] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: Info].self, from: data)) ?? [:]
    }

    static func save(_ cache: [String: Info]) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(cache).write(to: file, options: .atomic)
    }
}

/// What `send` already knows about the games it sends: title, title ID and version read from
/// the image on the Mac, and its ICON0. Saved under the key the next scan of the console uses,
/// so those games never have to be read there, and PS1/PS2 games keep the serial from
/// SYSTEM.CNF that their file name may lack. The icon shows until webMAN has made its own
/// copy in wmtmp.
enum SentGames {
    /// Where a sent file's game shows up in a listing: the folder to list, its rules, and the
    /// game's path (the folder itself for GAMES, else the file). Nil outside the game folders.
    static func location(of remote: String) -> (dir: String, folder: GameListing.Folder, game: String)? {
        let parts = remote.split(separator: "/").map(String.init)
        guard parts.count >= 3, let folder = GameListing.folders.first(where: { $0.name == parts[1] }) else { return nil }
        let top = "/" + parts[0] + "/" + parts[1]
        if folder.holdsFolders { return (top, folder, top + "/" + parts[2]) }
        return ((remote as NSString).deletingLastPathComponent, folder, remote)
    }

    /// The Mac file (or GAMES folder) a game on the console was sent from.
    static func localPath(of game: String, routes: [Route]) -> String? {
        if let exact = routes.first(where: { $0.remote == game }) { return exact.local.path }
        guard let inside = routes.first(where: { $0.remote.hasPrefix(game + "/") }) else { return nil }
        let rest = String(inside.remote.dropFirst(game.count))
        guard inside.local.path.hasSuffix(rest) else { return nil }
        return String(inside.local.path.dropLast(rest.count))
    }

    /// Lists the folders the games went to and saves what the Mac's copies say. Never fails a
    /// send: whatever cannot be read is read on the console next time, as before.
    static func remember(_ sent: [Route], ftp: FTPClient) async {
        let games = sent.filter(\.refreshesGameList)
        let dirs = Dictionary(grouping: games.compactMap { route in location(of: route.remote).map { ($0, route) } }) { $0.0.dir }
        guard !dirs.isEmpty else { return }
        var cache = GameCache.load()
        for (dir, items) in dirs {
            guard let folder = items.first?.0.folder, let entries = try? await ftp.list(dir) else { continue }
            let candidates = folder.holdsFolders
                ? GameListing.candidates(in: dir, folder: folder, entries: entries, nested: [:], wmtmp: [:])
                : GameListing.images(in: dir, files: entries.filter { !$0.isDirectory }, folder: folder, wmtmp: [:])
            let wanted = Set(items.map(\.0.game))
            for candidate in candidates where wanted.contains(candidate.game.path) {
                guard let local = localPath(of: candidate.game.path, routes: items.map(\.1)) else { continue }
                var mac = candidate.game
                mac.path = local
                mac.source = .mac
                let info = LocalGameReader.read(mac)
                guard info.title != nil || info.titleID != nil else { continue }
                cache[candidate.cacheKey] = GameCache.Info(title: info.title, titleID: info.titleID, version: info.version)
                if let icon = info.iconFile, let data = try? Data(contentsOf: URL(fileURLWithPath: icon)), !data.isEmpty {
                    try? data.write(to: iconFile(for: candidate.game.path), options: .atomic)
                }
            }
        }
        GameCache.save(cache)
    }

    /// ICON0 of a game sent from the Mac, by its path on the console.
    static func iconFile(for consolePath: String) -> URL {
        GameLibraryService.cacheDirectory("sent-icons").appendingPathComponent(AppsService.md5(Data(consolePath.utf8)) + ".png")
    }
}
