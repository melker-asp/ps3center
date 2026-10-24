import Foundation

/// Just enough ISO 9660 to identify a disc image and read small files from it.
/// (macOS's bsdtar misreads some PS3 ISOs because of the region table in sector 0.)
/// Also reads raw CD images (.bin with 2352-byte sectors, as PS1 and some PS2 games come).
public final class ISOImage {
    public struct Entry: Sendable {
        public let name: String
        public let extent: UInt64
        public let size: UInt64
        public let isDirectory: Bool
    }

    /// The logical block: what ISO 9660 counts in, whatever the image stores per sector.
    static let blockSize: UInt64 = 2048

    public let systemID: String
    public let volumeID: String
    private let handle: FileHandle
    private let root: Entry
    /// 2048 for plain images; 2352 for raw CD images, whose 2048 data bytes start at `dataOffset`.
    private let sectorSize: UInt64
    private let dataOffset: UInt64

    public init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        let head = try handle.read(upToCount: 16) ?? Data()
        let sync = Data([0x00] + Array(repeating: UInt8(0xFF), count: 10) + [0x00])
        if head.count == 16, head.prefix(12) == sync {
            sectorSize = 2352
            dataOffset = head[head.startIndex + 15] == 2 ? 24 : 16  // MODE2 form 1 or MODE1
        } else {
            sectorSize = 2048
            dataOffset = 0
        }
        let pvd = try Self.read(handle, block: 16, count: Int(Self.blockSize), sectorSize: sectorSize, dataOffset: dataOffset)
        guard pvd.count == Int(Self.blockSize) else {
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

    /// `count` bytes from logical block `block` on, skipping the headers of raw sectors.
    static func read(_ handle: FileHandle, block: UInt64, count: Int, sectorSize: UInt64, dataOffset: UInt64) throws -> Data {
        if sectorSize == blockSize {
            try handle.seek(toOffset: block * blockSize)
            return try handle.read(upToCount: count) ?? Data()
        }
        var result = Data()
        var current = block
        while result.count < count {
            try handle.seek(toOffset: current * sectorSize + dataOffset)
            guard let chunk = try handle.read(upToCount: min(Int(blockSize), count - result.count)), !chunk.isEmpty else { break }
            result.append(chunk)
            current += 1
        }
        return result
    }

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
                // Records never cross blocks; skip padding to the next one.
                offset = (offset / Int(Self.blockSize) + 1) * Int(Self.blockSize)
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
        try Self.read(handle, block: entry.extent, count: Int(min(entry.size, limit)), sectorSize: sectorSize, dataOffset: dataOffset)
    }

    public func readFile(_ path: String) throws -> Data? {
        guard let entry = try find(path), !entry.isDirectory else { return nil }
        return try read(entry)
    }
}
