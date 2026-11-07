import Foundation

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
        ("/dev_hdd0/game", "Installed games and apps"),
        ("/dev_hdd0/PS3ISO", "PS3 ISOs"),
        ("/dev_hdd0/GAMES", "Game folders"),
        ("/dev_hdd0/PS2ISO", "PS2 ISOs"),
        ("/dev_hdd0/PSXISO", "PS1 images"),
        ("/dev_hdd0/PSPISO", "PSP ISOs"),
        ("/dev_hdd0/BDISO", "Blu-ray"),
        ("/dev_hdd0/DVDISO", "DVD"),
        ("/dev_hdd0/home", "Users and saves"),
        ("/dev_hdd0/packages", "Packages"),
        ("/dev_hdd0/tmp", "Temporary files and webMAN's cache"),
        ("/dev_hdd0/video", "Video"),
        ("/dev_hdd0/music", "Music"),
        ("/dev_hdd0/photo", "Photos"),
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
        guard let parsed = Self.parseStat(page) else { throw PS3Error.invalidFile("webMAN's /stat.ps3 gave no answer for \(path)") }
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
