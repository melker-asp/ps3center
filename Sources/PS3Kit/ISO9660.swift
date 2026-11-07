import CryptoKit
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
    /// Names come from the Joliet tree (UCS-2): PS3 discs keep their long names there.
    private let joliet: Bool
    /// 2048 for plain images; 2352 for raw CD images, whose 2048 data bytes start at `dataOffset`.
    private let sectorSize: UInt64
    private let dataOffset: UInt64

    /// `joliet` reads names from the Joliet tree when the image has one, as the IRD tools do.
    public init(url: URL, joliet: Bool = false) throws {
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
            throw PS3Error.invalidFile("\(url.lastPathComponent) is too small to be an ISO.")
        }
        let b = [UInt8](pvd)
        guard b[0] == 1, String(decoding: b[1..<6], as: UTF8.self) == "CD001" else {
            throw PS3Error.invalidFile("\(url.lastPathComponent) is not an ISO 9660 image.")
        }
        systemID = String(decoding: b[8..<40], as: UTF8.self).trimmingCharacters(in: .whitespaces)
        volumeID = String(decoding: b[40..<72], as: UTF8.self).trimmingCharacters(in: .whitespaces)
        var rootRecord = Self.parseRecord(Array(b[156..<190]), joliet: false)
        var useJoliet = false
        if joliet {
            // Supplementary descriptors follow the primary; Joliet's escape sequence is %/@, %/C or %/E.
            for block in UInt64(17)..<UInt64(32) {
                let d = [UInt8](try Self.read(handle, block: block, count: Int(Self.blockSize), sectorSize: sectorSize, dataOffset: dataOffset))
                guard d.count == Int(Self.blockSize), String(decoding: d[1..<6], as: UTF8.self) == "CD001", d[0] != 255 else { break }
                if d[0] == 2, d[88] == 0x25, d[89] == 0x2F, [0x40, 0x43, 0x45].contains(d[90]),
                   let jolietRoot = Self.parseRecord(Array(d[156..<190]), joliet: true) {
                    rootRecord = jolietRoot
                    useJoliet = true
                    break
                }
            }
        }
        guard let found = rootRecord else {
            throw PS3Error.invalidFile("\(url.lastPathComponent): broken root directory.")
        }
        root = found
        self.joliet = useJoliet
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

    static func parseRecord(_ b: [UInt8], joliet: Bool = false) -> Entry? {
        guard b.count >= 34, Int(b[0]) <= b.count else { return nil }
        let nameLength = Int(b[32])
        guard 33 + nameLength <= b.count else { return nil }
        let raw = Array(b[33..<(33 + nameLength)])
        var name: String
        if joliet, nameLength > 1 {
            // UCS-2 big-endian; "." and ".." stay single bytes 0 and 1.
            let units = stride(from: 0, to: raw.count - 1, by: 2).map { UInt16(raw[$0]) << 8 | UInt16(raw[$0 + 1]) }
            name = String(decoding: units, as: UTF16.self)
        } else {
            name = String(decoding: raw, as: UTF8.self)
        }
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
            if let entry = Self.parseRecord(Array(b[offset..<(offset + length)]), joliet: joliet),
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

    /// Every file under the root as "PS3_GAME/USRDIR/EBOOT.BIN", with its first block and its
    /// size. A file over 4 GB is stored as several records with the same name (multi-extent);
    /// they are joined.
    public func allFiles() throws -> [(path: String, extent: UInt64, size: UInt64)] {
        try tree().files
    }

    /// Every file as `allFiles` lists them, and every folder ("PS3_GAME/USRDIR"), empty ones too.
    public func tree() throws -> (files: [(path: String, extent: UInt64, size: UInt64)], folders: [String]) {
        var result: [(path: String, extent: UInt64, size: UInt64)] = []
        var folders: [String] = []
        var visited = Set<UInt64>()
        func walk(_ dir: Entry, prefix: String, depth: Int) throws {
            guard depth < 32, visited.insert(dir.extent).inserted else { return }
            var previous: String?
            for entry in try listDirectory(dir) {
                let path = prefix.isEmpty ? entry.name : prefix + "/" + entry.name
                if entry.isDirectory {
                    folders.append(path)
                    try walk(entry, prefix: path, depth: depth + 1)
                    previous = nil
                } else if path == previous, let last = result.indices.last {
                    result[last].size += entry.size
                } else {
                    result.append((path, entry.extent, entry.size))
                    previous = path
                }
            }
        }
        try walk(root, prefix: "", depth: 0)
        return (result, folders)
    }

    /// MD5 of `size` bytes from block `extent` on, read in pieces (plain 2048-byte images).
    public func md5(extent: UInt64, size: UInt64, progress: (UInt64) -> Void = { _ in }) throws -> String {
        var hasher = Insecure.MD5()
        var done: UInt64 = 0
        try readChunks(extent: extent, size: size) { chunk in
            hasher.update(data: chunk)
            done += UInt64(chunk.count)
            progress(done)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// `size` bytes from block `extent` on, handed to `body` in pieces of at most 4 MB. Stops
    /// early if the image ends.
    public func readChunks(extent: UInt64, size: UInt64, _ body: (Data) throws -> Void) throws {
        var done: UInt64 = 0
        if sectorSize == Self.blockSize { try handle.seek(toOffset: extent * Self.blockSize) }
        while done < size {
            let count = Int(min(size - done, 4 << 20))
            let chunk: Data
            if sectorSize == Self.blockSize {
                chunk = try handle.read(upToCount: count) ?? Data()
            } else {
                chunk = try Self.read(handle, block: extent + done / Self.blockSize, count: count, sectorSize: sectorSize, dataOffset: dataOffset)
            }
            guard !chunk.isEmpty else { break }
            try body(chunk)
            done += UInt64(chunk.count)
        }
    }
}
