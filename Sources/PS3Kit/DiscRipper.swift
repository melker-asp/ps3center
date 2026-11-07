import Foundation

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
            throw PS3Error.refused("\((mounted as NSString).lastPathComponent) is mounted, so the disc does not show. Unmount it first.")
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
            throw PS3Error.refused("\(disc.destination) already exists.")
        }
        guard let url = URL(string: "http://\(host)/copy.ps3/dev_bdvd&to=" + WebMAN.encodeCommand(disc.destination)) else {
            throw PS3Error.invalidFile(disc.destination)
        }
        OperationLog.record(.rip, "\(disc.title) → \(disc.destination)")
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
                throw PS3Error.timeout("the copy has not moved for two minutes (\(Format.bytes(copied)) of \(Format.bytes(disc.bytes)))")
            }
        }
    }

    public func abort() async throws {
        OperationLog.record(.ripAbort, host)
        try await WebMAN(host: host).get("/copy.ps3$abort")
    }
}
