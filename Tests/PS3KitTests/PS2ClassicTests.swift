import CryptoKit
import Foundation
import Testing
@testable import PS3Kit

// Fas 10: PS2 Classics (ps2classic by psdev-net). The tests use made-up keys: the real ones are
// never in the repo, only their SHA-256.

private func hex(_ string: String) -> Data { Data(hex: string.replacingOccurrences(of: " ", with: ""))! }

private let testValues: [PS2ClassicKeys.Name: Data] = [
    .data: hex("000102030405060708090a0b0c0d0e0f"),
    .meta: hex("101112131415161718191a1b1c1d1e1f"),
    .npdKEK: hex("202122232425262728292a2b2c2d2e2f"),
    .npdOMAC2: hex("303132333435363738393a3b3c3d3e3f"),
    .npdOMAC3: hex("404142434445464748494a4b4c4d4e4f"),
    .klicensee: hex("505152535455565758595a5b5c5d5e5f"),
]

private func temporaryFolder(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ps3center-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// ps2classic's ps2_decrypt_image: the image back, and every meta table.
private func decrypt(_ file: Data, values: [PS2ClassicKeys.Name: Data]) throws -> (header: [UInt8], image: Data, tables: [[UInt8]]) {
    let segment = 0x4000
    let header = [UInt8](file.prefix(segment))
    let size = Int(header[0x88..<0x90].reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
    let dataKey = try PS2ClassicMaker.aes(key: values[.data]!, data: values[.klicensee]!, encrypt: true, ecb: true)
    let metaKey = try PS2ClassicMaker.aes(key: values[.meta]!, data: values[.klicensee]!, encrypt: true, ecb: true)
    var image = Data()
    var tables: [[UInt8]] = []
    var offset = segment
    while offset < file.count {
        tables.append([UInt8](try PS2ClassicMaker.aes(key: metaKey, data: file[offset..<(offset + segment)], encrypt: false)))
        offset += segment
        let count = min(0x200, (file.count - offset) / segment)
        for _ in 0..<count {
            image.append(try PS2ClassicMaker.aes(key: dataKey, data: file[offset..<(offset + segment)], encrypt: false))
            offset += segment
        }
    }
    return (header, image.prefix(size), tables)
}

@Test func computesAESCMACAsRFC4493() {
    // RFC 4493, section 4: the 16, 40 and 64 byte examples (ps2classic never hashes empty input).
    let key = hex("2b7e1516 28aed2a6 abf71588 09cf4f3c")
    let message = hex("6bc1bee2 2e409f96 e93d7e11 7393172a ae2d8a57 1e03ac9c 9eb76fac 45af8e51 30c81c46 a35ce411 e5fbc119 1a0a52ef f69f2445 df4f9b17 ad2b417b e66c3710")
    #expect(Data(PS2ClassicMaker.cmac(key: key, message: message.prefix(16))) == hex("070a16b4 6b4d4144 f79bdd9d d04a287c"))
    #expect(Data(PS2ClassicMaker.cmac(key: key, message: message.prefix(40))) == hex("dfa66747 de9ae630 30ca3261 1497c827"))
    #expect(Data(PS2ClassicMaker.cmac(key: key, message: message)) == hex("51f0bebf 7e3b9d92 fc497417 79363cfe"))
}

@Test func encryptsAPS2ImageAsPS2ClassicDoes() throws {
    let root = try temporaryFolder("ps2classic")
    defer { try? FileManager.default.removeItem(at: root) }
    // Not a multiple of 16 KB and over one block of 0x200 segments, so padding and two meta tables show.
    let size = 0x200 * 0x4000 + 3 * 2048 + 100
    let image = Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ $0 >> 11) })
    let iso = root.appendingPathComponent("God of War [SCES-53133].iso")
    try image.write(to: iso)
    let output = root.appendingPathComponent("God of War [SCES-53133].BIN.ENC")
    let random = [UInt8](repeating: 0xAB, count: 16)
    try PS2ClassicMaker.encrypt(from: iso, to: output, values: testValues, npdHash1: random) { _, _ in }
    #expect(!FileManager.default.fileExists(atPath: output.path + ".part"))

    let file = try Data(contentsOf: output)
    let padded = (size + 0x3FFF) / 0x4000 * 0x4000
    let prepared = padded + 0x4000  // + LIMG
    #expect(file.count == Int(PS2ClassicMaker.encryptedSize(forImage: Int64(size))))
    #expect(file.count == 0x4000 + 2 * 0x4000 + prepared)

    let result = try decrypt(file, values: testValues)
    let h = result.header
    #expect(h[0..<4] == [0x50, 0x53, 0x32, 0x00])
    #expect(h[4..<16] == [0, 1, 0, 1, 0, 0, 0, 2, 0, 0, 0, 1])
    #expect(String(decoding: h[0x10..<0x34], as: UTF8.self) == PS2ClassicMaker.contentID)
    #expect(h[0x34..<0x40].allSatisfy { $0 == 0 })
    #expect(Array(h[0x40..<0x50]) == random)
    #expect(h[0x84..<0x88] == [0, 0, 0x40, 0])
    #expect(result.image.count == prepared)
    // The two hashes in the header, as ps2classic's build_ps2_header makes them.
    let hash2 = PS2ClassicMaker.cmac(key: testValues[.npdOMAC3]!, message: Data(h[0x10..<0x40]) + Data("ISO.BIN.ENC".utf8))
    #expect(Array(h[0x50..<0x60]) == hash2)
    let headerKey = Data(zip(testValues[.npdKEK]!, testValues[.npdOMAC2]!).map { $0 ^ $1 })
    #expect(Array(h[0x60..<0x70]) == PS2ClassicMaker.cmac(key: headerKey, message: Data(h[0..<0x60])))

    // The image, zeros, and the LIMG block with the padded size in sectors.
    #expect(result.image.prefix(size) == image)
    #expect(result.image[size..<padded].allSatisfy { $0 == 0 })
    let limg = [UInt8](result.image[padded..<(padded + 16)])
    let sectors = UInt32(padded / 0x800)
    #expect(limg == Array("LIMG".utf8) + [0, 0, 0, 1] + [UInt8(sectors >> 24), UInt8((sectors >> 16) & 0xFF), UInt8((sectors >> 8) & 0xFF), UInt8(sectors & 0xFF)] + [0, 0, 8, 0])

    // Each table: SHA-1 of the encrypted segment and its number, counting on over blocks.
    #expect(result.tables.count == 2)
    let firstSegment = file[(2 * 0x4000)..<(3 * 0x4000)]
    #expect(Array(result.tables[0][0..<20]) == Array(Insecure.SHA1.hash(data: firstSegment)))
    #expect(result.tables[0][0x14..<0x18] == [0, 0, 0, 0])
    #expect(result.tables[0][0x20 * 0x1FF + 0x14..<0x20 * 0x1FF + 0x18] == [0, 0, 0x01, 0xFF])
    #expect(result.tables[1][0x14..<0x18] == [0, 0, 0x02, 0x00])
    let segmentsInSecond = prepared / 0x4000 - 0x200
    #expect(result.tables[1][(0x20 * segmentsInSecond)...].allSatisfy { $0 == 0 })
}

@Test func keepsAnLIMGBlockThatIsThereAndReadsRawCDSectors() throws {
    let root = try temporaryFolder("ps2raw")
    defer { try? FileManager.default.removeItem(at: root) }
    // A prepared image: 2 segments of data and an LIMG block of its own.
    var prepared = Data((0..<(2 * 0x4000)).map { UInt8(truncatingIfNeeded: $0) })
    var block = Data(count: 0x4000)
    block.replaceSubrange(0..<4, with: Data("LIMG".utf8))
    prepared.append(block)
    let iso = root.appendingPathComponent("Prepared.iso")
    try prepared.write(to: iso)
    let reader = try PS2ClassicMaker.PreparedReader(source: try PS2ClassicMaker.source(iso))
    #expect(reader.total == Int64(prepared.count))

    // The same 2048-byte sectors as a raw MODE2 image behind a .cue.
    let sectors = 5
    let plain = Data((0..<(sectors * 2048)).map { UInt8(truncatingIfNeeded: $0 &* 3) })
    var raw = Data()
    for s in 0..<sectors {
        raw.append(Data([0x00] + [UInt8](repeating: 0xFF, count: 10) + [0x00, 0, 2, UInt8(s), 2]))
        raw.append(Data(count: 8))  // subheader
        raw.append(plain[(s * 2048)..<((s + 1) * 2048)])
        raw.append(Data(count: 2352 - 24 - 2048))
    }
    try raw.write(to: root.appendingPathComponent("Spel.bin"))
    let cue = root.appendingPathComponent("Spel.cue")
    try Data("FILE \"Spel.bin\" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n".utf8).write(to: cue)
    let source = try PS2ClassicMaker.source(cue)
    #expect(source.sectorSize == 2352)
    #expect(source.size == Int64(sectors * 2048))
    let rawReader = try PS2ClassicMaker.PreparedReader(source: source)
    let first = try #require(try rawReader.next(0x4000))
    #expect(first.prefix(plain.count) == plain)
    #expect(first[plain.count...].allSatisfy { $0 == 0 })
    #expect(String(decoding: try #require(try rawReader.next(0x4000)).prefix(4), as: UTF8.self) == "LIMG")
    #expect(try rawReader.next(0x4000) == nil)
}

@Test func readsKeysFromThePCToolsFilesAndChecksFingerprints() throws {
    let root = try temporaryFolder("ps2keys")
    defer { try? FileManager.default.removeItem(at: root) }
    let source = """
    u8 ps2_key_cex_data[] = { 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F };
    u8 ps2_key_cex_meta[] = { 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F };
    u8 ps2_key_dex_data[] = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };
    u8 npd_kek[] = {0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,0x28,0x29,0x2a,0x2b,0x2c,0x2d,0x2e,0x2f};
    u8 npd_omac_key2[] = {0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x3a,0x3b,0x3c,0x3d,0x3e,0x3f};
    u8 npd_omac_key3[] = {0x40,0x41,0x42,0x43,0x44,0x45,0x46,0x47,0x48,0x49,0x4a,0x4b,0x4c,0x4d,0x4e,0x4f};
    """
    let sourceFile = root.appendingPathComponent("ps2classic.c")
    try Data(source.utf8).write(to: sourceFile)
    let rifkey = root.appendingPathComponent("\(PS2ClassicMaker.contentID).rifkey")
    try testValues[.klicensee]!.write(to: rifkey)

    let keys = try PS2ClassicKeys.read([sourceFile, rifkey])
    #expect(keys.values == testValues)
    #expect(keys.missing.isEmpty)
    // Made-up values are not Sony's: every one fails its fingerprint, and nothing gets encrypted.
    #expect(Set(keys.wrong) == Set(PS2ClassicKeys.Name.allCases))
    #expect(!keys.isComplete)
    #expect(keys.problem?.contains("ps2_key_cex_data") == true)
    #expect(throws: PS3Error.self) {
        try PS2ClassicMaker.make(from: sourceFile, to: root.appendingPathComponent("x.BIN.ENC"), keys: keys)
    }
    let partial = try PS2ClassicKeys.read([rifkey])
    #expect(partial.missing.count == 5)
    #expect(PS2ClassicKeys.matches(Data(count: 16), .data) == false)
}

@Test func namesPS2ClassicsWithTheirTitleID() {
    #expect(PS2ClassicMaker.outputName(for: URL(fileURLWithPath: "/x/God of War [SCES-53133].iso"), titleID: "SCES-53133") == "God of War [SCES-53133].BIN.ENC")
    #expect(PS2ClassicMaker.outputName(for: URL(fileURLWithPath: "/x/God of War.iso"), titleID: "SCES-53133") == "God of War [SCES-53133].BIN.ENC")
    #expect(PS2ClassicMaker.outputName(for: URL(fileURLWithPath: "/x/SLUS_206.80 Okami.iso"), titleID: "SLUS-20680") == "SLUS_206.80 Okami.BIN.ENC")
    #expect(PS2ClassicMaker.outputName(for: URL(fileURLWithPath: "/x/Spel.cue"), titleID: nil) == "Spel.BIN.ENC")
}
