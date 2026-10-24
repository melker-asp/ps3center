import Foundation

/// Just enough ISO 9660 to identify a disc image and read small files from it.
/// (macOS's bsdtar misreads some PS3 ISOs because of the region table in sector 0.)
public final class ISOImage {
    public struct Entry: Sendable {
        public let name: String
        public let extent: UInt64
        public let size: UInt64
        public let isDirectory: Bool
    }

    static let sectorSize: UInt64 = 2048

    public let systemID: String
    public let volumeID: String
    private let handle: FileHandle
    private let root: Entry

    public init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        try handle.seek(toOffset: 16 * Self.sectorSize)
        guard let pvd = try handle.read(upToCount: Int(Self.sectorSize)), pvd.count == Int(Self.sectorSize) else {
            throw PS3Error.invalidFile("\(url.lastPathComponent) är för liten för att vara en ISO.")
        }
        let b = [UInt8](pvd)
        guard b[0] == 1, String(decoding: b[1..<6], as: UTF8.self) == "CD001" else {
            throw PS3Error.invalidFile("\(url.lastPathComponent) är ingen ISO 9660-avbild.")
        }
        systemID = String(decoding: b[8..<40], as: UTF8.self).trimmingCharacters(in: .whitespaces)
        volumeID = String(decoding: b[40..<72], as: UTF8.self).trimmingCharacters(in: .whitespaces)
        guard let root = Self.parseRecord(Array(b[156..<190])) else {
            throw PS3Error.invalidFile("\(url.lastPathComponent): trasig rotkatalog.")
        }
        self.root = root
    }

    deinit { try? handle.close() }

    static func le32(_ b: [UInt8], _ o: Int) -> UInt64 {
        UInt64(b[o]) | UInt64(b[o + 1]) << 8 | UInt64(b[o + 2]) << 16 | UInt64(b[o + 3]) << 24
    }

    static func parseRecord(_ b: [UInt8]) -> Entry? {
        guard b.count >= 34, Int(b[0]) <= b.count else { return nil }
        let nameLength = Int(b[32])
        guard 33 + nameLength <= b.count else { return nil }
        var name = String(decoding: b[33..<(33 + nameLength)], as: UTF8.self)
        if let semicolon = name.firstIndex(of: ";") { name = String(name[..<semicolon]) }
        if name.hasSuffix(".") { name.removeLast() }
        return Entry(name: name, extent: le32(b, 2), size: le32(b, 10), isDirectory: b[25] & 0x02 != 0)
    }

    public func listDirectory(_ dir: Entry) throws -> [Entry] {
        guard dir.size <= 4 << 20 else { return [] }
        let data = try read(dir)
        let b = [UInt8](data)
        var entries: [Entry] = []
        var offset = 0
        while offset < b.count {
            let length = Int(b[offset])
            if length == 0 {
                // Records never cross sectors; skip padding to the next one.
                offset = (offset / Int(Self.sectorSize) + 1) * Int(Self.sectorSize)
                continue
            }
            guard offset + length <= b.count else { break }
            if let entry = Self.parseRecord(Array(b[offset..<(offset + length)])),
               entry.name != "\u{0}", entry.name != "\u{1}" {
                entries.append(entry)
            }
            offset += length
        }
        return entries
    }

    /// Case-insensitive lookup such as "PS3_GAME/PARAM.SFO".
    public func find(_ path: String) throws -> Entry? {
        var current = root
        for component in path.split(separator: "/") {
            guard current.isDirectory,
                  let next = try listDirectory(current).first(where: { $0.name.caseInsensitiveCompare(String(component)) == .orderedSame })
            else { return nil }
            current = next
        }
        return current
    }

    public func read(_ entry: Entry, limit: UInt64 = 4 << 20) throws -> Data {
        try handle.seek(toOffset: entry.extent * Self.sectorSize)
        return try handle.read(upToCount: Int(min(entry.size, limit))) ?? Data()
    }

    public func readFile(_ path: String) throws -> Data? {
        guard let entry = try find(path), !entry.isDirectory else { return nil }
        return try read(entry)
    }
}
