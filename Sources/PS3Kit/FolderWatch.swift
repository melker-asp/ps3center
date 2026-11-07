import Foundation

/// Watched game folders: a new game in one is queued once it has stopped growing (a download or
/// a copy can take a while). Which folders are watched is `watchedFolders` in config.json, set
/// in the app's Game Folders or with `ps3 config folder watch`. What has been seen is kept in
/// ~/Library/Application Support/ps3center/watch.json, so games added while nothing watched
/// are found too; the first look at a folder takes what is there as already handled.
public struct FolderWatch: Sendable {
    struct Growing: Codable, Sendable {
        var size: Int64
        var since: Date
    }

    struct State: Codable, Sendable {
        /// Folder path → names of the entries already handled.
        var known: [String: [String]] = [:]
        /// Full path of a new entry → its size and since when it has had it.
        var growing: [String: Growing] = [:]
    }

    /// A new game, ready to queue.
    public struct Arrival: Sendable {
        public let kind: GameFolders.Kind
        public let folder: URL
        public let entry: URL
    }

    /// How long a new entry must keep its size before it counts as complete.
    public var settle: TimeInterval = 60
    let store: JSONFile<State>

    public init(file: URL = FolderWatch.defaultFile) {
        store = JSONFile(file, empty: State())
    }

    public static var defaultFile: URL { StatePaths.support.appendingPathComponent("watch.json") }

    /// The linked folders that are watched.
    public static func watched(config: PS3Config = ConfigStore.load()) -> [(kind: GameFolders.Kind, url: URL)] {
        let paths = Set((config.watchedFolders ?? []).map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL.path })
        return GameFolders.linked(config: config).filter { paths.contains($0.url.path) }
    }

    public static func isWatched(_ folder: URL, config: PS3Config = ConfigStore.load()) -> Bool {
        (config.watchedFolders ?? []).contains(folder.standardizedFileURL.path)
    }

    /// Turns watching of a linked folder on or off in config.json.
    public static func setWatched(_ folder: URL, _ on: Bool) throws {
        let path = folder.standardizedFileURL.path
        try ConfigStore.edit { config in
            var paths = config.watchedFolders ?? []
            paths.removeAll { $0 == path }
            if on { paths.append(path) }
            config.watchedFolders = paths.isEmpty ? nil : paths
        }
    }

    /// Looks at the folders and returns the new entries that have kept their size for `settle`
    /// seconds; they count as handled from then on. What has been seen is read and saved under
    /// watch.json's lock, so the app and `ps3 watch` side by side never both report one game.
    /// When watch.json cannot be written nothing is reported, and the next look finds it again.
    public func poll(_ folders: [(kind: GameFolders.Kind, url: URL)], now: Date = Date()) -> [Arrival] {
        let settle = self.settle
        return (try? store.edit { Self.poll(&$0, folders, settle: settle, now: now) }) ?? []
    }

    static func poll(_ state: inout State, _ folders: [(kind: GameFolders.Kind, url: URL)], settle: TimeInterval,
                     now: Date) -> [Arrival] {
        var arrivals: [Arrival] = []
        var stillGrowing: [String: Growing] = [:]
        for (kind, folder) in folders {
            let key = folder.standardizedFileURL.path
            guard let names = Self.entries(in: folder) else { continue }  // a drive that is not plugged in
            guard var known = state.known[key].map({ Set($0) }) else {
                state.known[key] = names.sorted()  // the first look: what is there is not new
                continue
            }
            for name in names where !known.contains(name) {
                let entry = folder.appendingPathComponent(name)
                let size = Self.size(of: entry)
                if let last = state.growing[entry.path], last.size == size, size > 0 {
                    if now.timeIntervalSince(last.since) >= settle {
                        arrivals.append(Arrival(kind: kind, folder: folder, entry: entry))
                        known.insert(name)
                    } else {
                        stillGrowing[entry.path] = last
                    }
                } else {
                    stillGrowing[entry.path] = Growing(size: size, since: now)
                }
            }
            // A game removed and added again later counts as new.
            known.formIntersection(names)
            state.known[key] = known.sorted()
        }
        state.growing = stillGrowing
        return arrivals
    }

    /// Names in a folder, without hidden files and files that are still being downloaded.
    static func entries(in folder: URL) -> Set<String>? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        let unfinished = [".part", ".download", ".crdownload", ".tmp", ".partial", ".opdownload", ".!qb"]
        return Set(names.filter { name in
            !name.hasPrefix(".") && !unfinished.contains { name.lowercased().hasSuffix($0) }
        })
    }

    /// A file's size, or everything in a folder.
    static func size(of url: URL) -> Int64 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        guard isDirectory.boolValue else { return FileRouter.fileSize(url) }
        return ((try? FileRouter.filesRecursively(in: url)) ?? []).map(FileRouter.fileSize).reduce(0, +)
    }

    /// The games behind new entries, from the Mac's library: what `TransferQueue.add` takes.
    public static func routes(for arrivals: [Arrival]) -> [(title: String, routes: [Route])] {
        var result: [(title: String, routes: [Route])] = []
        let byFolder = Dictionary(grouping: arrivals) { $0.folder.path }
        for group in byFolder.values {
            guard let first = group.first else { continue }
            let games = LocalLibrary().scan(folders: [(first.kind, first.folder)])
            for arrival in group {
                let path = arrival.entry.path
                for game in games where game.path == path || game.path.hasPrefix(path + "/") {
                    if let routes = try? game.routes(), !routes.isEmpty { result.append((game.title, routes)) }
                }
            }
        }
        return result
    }
}
