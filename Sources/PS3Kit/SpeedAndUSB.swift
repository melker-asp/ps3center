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
            let sent = try await ftp.uploadZeros(to: remote, seconds: seconds, limit: limit) { sent in
                let now = Date()
                guard now.timeIntervalSince(lastReport) >= 0.25 else { return }
                lastReport = now
                let elapsed = max(now.timeIntervalSince(start), 0.001)
                // The time, not the size, sets how far along it is.
                events(.progress(route, sent: Int64(min(elapsed / seconds, 1) * 1000), total: 1000, bytesPerSecond: Double(sent) / elapsed))
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
/// folders, PS3 ISOs over 4 GB split into .iso.0, .iso.1 … (equal parts but the last), as
/// webMAN's wiki describes. macOS writes FAT32 ("MS-DOS (FAT32)" in Disk Utility) but not NTFS.
public enum USBDrive {
    /// The largest file FAT32 holds is 4 GiB − 1 byte; parts are a multiple of 64 KiB under that.
    static let partSize: Int64 = 0xFFFF_0000

    public struct Volume: Sendable {
        public let format: String
        public let free: Int64
        public var isFAT32: Bool { format.localizedCaseInsensitiveContains("FAT32") || format.localizedCaseInsensitiveContains("MS-DOS") }
    }

    public static func volume(_ url: URL) -> Volume? {
        guard let values = try? url.resourceValues(forKeys: [.volumeLocalizedFormatDescriptionKey, .volumeAvailableCapacityKey]) else { return nil }
        return Volume(format: values.volumeLocalizedFormatDescription ?? "", free: Int64(values.volumeAvailableCapacity ?? 0))
    }

    public struct Copy: Sendable {
        public let game: Game
        public let source: URL
        /// The destination, or the first part for a split ISO.
        public let destination: URL
        public let parts: Int
        public let size: Int64
    }

    /// What `copy` would do with `games` (from the Mac's library) on the drive at `root`; games
    /// that cannot go on FAT32 come back as skipped with the reason.
    public static func plan(_ games: [Game], on root: URL) -> (copies: [Copy], skipped: [(Game, String)]) {
        var copies: [Copy] = []
        var skipped: [(Game, String)] = []
        for game in games {
            guard game.source == .mac, let remotePath = game.remotePath else { continue }
            let folder = ((remotePath as NSString).deletingLastPathComponent as NSString).lastPathComponent
            if game.isFolder {
                if let big = largestFile(in: URL(fileURLWithPath: game.path)), big > partSize {
                    skipped.append((game, "spelmappen har en fil över 4 GB, som FAT32 inte rymmer"))
                    continue
                }
                copies.append(Copy(game: game, source: URL(fileURLWithPath: game.path),
                                   destination: root.appendingPathComponent("\(folder)/\((game.path as NSString).lastPathComponent)"),
                                   parts: 1, size: game.size ?? folderSize(URL(fileURLWithPath: game.path))))
                continue
            }
            for file in [game.path] + game.companions {
                let url = URL(fileURLWithPath: file)
                let size = FileRouter.fileSize(url)
                var destination = root.appendingPathComponent("\(folder)/\(url.lastPathComponent)")
                var parts = 1
                if size > partSize {
                    guard game.platform == .ps3, url.pathExtension.lowercased() == "iso" else {
                        skipped.append((game, "\(url.lastPathComponent) är över 4 GB och kan bara delas för PS3-ISO:er"))
                        break
                    }
                    parts = Int((size + partSize - 1) / partSize)
                    destination = root.appendingPathComponent("\(folder)/\(url.lastPathComponent).0")
                }
                copies.append(Copy(game: game, source: url, destination: destination, parts: parts, size: size))
            }
        }
        return (copies, skipped)
    }

    /// Copies (and splits) the planned files, skipping ones already there with the right size.
    public static func copy(_ copies: [Copy], events: TransferHandler) async throws {
        let fm = FileManager.default
        for copy in copies {
            let route = Route(local: copy.source, remote: copy.destination.path, kind: .other, size: copy.size, title: copy.game.title)
            try fm.createDirectory(at: copy.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: copy.source.path, isDirectory: &isDirectory), isDirectory.boolValue {
                if fm.fileExists(atPath: copy.destination.path) {
                    events(.skipped(route, reason: "finns redan på disken"))
                    continue
                }
                events(.started(route, resumingFrom: 0))
                try fm.copyItem(at: copy.source, to: copy.destination)
                events(.finished(route, seconds: 0))
                continue
            }
            let base = copy.parts > 1 ? String(copy.destination.path.dropLast(2)) : copy.destination.path
            let targets = copy.parts > 1 ? (0..<copy.parts).map { "\(base).\($0)" } : [base]
            let expected = (0..<targets.count).map { index -> Int64 in
                copy.parts > 1 ? min(partSize, copy.size - Int64(index) * partSize) : copy.size
            }
            if zip(targets, expected).allSatisfy({ FileRouter.fileSize(URL(fileURLWithPath: $0)) == $1 }) {
                events(.skipped(route, reason: "finns redan på disken"))
                continue
            }
            events(.started(route, resumingFrom: 0))
            let start = Date()
            var lastReport = Date.distantPast
            let input = try FileHandle(forReadingFrom: copy.source)
            defer { try? input.close() }
            var written: Int64 = 0
            for (index, target) in targets.enumerated() {
                try Task.checkCancellation()
                fm.createFile(atPath: target, contents: nil)
                let output = try FileHandle(forWritingTo: URL(fileURLWithPath: target))
                var remaining = expected[index]
                while remaining > 0 {
                    try Task.checkCancellation()
                    guard let chunk = try input.read(upToCount: Int(min(remaining, 8 << 20))), !chunk.isEmpty else { break }
                    try output.write(contentsOf: chunk)
                    remaining -= Int64(chunk.count)
                    written += Int64(chunk.count)
                    let now = Date()
                    if now.timeIntervalSince(lastReport) >= 0.25 {
                        lastReport = now
                        events(.progress(route, sent: written, total: copy.size, bytesPerSecond: Double(written) / max(now.timeIntervalSince(start), 0.001)))
                    }
                }
                try output.close()
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
