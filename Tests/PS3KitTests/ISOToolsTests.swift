import CryptoKit
import Foundation
import Testing
@testable import PS3Kit

// Phase 10: the PC tools for PS3 ISOs (PS3 ISO Tools, makeps3iso, extractps3iso, splitps3iso).

private func md5(_ url: URL) throws -> String {
    Insecure.MD5.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
}

/// A game folder as GAMES holds them: PARAM.SFO, files a few levels down, a folder with enough
/// files to need several directory sectors, an empty file and an empty folder, a file split for
/// FAT32 (.66600, .66601), the system update on the disc and a .DS_Store from Finder.
private func makeGameFolder(in root: URL, name: String = "TestGame [BLES12345]") throws -> URL {
    let fm = FileManager.default
    let game = root.appendingPathComponent(name)
    func write(_ path: String, _ data: Data) throws {
        let url = game.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
    func bytes(_ count: Int, seed: UInt8) -> Data { Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31) ^ seed }) }
    try write("PS3_GAME/PARAM.SFO", makeSFO(["TITLE": "TestGame: Åäö", "TITLE_ID": "BLES12345", "CATEGORY": "DG", "APP_VER": "01.00"]))
    try write("PS3_DISC.SFB", bytes(1024, seed: 1))
    try write("PS3_GAME/ICON0.PNG", bytes(30_000, seed: 2))
    try write("PS3_GAME/USRDIR/EBOOT.BIN", bytes(300_003, seed: 3))
    try write("PS3_GAME/USRDIR/empty.dat", Data())
    for i in 0..<70 {
        try write("PS3_GAME/USRDIR/data/level_\(String(format: "%03d", i))_with_a_rather_long_descriptive_name.pak", bytes(100 + i * 37, seed: UInt8(i)))
    }
    try write("PS3_GAME/USRDIR/data/deep/er/still.txt", Data("still".utf8))
    try write("PS3_GAME/USRDIR/movie.bik.66600", bytes(2048 * 3 + 7, seed: 4))
    try write("PS3_GAME/USRDIR/movie.bik.66601", bytes(1000, seed: 5))
    try write("PS3_UPDATE/PS3UPDAT.PUP", bytes(4096, seed: 6))
    try write(".DS_Store", bytes(10, seed: 7))
    try fm.createDirectory(at: game.appendingPathComponent("PS3_GAME/TROPDIR"), withIntermediateDirectories: true)
    return game
}

private func temporaryFolder(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ps3center-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func makesAPS3ISOFromAGameFolder() throws {
    let root = try temporaryFolder("makeiso")
    defer { try? FileManager.default.removeItem(at: root) }
    let game = try makeGameFolder(in: root)
    let builder = try PS3ISOBuilder(folder: game, created: Date(timeIntervalSince1970: 1_790_000_000))
    #expect(builder.titleID == "BLES12345")
    #expect(builder.title == "TestGame: Åäö")
    #expect(builder.leftOut == ["PS3_UPDATE/PS3UPDAT.PUP"])
    #expect(builder.fileCount == 77)  // 70 + still.txt + SFO, SFB, ICON0, EBOOT, empty, movie

    let iso = root.appendingPathComponent("TestGame.iso")
    let files = try builder.write(to: iso, split: false)
    #expect(files == [iso])
    #expect(!FileManager.default.fileExists(atPath: iso.path + ".part"))
    #expect(FileRouter.fileSize(iso) == builder.size)
    #expect(builder.size % 2048 == 0)

    // The PS3 header: one plain region over the whole image, and the title ID in sector 1.
    let head = [UInt8](try Data(contentsOf: iso).prefix(0x830))
    #expect(head[0..<4] == [0, 0, 0, 1])
    let last = builder.sectors - 1
    #expect(head[12..<16] == [UInt8(last >> 24), UInt8((last >> 16) & 0xFF), UInt8((last >> 8) & 0xFF), UInt8(last & 0xFF)])
    #expect(String(decoding: head[0x800..<0x80C], as: UTF8.self) == "PlayStation3")
    #expect(String(decoding: head[0x810..<0x81A], as: UTF8.self) == "BLES-12345")

    // The Joliet tree has the names as they were, the .666 parts joined and no update or .DS_Store.
    let image = try ISOImage(url: iso, joliet: true)
    #expect(image.volumeID == "PS3VOLUME")
    let tree = try image.tree()
    let paths = Set(tree.files.map(\.path))
    #expect(paths.count == 77)
    #expect(paths.contains("PS3_GAME/USRDIR/movie.bik"))
    #expect(paths.contains("PS3_GAME/USRDIR/data/level_042_with_a_rather_long_descriptive_name.pak"))
    #expect(!paths.contains { $0.contains("PS3UPDAT") || $0.contains(".DS_Store") || $0.contains(".666") })
    #expect(tree.folders.contains("PS3_UPDATE"))
    #expect(tree.folders.contains("PS3_GAME/TROPDIR"))
    for file in tree.files where !file.path.hasPrefix("PS3_GAME/USRDIR/movie") {
        #expect(try image.md5(extent: file.extent, size: file.size) == md5(game.appendingPathComponent(file.path)), "\(file.path)")
    }
    let movie = try #require(tree.files.first { $0.path == "PS3_GAME/USRDIR/movie.bik" })
    let joined = try Data(contentsOf: game.appendingPathComponent("PS3_GAME/USRDIR/movie.bik.66600"))
        + Data(contentsOf: game.appendingPathComponent("PS3_GAME/USRDIR/movie.bik.66601"))
    #expect(movie.size == UInt64(joined.count))
    #expect(try image.md5(extent: movie.extent, size: movie.size) == Insecure.MD5.hash(data: joined).map { String(format: "%02x", $0) }.joined())

    // The primary tree: the same files in capitals, as makeps3iso writes them.
    let primary = try ISOImage(url: iso)
    #expect(try primary.find("PS3_GAME/USRDIR/EBOOT.BIN")?.size == 300_003)
    #expect(try primary.find("PS3_GAME/USRDIR/DATA/DEEP/ER/STILL.TXT")?.size == 5)

    // The same folder always gives the same image.
    let again = try PS3ISOBuilder(folder: game, created: Date(timeIntervalSince1970: 1_790_000_000))
    #expect(again.header() == builder.header())
}

@Test func describesFilesOver4GBWithSeveralRecords() throws {
    let root = try temporaryFolder("multiextent")
    defer { try? FileManager.default.removeItem(at: root) }
    let game = try makeGameFolder(in: root)
    // A sparse file just over 4 GiB: the layout is all that is checked, nothing is written.
    let big = game.appendingPathComponent("PS3_GAME/USRDIR/big.dat")
    FileManager.default.createFile(atPath: big.path, contents: nil)
    let handle = try FileHandle(forWritingTo: big)
    try handle.truncate(atOffset: 4_294_971_392)
    try handle.close()

    let builder = try PS3ISOBuilder(folder: game)
    #expect(builder.largestFile == 4_294_971_392)
    let header = root.appendingPathComponent("header.iso")
    try Data(builder.header()).write(to: header)
    let image = try ISOImage(url: header, joliet: true)
    let usrdir = try #require(try image.find("PS3_GAME/USRDIR"))
    let records = try image.listDirectory(usrdir).filter { $0.name == "big.dat" }
    #expect(records.count == 2)
    #expect(records[0].size == 0xFFFF_F800)
    #expect(records[1].size == 4_294_971_392 - 0xFFFF_F800)
    #expect(records[1].extent == records[0].extent + 0x1F_FFFF)
    #expect(try image.allFiles().first { $0.path == "PS3_GAME/USRDIR/big.dat" }?.size == 4_294_971_392)
}

@Test func splitsInFAT32PartsAndJoinsThemAgain() throws {
    #expect(PS3ISO.partSize == 0xFFFF_0000)
    #expect(PS3ISO.partCount(for: 0xFFFF_0000) == 1)
    #expect(PS3ISO.partCount(for: 0xFFFF_0001) == 2)
    #expect(PS3ISO.partSizes(for: 2 * 0xFFFF_0000 + 5, parts: 3) == [0xFFFF_0000, 0xFFFF_0000, 5])

    let root = try temporaryFolder("split")
    defer { try? FileManager.default.removeItem(at: root) }
    let data = Data((0..<25).map { UInt8($0) })
    // Small parts so the test stays small; the parts are the same as with 4 GB ones.
    let writer = PartWriter(base: root.appendingPathComponent("Game.iso"), split: true, partSize: 10)
    try writer.write(data.prefix(7))
    try writer.write(data.dropFirst(7))
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Game.iso.0.part").path))
    try writer.close()
    let parts = PS3ISO.parts(startingAt: root.appendingPathComponent("Game.iso.0"))
    #expect(parts.map(\.lastPathComponent) == ["Game.iso.0", "Game.iso.1", "Game.iso.2"])
    #expect(parts.map(FileRouter.fileSize) == [10, 10, 5])
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasSuffix(".part") })

    // Exactly two parts' worth gives no empty third part.
    let even = PartWriter(base: root.appendingPathComponent("Even.iso"), split: true, partSize: 10)
    try even.write(data.prefix(20))
    try even.close()
    #expect(even.files.map(\.lastPathComponent) == ["Even.iso.0", "Even.iso.1"])

    let joined = try PS3ISO.join(root.appendingPathComponent("Game.iso.0"))
    #expect(joined.lastPathComponent == "Game.iso")
    #expect(try Data(contentsOf: joined) == data)
    #expect(throws: PS3Error.self) { try PS3ISO.join(root.appendingPathComponent("Game.iso.0")) }  // Game.iso is there now
    #expect(throws: PS3Error.self) { try PS3ISO.split(joined) }  // 25 bytes need no splitting

    // A failed or cancelled write leaves nothing that webMAN could list.
    let failed = PartWriter(base: root.appendingPathComponent("Avbruten.iso"), split: true, partSize: 10)
    try failed.write(data)
    failed.discard()
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix("Avbruten") })
}

@Test func extractsAnISOIntoAGameFolder() throws {
    let root = try temporaryFolder("extract")
    defer { try? FileManager.default.removeItem(at: root) }
    let game = try makeGameFolder(in: root)
    let iso = root.appendingPathComponent("TestGame.iso")
    try PS3ISOBuilder(folder: game).write(to: iso, split: false)

    let result = try PS3ISO.extract(iso)
    #expect(result.folder.lastPathComponent == "TestGame")
    #expect(result.leftOut.isEmpty)
    let out = result.folder
    #expect(try md5(out.appendingPathComponent("PS3_GAME/USRDIR/EBOOT.BIN")) == md5(game.appendingPathComponent("PS3_GAME/USRDIR/EBOOT.BIN")))
    #expect(FileRouter.fileSize(out.appendingPathComponent("PS3_GAME/USRDIR/movie.bik")) == 2048 * 3 + 7 + 1000)
    #expect(FileRouter.fileSize(out.appendingPathComponent("PS3_GAME/USRDIR/empty.dat")) == 0)
    #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent("PS3_GAME/TROPDIR").path))
    #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent("PS3_UPDATE").path))
    #expect(!FileManager.default.fileExists(atPath: out.appendingPathComponent("PS3_UPDATE/PS3UPDAT.PUP").path))
    #expect(try ParamSFO(data: Data(contentsOf: out.appendingPathComponent("PS3_GAME/PARAM.SFO")))?.titleID == "BLES12345")
    #expect(throws: PS3Error.self) { try PS3ISO.extract(iso) }  // the folder is there now
}

@Test func refusesFoldersThatAreNotPS3Games() throws {
    let root = try temporaryFolder("notagame")
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1, 2, 3]).write(to: root.appendingPathComponent("readme.txt"))
    #expect(throws: PS3Error.self) { try PS3ISOBuilder(folder: root) }
}

@Test func namesFilesSoFAT32TakesThem() {
    #expect(PS3ISO.fatName("Ratchet & Clank: A Crack in Time") == "Ratchet & Clank - A Crack in Time")
    #expect(PS3ISO.fatName("What? *Really* <yes>|\"no\"") == "What Really yesno")
    #expect(PS3ISO.fatName("Dots...") == "Dots")
    #expect(PS3ISO.fatName("???") == "Game")
}

@Test func plansAUSBDriveWithSplitISOsAndGameFoldersMadeIntoISOs() throws {
    let root = try temporaryFolder("usbplan")
    defer { try? FileManager.default.removeItem(at: root) }
    let drive = root.appendingPathComponent("PS3")
    try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
    func sparse(_ url: URL, _ size: UInt64) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: size)
        try handle.close()
    }
    let big: UInt64 = 6_000_000_000

    let folder = try makeGameFolder(in: root.appendingPathComponent("GAMES"), name: "Big Game: Part 2")
    try sparse(folder.appendingPathComponent("PS3_GAME/USRDIR/huge.psarc"), big)
    let small = try makeGameFolder(in: root.appendingPathComponent("GAMES"), name: "Small Game")
    let iso = root.appendingPathComponent("PS3/Game.iso")
    try sparse(iso, big)
    let film = root.appendingPathComponent("BD/Film.iso")
    try sparse(film, big)
    let ps2 = root.appendingPathComponent("PS2/Stort PS2.iso")
    try sparse(ps2, big)

    let games = [
        Game(path: folder.path, title: "Big Game", titleID: "BLES12345", platform: .ps3, isFolder: true, source: .mac,
             remotePath: "/dev_hdd0/GAMES/Big Game: Part 2"),
        Game(path: small.path, title: "Small Game", titleID: "BLES12345", platform: .ps3, isFolder: true, source: .mac,
             remotePath: "/dev_hdd0/GAMES/Small Game"),
        Game(path: iso.path, title: "Game", platform: .ps3, size: Int64(big), source: .mac, remotePath: "/dev_hdd0/PS3ISO/Game.iso"),
        Game(path: film.path, title: "Film", platform: .bluRay, size: Int64(big), source: .mac, remotePath: "/dev_hdd0/BDISO/Film.iso"),
        Game(path: ps2.path, title: "Stort PS2", platform: .ps2, size: Int64(big), source: .mac, remotePath: "/dev_hdd0/PS2ISO/Stort PS2.iso"),
    ]
    let plan = USBDrive.plan(games, on: drive)
    let relative = plan.copies.map { String($0.destination.path.dropFirst(drive.path.count + 1)) }
    #expect(relative == ["PS3ISO/Big Game - Part 2.iso.0", "GAMES/Small Game", "PS3ISO/Game.iso.0", "BDISO/Film.iso.0"])
    #expect(plan.copies.map(\.kind) == [.isoFromFolder, .folder, .file, .file])
    #expect(plan.copies.map(\.parts) == [2, 1, 2, 2])
    #expect(plan.copies[0].size > Int64(big))
    #expect(plan.skipped.map(\.game.title) == ["Stort PS2"])
}

@Test func listsSplitFilmsOnce() throws {
    let bdiso = try #require(GameListing.folders.first { $0.name == "BDISO" })
    let entries = [FTPClient.Entry(name: "Film.iso.0", size: 4_294_901_760, isDirectory: false, modified: "Oct 24 18:12"),
                   FTPClient.Entry(name: "Film.iso.1", size: 1_000, isDirectory: false, modified: "Oct 24 18:12")]
    let games = GameListing.candidates(in: "/dev_usb000/BDISO", folder: bdiso, entries: entries, nested: [:], wmtmp: [:])
    #expect(games.map(\.game.path) == ["/dev_usb000/BDISO/Film.iso.0"])
    #expect(games.first?.game.size == 4_294_902_760)
}
