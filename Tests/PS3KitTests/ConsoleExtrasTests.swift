import Foundation
import Testing
@testable import PS3Kit

// Phase 9: what aldostools/Resources, webMAN MOD and PS3HEN brought in.

@Test func blocksUpdatesWithWebMANsOwnFile() {
    let text = String(decoding: UpdateBlock.contents, as: UTF8.self)
    // _Projects_/updater/pkgfiles/USRDIR/ps3-updatelist.txt: 1907 bytes, 12 regions, no 8E.
    #expect(UpdateBlock.contents.count == 1907)
    #expect(text.hasPrefix("Dest=83;CompatibleSystemSoftwareVersion=1.0000-;\nDest=83;ImageVersion=000108dd;"))
    #expect(text.hasSuffix("CDN=http://127.0.0.1/PS3UPDAT.PUP;CDN_Timeout=30;\n"))
    #expect(!text.contains("Dest=8E"))
    #expect(text.components(separatedBy: "CDN=http://127.0.0.1/").count == 13)
}

@Test func knowsLibCryptGamesAndPS2OnHEN() {
    #expect(LibCrypt.protected.count == 225)
    #expect(LibCrypt.exeName(fromTitleID: "SCES-01431") == "SCES_014.31")
    #expect(LibCrypt.exeName(fromTitleID: "SCES01431") == "SCES_014.31")
    #expect(LibCrypt.exeName(fromTitleID: "SCES_014.31") == "SCES_014.31")
    #expect(LibCrypt.exeName(fromTitleID: "NPEA00418") == nil)

    let protected = Game(path: "/dev_hdd0/PSXISO/Ape Escape (Europe).cue", title: "Ape Escape", titleID: "SCES-01564", platform: .ps1)
    #expect(LibCrypt.exe(for: protected) == "SCES_015.64")
    let spyro = Game(path: "/dev_hdd0/PSXISO/Spyro.cue", title: "Spyro the Dragon", titleID: "SCES-01438", platform: .ps1)
    #expect(PlayCheck.offline(spyro, console: nil).isEmpty)
    #expect(PlayCheck.offline(protected, console: nil) == [.libCrypt(exe: "SCES_015.64", installed: false)])

    let hen = ConsoleProfile(firmware: "4.93", kind: .cex, exploit: .hen)
    let cfw = ConsoleProfile(firmware: "4.93", kind: .cex, exploit: .cfw)
    let iso = Game(path: "/dev_hdd0/PS2ISO/God of War.iso", title: "God of War", titleID: "SCES-53133", platform: .ps2)
    let classic = Game(path: "/dev_hdd0/PS2ISO/God of War.BIN.ENC", title: "God of War", titleID: "SCES-53133", platform: .ps2)
    #expect(PlayCheck.offline(iso, console: hen) == [.ps2NeedsClassic])
    #expect(PlayCheck.Finding.ps2NeedsClassic.blocksPlay)
    #expect(PlayCheck.offline(classic, console: hen).isEmpty)
    #expect(PlayCheck.offline(iso, console: cfw).isEmpty)
    #expect(PS2Classic.configID(for: iso) == "SCES_531.33")
    #expect(PS2Classic.configPaths(id: "SCES_531.33", classic: true) == ["/dev_hdd0/game/PS2CONFIG/USRDIR/CONFIG/ENC/SCES_531.33.ENC"])
    #expect(PS2Classic.configPaths(id: "SCES_531.33", classic: false).last == "/dev_hdd0/game/PS2CONFIG/USRDIR/CONFIG/SOFT/SCES_531.33.CONFIG")
}

@Test func routesThemesClassicsAndLibCryptData() throws {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("ps3center-route-\(UUID().uuidString)")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }
    let theme = dir.appendingPathComponent("Blå.p3t")
    let classic = dir.appendingPathComponent("God of War [SCES-53133].BIN.ENC")
    let cue = dir.appendingPathComponent("Ape Escape (Europe).cue")
    for file in [theme, classic] { try Data(count: 10).write(to: file) }
    try #"FILE "Ape Escape (Europe) (Track 1).bin" BINARY"#.write(to: cue, atomically: true, encoding: .utf8)
    try Data(count: 20).write(to: dir.appendingPathComponent("Ape Escape (Europe) (Track 1).bin"))
    try Data(count: 15).write(to: dir.appendingPathComponent("Ape Escape (Europe).SBI"))

    let routes = try FileRouter.routes(for: [theme, classic, cue], mirrorRoot: nil)
    #expect(routes.first { $0.local.lastPathComponent == "Blå.p3t" }?.kind == .theme)
    #expect(routes.first { $0.local.lastPathComponent == "Blå.p3t" }?.remote == "/dev_hdd0/packages/Blå.p3t")
    #expect(routes.first { $0.local.pathExtension == "ENC" }?.remote == "/dev_hdd0/PS2ISO/God of War [SCES-53133].BIN.ENC")
    // HEN looks for the data beside the data track, with ".bin" swapped for ".sbi".
    #expect(routes.contains { $0.remote == "/dev_hdd0/PSXISO/Ape Escape (Europe) (Track 1).sbi" })
    #expect(!ContentKind.theme.needsRefresh)
}

@Test func findsMoreCoversAndNamesTitles() {
    let patapon = Game(path: "/dev_hdd0/PSPISO/Patapon.iso", title: "Patapon", titleID: "UCES-00995", platform: .psp)
    #expect(CoverService.sources(for: patapon).map(\.absoluteString) == ["https://raw.githubusercontent.com/aldostools/Resources/master/PSP/UCES00995.PNG"])
    let spyro = Game(path: "/dev_hdd0/PSXISO/Spyro.cue", title: "Spyro", titleID: "SCES-01438", platform: .ps1)
    #expect(CoverService.sources(for: spyro).last?.absoluteString == "https://raw.githubusercontent.com/aldostools/Resources/master/PSX/SCES_014.38_COV.JPG")

    let db = TitleDatabase(titles: TitleDatabase.parse("NPUB31857 #KillAllZombies\nULJS00266 .hack // Link [PSP]\nBLES01614 007™ Legends\n"))
    #expect(db.title(for: "ULJS-00266") == ".hack // Link")
    let nameless = Game(path: "/dev_hdd0/game/BLES01614", title: "BLES01614", titleID: "BLES01614", platform: .ps3)
    let named = Game(path: "/dev_hdd0/game/NPUB31857", title: "Eget namn", titleID: "NPUB31857", platform: .psn)
    #expect(db.named([nameless, named]).map(\.title) == ["007™ Legends", "Eget namn"])
}

@Test func explainsErrorCodesAndRecordingState() {
    #expect(ConsoleErrorCode.parse("0x80010006") == 0x80010006)
    #expect(ConsoleErrorCode.parse("8001 0006") == 0x80010006)
    #expect(ConsoleErrorCode.info(0x80010006)?.name == "ENOENT")
    let found = ConsoleErrorCode.explain(in: "The install failed (80010017), again 0x80010017 and 8002f2c5")
    #expect(found.map(\.code) == [0x80010017])
    #expect(ConsoleErrorCode.describe(found[0]).hasPrefix("80010017 (EAUTHFAIL):"))

    #expect(WebMAN.isRecording(":<p>Video recording: <a href=\"/videorec.ps3\">Enabled</a></p>"))
    #expect(!WebMAN.isRecording(":<p>Video recording: <a href=\"/videorec.ps3\">Disabled</a></p>"))
    #expect(!WebMAN.isRecording("<html>nothing</html>"))
}

/// A tiny IRD made for the test: a disc with PS3_DISC.SFB and PS3_GAME/{PARAM.SFO, EBOOT.BIN}
/// in a Joliet tree, the whole file gzip-compressed with a CRC, as real IRDs are.
let testIRD = "H4sIAAAAAAAC/zP2DHLhdPJxDTYAAkOukNTikuKC1JzUEhM9S2MDQz2QKJAIZmRgkO/mYAABpv9vb8RrswTKsD24v+OWimZZYNcUafHs69OmBP3un7J19sG1+Y+Ef/nJVJu5SiSutznvU+x3tjrrVcye5Z0MBEDXvwVXs8QNNa2t4z3fvz82ffvih+rvn3/M3b1xlvrqwGrJrI8bduycosb9cvfl2Bt2DD8mtlp+/X/v4Af+X/W6/te+2DP8Wbo88j8zw3/3r/bfTrlslP86Z0X9nBW+p879rSw36QkzKdq0ce7xt5FGRUU/VS13aPw++2lN+aVttgwGy/+t/3U8bqaGn3ZUrbZaoJv6u2QB8cxr/WlV81z1/RbJtosub596/erzi72BPLlSDH92/d+fd//9l/+FOU+OHEuWk7//rV65tEz/2Mtdnmfve6c3rM78LH+8im+t/NOPL/7u8sz68zrz9XPhwxW7+Bh+zE1vXRm7hmEDA4MyA3KwJidIsC5OEOlpCjTgcjvowcwwb9eLjwxAWUb0cGIGYjEom8Ngzy6JDXyJV988C9vpVcspDhWv5xaMX8gvvIij+K3Z53U7f0hAxS2+x8f/Vnl2M1ik9GLpzrpDDIMXZOV/nwUAHN9EIaECAAA="
let testDiscFiles: [(String, Data)] = [
    ("PS3_DISC.SFB", Data(".SFB".utf8) + Data(String(repeating: "disc-info", count: 3).utf8)),
    ("PS3_GAME/PARAM.SFO", Data([0]) + Data("PSF".utf8) + Data(String(repeating: "param-data", count: 5).utf8)),
    ("PS3_GAME/EBOOT.BIN", Data("SCE".utf8) + Data([0]) + Data(String(repeating: "eboot", count: 40).utf8)),
]

@Test func checksDiscCopiesAgainstIRD() async throws {
    let ird = try IRD.parse(try #require(Data(base64Encoded: testIRD)))
    #expect(ird.titleID == "BLES00001")
    #expect(ird.title == "Testspelet")
    #expect(ird.gameVersion == "01.00")
    let files = try ird.files()
    #expect(Set(files.keys) == ["PS3_DISC.SFB", "PS3_GAME/PARAM.SFO", "PS3_GAME/EBOOT.BIN"])
    #expect(files["PS3_GAME/EBOOT.BIN"]?.size == 204)
    #expect(files["PS3_GAME/EBOOT.BIN"]?.md5 == ["38f75f5ffb24e6d9531475d175b97ec2"])

    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("ps3center-ird-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: dir) }

    // A game folder with one file broken and one extra.
    let folder = dir.appendingPathComponent("BLES00001")
    try fm.createDirectory(at: folder.appendingPathComponent("PS3_GAME"), withIntermediateDirectories: true)
    for (path, data) in testDiscFiles { try data.write(to: folder.appendingPathComponent(path)) }
    try Data(count: 204).write(to: folder.appendingPathComponent("PS3_GAME/EBOOT.BIN"))
    try Data("x".utf8).write(to: folder.appendingPathComponent("extra.txt"))
    let report = try await DiscVerifier.verify(folder: folder, ird: ird)
    #expect(report.checked == 3)
    #expect(report.matched == 2)
    #expect(report.mismatched == ["PS3_GAME/EBOOT.BIN"])
    #expect(report.extra == ["EXTRA.TXT"])
    #expect(!report.isIntact)

    // The whole image: the IRD's header and the files' blocks after it.
    var image = try Gzip.decompress(ird.header)
    for (_, data) in testDiscFiles { image += data + Data(count: 2048 - data.count) }
    let iso = dir.appendingPathComponent("Test Game.iso")
    try image.write(to: iso)
    let isoReport = try await DiscVerifier.verify(iso: iso, ird: ird)
    #expect(isoReport.isIntact)
    #expect(isoReport.summary.contains("all 3 files match"))

    // A damaged IRD is refused.
    var broken = try Gzip.decompress(try #require(Data(base64Encoded: testIRD)))
    broken[broken.count - 1] ^= 0xFF
    #expect(throws: PS3Error.self) { try IRD.parse(broken) }
}

@Test func readsTheIRDIndex() throws {
    let json = #"{"BLES01614":[{"title":"007 Legends","fw-ver":"4.25","game-ver":"01.00","app-ver":"01.00","file-count":22,"disc-size":8307474432,"link":"Redump/BLES-01614 - 007 Legends (Europe).ird"}]}"#
    let index = try IRDLibrary.parseIndex(Data(json.utf8))
    #expect(index["BLES01614"]?.first?.fileCount == 22)
    #expect(index["BLES01614"]?.first?.link == "Redump/BLES-01614 - 007 Legends (Europe).ird")
}
