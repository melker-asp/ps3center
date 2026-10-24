import Foundation

/// PS3 Center's own folder for backups: ~/Library/Application Support/ps3center/<name>.
enum BackupFolder {
    static func url(_ name: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ps3center/\(name)", isDirectory: true)
    }
}

// MARK: Saves

/// One save: a folder in /dev_hdd0/home/<user>/savedata, on the console or in the backup.
public struct SaveGame: Codable, Equatable, Sendable, Identifiable {
    public let user: String
    public let folder: String
    public var title: String
    public var subtitle: String?
    public var size: Int64
    /// When the game last wrote it (PARAM.SFO's MDTM), when known.
    public var modified: Date?

    public var id: String { user + "/" + folder }
    public var titleID: String? { TitleID.find(in: folder, platform: .ps3) }

    public init(user: String, folder: String, title: String, subtitle: String? = nil, size: Int64, modified: Date? = nil) {
        self.user = user
        self.folder = folder
        self.title = title
        self.subtitle = subtitle
        self.size = size
        self.modified = modified
    }
}

/// Copies the saves to the Mac and back. Backing up only reads the console: a save folder is
/// copied to Sparfiler/<user>/<folder> when a file in it changed (name, size or date in the
/// listing), and the copy it replaces is kept in Sparfiler/<user>/.tidigare. Only TITLE and
/// SUB_TITLE are read from PARAM.SFO; its account fields are never shown.
public struct SaveBackupService: Sendable {
    public let host: String

    public init(host: String) { self.host = host }

    public static var root: URL { BackupFolder.url("Sparfiler") }
    static let manifestName = ".ps3center.json"

    struct Manifest: Codable {
        var save: SaveGame
        /// "name|size|date" per file, as listed on the console.
        var files: [String]
        var backedUpAt: Date
    }

    public struct Report: Sendable {
        public var copied: [SaveGame] = []
        public var unchanged = 0
        public var failed: [String] = []
    }

    static func remoteFolder(_ save: SaveGame) -> String {
        "/dev_hdd0/home/\(save.user)/savedata/\(save.folder)"
    }

    static func localFolder(_ save: SaveGame) -> URL {
        root.appendingPathComponent(save.user, isDirectory: true).appendingPathComponent(save.folder, isDirectory: true)
    }

    /// Every save on the console, per user.
    public func list() async throws -> [SaveGame] {
        try await TransferService(host: host).withFTP { ftp in try await scan(ftp).map { $0.save } }
    }

    /// The users (/dev_hdd0/home/00000001 …) and their save folders, with each folder's files.
    private func scan(_ ftp: FTPClient) async throws -> [(save: SaveGame, files: [FTPClient.Entry])] {
        var result: [(save: SaveGame, files: [FTPClient.Entry])] = []
        let users = try await ftp.list("/dev_hdd0/home").filter { $0.isDirectory && Self.isUser($0.name) }
        for user in users {
            let base = "/dev_hdd0/home/\(user.name)/savedata"
            for folder in try await ftp.list(base) where folder.isDirectory {
                let path = base + "/" + folder.name
                let files = try await ftp.list(path).filter { !$0.isDirectory }
                let sfo = try await ftp.download(path + "/PARAM.SFO", limit: 1 << 20).flatMap(ParamSFO.init(data:))
                let stamp = try await ftp.modificationTime(path + "/PARAM.SFO")
                let save = SaveGame(user: user.name, folder: folder.name, title: sfo?.title ?? folder.name,
                                    subtitle: sfo?.string("SUB_TITLE").flatMap { $0.isEmpty ? nil : $0 },
                                    size: files.reduce(0) { $0 + $1.size }, modified: stamp.flatMap(Self.parseMDTM))
                result.append((save, files))
            }
        }
        return result
    }

    static func isUser(_ name: String) -> Bool {
        name.count == 8 && name.allSatisfy(\.isNumber)
    }

    /// "20261022214005" → a date (MDTM is UTC).
    static func parseMDTM(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.date(from: String(text.prefix(14)))
    }

    static func signature(_ files: [FTPClient.Entry]) -> [String] {
        files.map { "\($0.name)|\($0.size)|\($0.modified)" }.sorted()
    }

    /// Copies what changed since the last backup. Reads the console only.
    public func backup(events: @Sendable (String) -> Void = { _ in }) async throws -> Report {
        try FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
        let report = try await TransferService(host: host).withFTP { ftp in try await backup(ftp, events: events) }
        try? JSONEncoder().encode(Date()).write(to: Self.root.appendingPathComponent("senaste.json"))
        return report
    }

    private func backup(_ ftp: FTPClient, events: @Sendable (String) -> Void) async throws -> Report {
        var report = Report()
        for (save, files) in try await scan(ftp) {
            let folder = Self.localFolder(save)
            let signature = Self.signature(files)
            if Self.manifest(in: folder)?.files == signature {
                report.unchanged += 1
                continue
            }
            events("Kopierar \(save.title)")
            do {
                try await copy(save, files: files, from: ftp, into: folder)
                try Self.write(Manifest(save: save, files: signature, backedUpAt: Date()), in: folder)
                report.copied.append(save)
            } catch {
                report.failed.append("\(save.title): \(error.localizedDescription)")
            }
        }
        return report
    }

    /// Downloads into a new folder first, so a broken connection never leaves half a backup;
    /// the copy it replaces moves to .tidigare.
    private func copy(_ save: SaveGame, files: [FTPClient.Entry], from ftp: FTPClient, into folder: URL) async throws {
        let fm = FileManager.default
        let fresh = folder.deletingLastPathComponent().appendingPathComponent(".ny-\(save.folder)", isDirectory: true)
        try? fm.removeItem(at: fresh)
        try fm.createDirectory(at: fresh, withIntermediateDirectories: true)
        for file in files {
            guard let data = try await ftp.download(Self.remoteFolder(save) + "/" + file.name, limit: 512 << 20) else {
                throw PS3Error.invalidFile("\(file.name) gick inte att läsa")
            }
            try data.write(to: fresh.appendingPathComponent(file.name))
        }
        if fm.fileExists(atPath: folder.path) {
            let previous = folder.deletingLastPathComponent().appendingPathComponent(".tidigare", isDirectory: true)
            try fm.createDirectory(at: previous, withIntermediateDirectories: true)
            let old = previous.appendingPathComponent(save.folder, isDirectory: true)
            try? fm.removeItem(at: old)
            try fm.moveItem(at: folder, to: old)
        }
        try fm.moveItem(at: fresh, to: folder)
    }

    static func manifest(in folder: URL) -> Manifest? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(manifestName)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Manifest.self, from: data)
    }

    static func write(_ manifest: Manifest, in folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: folder.appendingPathComponent(manifestName))
    }

    /// The saves in the backup on the Mac.
    public static func local() -> [SaveGame] {
        let fm = FileManager.default
        let users = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return users.filter { Self.isUser($0.lastPathComponent) }.flatMap { user -> [SaveGame] in
            let folders = (try? fm.contentsOfDirectory(at: user, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            return folders.compactMap { Self.manifest(in: $0)?.save }
        }
        .sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
    }

    public static func lastBackup() -> Date? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("senaste.json")) else { return nil }
        return try? JSONDecoder().decode(Date.self, from: data)
    }

    /// Puts a save from the backup back on the console, for the same user. Not while a game
    /// runs. What is on the console now is copied to .innan-aterstallning first. Logged.
    public func restore(_ save: SaveGame, events: @Sendable (String) -> Void = { _ in }) async throws {
        let folder = Self.localFolder(save)
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .filter { $0.lastPathComponent != Self.manifestName }
        guard !files.isEmpty else { throw PS3Error.refused("\(save.title) finns inte i säkerhetskopian.") }
        guard try await WebMAN(host: host).runningProcess() == nil else { throw PS3Error.gameRunning }
        try await TransferService(host: host).withFTP { ftp in try await restore(save, files: files, ftp: ftp, events: events) }
    }

    private func restore(_ save: SaveGame, files: [URL], ftp: FTPClient, events: @Sendable (String) -> Void) async throws {
        let fm = FileManager.default
        let remote = Self.remoteFolder(save)
        let current = try await ftp.list(remote).filter { !$0.isDirectory }
        if !current.isEmpty {
            events("Sparar det som ligger på PS3:an nu")
            let safety = Self.root.appendingPathComponent(save.user, isDirectory: true)
                .appendingPathComponent(".innan-aterstallning", isDirectory: true)
                .appendingPathComponent(save.folder, isDirectory: true)
            try? fm.removeItem(at: safety)
            try fm.createDirectory(at: safety, withIntermediateDirectories: true)
            for file in current {
                if let data = try await ftp.download(remote + "/" + file.name, limit: 512 << 20) {
                    try data.write(to: safety.appendingPathComponent(file.name))
                }
            }
        }
        OperationLog.record("restore", "\(save.title) (\(save.user)/\(save.folder))")
        try await ftp.makeDirectories(remote)
        for file in files {
            events("Skickar \(file.lastPathComponent)")
            try await ftp.upload(file: file, to: remote + "/" + file.lastPathComponent) { _ in }
        }
    }
}

// MARK: System files

/// Copies of the console's settings and plugin lists, read only: the system settings
/// (xRegistry.sys), webMAN's settings and the boot_plugins lists. Each backup is a dated folder
/// in Systemfiler with the console's paths inside. The files are never read or shown.
public enum SystemFiles {
    public static let paths = [
        "/dev_flash2/etc/xRegistry.sys",
        "/dev_hdd0/tmp/wm_config.bin",
        "/dev_hdd0/boot_plugins.txt",
        "/dev_hdd0/boot_plugins_kernel.txt",
        "/dev_hdd0/boot_plugins_nocobra.txt",
        "/dev_hdd0/boot_plugins_nocobra_dex.txt",
    ]

    public static var root: URL { BackupFolder.url("Systemfiler") }

    /// The paths that existed and were copied, and the folder they went to.
    public static func backup(host: String) async throws -> (folder: URL, saved: [String]) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let folder = root.appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
        let saved = try await TransferService(host: host).withFTP { ftp -> [String] in
            var saved: [String] = []
            for path in Self.paths {
                guard let data = try await ftp.download(path, limit: 16 << 20) else { continue }
                let target = folder.appendingPathComponent(String(path.dropFirst()))
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: target)
                saved.append(path)
            }
            return saved
        }
        return (folder, saved)
    }

    /// The backups, newest first.
    public static func backups() -> [URL] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return folders.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}

// MARK: Maintenance

/// Something `ps3 maintain` found. Only leftover packages and unfinished uploads can be
/// removed by PS3 Center; the rest is advice.
public struct MaintenanceFinding: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case leftoverPackage, partialUpload, duplicate, cache, missingPlugin, henToggles, space
    }

    public let kind: Kind
    public let title: String
    public let detail: String
    public var path: String?
    public var size: Int64?
    public var canFix = false

    public var id: String { kind.rawValue + ":" + (path ?? title) }

    public init(kind: Kind, title: String, detail: String, path: String? = nil, size: Int64? = nil, canFix: Bool = false) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.path = path
        self.size = size
        self.canFix = canFix
    }
}

public struct MaintenanceReport: Codable, Equatable, Sendable {
    public var findings: [MaintenanceFinding] = []
    /// The checks that found nothing, to show as done.
    public var passed: [String] = []

    public init(findings: [MaintenanceFinding] = [], passed: [String] = []) {
        self.findings = findings
        self.passed = passed
    }
}

public struct MaintenanceService: Sendable {
    public let host: String

    public init(host: String) { self.host = host }

    /// Reads the console and reports. Changes nothing.
    public func check(queue: TransferQueue = TransferQueue.load(), events: @Sendable (String) -> Void = { _ in }) async throws -> MaintenanceReport {
        // The game list first: it opens its own FTP session.
        events("Dubbletter")
        let games = (try? await GameLibraryService(host: host).scan()) ?? []
        var report = try await TransferService(host: host).withFTP { ftp in
            try await check(ftp, queue: queue, games: games, events: events)
        }

        events("webMAN:s cache")
        if let cache = try? await StorageAnalyzer(host: host).size(of: "/dev_hdd0/tmp/wmtmp"), cache.bytes > 1 << 30 {
            report.findings.append(MaintenanceFinding(
                kind: .cache, title: "webMAN:s cache",
                detail: "/dev_hdd0/tmp/wmtmp är \(Format.bytes(cache.bytes)). Den byggs upp igen av sig själv om du tömmer den i webMAN.",
                path: "/dev_hdd0/tmp/wmtmp", size: cache.bytes))
        } else {
            report.passed.append("webMAN:s cache är liten")
        }

        if let free = try? await WebMAN(host: host).snapshot().freeBytes, free < 10_000_000_000 {
            report.findings.append(MaintenanceFinding(
                kind: .space, title: "Lite ledigt utrymme",
                detail: "\(Format.bytes(free)) ledigt på /dev_hdd0. Spel som körs och uppdateringar behöver plats."))
        } else {
            report.passed.append("Gott om ledigt utrymme")
        }
        return report
    }

    private func check(_ ftp: FTPClient, queue: TransferQueue, games: [Game], events: @Sendable (String) -> Void) async throws -> MaintenanceReport {
        var report = MaintenanceReport()

        events("Paket och avbrutna överföringar")
        let queued = Set(queue.pending.flatMap { $0.files.map(\.remote) })
        let packages = try await ftp.list("/dev_hdd0/packages")
        for file in packages where !file.isDirectory && file.name.lowercased().hasSuffix(".pkg") {
            report.findings.append(MaintenanceFinding(
                kind: .leftoverPackage, title: file.name,
                detail: "Ett paket som ligger kvar i /dev_hdd0/packages. Installerade program behöver det inte.",
                path: "/dev_hdd0/packages/" + file.name, size: file.size, canFix: true))
        }
        var parts: [(path: String, size: Int64)] = packages.filter { $0.name.hasSuffix(".part") }
            .map { ("/dev_hdd0/packages/" + $0.name, $0.size) }
        for folder in GameListing.folders {
            let base = "/dev_hdd0/" + folder.name
            for entry in try await ftp.list(base) {
                if !entry.isDirectory, entry.name.hasSuffix(".part") {
                    parts.append((base + "/" + entry.name, entry.size))
                } else if entry.isDirectory, !folder.holdsFolders {
                    for inner in try await ftp.list(base + "/" + entry.name) where !inner.isDirectory && inner.name.hasSuffix(".part") {
                        parts.append((base + "/" + entry.name + "/" + inner.name, inner.size))
                    }
                }
            }
        }
        for part in parts {
            let original = String(part.path.dropLast(".part".count))
            let waiting = queued.contains(original)
            report.findings.append(MaintenanceFinding(
                kind: .partialUpload, title: (original as NSString).lastPathComponent,
                detail: waiting ? "En överföring som fortsätter när kön går." : "En överföring som inte blev klar. Den syns inte i XMB:n.",
                path: part.path, size: part.size, canFix: !waiting))
        }
        if packages.isEmpty, parts.isEmpty { report.passed.append("Inga kvarglömda paket eller avbrutna överföringar") }

        let byID = Dictionary(grouping: games.filter { !$0.isInstalled && $0.platform == .ps3 && $0.titleID != nil }, by: { $0.titleID! })
        let duplicates = byID.filter { $0.value.count > 1 }.sorted { $0.key < $1.key }
        for (id, copies) in duplicates {
            report.findings.append(MaintenanceFinding(
                kind: .duplicate, title: copies[0].title,
                detail: "\(id) finns \(copies.count) gånger: " + copies.map(\.path).joined(separator: ", ") + ". Ta bort den du inte behöver i Spel-fliken.",
                size: copies.dropFirst().compactMap(\.size).reduce(0, +)))
        }
        if duplicates.isEmpty { report.passed.append("Inga spel som finns två gånger") }

        events("boot_plugins")
        var missing = 0
        for list in ["/dev_hdd0/boot_plugins.txt", "/dev_hdd0/boot_plugins_kernel.txt"] {
            guard let data = try await ftp.download(list, limit: 1 << 20) else { continue }
            for plugin in Self.pluginPaths(in: String(decoding: data, as: UTF8.self)) {
                guard try await ftp.size(plugin) == nil else { continue }
                missing += 1
                report.findings.append(MaintenanceFinding(
                    kind: .missingPlugin, title: (plugin as NSString).lastPathComponent,
                    detail: "\((list as NSString).lastPathComponent) pekar på \(plugin), som inte finns. PS3 Center ändrar aldrig listan; ta bort raden själv.",
                    path: plugin))
            }
        }
        if missing == 0 { report.passed.append("Alla plugins i boot_plugins finns") }

        events("HEN")
        let toggles = try await ftp.list("/dev_hdd0/hen/toggles").filter { !$0.isDirectory }.map(\.name)
        if !toggles.isEmpty {
            report.findings.append(MaintenanceFinding(
                kind: .henToggles, title: "HEN-inställningar",
                detail: "Filer i /dev_hdd0/hen/toggles: " + toggles.joined(separator: ", ") + ". Bara information.",
                path: "/dev_hdd0/hen/toggles"))
        }
        return report
    }

    /// The lines of a boot_plugins list that name a plugin file.
    static func pluginPaths(in text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("/") }
    }

    /// Removes what can be removed (`canFix`); the rest is skipped with the reason. Logged.
    public func fix(_ findings: [MaintenanceFinding], events: @Sendable (String) -> Void = { _ in }) async throws -> [(finding: MaintenanceFinding, skipped: String?)] {
        try await TransferService(host: host).withFTP { ftp in
            var results: [(finding: MaintenanceFinding, skipped: String?)] = []
            for finding in findings {
                guard finding.canFix, let path = finding.path else {
                    results.append((finding, "bara ett råd"))
                    continue
                }
                events("Tar bort \(finding.title)")
                do {
                    try await ftp.delete(path)
                    OperationLog.record("delete", path)
                    results.append((finding, nil))
                } catch {
                    results.append((finding, error.localizedDescription))
                }
            }
            return results
        }
    }
}

// MARK: Storage

/// How /dev_hdd0 is used, folder by folder, from webMAN's /stat.ps3 (include/cmd/stat_chmod.h),
/// which counts on the console instead of listing every file over FTP.
public struct StorageUsage: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let path: String
    public let bytes: Int64

    public var id: String { path }

    public init(name: String, path: String, bytes: Int64) {
        self.name = name
        self.path = path
        self.bytes = bytes
    }
}

public struct StorageMap: Codable, Equatable, Sendable {
    public var areas: [StorageUsage]
    /// The biggest single files in the ISO and package folders.
    public var largest: [StorageUsage]
    public var free: Int64?
    public var total: Int64?

    public init(areas: [StorageUsage], largest: [StorageUsage], free: Int64?, total: Int64?) {
        self.areas = areas
        self.largest = largest
        self.free = free
        self.total = total
    }

    /// What the areas do not cover (system data, other folders).
    public var other: Int64? {
        guard let free, let total else { return nil }
        return max(0, total - free - areas.reduce(0) { $0 + $1.bytes })
    }
}

public struct StorageAnalyzer: Sendable {
    public let host: String

    public init(host: String) { self.host = host }

    static let areas: [(path: String, name: String)] = [
        ("/dev_hdd0/game", "Installerade spel och program"),
        ("/dev_hdd0/PS3ISO", "PS3-ISO:er"),
        ("/dev_hdd0/GAMES", "Spelmappar"),
        ("/dev_hdd0/PS2ISO", "PS2-ISO:er"),
        ("/dev_hdd0/PSXISO", "PS1-avbilder"),
        ("/dev_hdd0/PSPISO", "PSP-ISO:er"),
        ("/dev_hdd0/BDISO", "Blu-ray"),
        ("/dev_hdd0/DVDISO", "DVD"),
        ("/dev_hdd0/home", "Användare och sparfiler"),
        ("/dev_hdd0/packages", "Paket"),
        ("/dev_hdd0/tmp", "Tillfälligt och webMAN:s cache"),
        ("/dev_hdd0/video", "Video"),
        ("/dev_hdd0/music", "Musik"),
        ("/dev_hdd0/photo", "Bilder"),
    ]

    public func analyze(events: @Sendable (String) -> Void = { _ in }) async throws -> StorageMap {
        var areas: [StorageUsage] = []
        for area in Self.areas {
            events(area.name)
            if let size = try? await size(of: area.path), size.bytes > 0 {
                areas.append(StorageUsage(name: area.name, path: area.path, bytes: size.bytes))
            }
        }
        let folders = GameListing.folders.filter { !$0.holdsFolders }.map { "/dev_hdd0/" + $0.name } + ["/dev_hdd0/packages"]
        let largest = (try? await TransferService(host: host).withFTP { ftp -> [StorageUsage] in
            var files: [StorageUsage] = []
            for folder in folders {
                for file in try await ftp.list(folder) where !file.isDirectory {
                    files.append(StorageUsage(name: file.name, path: folder + "/" + file.name, bytes: file.size))
                }
            }
            return files
        }) ?? []
        let snapshot = try? await WebMAN(host: host).snapshot()
        return StorageMap(areas: areas.sorted { $0.bytes > $1.bytes },
                          largest: Array(largest.sorted { $0.bytes > $1.bytes }.prefix(8)),
                          free: snapshot?.freeBytes, total: snapshot?.totalBytes)
    }

    /// A folder's size and counts, counted on the console. Reads only.
    public func size(of path: String) async throws -> (bytes: Int64, folders: Int, files: Int) {
        let page = try await WebMAN(host: host).long("/stat.ps3" + path, timeout: 300)
        guard let parsed = Self.parseStat(page) else { throw PS3Error.invalidFile("webMAN:s /stat.ps3 gav inget svar för \(path)") }
        return parsed
    }

    /// "Size: 12.3 GB (13,207,024,640 bytes)<br>Dir(s): 120<br>File(s): 4,210"
    static func parseStat(_ page: String) -> (bytes: Int64, folders: Int, files: Int)? {
        func number(_ pattern: String) -> Int64? {
            ConsoleSnapshot.firstMatch(pattern, in: page).flatMap { Int64($0[1].filter(\.isNumber)) }
        }
        guard let bytes = number(#"\(([\d,.' ]+) bytes\)"#) else { return nil }
        return (bytes, Int(number(#"Dir\(s\):\s*([\d,.' ]+)"#) ?? 0), Int(number(#"File\(s\):\s*([\d,.' ]+)"#) ?? 0))
    }
}

// MARK: Disc

/// The PS3 disc in the drive.
public struct DiscInfo: Codable, Equatable, Sendable {
    public let title: String
    public let titleID: String
    public let bytes: Int64

    public init(title: String, titleID: String, bytes: Int64) {
        self.title = title
        self.titleID = titleID
        self.bytes = bytes
    }

    /// webMAN's and multiMAN's way of naming a game folder: "BLES01234-[Title]".
    public var folderName: String {
        let clean = title.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|[]")).joined()
            .trimmingCharacters(in: .whitespaces)
        return "\(titleID)-[\(clean)]"
    }

    public var destination: String { "/dev_hdd0/GAMES/" + folderName }
}

/// Copies a PS3 disc to /dev_hdd0/GAMES with webMAN's /copy.ps3, which does the copying on the
/// console; PS3 Center only starts it and follows the folder's size.
public struct DiscRipper: Sendable {
    public let host: String

    public init(host: String) { self.host = host }

    /// The disc in the drive, or nil when there is none (or it is not a PS3 game).
    public func disc() async throws -> DiscInfo? {
        if let mounted = try await WebMAN(host: host).snapshot().mountedGamePath, !mounted.hasPrefix("/dev_bdvd") {
            throw PS3Error.refused("\((mounted as NSString).lastPathComponent) är monterat, så skivan syns inte. Avmontera det först.")
        }
        let sfoData = try await TransferService(host: host).withFTP { try await $0.download("/dev_bdvd/PS3_GAME/PARAM.SFO", limit: 1 << 20) }
        guard let data = sfoData, let sfo = ParamSFO(data: data), let titleID = sfo.titleID else { return nil }
        let bytes = (try? await StorageAnalyzer(host: host).size(of: "/dev_bdvd").bytes) ?? 0
        return DiscInfo(title: sfo.title ?? titleID, titleID: titleID, bytes: bytes)
    }

    /// Starts the copy and reports the bytes copied until the folder is as big as the disc, or
    /// stops growing for two minutes. Logged.
    public func rip(_ disc: DiscInfo, progress: @Sendable (Int64) -> Void) async throws {
        let analyzer = StorageAnalyzer(host: host)
        if let free = try? await WebMAN(host: host).snapshot().freeBytes, free < disc.bytes + 1_000_000_000 {
            throw PS3Error.notEnoughSpace(needed: disc.bytes, free: free)
        }
        if let existing = try? await analyzer.size(of: disc.destination), existing.files > 0 {
            throw PS3Error.refused("\(disc.destination) finns redan.")
        }
        guard let url = URL(string: "http://\(host)/copy.ps3/dev_bdvd&to=" + WebMAN.encodeCommand(disc.destination)) else {
            throw PS3Error.invalidFile(disc.destination)
        }
        OperationLog.record("rip", "\(disc.title) → \(disc.destination)")
        // webMAN may answer only when the copy is done: the request gets a session of its own,
        // and the progress is read over FTP, which keeps answering meanwhile.
        var request = URLRequest(url: url)
        request.timeoutInterval = 4 * 3600
        request.setValue("close", forHTTPHeaderField: "Connection")
        let session = URLSession(configuration: .ephemeral)
        let copying = Task { _ = try? await session.data(for: request) }
        // The console is busy copying; the app should not take slow answers for it being gone.
        LongCommands.shared.begin()
        defer {
            LongCommands.shared.end()
            copying.cancel()
            session.invalidateAndCancel()
        }
        let transfer = TransferService(host: host)
        var last: Int64 = 0
        var still = Date()
        while true {
            try await Task.sleep(nanoseconds: 15_000_000_000)
            try Task.checkCancellation()
            let copied = (try? await transfer.withFTP { try await $0.treeSize(disc.destination) }) ?? last
            progress(copied)
            if disc.bytes > 0, copied >= disc.bytes { return }
            if copied > last {
                last = copied
                still = Date()
            } else if Date().timeIntervalSince(still) > 120 {
                if disc.bytes == 0 || copied >= disc.bytes * 99 / 100 { return }
                throw PS3Error.timeout("kopieringen har stått still i två minuter (\(Format.bytes(copied)) av \(Format.bytes(disc.bytes)))")
            }
        }
    }

    public func abort() async throws {
        OperationLog.record("rip-abort", host)
        try await WebMAN(host: host).get("/copy.ps3$abort")
    }
}
