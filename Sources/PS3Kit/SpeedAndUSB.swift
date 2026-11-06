import Foundation

/// How fast files move between the Mac and the console, measured with `ps3 speedtest` (or the
/// app's Överföringar) and kept in ~/.config/ps3center/speed.json for time estimates.
public struct SpeedResult: Codable, Equatable, Sendable {
    /// Bytes per second.
    public let upload: Double
    public let download: Double?
    /// "Wi-Fi" or "LAN", as the console reported it.
    public let network: String?
    public let measuredAt: Date
}

public enum SpeedTest {
    static var file: URL { ConfigStore.directory.appendingPathComponent("speed.json") }
    static let remote = "/dev_hdd0/tmp/ps3center-speedtest.bin"

    public static func last() -> SpeedResult? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SpeedResult.self, from: data)
    }

    static func save(_ result: SpeedResult) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: ConfigStore.directory, withIntermediateDirectories: true)
        try? encoder.encode(result).write(to: file, options: .atomic)
        if let network = result.network {
            var all = byNetwork()
            all[network] = result
            try? encoder.encode(all).write(to: networksFile, options: .atomic)
        }
    }

    static var networksFile: URL { ConfigStore.directory.appendingPathComponent("speeds.json") }

    /// The latest measurement per network ("Wi-Fi", "LAN"), so a measurement with a cable still
    /// counts while the console is back on Wi-Fi.
    public static func byNetwork() -> [String: SpeedResult] {
        guard let data = try? Data(contentsOf: networksFile) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: SpeedResult].self, from: data)) ?? [:]
    }

    /// What forum reports give for a PS3 on a cable, 10–40 MB/s (PLAN.md); used until there is
    /// a measurement over LAN.
    public static let typicalCable: ClosedRange<Double> = 10e6...40e6

    /// "ca 7 min" from a measurement over LAN, else "ca 4–16 min" from typical cable speeds.
    public static func cableEstimate(bytes: Int64, measured: [String: SpeedResult] = byNetwork()) -> String {
        if let lan = measured["LAN"], lan.upload > 0 {
            let seconds = Double(bytes) / lan.upload
            return seconds < 60 ? Format.playTime(seconds) : "ca \(Format.playTime(seconds))"
        }
        let fast = Double(bytes) / typicalCable.upperBound
        let slow = Double(bytes) / typicalCable.lowerBound
        let fastMinutes = max(1, Int((fast / 60).rounded()))
        let slowMinutes = max(1, Int((slow / 60).rounded()))
        if slowMinutes < 60 {
            return fastMinutes == slowMinutes ? "ca \(fastMinutes) min" : "ca \(fastMinutes)–\(slowMinutes) min"
        }
        return "ca \(Format.playTime(fast))–\(Format.playTime(slow))"
    }

    /// Seconds to send `bytes` at the last measured upload speed, or nil before a measurement.
    public static func estimate(bytes: Int64) -> TimeInterval? {
        guard let speed = last()?.upload, speed > 0 else { return nil }
        return Double(bytes) / speed
    }

    /// Sends data to /dev_hdd0/tmp for `seconds` (at most `megabytes`), reads back what arrived
    /// and removes it, so the test takes about the same short time on Wi-Fi and with a cable.
    /// Only the upload has to work; the read-back is reported when it does. The console is
    /// marked busy meanwhile (`WebMAN.isBusy`), since it answers slowly while it takes in data
    /// at full speed.
    public static func run(host: String, seconds: TimeInterval = 5, megabytes: Int = 256, events: TransferHandler) async throws -> SpeedResult {
        LongCommands.shared.begin()
        defer { LongCommands.shared.end() }
        let limit = Int64(megabytes) << 20
        let route = Route(local: URL(fileURLWithPath: "/dev/zero"), remote: remote, kind: .other, size: limit, title: "Hastighetstest")
        let transfer = TransferService(host: host)
        let (up, down) = try await transfer.withFTP { ftp -> (Double, Double) in
            events(.started(route, resumingFrom: 0))
            let start = Date()
            var lastReport = Date.distantPast
            let sent = try await ftp.uploadZeros(to: remote, seconds: seconds, limit: limit) { bytes in
                let now = Date()
                guard now.timeIntervalSince(lastReport) >= 0.25 else { return }
                lastReport = now
                let elapsed = max(now.timeIntervalSince(start), 0.001)
                // The time, not the size, sets how far along it is.
                events(.progress(route, sent: Int64(min(elapsed / seconds, 1) * 1000), total: 1000, bytesPerSecond: Double(bytes) / elapsed))
            }
            let upSeconds = max(Date().timeIntervalSince(start), 0.001)
            events(.finished(route, seconds: upSeconds))
            events(.note("Läser tillbaka…"))
            let readStart = Date()
            let data = try? await ftp.download(remote, limit: Int(sent) + 1)
            let downSeconds = max(Date().timeIntervalSince(readStart), 0.001)
            try? await ftp.delete(remote)
            return (Double(sent) / upSeconds, Double(data?.count ?? 0) / downSeconds)
        }
        let network = try? await WebMAN(host: host).snapshot().network
        let result = SpeedResult(upload: up, download: down > 0 ? down : nil, network: network, measuredAt: Date())
        save(result)
        return result
    }
}

/// Getting many games onto the console without the network: a FAT32 USB drive with webMAN's
/// folders. FAT32 holds no file over 4 GB, so a PS3 ISO or a film over that is split into
/// .iso.0, .iso.1 … (as webMAN does when it copies to USB), and a game folder with such a file
/// becomes a PS3 ISO in parts, which plays from the drive (what PS3 ISO Tools does by hand).
/// macOS writes FAT32 ("MS-DOS (FAT)" in Disk Utility) but not NTFS.
public enum USBDrive {
    static var partSize: Int64 { PS3ISO.partSize }

    public struct Volume: Sendable, Equatable, Identifiable {
        public let url: URL
        public let name: String
        public let format: String
        public let free: Int64
        public let capacity: Int64
        public var id: String { url.path }
        public var isFAT32: Bool { format.localizedCaseInsensitiveContains("FAT32") || format.localizedCaseInsensitiveContains("MS-DOS") }

        init(url: URL, name: String, format: String, free: Int64, capacity: Int64) {
            self.url = url
            self.name = name
            self.format = format
            self.free = free
            self.capacity = capacity
        }
    }

    static let volumeKeys: [URLResourceKey] = [.volumeNameKey, .volumeLocalizedFormatDescriptionKey, .volumeAvailableCapacityKey,
                                               .volumeTotalCapacityKey, .volumeIsInternalKey, .volumeIsReadOnlyKey]

    public static func volume(_ url: URL) -> Volume? {
        guard let values = try? url.resourceValues(forKeys: Set(volumeKeys)) else { return nil }
        return Volume(url: url, name: values.volumeName ?? url.lastPathComponent, format: values.volumeLocalizedFormatDescription ?? "",
                      free: Int64(values.volumeAvailableCapacity ?? 0), capacity: Int64(values.volumeTotalCapacity ?? 0))
    }

    /// The drives a game can go to: mounted under /Volumes, writable, and not the Mac's own disk.
    public static func volumes() -> [Volume] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: volumeKeys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url -> Volume? in
            guard url.path.hasPrefix("/Volumes/"),
                  let values = try? url.resourceValues(forKeys: Set(volumeKeys)),
                  values.volumeIsInternal != true, values.volumeIsReadOnly != true else { return nil }
            return volume(url)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public struct Copy: Sendable, Identifiable {
        public enum Kind: Sendable {
            /// A file, split in parts when it is over 4 GB.
            case file
            /// A game folder that fits as it is (GAMES).
            case folder
            /// A game folder with a file over 4 GB, made into a PS3 ISO on the drive (PS3ISO).
            case isoFromFolder
        }

        public let game: Game
        public let source: URL
        /// The destination, or the first part for a split image.
        public let destination: URL
        public let parts: Int
        public let size: Int64
        public var kind: Kind = .file
        var iso: PS3ISOBuilder?

        public var id: String { destination.path }
    }

    public struct Plan: Sendable {
        public var copies: [Copy] = []
        /// Games that cannot go on FAT32, with the reason.
        public var skipped: [(game: Game, reason: String)] = []
        public var total: Int64 { copies.reduce(0) { $0 + $1.size } }

        public init() {}
    }

    /// webMAN mounts parts for PS3 games, Blu-ray and DVD images (`include/mount/mount_cobra.h`).
    static let splittable: Set<Game.Platform> = [.ps3, .bluRay, .dvd]

    /// What `copy` would do with `games` (from the Mac's library) on the drive at `root`.
    public static func plan(_ games: [Game], on root: URL) -> Plan {
        var plan = Plan()
        for game in games {
            guard game.source == .mac, let remotePath = game.remotePath else { continue }
            let folder = ((remotePath as NSString).deletingLastPathComponent as NSString).lastPathComponent
            if game.isFolder {
                let url = URL(fileURLWithPath: game.path)
                if let big = largestFile(in: url), big > partSize {
                    do {
                        let iso = try PS3ISOBuilder(folder: url)
                        let base = root.appendingPathComponent("PS3ISO/\(PS3ISO.fatName(url.lastPathComponent)).iso")
                        let parts = PS3ISO.partCount(for: iso.size)
                        plan.copies.append(Copy(game: game, source: url, destination: parts > 1 ? URL(fileURLWithPath: base.path + ".0") : base,
                                                parts: parts, size: iso.size, kind: .isoFromFolder, iso: iso))
                    } catch {
                        plan.skipped.append((game, "spelmappen har en fil över 4 GB och går inte att göra om till en ISO: \(error.localizedDescription)"))
                    }
                    continue
                }
                plan.copies.append(Copy(game: game, source: url,
                                        destination: root.appendingPathComponent("\(folder)/\((game.path as NSString).lastPathComponent)"),
                                        parts: 1, size: game.size ?? folderSize(url), kind: .folder))
                continue
            }
            for file in [game.path] + game.companions {
                let url = URL(fileURLWithPath: file)
                let size = FileRouter.fileSize(url)
                var destination = root.appendingPathComponent("\(folder)/\(url.lastPathComponent)")
                var parts = 1
                if size > partSize {
                    guard splittable.contains(game.platform), url.pathExtension.lowercased() == "iso" else {
                        plan.skipped.append((game, "\(url.lastPathComponent) är över 4 GB och kan bara delas för PS3-ISO:er och filmer"))
                        break
                    }
                    parts = PS3ISO.partCount(for: size)
                    destination = root.appendingPathComponent("\(folder)/\(url.lastPathComponent).0")
                }
                plan.copies.append(Copy(game: game, source: url, destination: destination, parts: parts, size: size))
            }
        }
        return plan
    }

    /// Copies (and splits, or makes into an ISO) the planned files, skipping ones already there
    /// with the right size. Files are written as .part and get their names when they are whole.
    public static func copy(_ copies: [Copy], events: TransferHandler) async throws {
        let fm = FileManager.default
        for copy in copies {
            let route = Route(local: copy.source, remote: copy.destination.path, kind: .other, size: copy.size, title: copy.game.title)
            try fm.createDirectory(at: copy.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if copy.kind == .folder {
                if fm.fileExists(atPath: copy.destination.path) {
                    events(.skipped(route, reason: "finns redan på disken"))
                    continue
                }
                events(.started(route, resumingFrom: 0))
                try fm.copyItem(at: copy.source, to: copy.destination)
                events(.finished(route, seconds: 0))
                continue
            }
            let base = URL(fileURLWithPath: copy.parts > 1 ? String(copy.destination.path.dropLast(2)) : copy.destination.path)
            let targets = copy.parts > 1 ? (0..<copy.parts).map { URL(fileURLWithPath: "\(base.path).\($0)") } : [base]
            if zip(targets, PS3ISO.partSizes(for: copy.size, parts: copy.parts)).allSatisfy({ FileRouter.fileSize($0) == $1 }) {
                events(.skipped(route, reason: "finns redan på disken"))
                continue
            }
            events(.started(route, resumingFrom: 0))
            let start = Date()
            var lastReport = Date.distantPast
            func report(_ written: Int64) {
                let now = Date()
                guard now.timeIntervalSince(lastReport) >= 0.25 else { return }
                lastReport = now
                events(.progress(route, sent: written, total: copy.size, bytesPerSecond: Double(written) / max(now.timeIntervalSince(start), 0.001)))
            }
            if copy.kind == .isoFromFolder, let iso = copy.iso {
                try iso.write(to: base, split: copy.parts > 1) { report($0) }
            } else {
                let writer = PartWriter(base: base, split: copy.parts > 1)
                try PS3ISO.copy([copy.source], into: writer, total: copy.size) { written, _ in report(written) }
            }
            events(.finished(route, seconds: Date().timeIntervalSince(start)))
        }
    }

    static func largestFile(in folder: URL) -> Int64? {
        ((try? FileRouter.filesRecursively(in: folder)) ?? []).map(FileRouter.fileSize).max()
    }

    static func folderSize(_ folder: URL) -> Int64 {
        ((try? FileRouter.filesRecursively(in: folder)) ?? []).map(FileRouter.fileSize).reduce(0, +)
    }
}
