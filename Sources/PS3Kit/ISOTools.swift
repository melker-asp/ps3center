import CryptoKit
import Foundation

/// What the PC tools for PS3 ISOs do (aldostools' PS3 ISO Tools on Windows, built on Estwald's
/// makeps3iso, extractps3iso and splitps3iso), on the Mac: an ISO from a game folder, a game
/// folder from an ISO, and ISOs split for FAT32 and joined again.
public enum PS3ISO {
    /// FAT32 holds files up to 4 GiB − 1 byte. Parts are 4 GiB − 64 KiB, as webMAN writes them
    /// when it copies to USB (`include/file/file_copy.h`) and as splitps3iso does. webMAN mounts
    /// name.iso.0, .iso.1 … in order, for PS3 games, Blu-ray and DVD (`include/mount/mount_cobra.h`).
    public static let partSize: Int64 = 0xFFFF_0000

    static let chunkSize = 8 << 20

    /// How many parts of `partSize` hold `size` bytes.
    public static func partCount(for size: Int64) -> Int {
        max(1, Int((size + partSize - 1) / partSize))
    }

    /// The bytes in each part of a file of `size` split in `parts`: equal parts but the last.
    public static func partSizes(for size: Int64, parts: Int) -> [Int64] {
        guard parts > 1 else { return [size] }
        return (0..<parts).map { min(partSize, size - Int64($0) * partSize) }
    }

    /// The parts of a split image that exist, from "Game.iso.0" on, until one is missing.
    public static func parts(startingAt first: URL) -> [URL] {
        guard first.path.hasSuffix(".0") else { return [first] }
        let stem = String(first.path.dropLast(2))
        var result: [URL] = []
        while FileManager.default.fileExists(atPath: "\(stem).\(result.count)") {
            result.append(URL(fileURLWithPath: "\(stem).\(result.count)"))
        }
        return result
    }

    /// A name FAT32 takes: no \ / : * ? " < > |, and no dot or space at the end.
    public static func fatName(_ name: String) -> String {
        var result = name.replacingOccurrences(of: ":", with: " -")
        result.removeAll { "\\/*?\"<>|".contains($0) || $0.isNewline }
        while let last = result.last, last == "." || last == " " { result.removeLast() }
        return result.isEmpty ? "Game" : result
    }

    /// Splits `iso` into .iso.0, .iso.1 … in `folder` (beside it by default), as splitps3iso
    /// does. The ISO is left as it is.
    @discardableResult
    public static func split(_ iso: URL, into folder: URL? = nil, progress: (Int64, Int64) -> Void = { _, _ in }) throws -> [URL] {
        guard iso.pathExtension.lowercased() == "iso" else {
            throw PS3Error.invalidFile("\(iso.lastPathComponent) is not an .iso.")
        }
        let size = FileRouter.fileSize(iso)
        guard size > partSize else {
            throw PS3Error.refused("\(iso.lastPathComponent) is \(Format.bytes(size)) and fits on FAT32 without being split.")
        }
        let base = (folder ?? iso.deletingLastPathComponent()).appendingPathComponent(iso.lastPathComponent)
        if FileManager.default.fileExists(atPath: base.path + ".0") {
            throw PS3Error.refused("\(base.lastPathComponent).0 already exists.")
        }
        let writer = PartWriter(base: base, split: true)
        try copy([iso], into: writer, total: size, progress: progress)
        return writer.files
    }

    /// Joins Game.iso.0, .iso.1 … into Game.iso in `folder` (beside the parts by default).
    @discardableResult
    public static func join(_ first: URL, into folder: URL? = nil, progress: (Int64, Int64) -> Void = { _, _ in }) throws -> URL {
        guard first.lastPathComponent.lowercased().hasSuffix(".iso.0") else {
            throw PS3Error.invalidFile("\(first.lastPathComponent) is not the first part (.iso.0).")
        }
        let parts = parts(startingAt: first)
        guard !parts.isEmpty else { throw PS3Error.invalidFile("Can't find \(first.lastPathComponent).") }
        let target = (folder ?? first.deletingLastPathComponent()).appendingPathComponent(String(first.lastPathComponent.dropLast(2)))
        if FileManager.default.fileExists(atPath: target.path) {
            throw PS3Error.refused("\(target.lastPathComponent) already exists.")
        }
        let writer = PartWriter(base: target, split: false)
        try copy(parts, into: writer, total: parts.map(FileRouter.fileSize).reduce(0, +), progress: progress)
        return target
    }

    /// Unpacks a PS3 ISO into a game folder (as extractps3iso does), with the names from the
    /// Joliet tree. Like makeps3iso, it leaves out the system update on the disc (PS3_UPDATE):
    /// PS3 Center never brings firmware along.
    public static func extract(_ iso: URL, into folder: URL? = nil,
                               progress: (Int64, Int64) -> Void = { _, _ in }) throws -> (folder: URL, leftOut: [String]) {
        if iso.lastPathComponent.lowercased().hasSuffix(".iso.0") {
            throw PS3Error.refused("Join the parts first (ps3 iso join); then the ISO can be extracted.")
        }
        let image = try ISOImage(url: iso, joliet: true)
        let tree = try image.tree()
        let all = tree.files
        let isUpdate = { (path: String) in path.split(separator: "/").dropLast().last?.uppercased() == "PS3_UPDATE" }
        let files = all.filter { !isUpdate($0.path) }
        let target = folder ?? iso.deletingPathExtension()
        let fm = FileManager.default
        if fm.fileExists(atPath: target.path) {
            throw PS3Error.refused("\(target.path) already exists.")
        }
        let total = Int64(files.reduce(0) { $0 + $1.size })
        var done: Int64 = 0
        // A name in the image must never point outside the folder.
        func inside(_ path: String) throws -> URL {
            let components = path.split(separator: "/").map(String.init)
            guard !components.isEmpty, components.allSatisfy({ $0 != "." && $0 != ".." && !$0.contains("\0") }) else {
                throw PS3Error.invalidFile("A file name in the ISO points outside the folder: \(path)")
            }
            return components.reduce(target) { $0.appendingPathComponent($1) }
        }
        do {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            for path in tree.folders {
                try fm.createDirectory(at: try inside(path), withIntermediateDirectories: true)
            }
            for file in files {
                let url = try inside(file.path)
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard fm.createFile(atPath: url.path, contents: nil) else {
                    throw PS3Error.invalidFile("Can't create \(url.path).")
                }
                let output = try FileHandle(forWritingTo: url)
                defer { try? output.close() }
                try image.readChunks(extent: file.extent, size: file.size) { chunk in
                    try Task.checkCancellation()
                    try output.write(contentsOf: chunk)
                    done += Int64(chunk.count)
                    progress(done, total)
                }
            }
        } catch {
            try? fm.removeItem(at: target)
            throw error
        }
        return (target, all.filter { isUpdate($0.path) }.map(\.path))
    }

    /// Copies `sources` one after the other into `writer`, and removes what it wrote if that fails.
    static func copy(_ sources: [URL], into writer: PartWriter, total: Int64, progress: (Int64, Int64) -> Void) throws {
        do {
            for source in sources {
                let input = try FileHandle(forReadingFrom: source)
                defer { try? input.close() }
                while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
                    try Task.checkCancellation()
                    try writer.write(chunk)
                    progress(writer.written, total)
                }
            }
            try writer.close()
        } catch {
            writer.discard()
            throw error
        }
    }
}

/// Writes one stream of bytes to a file, or to name.0, name.1 … of `PS3ISO.partSize` each. A part
/// is only opened when there is something to put in it, so an image of exactly 4 GiB − 64 KiB
/// gets no empty .1 (splitps3iso leaves one). Everything is written as name.part and gets its
/// name in `close`, so webMAN never lists half an image, even after ctrl-C.
final class PartWriter {
    let base: URL
    let split: Bool
    let partSize: Int64
    /// The finished names.
    private(set) var files: [URL] = []
    private(set) var written: Int64 = 0
    private var handle: FileHandle?
    private var inPart: Int64 = 0

    init(base: URL, split: Bool, partSize: Int64 = PS3ISO.partSize) {
        self.base = base
        self.split = split
        self.partSize = partSize
    }

    static func partial(_ url: URL) -> URL { URL(fileURLWithPath: url.path + ".part") }

    func write(_ data: Data) throws {
        var offset = data.startIndex
        while offset < data.endIndex {
            if handle == nil { try openNext() }
            let room = split ? partSize - inPart : Int64.max
            let count = Int(min(Int64(data.endIndex - offset), room))
            try handle?.write(contentsOf: data[offset..<(offset + count)])
            offset += count
            inPart += Int64(count)
            written += Int64(count)
            if split, inPart == partSize {
                try handle?.close()
                handle = nil
            }
        }
    }

    private func openNext() throws {
        let url = split ? URL(fileURLWithPath: base.path + ".\(files.count)") : base
        let partial = Self.partial(url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: partial.path, contents: nil) else {
            throw PS3Error.invalidFile("Can't create \(partial.path).")
        }
        handle = try FileHandle(forWritingTo: partial)
        files.append(url)
        inPart = 0
    }

    /// Finishes the last part and gives every part its name, replacing an older file with it.
    func close() throws {
        if files.isEmpty { try openNext() }  // an empty stream still makes its file
        try handle?.close()
        handle = nil
        let fm = FileManager.default
        for file in files {
            if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
            try fm.moveItem(at: Self.partial(file), to: file)
        }
    }

    /// Removes what was written, after a failure or a cancel.
    func discard() {
        try? handle?.close()
        handle = nil
        for file in files { try? FileManager.default.removeItem(at: Self.partial(file)) }
    }
}

/// A PS3 ISO made from a game folder (PS3_GAME/…, as in GAMES), laid out as Estwald's
/// makeps3iso lays it out: the PS3 disc header in sectors 0–1 (one plain region, the title ID),
/// ISO 9660 and Joliet descriptors in 16–18, path tables from 20, directories from 32, then the
/// files, a folder's own files before its subfolders'. A file over 4 GB gets several records
/// (multi-extent). .66600, .66601 … (a file split for FAT32 by webMAN or multiMAN) become one file.
public struct PS3ISOBuilder: Sendable {
    /// The most one directory record describes; bigger files get one record per piece.
    static let extentLimit: UInt64 = 0xFFFF_F800
    static let sector = 2048

    struct File: Sendable {
        let name: String
        let sources: [URL]
        let size: UInt64
        let date: Date
        var lba: UInt32 = 0

        var extents: Int { size == 0 ? 1 : Int((size + PS3ISOBuilder.extentLimit - 1) / PS3ISOBuilder.extentLimit) }
    }

    struct Directory: Sendable {
        let name: String
        /// Index of the parent in `directories`; the root is its own parent.
        let parent: Int
        let date: Date
        var files: [File] = []
        var children: [Int] = []
        var primaryLBA: UInt32 = 0
        var jolietLBA: UInt32 = 0
        var primarySectors: UInt32 = 1
        var jolietSectors: UInt32 = 1
    }

    struct PathTables: Sendable {
        var primarySize = 0
        var jolietSize = 0
        var primaryL: UInt32 = 20
        var primaryM: UInt32 = 0
        var jolietL: UInt32 = 0
        var jolietM: UInt32 = 0
    }

    public let folder: URL
    /// "BLES00932", from PS3_GAME/PARAM.SFO.
    public let titleID: String
    public let title: String
    /// Files left out, relative to the folder: the system update on the disc (PS3_UPDATE), as
    /// makeps3iso leaves it out.
    public let leftOut: [String]
    /// In path-table order: level by level, and by name within a parent.
    let directories: [Directory]
    let pathTables: PathTables
    let firstFileLBA: UInt32
    /// Sectors of 2048 bytes in the image.
    public let sectors: UInt32
    let created: Date

    /// Bytes in the image.
    public var size: Int64 { Int64(sectors) * Int64(Self.sector) }
    public var fileCount: Int { directories.reduce(0) { $0 + $1.files.count } }
    public var largestFile: UInt64 { directories.flatMap(\.files).map(\.size).max() ?? 0 }

    public init(folder: URL, created: Date = Date()) throws {
        let folder = folder.standardizedFileURL
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("PS3_GAME/PARAM.SFO")),
              let sfo = ParamSFO(data: data), let id = sfo.titleID, id.count >= 5 else {
            throw PS3Error.invalidFile("\(folder.lastPathComponent) is not a PS3 game folder: PS3_GAME/PARAM.SFO is missing.")
        }
        self.folder = folder
        self.titleID = id
        self.title = sfo.title ?? folder.lastPathComponent
        self.created = created

        // The tree, level by level, so the indices are the path table's directory numbers.
        var directories = [Directory(name: "", parent: 0, date: Self.modified(folder))]
        var urls = [folder]
        var paths = [""]  // relative to the folder, "PS3_GAME/USRDIR"
        var leftOut: [String] = []
        var index = 0
        while index < directories.count {
            let skipsFiles = directories[index].name.uppercased() == "PS3_UPDATE"
            let scan = try Self.scan(urls[index], skipsFiles: skipsFiles)
            directories[index].files = scan.files
            leftOut += scan.leftOut.map { paths[index] + $0.lastPathComponent }
            for sub in scan.folders {
                directories[index].children.append(directories.count)
                directories.append(Directory(name: sub.lastPathComponent, parent: index, date: Self.modified(sub)))
                urls.append(sub)
                paths.append(paths[index] + sub.lastPathComponent + "/")
            }
            index += 1
        }

        var tables = PathTables()
        tables.primarySize = Self.pathTableSize(directories, joliet: false)
        tables.jolietSize = Self.pathTableSize(directories, joliet: true)
        let primarySectors = UInt32((tables.primarySize + 2047) / 2048)
        let jolietSectors = UInt32((tables.jolietSize + 2047) / 2048)
        tables.primaryM = tables.primaryL + primarySectors
        tables.jolietL = tables.primaryM + primarySectors
        tables.jolietM = tables.jolietL + jolietSectors

        var next = UInt64(max(32, tables.jolietM + jolietSectors))
        for i in directories.indices {
            directories[i].primarySectors = Self.pack(Self.recordLengths(directories, i, joliet: false)).sectors
            directories[i].jolietSectors = Self.pack(Self.recordLengths(directories, i, joliet: true)).sectors
        }
        for i in directories.indices {
            directories[i].primaryLBA = UInt32(next)
            next += UInt64(directories[i].primarySectors)
        }
        for i in directories.indices {
            directories[i].jolietLBA = UInt32(next)
            next += UInt64(directories[i].jolietSectors)
        }
        let firstFile = UInt32(next)
        func place(_ index: Int) {
            for f in directories[index].files.indices {
                directories[index].files[f].lba = UInt32(truncatingIfNeeded: next)
                next += (directories[index].files[f].size + 2047) / 2048
            }
            for child in directories[index].children { place(child) }
        }
        place(0)
        guard next < UInt64(UInt32.max) else {
            throw PS3Error.invalidFile("\(folder.lastPathComponent) is too large for an ISO.")
        }
        self.directories = directories
        self.pathTables = tables
        self.firstFileLBA = firstFile
        self.sectors = UInt32(next)
        self.leftOut = leftOut
    }

    /// Writes the image to `base` ("Game.iso"), or to Game.iso.0, .iso.1 … when `split`, and
    /// removes what it wrote if that fails or is cancelled. `progress` gets the bytes written.
    @discardableResult
    public func write(to base: URL, split: Bool, progress: (Int64) -> Void = { _ in }) throws -> [URL] {
        let writer = PartWriter(base: base, split: split)
        do {
            try writer.write(Data(header()))
            try writeFiles(of: 0, to: writer, progress: progress)
            guard writer.written == size else {
                throw PS3Error.invalidFile("The ISO came to \(writer.written) bytes instead of \(size).")
            }
            try writer.close()
            return writer.files
        } catch {
            writer.discard()
            throw error
        }
    }

    private func writeFiles(of index: Int, to writer: PartWriter, progress: (Int64) -> Void) throws {
        for file in directories[index].files {
            var copied: UInt64 = 0
            for source in file.sources {
                let input = try FileHandle(forReadingFrom: source)
                defer { try? input.close() }
                while let chunk = try input.read(upToCount: PS3ISO.chunkSize), !chunk.isEmpty {
                    try Task.checkCancellation()
                    guard copied + UInt64(chunk.count) <= file.size else { throw Self.changed(file) }
                    try writer.write(chunk)
                    copied += UInt64(chunk.count)
                    progress(writer.written)
                }
            }
            guard copied == file.size else { throw Self.changed(file) }
            let padding = Int((2048 - copied % 2048) % 2048)
            if padding > 0 { try writer.write(Data(count: padding)) }
        }
        for child in directories[index].children {
            try writeFiles(of: child, to: writer, progress: progress)
        }
    }

    static func changed(_ file: File) -> PS3Error {
        .invalidFile("\(file.name) changed while the ISO was being written.")
    }

    // MARK: Scanning

    /// A folder's files and subfolders, sorted by name; hidden files (.DS_Store, ._*) and
    /// symbolic links are not part of a game.
    static func scan(_ dir: URL, skipsFiles: Bool) throws -> (files: [File], folders: [URL], leftOut: [URL]) {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let entries = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
            .filter { !FileRouter.ignoredNames.contains($0.lastPathComponent) }
        let names = Set(entries.map(\.lastPathComponent))
        var files: [File] = []
        var folders: [URL] = []
        var leftOut: [URL] = []
        for url in entries {
            let values = try url.resourceValues(forKeys: keys)
            let name = url.lastPathComponent
            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true {
                try checkName(name, at: url)
                folders.append(url)
                continue
            }
            guard values.isRegularFile == true else { continue }
            if skipsFiles {
                leftOut.append(url)
                continue
            }
            let date = values.contentModificationDate ?? Date(timeIntervalSince1970: 0)
            if let range = name.range(of: #"\.666\d\d$"#, options: .regularExpression) {
                // .66601 … are read with the .66600 that starts them.
                guard name.hasSuffix(".66600") else { continue }
                let base = String(name[..<range.lowerBound])
                var sources = [url]
                while sources.count < 100, names.contains(base + String(format: ".666%02d", sources.count)) {
                    sources.append(dir.appendingPathComponent(base + String(format: ".666%02d", sources.count)))
                }
                try checkName(base, at: url)
                let size = sources.map { UInt64(FileRouter.fileSize($0)) }.reduce(0, +)
                files.append(File(name: base, sources: sources, size: size, date: date))
                continue
            }
            try checkName(name, at: url)
            files.append(File(name: name, sources: [url], size: UInt64(values.fileSize ?? 0), date: date))
        }
        let byName = { (a: String, b: String) in upper(a).lexicographicallyPrecedes(upper(b)) }
        return (files.sorted { byName($0.name, $1.name) }, folders.sorted { byName($0.lastPathComponent, $1.lastPathComponent) }, leftOut)
    }

    /// A directory record holds at most 255 bytes, name included (twice as long in Joliet).
    static func checkName(_ name: String, at url: URL) throws {
        guard name.utf16.count <= 100, name.utf8.count <= 200 else {
            throw PS3Error.invalidFile("\(url.lastPathComponent) has too long a name for an ISO (100 characters at most).")
        }
    }

    static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date(timeIntervalSince1970: 0)
    }

    // MARK: Layout

    /// The name in the primary tree: the name in capitals, as makeps3iso writes it.
    static func upper(_ name: String) -> [UInt8] {
        name.utf8.map { (0x61...0x7A).contains($0) ? $0 - 0x20 : $0 }
    }

    /// UCS-2 big-endian, Joliet's names.
    static func ucs2(_ name: String) -> [UInt8] {
        name.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
    }

    enum Item {
        case dot, dotdot, file(Int, part: Int), folder(Int)
    }

    static func items(_ directories: [Directory], _ index: Int) -> [Item] {
        var items: [Item] = [.dot, .dotdot]
        for (f, file) in directories[index].files.enumerated() {
            for part in 0..<file.extents { items.append(.file(f, part: part)) }
        }
        items += directories[index].children.map { .folder($0) }
        return items
    }

    static func name(_ item: Item, _ directories: [Directory], _ index: Int, joliet: Bool) -> [UInt8] {
        switch item {
        case .dot: return [0]
        case .dotdot: return [1]
        case .file(let f, _):
            let name = directories[index].files[f].name
            return joliet ? ucs2(name) + [0, 0x3B, 0, 0x31] : upper(name) + [0x3B, 0x31]  // ";1"
        case .folder(let child):
            return joliet ? ucs2(directories[child].name) : upper(directories[child].name)
        }
    }

    /// 33 bytes, the name, and six spare bytes after it, as makeps3iso leaves them; even length.
    static func recordLength(nameLength: Int) -> Int {
        let length = 33 + nameLength + 6
        return length + (length & 1)
    }

    static func recordLengths(_ directories: [Directory], _ index: Int, joliet: Bool) -> [Int] {
        items(directories, index).map { recordLength(nameLength: name($0, directories, index, joliet: joliet).count) }
    }

    /// Where each record goes in a directory's sectors: a record never crosses a sector.
    static func pack(_ lengths: [Int]) -> (offsets: [Int], sectors: UInt32) {
        var offsets: [Int] = []
        var offset = 0
        for length in lengths {
            if offset % sector + length > sector { offset = (offset / sector + 1) * sector }
            offsets.append(offset)
            offset += length
        }
        return (offsets, UInt32(max(1, (offset + sector - 1) / sector)))
    }

    static func pathName(_ directories: [Directory], _ index: Int, joliet: Bool) -> [UInt8] {
        index == 0 ? [0] : (joliet ? ucs2(directories[index].name) : upper(directories[index].name))
    }

    static func pathTableSize(_ directories: [Directory], joliet: Bool) -> Int {
        directories.indices.reduce(0) { total, i in
            let length = pathName(directories, i, joliet: joliet).count
            return total + 8 + length + (length & 1)
        }
    }

    // MARK: Header

    /// Sectors 0 up to the first file: disc header, descriptors, path tables and directories.
    func header() -> [UInt8] {
        var b = [UInt8](repeating: 0, count: Int(firstFileLBA) * Self.sector)
        // Sector 0: one region of plain (decrypted) sectors, the whole image.
        b[3] = 1
        Self.be32(&b, 8, 0)
        Self.be32(&b, 12, sectors - 1)
        // Sector 1: "PlayStation3" and the title ID as "BLES-00932"; the rest is filler, as in makeps3iso.
        Self.put(&b, 0x800, Array("PlayStation3".utf8))
        Self.fill(&b, 0x810, 0x20, 0x20)
        Self.put(&b, 0x810, Array((titleID.prefix(4) + "-" + titleID.dropFirst(4)).utf8.prefix(0x20)))
        let filler = self.filler(0x1C0)
        Self.put(&b, 0x840, Array(filler.prefix(0x1B0)))
        Self.put(&b, 0x9F0, Array(filler.suffix(0x10)))

        descriptor(&b, at: 16 * Self.sector, joliet: false)
        descriptor(&b, at: 17 * Self.sector, joliet: true)
        let end = 18 * Self.sector
        b[end] = 255
        Self.put(&b, end + 1, Array("CD001".utf8))
        b[end + 6] = 1

        pathTable(&b, at: Int(pathTables.primaryL) * Self.sector, joliet: false, bigEndian: false)
        pathTable(&b, at: Int(pathTables.primaryM) * Self.sector, joliet: false, bigEndian: true)
        pathTable(&b, at: Int(pathTables.jolietL) * Self.sector, joliet: true, bigEndian: false)
        pathTable(&b, at: Int(pathTables.jolietM) * Self.sector, joliet: true, bigEndian: true)

        for index in directories.indices {
            records(&b, of: index, joliet: false)
            records(&b, of: index, joliet: true)
        }
        return b
    }

    func descriptor(_ b: inout [UInt8], at o: Int, joliet: Bool) {
        b[o] = joliet ? 2 : 1
        Self.put(&b, o + 1, Array("CD001".utf8))
        b[o + 6] = 1
        let blank: UInt8 = joliet ? 0 : 0x20
        let volume = joliet ? Self.ucs2("PS3VOLUME") : Array("PS3VOLUME".utf8)
        Self.fill(&b, o + 8, 32, blank)  // system
        Self.fill(&b, o + 40, 32, blank)
        Self.put(&b, o + 40, volume)
        Self.both32(&b, o + 80, sectors)
        if joliet {
            // UCS-2 level 1.
            b[o + 88] = 0x25
            b[o + 89] = 0x2F
            b[o + 90] = 0x40
        }
        Self.both16(&b, o + 120, 1)
        Self.both16(&b, o + 124, 1)
        Self.both16(&b, o + 128, UInt16(Self.sector))
        Self.both32(&b, o + 132, UInt32(joliet ? pathTables.jolietSize : pathTables.primarySize))
        Self.le32(&b, o + 140, joliet ? pathTables.jolietL : pathTables.primaryL)
        Self.be32(&b, o + 148, joliet ? pathTables.jolietM : pathTables.primaryM)
        let root = directories[0]
        Self.record(&b, at: o + 156, length: 34, extent: joliet ? root.jolietLBA : root.primaryLBA,
                    size: (joliet ? root.jolietSectors : root.primarySectors) * UInt32(Self.sector),
                    date: root.date, flags: 2, name: [0])
        Self.fill(&b, o + 190, 128, blank)  // volume set
        Self.put(&b, o + 190, volume)
        Self.fill(&b, o + 318, 128 * 3, blank)  // publisher, preparer, application
        Self.fill(&b, o + 702, 37 * 3, blank)  // copyright, abstract and bibliographic files
        Self.put(&b, o + 813, Array(Self.longDate(created).utf8))
        for offset in [830, 847, 864] { Self.put(&b, o + offset, Array("0000000000000000".utf8)) }
        b[o + 881] = 1
    }

    func pathTable(_ b: inout [UInt8], at start: Int, joliet: Bool, bigEndian: Bool) {
        var o = start
        for (i, directory) in directories.enumerated() {
            let name = Self.pathName(directories, i, joliet: joliet)
            let lba = joliet ? directory.jolietLBA : directory.primaryLBA
            b[o] = UInt8(name.count)
            if bigEndian {
                Self.be32(&b, o + 2, lba)
                b[o + 6] = UInt8((directory.parent + 1) >> 8)
                b[o + 7] = UInt8((directory.parent + 1) & 0xFF)
            } else {
                Self.le32(&b, o + 2, lba)
                b[o + 6] = UInt8((directory.parent + 1) & 0xFF)
                b[o + 7] = UInt8((directory.parent + 1) >> 8)
            }
            Self.put(&b, o + 8, name)
            o += 8 + name.count + (name.count & 1)
        }
    }

    func records(_ b: inout [UInt8], of index: Int, joliet: Bool) {
        let directory = directories[index]
        let items = Self.items(directories, index)
        let names = items.map { Self.name($0, directories, index, joliet: joliet) }
        let offsets = Self.pack(names.map { Self.recordLength(nameLength: $0.count) }).offsets
        let start = Int(joliet ? directory.jolietLBA : directory.primaryLBA) * Self.sector
        func place(_ d: Directory) -> (UInt32, UInt32) {
            joliet ? (d.jolietLBA, d.jolietSectors * UInt32(Self.sector)) : (d.primaryLBA, d.primarySectors * UInt32(Self.sector))
        }
        for (k, item) in items.enumerated() {
            let at = start + offsets[k]
            let length = Self.recordLength(nameLength: names[k].count)
            switch item {
            case .dot:
                let (lba, size) = place(directory)
                Self.record(&b, at: at, length: length, extent: lba, size: size, date: directory.date, flags: 2, name: names[k])
            case .dotdot:
                let parent = directories[directory.parent]
                let (lba, size) = place(parent)
                Self.record(&b, at: at, length: length, extent: lba, size: size, date: parent.date, flags: 2, name: names[k])
            case .file(let f, let part):
                let file = directory.files[f]
                let last = part == file.extents - 1
                let size = last ? file.size - UInt64(part) * Self.extentLimit : Self.extentLimit
                let extent = file.lba + UInt32(UInt64(part) * Self.extentLimit / UInt64(Self.sector))
                Self.record(&b, at: at, length: length, extent: extent, size: UInt32(size), date: file.date,
                            flags: last ? 0 : 0x80, name: names[k])
            case .folder(let child):
                let (lba, size) = place(directories[child])
                Self.record(&b, at: at, length: length, extent: lba, size: size, date: directories[child].date, flags: 2, name: names[k])
            }
        }
    }

    static func record(_ b: inout [UInt8], at o: Int, length: Int, extent: UInt32, size: UInt32, date: Date, flags: UInt8, name: [UInt8]) {
        b[o] = UInt8(length)
        both32(&b, o + 2, extent)
        both32(&b, o + 10, size)
        put(&b, o + 18, shortDate(date))
        b[o + 25] = flags
        both16(&b, o + 28, 1)
        b[o + 32] = UInt8(name.count)
        put(&b, o + 33, name)
    }

    /// Bytes that only need to differ between games, made from the title so that the same folder
    /// always gives the same image.
    func filler(_ count: Int) -> [UInt8] {
        var bytes: [UInt8] = []
        var block = Array(SHA256.hash(data: Data("\(titleID)|\(title)|\(sectors)".utf8)))
        while bytes.count < count {
            bytes += block
            block = Array(SHA256.hash(data: Data(block)))
        }
        return Array(bytes.prefix(count))
    }

    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// A directory record's date: years since 1900, month, day, hour, minute, second, UTC.
    static func shortDate(_ date: Date) -> [UInt8] {
        let c = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return [UInt8(clamping: (c.year ?? 1900) - 1900), UInt8(c.month ?? 1), UInt8(c.day ?? 1),
                UInt8(c.hour ?? 0), UInt8(c.minute ?? 0), UInt8(c.second ?? 0), 0]
    }

    /// A descriptor's date: "YYYYMMDDHHMMSS00", UTC.
    static func longDate(_ date: Date) -> String {
        let c = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02d%02d%02d%02d00", c.year ?? 1970, c.month ?? 1, c.day ?? 1, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    static func put(_ b: inout [UInt8], _ o: Int, _ bytes: [UInt8]) {
        b.replaceSubrange(o..<(o + bytes.count), with: bytes)
    }

    static func fill(_ b: inout [UInt8], _ o: Int, _ count: Int, _ value: UInt8) {
        b.replaceSubrange(o..<(o + count), with: repeatElement(value, count: count))
    }

    static func le32(_ b: inout [UInt8], _ o: Int, _ v: UInt32) {
        for i in 0..<4 { b[o + i] = UInt8((v >> (8 * UInt32(i))) & 0xFF) }
    }

    static func be32(_ b: inout [UInt8], _ o: Int, _ v: UInt32) {
        for i in 0..<4 { b[o + i] = UInt8((v >> (8 * UInt32(3 - i))) & 0xFF) }
    }

    static func both32(_ b: inout [UInt8], _ o: Int, _ v: UInt32) {
        le32(&b, o, v)
        be32(&b, o + 4, v)
    }

    static func both16(_ b: inout [UInt8], _ o: Int, _ v: UInt16) {
        b[o] = UInt8(v & 0xFF)
        b[o + 1] = UInt8(v >> 8)
        b[o + 2] = UInt8(v >> 8)
        b[o + 3] = UInt8(v & 0xFF)
    }
}
