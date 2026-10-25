import Foundation

/// Box art for games, keyed by title ID and kept on the Mac for good. PS3 and PSN covers come
/// from aldostools/Resources (webMAN's online covers), then GameTDB; PS2 and PS1 covers from
/// xlenore's ps2-covers and psx-covers, the collections PCSX2's and DuckStation's cover
/// downloaders use. A picture the user drops on a game's page wins over all of them.
public struct CoverService: Sendable {
    public init() {}

    static var cacheDirectory: URL { GameLibraryService.cacheDirectory("covers") }

    /// The user's own covers are not a cache, so they live in Application Support.
    static var customDirectory: URL {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ps3center/covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// "ps3-BCES00569": covers follow the title ID, so the same game on the disk and a USB drive shares one.
    static func key(for game: Game) -> String? {
        game.titleID.map { "\(game.platform == .psn ? Game.Platform.ps3.rawValue : game.platform.rawValue)-\($0)" }
    }

    /// Where a game's cover is looked for, best first.
    static func sources(for game: Game) -> [URL] {
        guard let id = game.titleID else { return [] }
        let urls: [String]
        switch game.platform {
        case .ps3, .psn:
            let languages: [String]
            switch game.region {
            case .usa?: languages = ["US"]
            case .japan?: languages = ["JA", "EN"]
            default: languages = ["EN", "US"]
            }
            urls = ["https://raw.githubusercontent.com/aldostools/Resources/master/COV/\(id).JPG"]
                + languages.map { "https://art.gametdb.com/ps3/coverM/\($0)/\(id).jpg" }
        case .ps2:
            urls = ["https://raw.githubusercontent.com/xlenore/ps2-covers/main/covers/default/\(id).jpg"] + aldosRetro(id)
        case .ps1:
            urls = ["https://raw.githubusercontent.com/xlenore/psx-covers/main/covers/default/\(id).jpg"] + aldosRetro(id)
        case .psp:
            // aldostools/Resources/PSP: "UCES00995.PNG" for UCES-00995.
            urls = ["https://raw.githubusercontent.com/aldostools/Resources/master/PSP/\(id.replacingOccurrences(of: "-", with: "").uppercased()).PNG"]
        case .bluRay, .dvd:
            urls = []
        }
        return urls.compactMap(URL.init(string:))
    }

    /// aldostools/Resources/PSX holds PS1 and PS2 covers under the boot file's name:
    /// "SCES_014.38_COV.JPG" for SCES-01438. Used when xlenore's collections have none.
    static func aldosRetro(_ id: String) -> [String] {
        guard let exe = LibCrypt.exeName(fromTitleID: id) else { return [] }
        return ["https://raw.githubusercontent.com/aldostools/Resources/master/PSX/\(exe)_COV.JPG"]
    }

    /// The cover's file on the Mac, fetched when missing. Nil when no source has one; a definite
    /// "none" is remembered with an empty file until `refresh`, a network error is not.
    public func cover(for game: Game, refresh: Bool = false) async -> URL? {
        guard let key = Self.key(for: game) else { return nil }
        let custom = Self.customDirectory.appendingPathComponent(key + ".cover")
        if FileManager.default.fileExists(atPath: custom.path) { return custom }
        let file = Self.cacheDirectory.appendingPathComponent(key + ".jpg")
        if !refresh, let data = try? Data(contentsOf: file) { return data.isEmpty ? nil : file }
        var definite = true
        for url in Self.sources(for: game) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("ps3center", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count > 1000 else { continue }
                try? data.write(to: file, options: .atomic)
                return file
            } catch {
                definite = false
            }
        }
        if definite { try? Data().write(to: file) }
        return nil
    }

    /// Covers for many games, six at a time, by game id.
    public func covers(for games: [Game], refresh: Bool = false) async -> [String: URL] {
        await withTaskGroup(of: (String, URL?).self) { group in
            var result: [String: URL] = [:]
            var iterator = games.makeIterator()
            func launchNext() {
                guard let game = iterator.next() else { return }
                group.addTask { (game.id, await self.cover(for: game, refresh: refresh)) }
            }
            for _ in 0..<6 { launchNext() }
            for await (id, url) in group {
                if let url { result[id] = url }
                launchNext()
            }
            return result
        }
    }

    /// Uses the user's own picture as the game's cover (dropped on its page in the app).
    public func setCustomCover(_ image: Data, for game: Game) throws {
        guard let key = Self.key(for: game) else {
            throw PS3Error.refused("\(game.title) har inget title ID, så omslaget kan inte sparas.")
        }
        try image.write(to: Self.customDirectory.appendingPathComponent(key + ".cover"), options: .atomic)
    }

    public func removeCustomCover(for game: Game) {
        guard let key = Self.key(for: game) else { return }
        try? FileManager.default.removeItem(at: Self.customDirectory.appendingPathComponent(key + ".cover"))
    }

    // MARK: On the console

    /// Puts PS3 and PSN covers in /dev_hdd0/tmp/wmtmp/covers as <TITLEID>.JPG (or .PNG), where
    /// webMAN looks for them, so its game list and the XMB show them too. Covers already there
    /// with the same size are skipped. Returns how many were sent.
    @discardableResult
    public func upload(_ covers: [String: URL], for games: [Game], host: String, dryRun: Bool,
                       events: TransferHandler) async throws -> Int {
        let folder = "/dev_hdd0/tmp/wmtmp/covers"
        var routes: [Route] = []
        var seen = Set<String>()
        for game in games where game.platform == .ps3 || game.platform == .psn {
            guard let titleID = game.titleID, let file = covers[game.id], seen.insert(titleID).inserted else { continue }
            let ext = Self.isPNG(file) ? "PNG" : "JPG"
            routes.append(Route(local: file, remote: "\(folder)/\(titleID).\(ext)", kind: .other,
                                size: FileRouter.fileSize(file), title: game.title))
        }
        guard !routes.isEmpty else { return 0 }
        return try await TransferService(host: host).withFTP { ftp in
            var sent = 0
            for route in routes {
                if try await ftp.size(route.remote) == route.size {
                    events(.skipped(route, reason: "finns redan på PS3:an"))
                    continue
                }
                if dryRun {
                    events(.started(route, resumingFrom: 0))
                    continue
                }
                try await ftp.makeDirectories(folder)
                try await ftp.upload(file: route.local, to: route.remote) { _ in }
                events(.finished(route, seconds: 0))
                sent += 1
            }
            if sent > 0 { OperationLog.record("covers", "\(sent) omslag till \(folder)") }
            return sent
        }
    }

    static func isPNG(_ file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 4)) == Data([0x89, 0x50, 0x4E, 0x47])
    }
}
