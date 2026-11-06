import CommonCrypto
import CryptoKit
import Foundation

/// The values PS2 Classics are encrypted with in ps2classic (psdev-net, the tool behind PS2
/// Classic GUI): two CEX keys, three NPD keys and the klicensee of the PS2 Classics placeholder.
/// They are Sony's, so PS3 Center's code holds none of them, only their SHA-256 (the user's
/// decision 7 Nov 2026). They are fetched on request from webMAN MOD's repo on GitHub, or imported
/// from the PC tool's files, and kept in ~/.config/ps3center/ps2classic-keys.json, readable by the
/// user only. The IV is sixteen zero bytes and no secret.
public struct PS2ClassicKeys: Equatable, Sendable {
    public enum Name: String, CaseIterable, Sendable {
        case data, meta, npdKEK, npdOMAC2, npdOMAC3, klicensee

        /// Where the value is: its array in ps2classic.c, or the placeholder's .rifkey file.
        public var source: String {
            switch self {
            case .data: return "ps2_key_cex_data"
            case .meta: return "ps2_key_cex_meta"
            case .npdKEK: return "npd_kek"
            case .npdOMAC2: return "npd_omac_key2"
            case .npdOMAC3: return "npd_omac_key3"
            case .klicensee: return PS2ClassicMaker.contentID + ".rifkey"
            }
        }

        /// SHA-256 of the right value, worked out 7 Nov 2026 from webMAN MOD's
        /// `_Projects_/tools/ps2classic_*.7z`. A hash says whether a value is right without
        /// holding it.
        var fingerprint: String {
            switch self {
            case .data: return "5e8554174a44625f09e53bc8a9a64f23a2ea0f9402d4928d38c470221ea44c8c"
            case .meta: return "8ff377e110a5f0045bfe9af6799b51dddb14840742365da873456ced0b8f8aa4"
            case .npdKEK: return "54978dc85d27e051d571cbd3cdf330ff444ee31a909f75d46f9ea6139d86968b"
            case .npdOMAC2: return "7eddc78a29cd6ecaecf46d101ab2143d018861bebecf3608f84909ed825fdc63"
            case .npdOMAC3: return "842193d954d2476741563151d674deec1549d11a03000be97d2e8c93b6100d04"
            case .klicensee: return "159e49617f661c59f98748d7ab6fa168df0af64f12ac14adf87eec64c535e14a"
            }
        }
    }

    public internal(set) var values: [Name: Data]

    public init(values: [Name: Data] = [:]) {
        self.values = values
    }

    public var missing: [Name] { Name.allCases.filter { values[$0] == nil } }
    /// Values that are there but not the right ones.
    public var wrong: [Name] { Name.allCases.filter { name in values[name].map { !Self.matches($0, name) } ?? false } }
    public var isComplete: Bool { missing.isEmpty && wrong.isEmpty }

    static func matches(_ value: Data, _ name: Name) -> Bool {
        value.count == 16 && SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined() == name.fingerprint
    }

    /// What is wrong, in words, or nil when the keys are complete.
    public var problem: String? {
        if !wrong.isEmpty {
            return "Fel värde för \(wrong.map(\.source).joined(separator: ", ")) (stämmer inte med PS3 Centers fingeravtryck)."
        }
        if !missing.isEmpty {
            return "Saknar \(missing.map(\.source).joined(separator: ", "))."
        }
        return nil
    }

    // MARK: Storage

    static var file: URL { ConfigStore.directory.appendingPathComponent("ps2classic-keys.json") }

    /// The keys saved on this Mac, or nil.
    public static func load() -> PS2ClassicKeys? {
        guard let data = try? Data(contentsOf: file),
              let hex = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
        var values: [Name: Data] = [:]
        for (key, value) in hex {
            guard let name = Name(rawValue: key), let bytes = Data(hex: value) else { continue }
            values[name] = bytes
        }
        return PS2ClassicKeys(values: values)
    }

    /// Saves the keys for the user only (0600). Nothing else ever writes them out.
    public func save() throws {
        try FileManager.default.createDirectory(at: ConfigStore.directory, withIntermediateDirectories: true)
        let hex = Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value.map { String(format: "%02x", $0) }.joined()) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let file = Self.file
        FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        try encoder.encode(hex).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    public static func remove() throws {
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    // MARK: Reading the PC tool's files

    /// Where webMAN MOD's repo keeps ps2classic's source (with the CEX and NPD keys) and the
    /// placeholder's .rifkey, and their paths inside the archives.
    static let archives = [
        URL(string: "https://raw.githubusercontent.com/aldostools/webMAN-MOD/master/_Projects_/tools/ps2classic_for_multidisc.7z")!,
        URL(string: "https://raw.githubusercontent.com/aldostools/webMAN-MOD/master/_Projects_/tools/ps2classic_misc.7z")!,
    ]
    static let members = ["src/ps2classic.c", "src/ps2classic_v2_mod_by_d00bz/ps2rap/\(PS2ClassicMaker.contentID).rifkey"]

    /// Reads the values from the files PS2 Classic GUI and ps2classic come with: ps2classic.c (its
    /// arrays), the placeholder's .rifkey (16 bytes), or the .7z archives in webMAN MOD's repo
    /// that hold them. Values found later replace earlier ones.
    public static func read(_ urls: [URL]) throws -> PS2ClassicKeys {
        var keys = PS2ClassicKeys()
        for url in urls {
            let lower = url.lastPathComponent.lowercased()
            if lower.hasSuffix(".7z") {
                for member in members {
                    guard let data = try? extract(member, from: url) else { continue }
                    keys.merge(member.hasSuffix(".c") ? values(inSource: String(decoding: data, as: UTF8.self)) : [.klicensee: data])
                }
            } else if FileRouter.fileSize(url) == 16 {
                keys.merge([.klicensee: try Data(contentsOf: url)])
            } else {
                let data = try Data(contentsOf: url)
                guard data.count < 1 << 20 else { throw PS3Error.invalidFile("\(url.lastPathComponent) är för stor för att vara ps2classic.c.") }
                keys.merge(values(inSource: String(decoding: data, as: UTF8.self)))
            }
        }
        return keys
    }

    mutating func merge(_ other: [Name: Data]) {
        values.merge(other) { $1 }
    }

    /// The values in C source like ps2classic.c: `u8 ps2_key_cex_data[] = { 0x.., … };`.
    static func values(inSource text: String) -> [Name: Data] {
        var result: [Name: Data] = [:]
        for name in Name.allCases where name != .klicensee {
            let pattern = #"\b"# + name.source + #"\s*\[\s*\]\s*=\s*\{([^}]*)\}"#
            guard let range = text.range(of: pattern, options: .regularExpression) else { continue }
            let body = text[range].drop { $0 != "{" }
            let bytes = body.matches(of: #/0[xX]([0-9A-Fa-f]{2})/#).compactMap { UInt8($0.1, radix: 16) }
            result[name] = Data(bytes)
        }
        return result
    }

    /// One file out of a .7z, with macOS's own bsdtar (libarchive reads 7z), written to memory only.
    static func extract(_ member: String, from archive: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
        process.arguments = ["-xOf", archive.path, member]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PS3Error.invalidFile("\(member) finns inte i \(archive.lastPathComponent).")
        }
        return data
    }

    /// Downloads the two archives from webMAN MOD's repo, reads the six values, checks them against
    /// the fingerprints and saves them on this Mac. Nothing else is kept.
    public static func fetch() async throws -> PS2ClassicKeys {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ps3center-ps2keys-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var files: [URL] = []
        for url in archives {
            let file = folder.appendingPathComponent(url.lastPathComponent)
            try await GitHub.download(url, to: file)
            files.append(file)
        }
        let keys = try read(files)
        if let problem = keys.problem {
            throw PS3Error.invalidFile("webMAN MOD:s arkiv gav inte de rätta nycklarna. \(problem)")
        }
        try keys.save()
        return keys
    }
}

extension Data {
    /// "0a1b…" → bytes, or nil for anything but an even number of hex digits.
    init?(hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}

/// A PS2 Classic (`<name>.BIN.ENC`) from a PS2 game's image, as `ps2classic prepare` and
/// `ps2classic e cex <rifkey> <iso> <out> ISO.BIN.ENC <content ID>` make it:
/// - the image is padded to 16 KB and gets an LIMG block at the end ("LIMG", 1, sectors, 0x800),
/// - a header of 16 KB: "PS2\0", version 1.1, NPD type 2, the placeholder's content ID, a random
///   hash and two AES-CMACs (over the content ID and "ISO.BIN.ENC", and over the header),
/// - then blocks of up to 0x200 segments of 16 KB, each segment AES-128-CBC with the data key and a
///   zero IV, after a table of SHA-1 and segment number per segment, encrypted with the meta key.
/// The data and meta keys are the klicensee encrypted with the two CEX keys. On HEN, webMAN links
/// the file as ISO.BIN.ENC in the PS2 Classics Launcher (PS2U10000), and PS3HEN makes the
/// placeholder's licence itself.
public enum PS2ClassicMaker {
    /// The PS2 Classics placeholder that webMAN's PS2 Classics Launcher installs.
    public static let contentID = "2P0001-PS2U10000_00-0000111122223333"
    static let fileName = "ISO.BIN.ENC"
    static let segment = 0x4000
    static let segmentsPerBlock = 0x200
    static let metaEntry = 0x20

    /// A PS2 image to read: an ISO (2048-byte sectors), or a raw CD image (.bin, 2352-byte sectors,
    /// behind a .cue), whose 2048 data bytes are taken from each sector.
    struct Source {
        let url: URL
        let sectorSize: Int
        let dataOffset: Int
        /// Bytes as 2048-byte sectors.
        let size: Int64
    }

    static func source(_ image: URL) throws -> Source {
        let url = try dataFile(for: image)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 16) ?? Data()
        let sync = Data([0x00] + Array(repeating: UInt8(0xFF), count: 10) + [0x00])
        let fileSize = FileRouter.fileSize(url)
        if head.count == 16, head.prefix(12) == sync {
            let offset = head[head.startIndex + 15] == 2 ? 24 : 16  // MODE2 form 1 or MODE1
            return Source(url: url, sectorSize: 2352, dataOffset: offset, size: fileSize / 2352 * 2048)
        }
        guard fileSize > 0 else { throw PS3Error.invalidFile("\(url.lastPathComponent) är tom.") }
        return Source(url: url, sectorSize: 2048, dataOffset: 0, size: fileSize)
    }

    /// The image itself: for a .cue, the first file it names.
    public static func dataFile(for image: URL) throws -> URL {
        guard image.pathExtension.lowercased() == "cue" else { return image }
        let text = String(decoding: try Data(contentsOf: image), as: UTF8.self)
        guard let match = text.firstMatch(of: #/FILE\s+"([^"]+)"/#) else {
            throw PS3Error.invalidFile("\(image.lastPathComponent) pekar inte på någon .bin.")
        }
        return image.deletingLastPathComponent().appendingPathComponent(String(match.1))
    }

    /// The title ID of a PS2 image ("SLES-53133"), from BOOT2 in its SYSTEM.CNF. Anything else is
    /// refused: a PS1 game (BOOT) already starts on HEN, and a PS3 or PSP image is no PS2 game.
    public static func check(_ image: URL) throws -> String? {
        let iso = try ISOImage(url: dataFile(for: image))
        guard let cnf = try iso.readFile("SYSTEM.CNF").map({ String(decoding: $0, as: UTF8.self) }) else {
            throw PS3Error.unsupportedFile("\(image.lastPathComponent) är inget PS2-spel (SYSTEM.CNF saknas).")
        }
        guard cnf.uppercased().contains("BOOT2") else {
            throw PS3Error.unsupportedFile("\(image.lastPathComponent) är ett PS1-spel. De startar redan på HEN, utan att göras om.")
        }
        return LocalGameReader.serial(from: cnf)
    }

    /// `<name>.BIN.ENC` for an image, with the title ID in brackets when the name lacks it:
    /// webMAN finds the game's CONFIG by the ID in the path (`include/mount/ps2_classic.h`).
    public static func outputName(for image: URL, titleID: String?) -> String {
        var stem = image.deletingPathExtension().lastPathComponent
        if stem.lowercased().hasSuffix(".dec") { stem = String(stem.dropLast(4)) }
        let squash = { (text: String) in text.uppercased().filter { $0.isLetter || $0.isNumber } }
        if let id = titleID, !squash(stem).contains(squash(id)) { stem += " [\(id)]" }
        return PS3ISO.fatName(stem) + ".BIN.ENC"
    }

    /// The size of the PS2 Classic made from an image of `size` bytes (2048-byte sectors).
    public static func encryptedSize(forImage size: Int64) -> Int64 {
        let prepared = (size + Int64(segment) - 1) / Int64(segment) * Int64(segment) + Int64(segment)
        let segments = prepared / Int64(segment)
        let blocks = (segments + Int64(segmentsPerBlock) - 1) / Int64(segmentsPerBlock)
        return Int64(segment) * (1 + blocks + segments)
    }

    /// Makes the PS2 Classic `output` from `image` (an ISO, or a .cue or .bin). The image is not
    /// changed; the output is written as .part and named when it is whole. `progress` gets the
    /// bytes of the image read and their total.
    public static func make(from image: URL, to output: URL, keys: PS2ClassicKeys,
                            progress: (Int64, Int64) -> Void = { _, _ in }) throws {
        if let problem = keys.problem { throw PS3Error.refused("Nycklarna för PS2 Classics: \(problem)") }
        let random = SymmetricKey(size: .bits128).withUnsafeBytes { Array($0) }
        try encrypt(from: image, to: output, values: keys.values, npdHash1: random, progress: progress)
    }

    static func encrypt(from image: URL, to output: URL, values: [PS2ClassicKeys.Name: Data], npdHash1: [UInt8],
                        progress: (Int64, Int64) -> Void) throws {
        guard let klicensee = values[.klicensee], let data = values[.data], let meta = values[.meta] else {
            throw PS3Error.refused("Nycklarna för PS2 Classics saknas.")
        }
        let source = try source(image)
        let reader = try PreparedReader(source: source)
        // CBC of one block with a zero IV is the block encrypted on its own.
        let dataKey = try aes(key: data, data: klicensee, encrypt: true, ecb: true)
        let metaKey = try aes(key: meta, data: klicensee, encrypt: true, ecb: true)
        let writer = PartWriter(base: output, split: false)
        do {
            try writer.write(Data(header(size: reader.total, values: values, npdHash1: npdHash1)))
            var number: UInt32 = 0
            while let block = try reader.next(segment * segmentsPerBlock) {
                try Task.checkCancellation()
                var table = [UInt8](repeating: 0, count: segment)
                var encrypted = Data(capacity: block.count)
                for i in 0..<(block.count / segment) {
                    let start = block.startIndex + i * segment
                    let piece = try aes(key: dataKey, data: block[start..<(start + segment)], encrypt: true)
                    let hash = Array(Insecure.SHA1.hash(data: piece))
                    table.replaceSubrange((i * metaEntry)..<(i * metaEntry + 20), with: hash)
                    for k in 0..<4 { table[i * metaEntry + 0x14 + k] = UInt8((number >> (8 * UInt32(3 - k))) & 0xFF) }
                    number += 1
                    encrypted.append(piece)
                }
                try writer.write(try aes(key: metaKey, data: Data(table), encrypt: true))
                try writer.write(encrypted)
                progress(reader.position, reader.total)
            }
            try writer.close()
        } catch {
            writer.discard()
            throw error
        }
    }

    /// The first 16 KB of a PS2 Classic.
    static func header(size: Int64, values: [PS2ClassicKeys.Name: Data], npdHash1: [UInt8]) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: segment)
        func be(_ value: UInt64, _ offset: Int, _ count: Int) {
            for k in 0..<count { b[offset + k] = UInt8((value >> (8 * UInt64(count - 1 - k))) & 0xFF) }
        }
        be(0x5053_3200, 0x00, 4)  // "PS2\0"
        be(1, 0x04, 2)
        be(1, 0x06, 2)
        be(2, 0x08, 4)  // NPD type
        be(1, 0x0C, 4)
        b.replaceSubrange(0x10..<(0x10 + contentID.utf8.count), with: Array(contentID.utf8))
        b.replaceSubrange(0x40..<0x50, with: npdHash1.prefix(16))
        let omac3 = values[.npdOMAC3] ?? Data(count: 16)
        b.replaceSubrange(0x50..<0x60, with: cmac(key: omac3, message: Data(b[0x10..<0x40]) + Data(fileName.utf8)))
        let kek = values[.npdKEK] ?? Data(count: 16), omac2 = values[.npdOMAC2] ?? Data(count: 16)
        let headerKey = Data(zip(kek, omac2).map { $0 ^ $1 })
        b.replaceSubrange(0x60..<0x70, with: cmac(key: headerKey, message: Data(b[0..<0x60])))
        be(UInt64(segment), 0x84, 4)
        be(UInt64(size), 0x88, 8)
        return b
    }

    /// The image as ps2classic encrypts it: its bytes, zeros up to 16 KB, and the LIMG block
    /// unless the image already ends with one.
    final class PreparedReader {
        let source: Source
        let padded: Int64
        let total: Int64
        private(set) var position: Int64 = 0
        private let handle: FileHandle
        private let limg: Data?

        init(source: Source) throws {
            self.source = source
            handle = try FileHandle(forReadingFrom: source.url)
            let segment = Int64(PS2ClassicMaker.segment)
            padded = (source.size + segment - 1) / segment * segment
            var last = Data()
            if padded - segment < source.size {
                try handle.seek(toOffset: Self.fileOffset(of: padded - segment, in: source))
                last = try handle.read(upToCount: 4) ?? Data()
                try handle.seek(toOffset: 0)
            }
            if last == Data("LIMG".utf8) {
                limg = nil
            } else {
                var block = [UInt8](repeating: 0, count: Int(segment))
                block.replaceSubrange(0..<4, with: Array("LIMG".utf8))
                for (offset, value) in [(4, UInt32(1)), (8, UInt32(padded / 0x800)), (12, UInt32(0x800))] {
                    for k in 0..<4 { block[offset + k] = UInt8((value >> (8 * UInt32(3 - k))) & 0xFF) }
                }
                limg = Data(block)
            }
            total = padded + Int64(limg?.count ?? 0)
        }

        deinit { try? handle.close() }

        static func fileOffset(of position: Int64, in source: Source) -> UInt64 {
            guard source.sectorSize != 2048 else { return UInt64(position) }
            return UInt64(position / 2048 * Int64(source.sectorSize) + Int64(source.dataOffset) + position % 2048)
        }

        /// The next `count` bytes (a multiple of 16 KB), or nil at the end.
        func next(_ count: Int) throws -> Data? {
            guard position < total else { return nil }
            var result = Data(capacity: count)
            while result.count < count, position < total {
                let want = count - result.count
                if position < source.size {
                    let piece = try readImage(Int(min(Int64(want), source.size - position)))
                    guard !piece.isEmpty else { throw PS3Error.invalidFile("\(source.url.lastPathComponent) tog slut för tidigt.") }
                    result.append(piece)
                    position += Int64(piece.count)
                } else if position < padded {
                    let zeros = Int(min(Int64(want), padded - position))
                    result.append(Data(count: zeros))
                    position += Int64(zeros)
                } else if let limg {
                    let start = Int(position - padded)
                    let piece = limg[start..<min(limg.count, start + want)]
                    result.append(piece)
                    position += Int64(piece.count)
                }
            }
            return result
        }

        private func readImage(_ count: Int) throws -> Data {
            if source.sectorSize == 2048 { return try handle.read(upToCount: count) ?? Data() }
            // Raw sectors: 2048 data bytes out of every 2352, sector by sector.
            var result = Data(capacity: count)
            while result.count < count {
                let sector = (position + Int64(result.count)) / 2048
                let inside = Int((position + Int64(result.count)) % 2048)
                try handle.seek(toOffset: UInt64(sector) * UInt64(source.sectorSize) + UInt64(source.dataOffset + inside))
                guard let chunk = try handle.read(upToCount: min(2048 - inside, count - result.count)), !chunk.isEmpty else { break }
                result.append(chunk)
            }
            return result
        }
    }

    // MARK: Crypto

    /// AES-128 with a zero IV (CBC), or a single block on its own (ECB).
    static func aes(key: Data, data: Data, encrypt: Bool, ecb: Bool = false) throws -> Data {
        var output = Data(count: data.count)
        var moved = 0
        let iv = [UInt8](repeating: 0, count: 16)
        let status = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(ecb ? kCCOptionECBMode : 0), keyBytes.baseAddress, key.count,
                            ecb ? nil : iv, input.baseAddress, data.count, out.baseAddress, data.count, &moved)
                }
            }
        }
        guard status == kCCSuccess, moved == data.count else {
            throw PS3Error.invalidFile("AES misslyckades (\(status)).")
        }
        return output
    }

    /// AES-CMAC (OMAC1, RFC 4493), as ps2classic's aesOmacMode1 computes it for non-empty input.
    static func cmac(key: Data, message: Data) -> [UInt8] {
        func block(_ input: [UInt8]) -> [UInt8] {
            (try? Array(aes(key: key, data: Data(input), encrypt: true, ecb: true))) ?? []
        }
        func double(_ value: [UInt8]) -> [UInt8] {
            var out = [UInt8](repeating: 0, count: 16)
            for i in 0..<16 { out[i] = value[i] << 1 | (i < 15 ? value[i + 1] >> 7 : 0) }
            if value[0] & 0x80 != 0 { out[15] ^= 0x87 }
            return out
        }
        let k1 = double(block([UInt8](repeating: 0, count: 16)))
        let k2 = double(k1)
        let bytes = [UInt8](message)
        let blocks = max(1, (bytes.count + 15) / 16)
        let complete = !bytes.isEmpty && bytes.count % 16 == 0
        var last = Array(bytes[((blocks - 1) * 16)...])
        if complete {
            last = zip(last, k1).map { $0 ^ $1 }
        } else {
            last.append(0x80)
            last += [UInt8](repeating: 0, count: 16 - last.count)
            last = zip(last, k2).map { $0 ^ $1 }
        }
        var running = [UInt8](repeating: 0, count: 16)
        for i in 0..<(blocks - 1) {
            running = block(zip(running, bytes[(i * 16)..<(i * 16 + 16)]).map { $0 ^ $1 })
        }
        return block(zip(running, last).map { $0 ^ $1 })
    }
}
