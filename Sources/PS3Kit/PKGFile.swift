import Foundation

/// Reads the header of a PS3 .pkg: magic 7F 50 4B 47, content ID at 0x30.
public struct PKGInfo: Equatable, Sendable {
    /// e.g. "UP0001-RMTC00001_00-0000000000000000"
    public let contentID: String

    /// e.g. "RMTC00001"
    public var titleID: String? {
        let parts = contentID.split(separator: "-")
        guard parts.count >= 2 else { return nil }
        return String(parts[1].prefix(9))
    }

    public init(contentID: String) {
        self.contentID = contentID
    }

    public init?(header: Data) {
        let b = [UInt8](header)
        guard b.count >= 0x54, b[0] == 0x7F, b[1] == 0x50, b[2] == 0x4B, b[3] == 0x47 else { return nil }
        let id = b[0x30..<0x54].prefix { $0 != 0 }
        contentID = String(decoding: id, as: UTF8.self)
    }

    public init?(url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 0x60) else { return nil }
        self.init(header: data)
    }
}
