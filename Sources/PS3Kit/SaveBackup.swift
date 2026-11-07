import Foundation

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
/// copied to Saves/<user>/<folder> when a file in it changed (name, size or date in the
/// listing), and the copy it replaces is kept in Saves/<user>/.previous. Only TITLE and
/// SUB_TITLE are read from PARAM.SFO; its account fields are never shown.
public struct SaveBackupService: Sendable {
    public let host: String

    public init(host: String) { self.host = host }

    public static var root: URL {
        _ = migration
        return BackupFolder.url(rootName)
    }

    static let rootName = "Saves"
    static let manifestName = ".ps3center.json"
    static let lastBackupName = "last-backup.json"
    static let previousName = ".previous"
    static let beforeRestoreName = ".before-restore"

    /// Once per process: the Swedish names the backup had before (Sparfiler, senaste.json,
    /// .tidigare, .innan-aterstallning) become the English ones.
    private static let migration: Void = migrateNames(in: BackupFolder.base)

    static func migrateNames(in base: URL) {
        BackupFolder.migrate("Sparfiler", to: rootName, in: base)
        let root = base.appendingPathComponent(rootName, isDirectory: true)
        BackupFolder.migrate("senaste.json", to: lastBackupName, in: root)
        let users = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for user in users where isUser(user.lastPathComponent) {
            BackupFolder.migrate(".tidigare", to: previousName, in: user)
            BackupFolder.migrate(".innan-aterstallning", to: beforeRestoreName, in: user)
        }
    }

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
        try? JSONEncoder().encode(Date()).write(to: Self.root.appendingPathComponent(Self.lastBackupName))
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
            events("Copying \(save.title)")
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
    /// the copy it replaces moves to .previous.
    private func copy(_ save: SaveGame, files: [FTPClient.Entry], from ftp: FTPClient, into folder: URL) async throws {
        let fm = FileManager.default
        let fresh = folder.deletingLastPathComponent().appendingPathComponent(".new-\(save.folder)", isDirectory: true)
        try? fm.removeItem(at: fresh)
        try fm.createDirectory(at: fresh, withIntermediateDirectories: true)
        for file in files {
            guard let data = try await ftp.download(Self.remoteFolder(save) + "/" + file.name, limit: 512 << 20) else {
                throw PS3Error.invalidFile("\(file.name) could not be read")
            }
            try data.write(to: fresh.appendingPathComponent(file.name))
        }
        if fm.fileExists(atPath: folder.path) {
            let previous = folder.deletingLastPathComponent().appendingPathComponent(Self.previousName, isDirectory: true)
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
        guard let data = try? Data(contentsOf: root.appendingPathComponent(lastBackupName)) else { return nil }
        return try? JSONDecoder().decode(Date.self, from: data)
    }

    /// Removes a save from the console, after copying it to the backup so it can be put back.
    /// Not while a game runs. Logged.
    public func delete(_ save: SaveGame, events: @Sendable (String) -> Void = { _ in }) async throws {
        guard try await WebMAN(host: host).runningProcess() == nil else { throw PS3Error.gameRunning }
        try await TransferService(host: host).withFTP { ftp in
            let remote = Self.remoteFolder(save)
            let files = try await ftp.list(remote).filter { !$0.isDirectory }
            guard !files.isEmpty else { throw PS3Error.refused("\(save.title) is not on the PS3.") }
            events("Saving a copy on the Mac")
            let folder = Self.localFolder(save)
            try await copy(save, files: files, from: ftp, into: folder)
            try Self.write(Manifest(save: save, files: Self.signature(files), backedUpAt: Date()), in: folder)
            OperationLog.record(.deleteSave, "\(save.title) (\(save.user)/\(save.folder))")
            events("Deleting the save")
            try await ftp.removeTree(remote)
        }
    }

    /// Puts a save from the backup back on the console, for the same user. Not while a game
    /// runs. What is on the console now is copied to .before-restore first. Logged.
    public func restore(_ save: SaveGame, events: @Sendable (String) -> Void = { _ in }) async throws {
        let folder = Self.localFolder(save)
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .filter { $0.lastPathComponent != Self.manifestName }
        guard !files.isEmpty else { throw PS3Error.refused("\(save.title) is not in the backup.") }
        guard try await WebMAN(host: host).runningProcess() == nil else { throw PS3Error.gameRunning }
        try await TransferService(host: host).withFTP { ftp in try await restore(save, files: files, ftp: ftp, events: events) }
    }

    private func restore(_ save: SaveGame, files: [URL], ftp: FTPClient, events: @Sendable (String) -> Void) async throws {
        let fm = FileManager.default
        let remote = Self.remoteFolder(save)
        let current = try await ftp.list(remote).filter { !$0.isDirectory }
        if !current.isEmpty {
            events("Saving what is on the PS3 now")
            let safety = Self.root.appendingPathComponent(save.user, isDirectory: true)
                .appendingPathComponent(Self.beforeRestoreName, isDirectory: true)
                .appendingPathComponent(save.folder, isDirectory: true)
            try? fm.removeItem(at: safety)
            try fm.createDirectory(at: safety, withIntermediateDirectories: true)
            for file in current {
                if let data = try await ftp.download(remote + "/" + file.name, limit: 512 << 20) {
                    try data.write(to: safety.appendingPathComponent(file.name))
                }
            }
        }
        OperationLog.record(.restore, "\(save.title) (\(save.user)/\(save.folder))")
        try await ftp.makeDirectories(remote)
        for file in files {
            events("Sending \(file.lastPathComponent)")
            try await ftp.upload(file: file, to: remote + "/" + file.lastPathComponent) { _ in }
        }
    }
}
