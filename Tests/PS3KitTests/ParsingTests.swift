import Darwin
import Foundation
import Testing
@testable import PS3Kit

// Fixtures are trimmed copies of real responses from the console (PSID/IDPS removed).

@Test func parsesSysInfoAndStatusPage() {
    let sysInfo = "CPU: 60°C RSX: 67°C FAN: 31% Play: 00:28:50 MAX: 68°C Firmware : 4.93 CEX PS3HEN 3.5.0 IP: 10.0.1.35 WLAN System storage: 355.8 GB free Memory: 1044 KB free [Full] "
    let page = #"<a href="/dev_bdvd">/dev_bdvd</a> -> <a class="f" href="/dev_hdd0/">/dev_hdd0</a>/<a class="f" href="/dev_hdd0/PS3ISO/">PS3ISO</a>/<a href="/mount.ps3/dev_hdd0/PS3ISO/Test+Drive+Unlimited+2+(Europe)+(En,Fr,De,Es,It).dec.iso">Test Drive Unlimited 2 (Europe) (En,Fr,De,Es,It).dec.iso</a></font><hr>webMAN 1.47.50c MOD - Simple Web Server (NTFS) [Full]"#
    var s = ConsoleSnapshot.parse(sysInfo: sysInfo, statusPage: page)
    s.computeHealth()
    #expect(s.cpuTemp == 60)
    #expect(s.rsxTemp == 67)
    #expect(s.fanPercent == 31)
    #expect(s.fanTargetMax == 68)
    #expect(s.playTime == "00:28:50")
    #expect(s.firmware == "4.93")
    #expect(s.firmwareType == "CEX")
    #expect(s.henVersion == "3.5.0")
    #expect(s.ip == "10.0.1.35")
    #expect(s.network == "Wi-Fi")
    #expect(s.freeBytes == 355_800_000_000)
    #expect(s.webmanVersion == "1.47.50c")
    #expect(s.mountedGamePath == "/dev_hdd0/PS3ISO/Test Drive Unlimited 2 (Europe) (En,Fr,De,Es,It).dec.iso")
    #expect(s.mountedGameName == "Test Drive Unlimited 2")
    #expect(s.health == 100)
}

@Test func healthDropsWhenHotOrFull() {
    var s = ConsoleSnapshot()
    s.cpuTemp = 80
    s.freeBytes = 10_000_000_000
    s.computeHealth()
    #expect(s.health == 40)
    #expect(s.healthLabel == "Varning")
}

@Test func extractsPS3MAPIResponses() {
    #expect(WebMAN.extractResponse(#"{"response": "0x0000000001030200"}"#) == "0x0000000001030200")
    #expect(WebMAN.extractResponse(#"{"response": [60,67]}"#) == "[60,67]")
    #expect(WebMAN.parseHex("0x0000000001030200") == 0x1030200)
    #expect(WebMAN.foregroundName(fromProcessName: "01030200_main_EBOOT.BIN") == "EBOOT.BIN")
    #expect(WebMAN.foregroundName(fromProcessName: "01000300_main_vsh.self") == nil)
    #expect(WebMAN.foregroundName(fromProcessName: "") == nil)
}

@Test func parsesDiskSpace() {
    let space = WebMAN.parseDiskSpace("[355812345856,500107862016,8,2]")
    #expect(space?.free == 355_812_345_856)
    #expect(space?.total == 500_107_862_016)
    #expect(WebMAN.parseDiskSpace("ERROR") == nil)
    #expect(WebMAN.parseDiskSpace("[0,0,0,0]") == nil)
}

@Test func encodesWebCommands() {
    #expect(WebMAN.encodeCommand("/install.ps3/dev_hdd0/packages/a b.pkg") == "/install.ps3/dev_hdd0/packages/a%20b.pkg")
    #expect(WebMAN.encodeText("Klart & klart") == "Klart%20%26%20klart")
    #expect(WebMAN.encodeText("Spel är klart") == "Spel%20%C3%A4r%20klart")
}

@Test func parsesFTPListLines() {
    let line = "-rwxrwxrwx 1 root  root     9642180608 Jun 05 18:33 Test Drive Unlimited 2 (Europe) (En,Fr,De,Es,It).dec.iso"
    #expect(FTPClient.parseListLine(line) == FTPClient.Entry(name: "Test Drive Unlimited 2 (Europe) (En,Fr,De,Es,It).dec.iso", size: 9_642_180_608, isDirectory: false, modified: "Jun 05 18:33"))
    #expect(FTPClient.parseListLine("drwxrwxrwx 1 root  root            512 Jul 20 13:17 GAMES")?.isDirectory == true)
    #expect(FTPClient.parseListLine("total 0") == nil)
}

@Test func comparesVersionsAcrossStyles() {
    let installed = { (s: String) in Version(s, style: .appVer)! }
    #expect(installed("02.40") == Version("v2.4.0", style: .semverAsAppVer)!)
    #expect(installed("02.40") < Version("v2.4.1", style: .semverAsAppVer)!)
    #expect(installed("01.30") == Version("v1.3.0", style: .semverAsAppVer)!)
    #expect(installed("00.64") == Version("r6.4", style: .artemis)!)
    #expect(installed("00.64") < Version("r6.5", style: .artemis)!)
    #expect(installed("01.15") == Version("1.15", style: .dotted)!)
    #expect(Version("1.47.50c", style: .dotted)! == Version("1.47.50", style: .dotted)!)
    #expect(Version("1.47.50c", style: .dotted)! < Version("1.47.51", style: .dotted)!)
    #expect(Version("3.5.0", style: .dotted)! < Version("3.6.0", style: .dotted)!)
}

@Test func parsesParamSFO() throws {
    let sfo = makeSFO(["APP_VER": "02.40", "CATEGORY": "HG", "TITLE": "Apollo Save Tool", "TITLE_ID": "NP0APOLLO"])
    let parsed = try #require(ParamSFO(data: sfo))
    #expect(parsed.titleID == "NP0APOLLO")
    #expect(parsed.title == "Apollo Save Tool")
    #expect(parsed.appVersion == "02.40")
    #expect(ParamSFO(data: Data("nope".utf8)) == nil)
}

@Test func readsPKGContentID() {
    var header = Data([0x7F, 0x50, 0x4B, 0x47]) + Data(count: 0x2C)
    header += Data("UP0001-RMTC00001_00-0000000000000000".utf8)
    header += Data(count: 0x60 - header.count)
    let info = PKGInfo(header: header)
    #expect(info?.contentID == "UP0001-RMTC00001_00-0000000000000000")
    #expect(info?.titleID == "RMTC00001")
}

@Test func onlyGameFoldersRefreshTheGameList() {
    let file = URL(fileURLWithPath: "/tmp/x.bin")
    let game = Route(local: file, remote: "/dev_hdd0/PSXISO/x.bin", kind: .psxISO, size: 1, title: nil)
    let scratch = Route(local: file, remote: "/dev_hdd0/tmp/x.bin", kind: .psxISO, size: 1, title: nil)
    #expect(game.refreshesGameList)
    #expect(!scratch.refreshesGameList)
}

@Test func findsGamesStoredFlatOrInAFolder() {
    let iso = URL(fileURLWithPath: "/m/dev_hdd0/PS3ISO/Game (Europe)/Game (Europe).dec.iso")
    let nested = Route(local: iso, remote: "/dev_hdd0/PS3ISO/Game (Europe)/Game (Europe).dec.iso", kind: .ps3ISO, size: 1, title: nil)
    #expect(TransferService.alternativeLocations(for: nested) == ["/dev_hdd0/PS3ISO/Game (Europe).dec.iso"])
    let flat = Route(local: iso, remote: "/dev_hdd0/PS3ISO/Game (Europe).dec.iso", kind: .ps3ISO, size: 1, title: nil)
    #expect(TransferService.alternativeLocations(for: flat) == ["/dev_hdd0/PS3ISO/Game (Europe)/Game (Europe).dec.iso"])
}

@Test func cleansGameNames() {
    #expect(GameName.clean("Ferrari - The Race Experience (Europe) (En,Fr,De,Es,It).dec.iso") == "Ferrari - The Race Experience")
    #expect(GameName.clean("/dev_hdd0/PS3ISO/Game.iso") == "Game")
    #expect(GameName.clean("Shadow of the Colossus [SCES-53326].iso") == "Shadow of the Colossus")
    #expect(GameName.clean("Big Game (Europe).iso.0") == "Big Game")
    #expect(GameName.clean("Classic.BIN.ENC") == "Classic")
    #expect(GameName.clean("BLUS30443-[Demon's Souls]") == "Demon's Souls")
}

// MARK: Games

@Test func readsTitleIDsAndRegions() {
    #expect(TitleID.find(in: "Shadow of the Colossus [SCES-53326].iso", platform: .ps2) == "SCES-53326")
    #expect(TitleID.find(in: "SLUS_209.46.Ratchet.iso", platform: .ps2) == "SLUS-20946")
    #expect(TitleID.find(in: "BLES01234-[Game]", platform: .ps3) == "BLES01234")
    #expect(TitleID.find(in: "Gran Turismo 5 (Europe).iso", platform: .ps3) == nil)
    #expect(TitleID.find(in: "FIFA 2014 (Europe).iso", platform: .ps3) == nil)
    #expect(TitleID.isOfficial("BCES00569"))
    #expect(TitleID.isOfficial("NPUB31234"))
    #expect(!TitleID.isOfficial("NP0APOLLO"))
    #expect(!TitleID.isOfficial("IRISMAN00"))
    #expect(Region(titleID: "BLES01234") == .europe)
    #expect(Region(titleID: "NPUB31234") == .usa)
    #expect(Region(titleID: "SLPM-65555") == .japan)
    #expect(Region(titleID: "ULJM05500") == .japan)
    #expect(Region(titleID: "BLAS50001") == .asia)
    #expect(Region(titleID: "NP0APOLLO") == nil)
}

private func entry(_ name: String, _ size: Int64 = 1, dir: Bool = false) -> FTPClient.Entry {
    FTPClient.Entry(name: name, size: size, isDirectory: dir, modified: "Oct 24 18:12")
}

@Test func listsGamesFromWebMANsFolders() throws {
    let ps3iso = try #require(GameListing.folders.first { $0.name == "PS3ISO" })
    let wmtmp = GameListing.names([entry("Gran Turismo 5 (Europe).PNG"), entry("Gran Turismo 5 (Europe).SFO")])
    let games = GameListing.candidates(
        in: "/dev_hdd0/PS3ISO", folder: ps3iso,
        entries: [entry("Gran Turismo 5 (Europe).iso", 13_000), entry("Big Game.iso.0", 4_000), entry("Big Game.iso.1", 2_000),
                  entry(".DS_Store"), entry("Nested", dir: true)],
        nested: ["Nested": [entry("Nested.iso", 500), entry("Nested.jpg")]],
        wmtmp: wmtmp)
    #expect(games.map(\.game.path) == ["/dev_hdd0/PS3ISO/Big Game.iso.0", "/dev_hdd0/PS3ISO/Gran Turismo 5 (Europe).iso",
                                        "/dev_hdd0/PS3ISO/Nested/Nested.iso"])
    let split = games[0].game
    #expect(split.size == 6_000)
    #expect(split.companions == ["/dev_hdd0/PS3ISO/Big Game.iso.1"])
    #expect(split.title == "Big Game")
    let gt5 = games[1]
    #expect(gt5.game.iconPath == "/dev_hdd0/tmp/wmtmp/Gran Turismo 5 (Europe).PNG")
    #expect(gt5.sfoPath == "/dev_hdd0/tmp/wmtmp/Gran Turismo 5 (Europe).SFO")
    #expect(games[2].game.iconPath == "/dev_hdd0/PS3ISO/Nested/Nested.jpg")

    // A .cue takes its .bin tracks; a .bin without a .cue is a game of its own.
    let psx = try #require(GameListing.folders.first { $0.name == "PSXISO" })
    let ps1 = GameListing.candidates(
        in: "/dev_hdd0/PSXISO", folder: psx,
        entries: [entry("FF7 (Disc 1).cue", 100), entry("FF7 (Disc 1) (Track 1).bin", 600), entry("FF7 (Disc 1) (Track 2).bin", 50),
                  entry("Crash [SCES-00344].bin", 500)],
        nested: [:], wmtmp: [:])
    #expect(ps1.map(\.game.path) == ["/dev_hdd0/PSXISO/Crash [SCES-00344].bin", "/dev_hdd0/PSXISO/FF7 (Disc 1).cue"])
    #expect(ps1[0].game.titleID == "SCES-00344")
    #expect(ps1[1].game.size == 750)
    #expect(ps1[1].game.companions.count == 2)

    // Another game whose name starts the same is not a track, and is not deleted with this one.
    let similar = GameListing.candidates(
        in: "/dev_hdd0/PSXISO", folder: psx,
        entries: [entry("Crash.cue", 1), entry("Crash.bin", 10), entry("Crash (Track 2).bin", 20),
                  entry("Crash 2.cue", 1), entry("Crash 2.bin", 30), entry("Crash Bandicoot.bin", 40)],
        nested: [:], wmtmp: [:])
    #expect(similar.map(\.game.path) == ["/dev_hdd0/PSXISO/Crash 2.cue", "/dev_hdd0/PSXISO/Crash Bandicoot.bin", "/dev_hdd0/PSXISO/Crash.cue"])
    #expect(similar[0].game.companions == ["/dev_hdd0/PSXISO/Crash 2.bin"])
    #expect(similar[2].game.companions == ["/dev_hdd0/PSXISO/Crash (Track 2).bin", "/dev_hdd0/PSXISO/Crash.bin"])
    #expect(similar[2].game.size == 31)

    let folders = try #require(GameListing.folders.first { $0.name == "GAMES" })
    let folderGames = GameListing.candidates(in: "/dev_hdd0/GAMES", folder: folders,
                                             entries: [entry("BLUS30443-[Demon's Souls]", dir: true), entry("readme.txt")],
                                             nested: [:], wmtmp: [:])
    #expect(folderGames.count == 1)
    #expect(folderGames[0].game.titleID == "BLUS30443")
    #expect(folderGames[0].sfoPath == "/dev_hdd0/GAMES/BLUS30443-[Demon's Souls]/PS3_GAME/PARAM.SFO")
}

@Test func installedFoldersAreGamesOrUpdates() throws {
    var updates: [String: String] = [:]
    let game = GameListing.installedCandidate(entry("NPEA00418", dir: true))
    let info = GameCache.Info(sfo: ParamSFO(data: makeSFO(["CATEGORY": "HG", "TITLE": "Journey", "TITLE_ID": "NPEA00418", "APP_VER": "01.03"])))
    let result = GameListing.resolve(game, info: info, updates: &updates)
    let resolved = try #require(result)
    #expect(resolved.title == "Journey")
    #expect(resolved.platform == .psn)
    #expect(resolved.isInstalled)

    let patch = GameListing.installedCandidate(entry("BCES00569", dir: true))
    let patchInfo = GameCache.Info(sfo: ParamSFO(data: makeSFO(["CATEGORY": "GD", "TITLE_ID": "BCES00569", "APP_VER": "02.17"])))
    let patchResult = GameListing.resolve(patch, info: patchInfo, updates: &updates)
    #expect(patchResult == nil)
    #expect(updates == ["BCES00569": "02.17"])

    let disc = Game(path: "/dev_hdd0/PS3ISO/GT5.iso", title: "Gran Turismo 5", titleID: "BCES00569", platform: .ps3, size: 1)
    #expect(GameListing.attach(updates, to: [disc]).first?.updateVersion == "02.17")
    #expect(!GameListing.isGame(titleID: "NP0APOLLO"))
    #expect(!GameListing.isGame(titleID: "BLES80608"))
    #expect(GameListing.isGame(titleID: "BLES01200"))
}

@Test func readsSonysUpdateList() {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <titlepatch status="alive" titleid="BCES00569">
    <tag name="BCES00569_T5" popup="true" signoff="false">
    <package version="02.16" size="212000000" sha1sum="0123456789abcdef0123456789abcdef01234567" url="http://b0.ww.np.dl.playstation.net/tppkg/np/BCES00569/BCES00569_T5/a/EP9000-BCES00569_00-GRANTURISMO5XXXX-A0216-V0100-PE.pkg" ps3_system_ver="04.0000"/>
    <package version="02.17" size="215000000" sha1sum="89abcdef0123456789abcdef0123456789abcdef" url="http://b0.ww.np.dl.playstation.net/tppkg/np/BCES00569/BCES00569_T5/b/EP9000-BCES00569_00-GRANTURISMO5XXXX-A0217-V0100-PE.pkg" ps3_system_ver="04.2500"><paramsfo><TITLE>Gran Turismo 5</TITLE></paramsfo></package>
    </tag>
    </titlepatch>
    """
    let patches = GameUpdateService.parse(Data(xml.utf8))
    #expect(patches.map(\.version) == ["02.16", "02.17"])
    #expect(patches[1].titleID == "BCES00569")
    #expect(patches[1].size == 215_000_000)
    #expect(patches[1].systemVersion == "4.25")
    #expect(GameUpdateService.newer(patches, than: "02.16").map(\.version) == ["02.17"])
    #expect(GameUpdateService.newer(patches.reversed(), than: nil).map(\.version) == ["02.16", "02.17"])
    #expect(GameUpdateService.newer(patches, than: "02.17").isEmpty)
    #expect(GameUpdateService.firmware(fromSystemVersion: "03.5500") == "3.55")
    #expect(GameUpdateService.parse(Data()).isEmpty)

    let ps2 = Game(path: "/dev_hdd0/PS2ISO/x.iso", title: "X", titleID: "SLES-12345", platform: .ps2)
    #expect(!GameUpdateService.canHaveUpdates(ps2))
    #expect(GameUpdateService.canHaveUpdates(Fixtures.games[0]))
}

@Test func findsCoverSourcesByPlatform() {
    let gt5 = Game(path: "/dev_hdd0/PS3ISO/GT5.iso", title: "Gran Turismo 5", titleID: "BCES00569", platform: .ps3)
    #expect(CoverService.sources(for: gt5).map(\.absoluteString) == [
        "https://raw.githubusercontent.com/aldostools/Resources/master/COV/BCES00569.JPG",
        "https://art.gametdb.com/ps3/coverM/EN/BCES00569.jpg",
        "https://art.gametdb.com/ps3/coverM/US/BCES00569.jpg",
    ])
    let sotc = Game(path: "/dev_hdd0/PS2ISO/SotC.iso", title: "Shadow of the Colossus", titleID: "SCES-53326", platform: .ps2)
    #expect(CoverService.sources(for: sotc).first?.absoluteString == "https://raw.githubusercontent.com/xlenore/ps2-covers/main/covers/default/SCES-53326.jpg")
    let unknown = Game(path: "/dev_hdd0/PS3ISO/X.iso", title: "X", platform: .ps3)
    #expect(CoverService.sources(for: unknown).isEmpty)
    #expect(CoverService.key(for: Game(path: "/dev_hdd0/game/NPEA00418", title: "Journey", titleID: "NPEA00418", platform: .psn)) == "ps3-NPEA00418")
}

@Test func looksUpGames() {
    let games = Fixtures.games
    guard case .found(let byID) = Game.lookup("bces00569", in: games) else { Issue.record("by title ID"); return }
    #expect(byID.title == "Gran Turismo 5")
    guard case .found(let bySerial) = Game.lookup("SCES53326", in: games) else { Issue.record("by serial"); return }
    #expect(bySerial.title == "Shadow of the Colossus")
    guard case .found(let partial) = Game.lookup("demon", in: games) else { Issue.record("partial"); return }
    #expect(partial.titleID == "BLUS30443")
    guard case .ambiguous = Game.lookup("the", in: games) else { Issue.record("the should be ambiguous"); return }
    guard case .missing = Game.lookup("halo", in: games) else { Issue.record("halo should be missing"); return }
}

@Test func routesFilesInsideTheMirrorByPath() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("ps3center-test-\(UUID().uuidString)")
    try fm.createDirectory(at: root.appendingPathComponent("dev_hdd0/packages"), withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("_Installerat"), withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("USB/PKG"), withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    let pkg = root.appendingPathComponent("dev_hdd0/packages/app.pkg")
    try Data([0x7F, 0x50, 0x4B, 0x47]).write(to: pkg)
    let routes = try FileRouter.routes(for: [pkg], mirrorRoot: root)
    #expect(routes.map(\.remote) == ["/dev_hdd0/packages/app.pkg"])
    #expect(routes.first?.kind == .package)

    let outside = fm.temporaryDirectory.appendingPathComponent("ps3center-\(UUID().uuidString).rap")
    try Data([1]).write(to: outside)
    defer { try? fm.removeItem(at: outside) }
    #expect(try FileRouter.routes(for: [outside], mirrorRoot: root).first?.remote == "/dev_hdd0/exdata/" + outside.lastPathComponent)

    let usbFile = root.appendingPathComponent("USB/PKG/x.pkg")
    try Data([1]).write(to: usbFile)
    #expect(throws: PS3Error.self) { try FileRouter.routes(for: [usbFile], mirrorRoot: root) }
}

/// Builds a minimal PARAM.SFO with string values.
func makeSFO(_ values: [String: String]) -> Data { ParamSFO.encode(values) }

@Test func looksUpCatalogEntries() {
    guard case .found(let byID) = Catalog.lookup("ezremote") else { Issue.record("ezremote"); return }
    #expect(byID.titleID == "RMTC00001")
    guard case .found(let byTitle) = Catalog.lookup("np0apollo") else { Issue.record("np0apollo"); return }
    #expect(byTitle.id == "apollo")
    guard case .found(let partial) = Catalog.lookup("iris") else { Issue.record("iris"); return }
    #expect(partial.id == "irisman")
    guard case .ambiguous = Catalog.lookup("psp") else { Issue.record("psp should be ambiguous"); return }
    guard case .missing = Catalog.lookup("multiman") else { Issue.record("multiman should be missing"); return }
    #expect(Catalog.entries.map(\.id).count == Set(Catalog.entries.map(\.id)).count)
}

@Test func addOnsNeverReportUpdatesFromWebMANsTag() throws {
    let entry = try #require(Catalog.entry(named: "pspremasters"))
    let sfo = makeSFO(["APP_VER": "01.00", "TITLE_ID": "PSPC66820"])
    let release = AppsService.LatestInfo(version: "1.47.50", assetURL: URL(string: "https://example.invalid/a.pkg"), assetName: "a.pkg", assetData: nil)
    let status = AppsService(host: "x").status(for: entry, installedFile: sfo, console: ConsoleSnapshot(), release: .success(release))
    #expect(status.state == .upToDate)
    #expect(status.latest == nil)
    #expect(status.installable)
}

@Test func detectsUpdatesAndNotInstalledApps() throws {
    let apollo = try #require(Catalog.entry(named: "apollo"))
    let release = AppsService.LatestInfo(version: "v2.4.1", assetURL: URL(string: "https://example.invalid/apollo.pkg"), assetName: "apollo-ps3.pkg", assetData: nil)
    let service = AppsService(host: "x")
    let old = service.status(for: apollo, installedFile: makeSFO(["APP_VER": "02.40"]), console: ConsoleSnapshot(), release: .success(release))
    #expect(old.state == .updateAvailable)
    #expect(old.canInstall)
    let missing = service.status(for: apollo, installedFile: nil, console: ConsoleSnapshot(), release: .success(release))
    #expect(missing.state == .notInstalled)
    #expect(missing.installable)
    let hen = try #require(Catalog.entry(named: "hen"))
    var console = ConsoleSnapshot()
    console.henVersion = "3.5.0"
    let henStatus = service.status(for: hen, installedFile: nil, console: console,
                                   release: .success(.init(version: "3.6.0", assetURL: nil, assetName: nil, assetData: nil)))
    #expect(henStatus.state == .updateAvailable)
    #expect(!henStatus.canInstall)
    #expect(!henStatus.installable)
}

// MARK: Compatibility

@Test func readsFirmwareProfiles() {
    let hen = ConsoleProfile(snapshot: ConsoleSnapshot.parse(sysInfo: "CPU: 60°C RSX: 67°C FAN: 31% Firmware : 4.93 CEX PS3HEN 3.5.0 IP: 10.0.1.35 WLAN", statusPage: ""))
    #expect(hen == ConsoleProfile(firmware: "4.93", kind: .cex, exploit: .hen, payload: "PS3HEN 3.5.0"))
    #expect(hen.label == "4.93 CEX · PS3HEN 3.5.0")
    // webMAN's get_cobra_version: "<CEX|DEX|DECR> <Cobra|Mamba|qCFW> <version>", P for PEX/D-PEX.
    let cfw = ConsoleProfile(snapshot: ConsoleSnapshot.parse(sysInfo: "Firmware : 4.92 DEX Mamba 8.4 IP: 10.0.1.35 LAN", statusPage: ""))
    #expect(cfw == ConsoleProfile(firmware: "4.92", kind: .dex, exploit: .cfw, payload: "Mamba 8.4"))
    let pex = ConsoleProfile(snapshot: ConsoleSnapshot.parse(sysInfo: "Firmware : 4.93 PEX Cobra 8.5 IP: 10.0.1.35 LAN", statusPage: ""))
    #expect(pex.exploit == .cfw)
    #expect(pex.kind == nil)
    #expect(ConsoleProfile(snapshot: ConsoleSnapshot()).exploit == nil)
}

@Test func blocksProgramsTheConsoleCannotRun() {
    let hen = ConsoleProfile(firmware: "4.93", kind: .cex, exploit: .hen)
    let cfwOnHEN = Compatibility.check(.cfwOnly, on: hen)
    #expect(cfwOnHEN.verdict == .incompatible)
    #expect(cfwOnHEN.reasons == ["Kräver CFW, din PS3 kör HEN"])
    #expect(throws: PS3Error.self) { try cfwOnHEN.enforce("Test") }
    #expect(Compatibility.check(.dexOnly, on: hen).blocksInstall)
    #expect(Compatibility.check(Requirements(minFirmware: "4.80"), on: hen) == .compatible)
    #expect(Compatibility.check(Requirements(maxFirmware: "4.88"), on: hen).reasons == ["Fungerar bara till och med firmware 4.88, din har 4.93"])
    // Requirements that cannot be checked block too; programs without any never do.
    #expect(Compatibility.check(.cfwOnly, on: ConsoleProfile()).verdict == .unknown)
    #expect(Compatibility.check(.any, on: ConsoleProfile()) == .compatible)
    // Untested is a warning, not a block.
    let untested = Compatibility.check(Requirements(untestedOn: [.cfw]), on: ConsoleProfile(firmware: "4.92", kind: .cex, exploit: .cfw))
    #expect(untested.verdict == .untested)
    #expect(!untested.blocksInstall)
}

@Test func blockedAppsCannotBeInstalledOrUpdated() throws {
    let entry = CatalogEntry(id: "cfwtool", name: "CFW Tool", summary: "", category: .tools,
                             installed: .paramSFO(titleID: "CFWTOOL00"),
                             source: .github(repo: "example/cfwtool", asset: #"\.pkg$"#),
                             homepage: "https://example.invalid", requirements: .cfwOnly)
    var console = ConsoleSnapshot()
    console.firmware = "4.93"
    console.firmwareType = "CEX"
    console.henVersion = "3.5.0"
    let release = AppsService.LatestInfo(version: "1.1", assetURL: URL(string: "https://example.invalid/a.pkg"), assetName: "a.pkg", assetData: nil)
    let service = AppsService(host: "x")
    let missing = service.status(for: entry, installedFile: nil, console: console, release: .success(release))
    #expect(!missing.installable)
    #expect(missing.blocked)
    #expect(missing.compatibility.verdict == .incompatible)
    let old = service.status(for: entry, installedFile: makeSFO(["APP_VER": "01.00"]), console: console, release: .success(release))
    #expect(old.state == .updateAvailable)
    #expect(!old.canInstall)
    #expect(old.note == "Kräver CFW, din PS3 kör HEN")

    let apollo = try #require(Catalog.entry(titleID: "np0apollo"))
    #expect(apollo.id == "apollo")
    #expect(apollo.repository == "bucanero/apollo-ps3")
    #expect(service.status(for: apollo, installedFile: nil, console: console, release: .success(release)).installable)
}

// MARK: README

@Test func parsesReadmeMarkdownAndHTML() {
    let markdown = """
    <h1 align="center">Tool<br>for PS3</h1>
    <p align="center"><img src="docs/logo.png" alt="Logo" width="200"></p>

    [![Build](https://github.com/o/r/actions/workflows/build.yml/badge.svg)](https://github.com/o/r/actions) [![Downloads][img]][dl]

    A **tool** with [docs](docs/USAGE.md), [a section](#usage) and `<titleID>`.
    Second line<br>
    third line.

    Changelog
    ---------

    - [x] Done
    - Item with ![shot](https://github.com/o/r/blob/main/shot.png)
      continued here
      - Nested

    > [!WARNING]
    > Can freeze the console.

    | Key | Action |
    |-----|--------|
    | X   | Select |

    ```
    <b>not html</b>
    ```

    [img]: https://img.shields.io/github/downloads/o/r/total.svg
    [dl]: https://github.com/o/r/releases
    """
    let readme = Readme(markdown: markdown, repo: "o/r",
                        rawBase: URL(string: "https://raw.githubusercontent.com/o/r/main/"),
                        htmlBase: URL(string: "https://github.com/o/r/blob/main/"))
    #expect(readme.blocks == [
        .heading(level: 1, text: "Tool for PS3"),
        .image(.init(url: URL(string: "https://raw.githubusercontent.com/o/r/main/docs/logo.png")!, alt: "Logo")),
        .paragraph("A **tool** with [docs](https://github.com/o/r/blob/main/docs/USAGE.md), a section and `<titleID>`. Second line\nthird line."),
        .heading(level: 2, text: "Changelog"),
        .list(items: [.init(text: "☑ Done", depth: 0), .init(text: "Item with continued here", depth: 0), .init(text: "Nested", depth: 1)], ordered: false),
        .image(.init(url: URL(string: "https://raw.githubusercontent.com/o/r/main/shot.png")!, alt: "shot")),
        .quote("**Varning**\nCan freeze the console."),
        .table(rows: [["Key", "Action"], ["X", "Select"]]),
        .code("<b>not html</b>"),
    ])
    #expect(Readme.plainText("Se **[Apollo](https://x.invalid/a)** och `kod`, *kursiv*, ds45pad_vsh*2") == "Se Apollo (https://x.invalid/a) och kod, kursiv, ds45pad_vsh*2")
}

// MARK: Fixtures

@Test func fixturesMatchWhatTheScreensShow() throws {
    let snapshot = Fixtures.snapshot
    #expect(snapshot.henVersion == "3.5.0")
    #expect(snapshot.isGameRunning)
    let statuses = Fixtures.appStatuses()
    #expect(statuses.count == Catalog.entries.count)
    let byID = Dictionary(uniqueKeysWithValues: statuses.map { ($0.id, $0) })
    #expect(byID["apollo"]?.state == .updateAvailable)
    #expect(byID["apollo"]?.canInstall == true)
    #expect(byID["hen"]?.state == .updateAvailable)
    #expect(byID["hen"]?.canInstall == false)
    #expect(byID["pkgi"]?.state == .upToDate)
    #expect(byID["ds45pad"]?.state == .upToDate)
    // mohasi's File Manager now comes from GitHub; untracked versions count as up to date.
    #expect(byID["filemanager"]?.state == .upToDate)
    #expect(byID["filemanager"]?.installable == true)
    #expect(byID["yoplayer"]?.latest == nil)
    #expect(byID["ezremote"]?.installable == true)
    #expect(statuses.allSatisfy { !$0.blocked })

    let cfw = Dictionary(uniqueKeysWithValues: Fixtures.appStatuses(on: Fixtures.cfwSnapshot).map { ($0.id, $0) })
    #expect(cfw["ps3health"]?.compatibility.verdict == .untested)
    #expect(cfw["ps3health"]?.installable == true)
    #expect(cfw["hen"]?.compatibility.verdict == .incompatible)
    #expect(Fixtures.readme.blocks.contains { if case .table = $0 { return true }; return false })

    let games = Fixtures.games
    #expect(games.contains { $0.path == snapshot.mountedGamePath })
    #expect(games.first { $0.titleID == "BCES00569" }?.updateVersion == "02.11")
    #expect(Fixtures.patches.count == 2)
    #expect(games.map(\.platform.order) == games.map(\.platform.order).sorted())
}

// MARK: The Mac's games and the queue

/// A minimal ISO 9660 image: files in the root and, optionally, in PS3_GAME. Files are small
/// (one 2048-byte block each).
private func makeISO(root rootFiles: [(String, Data)] = [], game gameFiles: [(String, Data)] = []) -> Data {
    func block(_ bytes: [UInt8]) -> [UInt8] { bytes + [UInt8](repeating: 0, count: 2048 - bytes.count) }
    func le32(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24 & 0xFF)] }
    func be32(_ v: Int) -> [UInt8] { le32(v).reversed() }
    func record(_ name: [UInt8], extent: Int, size: Int, directory: Bool) -> [UInt8] {
        var r: [UInt8] = [0, 0] + le32(extent) + be32(extent) + le32(size) + be32(size)
        r += [UInt8](repeating: 0, count: 7) + [directory ? 2 : 0, 0, 0] + [1, 0, 0, 1] + [UInt8(name.count)] + name
        if r.count % 2 == 1 { r.append(0) }
        r[0] = UInt8(r.count)
        return r
    }
    var next = 20
    var data: [UInt8] = []
    var rootDir = record([0], extent: 18, size: 2048, directory: true) + record([1], extent: 18, size: 2048, directory: true)
    if !gameFiles.isEmpty { rootDir += record([UInt8]("PS3_GAME".utf8), extent: 19, size: 2048, directory: true) }
    for (name, content) in rootFiles {
        rootDir += record([UInt8]((name + ";1").utf8), extent: next, size: content.count, directory: false)
        data += block([UInt8](content))
        next += 1
    }
    var gameDir = record([0], extent: 19, size: 2048, directory: true) + record([1], extent: 18, size: 2048, directory: true)
    for (name, content) in gameFiles {
        gameDir += record([UInt8]((name + ";1").utf8), extent: next, size: content.count, directory: false)
        data += block([UInt8](content))
        next += 1
    }
    var pvd: [UInt8] = [1] + [UInt8]("CD001".utf8) + [1, 0]
    pvd += [UInt8]((gameFiles.isEmpty ? "PLAYSTATION" : "PS3").padding(toLength: 32, withPad: " ", startingAt: 0).utf8)
    pvd += [UInt8]((gameFiles.isEmpty ? "TEST" : "PS3VOLUME").padding(toLength: 32, withPad: " ", startingAt: 0).utf8)
    pvd += [UInt8](repeating: 0, count: 156 - pvd.count) + record([0], extent: 18, size: 2048, directory: true)
    var image = [UInt8](repeating: 0, count: 16 * 2048)
    image += block(pvd) + block([255] + [UInt8]("CD001".utf8)) + block(rootDir) + block(gameDir) + data
    return Data(image)
}

private func makeISO(systemCNF: String) -> Data {
    makeISO(root: [("SYSTEM.CNF", Data(systemCNF.utf8))])
}

/// The same image as a raw CD image: 2352-byte MODE2 sectors, 24 bytes of header first.
private func rawCD(_ iso: Data) -> Data {
    var raw = Data()
    let sync: [UInt8] = [0x00] + [UInt8](repeating: 0xFF, count: 10) + [0x00]
    for start in stride(from: 0, to: iso.count, by: 2048) {
        raw += sync + [0, 2, 0, 2] + [UInt8](repeating: 0, count: 8)
        raw += iso[start..<(start + 2048)]
        raw += Data(count: 280)
    }
    return raw
}

@Test func readsSerialsFromPlainAndRawImages() throws {
    let fm = FileManager.default
    let folder = fm.temporaryDirectory.appendingPathComponent("ps3center-iso-\(UUID().uuidString)")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: folder) }
    let iso = makeISO(systemCNF: "BOOT2 = cdrom0:\\SLES_533.26;1\r\nVER = 1.00\r\n")
    let plain = folder.appendingPathComponent("Shadow of the Colossus.iso")
    try iso.write(to: plain)
    let raw = folder.appendingPathComponent("Spyro.bin")
    try rawCD(makeISO(systemCNF: "BOOT = cdrom:\\SCES_014.38;1\r\n")).write(to: raw)
    let cue = folder.appendingPathComponent("Spyro.cue")
    try Data("FILE \"Spyro.bin\" BINARY\n  TRACK 01 MODE2/2352\n".utf8).write(to: cue)

    #expect(try FileRouter.classify(plain).0 == .ps2ISO)
    #expect(try ISOImage(url: raw).readFile("SYSTEM.CNF").map { String(decoding: $0, as: UTF8.self) }?.contains("SCES_014.38") == true)
    let ps2 = Game(path: plain.path, title: "x", platform: .ps2, source: .mac)
    #expect(LocalGameReader.read(ps2).titleID == "SLES-53326")
    let ps1 = Game(path: cue.path, title: "x", platform: .ps1, source: .mac)
    #expect(LocalGameReader.read(ps1).titleID == "SCES-01438")
    #expect(LocalGameReader.serial(from: "ULES00995") == "ULES-00995")
}

@Test func matchesMacGamesWithTheConsole() {
    let states = LibraryMatch.states(mac: Fixtures.macGames, console: Fixtures.games)
    func state(_ title: String) -> MacGameState? {
        Fixtures.macGames.first { $0.title == title }.flatMap { states[$0.id] }
    }
    #expect(state("Gran Turismo 5") == .onConsole)
    #expect(state("Uncharted 2: Among Thieves") == .notOnConsole)
    let partial = Game(path: "/Users/x/PS3/Test Drive Unlimited 2 (Europe) (En,Fr,De,Es,It).dec.iso", title: "TDU2",
                       platform: .ps3, size: 20_000_000_000, source: .mac)
    #expect(LibraryMatch.states(mac: [partial], console: Fixtures.games)[partial.id] == .partial)
}

@Test func queuesOneItemPerGame() {
    let cue = Route(local: URL(fileURLWithPath: "/m/FF7.cue"), remote: "/dev_hdd0/PSXISO/FF7.cue", kind: .psxISO, size: 100, title: "Final Fantasy VII")
    let bin = Route(local: URL(fileURLWithPath: "/m/FF7.bin"), remote: "/dev_hdd0/PSXISO/FF7.bin", kind: .psxISO, size: 700, title: "Final Fantasy VII")
    let iso = Route(local: URL(fileURLWithPath: "/m/GT5.iso"), remote: "/dev_hdd0/PS3ISO/GT5.iso", kind: .ps3ISO, size: 13, title: nil)
    var queue = TransferQueue()
    let added = queue.add([cue, bin, iso])
    #expect(added.map(\.title) == ["Final Fantasy VII", "GT5"])
    #expect(added[0].total == 800)
    #expect(queue.add([cue, bin]).isEmpty)  // already waiting
    #expect(queue.pending.count == 2)
    #expect(queue.remainingBytes == 813)
    queue.update(added[0].id) { $0.state = .done }
    queue.removeFinished()
    #expect(queue.items.map(\.title) == ["GT5"])
    #expect(Fixtures.queue.items.contains { $0.state == .sending })
}

@Test func queueEditsKeepWhatOthersChanged() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("queue.json")
    let route = { (name: String) in
        Route(local: URL(fileURLWithPath: "/m/\(name).iso"), remote: "/dev_hdd0/PS3ISO/\(name).iso", kind: .ps3ISO, size: 1, title: nil)
    }
    let first = try #require(TransferQueue.edit(at: file) { $0.add([route("A")]) }.first)

    // Another process adds a game while this one holds an older copy of the queue.
    let older = TransferQueue.load(from: file)
    TransferQueue.edit(at: file) { $0.add([route("B")]) }
    #expect(older.items.count == 1)
    TransferQueue.edit(at: file) { $0.update(first.id) { $0.state = .sending } }

    let latest = TransferQueue.load(from: file)
    #expect(latest.items.map(\.title) == ["A", "B"])
    #expect(latest.items[0].state == .sending)

    // A change that throws writes nothing.
    struct Stop: Error {}
    #expect(throws: Stop.self) {
        try TransferQueue.edit(at: file) { queue in
            queue.items.removeAll()
            throw Stop()
        }
    }
    #expect(TransferQueue.load(from: file).items.count == 2)
}

@Test func anErrorIsNeverTakenForNoGameRunning() async throws {
    struct Slow: Error {}
    // Slow answers are waited out, and only the answer that nothing runs ends the wait.
    var answers: [Result<String?, Error>] = [.success("EBOOT.BIN"), .failure(Slow()), .failure(Slow()), .success("EBOOT.BIN"), .success(nil)]
    var announced: [String] = []
    try await TransferService.waitForNoGame(pollSeconds: 0, check: { try answers.removeFirst().get() }, announce: { announced.append($0) })
    #expect(answers.isEmpty)
    #expect(announced == ["EBOOT.BIN"])

    // A console that keeps not answering is an error, so no shutdown or refresh follows.
    var calls = 0
    await #expect(throws: PS3Error.self) {
        try await TransferService.waitForNoGame(pollSeconds: 0, allowedFailures: 3, check: {
            calls += 1
            throw Slow()
        }, announce: { _ in })
    }
    #expect(calls == 3)
}

// MARK: Game server

private func packet(_ opcode: UInt16, length: UInt16 = 0, count: UInt32 = 0, offset: UInt64 = 0) -> Data {
    var data = Data()
    data.appendBE(opcode)
    data.appendBE(length)
    data.appendBE(count)
    data.appendBE(offset)
    return data
}

/// A blocking client, as webMAN talks to ps3netsrv: one command, then its answer.
private final class NetClient {
    let fd: Int32

    init?(port: UInt16) {
        fd = socket(AF_INET, SOCK_STREAM, 0)
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if connected != 0 { return nil }  // deinit closes the socket
    }

    deinit { close(fd) }

    func send(_ data: Data) {
        data.withUnsafeBytes { _ = Darwin.send(fd, $0.baseAddress, data.count, 0) }
    }

    func send(_ opcode: UInt16, path: String) {
        let bytes = Data(path.utf8)
        send(packet(opcode, length: UInt16(bytes.count)) + bytes)
    }

    func receive(_ count: Int) -> Data {
        var out = Data()
        var buffer = [UInt8](repeating: 0, count: max(count, 1))
        while out.count < count {
            let n = recv(fd, &buffer, count - out.count, 0)
            if n <= 0 { break }
            out.append(contentsOf: buffer[0..<n])
        }
        return out
    }
}

@Test func servesGamesOverThePS3NetsrvProtocol() async throws {
    let fm = FileManager.default
    let folder = fm.temporaryDirectory.appendingPathComponent("ps3center-net-\(UUID().uuidString)")
    try fm.createDirectory(at: folder.appendingPathComponent("Sub"), withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: folder) }
    let sfo = makeSFO(["TITLE": "Net Game", "TITLE_ID": "BLES99999", "APP_VER": "01.00"])
    let iso = makeISO(game: [("PARAM.SFO", sfo), ("ICON0.PNG", Data([0x89, 0x50, 0x4E, 0x47]))])
    try iso.write(to: folder.appendingPathComponent("Game.iso"))
    try Data(count: 4096).write(to: folder.appendingPathComponent("Sub/Other.iso"))

    let port = UInt16.random(in: 41000...49000)
    let kind = try #require(GameFolders.kind(named: "PS3ISO"))
    let server = NetServer(folders: [(kind, folder)], allowedHost: nil, port: port)
    try server.start()
    defer { server.stop() }
    for _ in 0..<50 where !server.currentStatus.isRunning { try await Task.sleep(nanoseconds: 50_000_000) }
    let client = try #require(NetClient(port: port))

    // The merged folder, all at once (READ_DIR): a count, then 529-byte records.
    client.send(NetCommand.openDir.rawValue, path: "/PS3ISO")
    #expect(client.receive(4) == Data([0, 0, 0, 0]))
    client.send(packet(NetCommand.readDir.rawValue))
    let count = Int(client.receive(8).be64(0))
    try #require(count == 2)
    let records = client.receive(count * 529)
    let names = (0..<count).map { i -> String in
        String(decoding: records[(i * 529 + 17)..<(i * 529 + 529)].prefix { $0 != 0 }, as: UTF8.self)
    }
    #expect(names == ["Game.iso", "Sub"])
    #expect(records[529 + 16] == 1)  // Sub is a directory

    // Open the ISO and read the volume descriptor, with and without a result header.
    client.send(NetCommand.openFile.rawValue, path: "/PS3ISO/Game.iso")
    let opened = client.receive(16)
    #expect(Int(opened.be64(0)) == iso.count)
    client.send(packet(NetCommand.readFile.rawValue, count: 6, offset: 32768))
    #expect(client.receive(4).be32(0) == 6)
    #expect(client.receive(6) == Data([1]) + Data("CD001".utf8))
    client.send(packet(NetCommand.readFileCritical.rawValue, count: 16, offset: 32768))
    #expect(client.receive(16).prefix(6) == Data([1]) + Data("CD001".utf8))

    // PARAM.SFO next to the ISO comes from inside it.
    client.send(NetCommand.statFile.rawValue, path: "/PS3ISO/Game.SFO")
    let stat = client.receive(33)
    #expect(Int(stat.be64(0)) == sfo.count)
    client.send(NetCommand.openFile.rawValue, path: "/PS3ISO/Game.SFO")
    #expect(Int(client.receive(16).be64(0)) == sfo.count)
    client.send(packet(NetCommand.readFile.rawValue, count: UInt32(sfo.count), offset: 0))
    #expect(Int(client.receive(4).be32(0)) == sfo.count)
    #expect(client.receive(sfo.count) == sfo)

    // "//" lists the files of subfolders too.
    client.send(NetCommand.openDir.rawValue, path: "/PS3ISO//")
    #expect(client.receive(4) == Data([0, 0, 0, 0]))
    client.send(packet(NetCommand.readDir.rawValue))
    let deep = Int(client.receive(8).be64(0))
    try #require(deep == 2)
    let deepRecords = client.receive(deep * 529)
    let deepNames = (0..<deep).map { i -> String in
        String(decoding: deepRecords[(i * 529 + 17)..<(i * 529 + 529)].prefix { $0 != 0 }, as: UTF8.self)
    }
    #expect(deepNames == ["Game.iso", "Sub/Other.iso"])

    // Nothing outside the folders, and nothing written.
    client.send(NetCommand.openFile.rawValue, path: "/PS3ISO/../../etc/passwd")
    #expect(client.receive(16).be64(0) == UInt64.max)
    client.send(NetCommand.createFile.rawValue, path: "/PS3ISO/new.iso")
    #expect(client.receive(1).isEmpty)
}

// MARK: Controlling the console

@Test func padButtonsAreFixedNames() {
    #expect(PadButton(name: "ner") == .down)
    #expect(PadButton(name: "OK") == .accept)
    #expect(PadButton(name: "x") == .cross)
    #expect(PadButton(name: "ps") == .ps)
    #expect(PadButton(name: "cross=swap") == nil)
    // No name holds "=", which webMAN reads as "change the enter button".
    #expect(PadButton.allCases.allSatisfy { !$0.rawValue.contains("=") })
}

@Test func findsTheScreenshotOnWebMANsPage() {
    let page = #"<html><body><img src="/dev_hdd0/tmp/screenshot.bmp" width="100%"></body></html>"#
    #expect(WebMAN.imageSource(in: page) == "/dev_hdd0/tmp/screenshot.bmp")
    #expect(WebMAN.imageSource(in: "<p>no image</p>") == nil)
    #expect(ImageKind(Data([0x42, 0x4D, 0, 0])) == .bmp)
    #expect(ImageKind(Data([0xFF, 0xD8, 0xFF, 0xE0])) == .jpeg)
    #expect(ImageKind(Data("<html>".utf8)) == nil)
}

@Test func fanTargetOnlyInDynamicModeAndRange() {
    var dynamic = ConsoleSnapshot()
    dynamic.fanTargetMax = 68
    #expect(FanControl.refusal(target: 70, snapshot: dynamic) == nil)
    #expect(FanControl.refusal(target: 55, snapshot: dynamic) != nil)
    #expect(FanControl.refusal(target: 80, snapshot: dynamic) != nil)
    #expect(FanControl.refusal(target: 70, snapshot: ConsoleSnapshot()) != nil)  // SYSCON: no target
}

@Test func pingPacketChecksums() {
    let packet: [UInt8] = [8, 0, 0, 0, 0x12, 0x34, 0, 1]
    let sum = Reachability.checksum(packet)
    #expect(sum == 0xE5CA)
    #expect(Reachability.checksum([8, 0, UInt8(sum >> 8), UInt8(sum & 0xFF), 0x12, 0x34, 0, 1]) == 0)
}

@Test func tracksPlayTimeFromPolls() {
    var running = ConsoleSnapshot()
    running.mountedGamePath = "/dev_hdd0/PS3ISO/Gran Turismo 5.iso"
    running.mountedGameName = "Gran Turismo 5"
    running.runningProcess = "EBOOT.BIN"
    var tracker = PlayTracker(interval: 3)
    var log = PlayLog()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let first = tracker.observe(running, at: start, log: &log)
    #expect(first)
    _ = tracker.observe(running, at: start.addingTimeInterval(3), log: &log)
    _ = tracker.observe(running, at: start.addingTimeInterval(603), log: &log)  // the Mac slept: 6 s, not 600
    let afterSleep = log.games[running.mountedGamePath!]
    #expect(afterSleep?.seconds == 9)
    #expect(afterSleep?.sessions == 1)

    var xmb = running
    xmb.runningProcess = nil
    let onXMB = tracker.observe(xmb, at: start.addingTimeInterval(606), log: &log)
    #expect(!onXMB)
    _ = tracker.observe(running, at: start.addingTimeInterval(700), log: &log)
    #expect(log.games[running.mountedGamePath!]?.sessions == 2)
    #expect(log.games[running.mountedGamePath!]?.seconds == 9)

    let game = Game(path: "/dev_hdd0/PS3ISO/Gran Turismo 5.iso", title: "Gran Turismo 5", platform: .ps3)
    #expect(log.record(for: game)?.title == "Gran Turismo 5")
    #expect(Format.playTime(9) == "under en minut")
    #expect(Format.playTime(3 * 3600 + 20 * 60) == "3 h 20 min")
}

// MARK: Backups and maintenance

@Test func readsWebMANsFolderStats() {
    let page = #"<a href="/dev_hdd0">dev_hdd0</a>/<a href="/dev_hdd0/game">game</a><p>Size: 12.3 GB (13,207,024,640 bytes)<br>Dir(s): 1,120<br>File(s): 24,210"#
    let stat = StorageAnalyzer.parseStat(page)
    #expect(stat?.bytes == 13_207_024_640)
    #expect(stat?.folders == 1120)
    #expect(stat?.files == 24210)
    #expect(StorageAnalyzer.parseStat("<p>Size: 0.1 MB (512 bytes)<br>Dir(s): 0<br>File(s): 1")?.bytes == 512)
    #expect(StorageAnalyzer.parseStat("Not found") == nil)

    let map = StorageMap(areas: [StorageUsage(name: "Spel", path: "/dev_hdd0/game", bytes: 100)], largest: [], free: 300, total: 1000)
    #expect(map.other == 600)
}

@Test func readsPluginListsAndSaveFolders() {
    let list = "# kernel\n/dev_hdd0/plugins/webftp_server.sprx\r\n\n  /dev_hdd0/plugins/ds45pad.sprx  \nwhatever\n"
    #expect(MaintenanceService.pluginPaths(in: list) == ["/dev_hdd0/plugins/webftp_server.sprx", "/dev_hdd0/plugins/ds45pad.sprx"])
    #expect(SaveBackupService.isUser("00000001"))
    #expect(!SaveBackupService.isUser("tmp"))
    let date = SaveBackupService.parseMDTM("20261022214005")
    #expect(date == Date(timeIntervalSince1970: 1_792_705_205))
    let save = SaveGame(user: "00000001", folder: "BCES00569-AUTOSAVE", title: "Gran Turismo 5", size: 1024)
    #expect(save.titleID == "BCES00569")
    let files = [FTPClient.Entry(name: "SYS-DATA", size: 10, isDirectory: false, modified: "Oct 22 21:40"),
                 FTPClient.Entry(name: "PARAM.SFO", size: 5, isDirectory: false, modified: "Oct 22 21:40")]
    #expect(SaveBackupService.signature(files) == ["PARAM.SFO|5|Oct 22 21:40", "SYS-DATA|10|Oct 22 21:40"])
}

@Test func namesARippedDiscLikeWebMAN() {
    let disc = DiscInfo(title: "Uncharted 2: Among Thieves", titleID: "BCES00757", bytes: 25_000_000_000)
    #expect(disc.folderName == "BCES00757-[Uncharted 2 Among Thieves]")
    #expect(disc.destination == "/dev_hdd0/GAMES/BCES00757-[Uncharted 2 Among Thieves]")
}

@Test func comparesWebMANSettingsForms() {
    let sent = "u0=1&autop=%2Fdev_hdd0%2FPS3ISO%2FAUTOBOOT.ISO&ic=1&nd0=1&neth0=10.0.1.43&netp0=38008&l=0"
    let sameInAnotherOrder = "ic=1&u0=1&l=0&nd0=1&neth0=10.0.1.43&netp0=38008&autop=%2Fdev_hdd0%2FPS3ISO%2FAUTOBOOT.ISO"
    #expect(WebMANSettings.differences(sent: sent, saved: sameInAnotherOrder).isEmpty)
    let lostTwo = "u0=1&autop=%2Fdev_hdd0%2FPS3ISO%2FAUTOBOOT.ISO&ic=0&neth0=10.0.1.43&netp0=38008&l=0"
    #expect(WebMANSettings.differences(sent: sent, saved: lostTwo) == ["ic", "nd0"])
}

// MARK: Watching, retries and uninstalling

@Test func queuesNewGamesOnceTheyStopGrowing() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent("ps3center-watch-\(UUID().uuidString)")
    let folder = base.appendingPathComponent("PS2")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }
    try Data(count: 10).write(to: folder.appendingPathComponent("Old.iso"))
    let kind = try #require(GameFolders.kind(named: "PS2ISO"))
    var watch = FolderWatch(file: base.appendingPathComponent("watch.json"))
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    // The first look takes what is there as handled.
    #expect(watch.poll([(kind, folder)], now: start).isEmpty)
    try Data(count: 100).write(to: folder.appendingPathComponent("New.iso"))
    try Data(count: 5).write(to: folder.appendingPathComponent("Half.iso.part"))
    #expect(watch.poll([(kind, folder)], now: start.addingTimeInterval(10)).isEmpty)  // first seen
    try Data(count: 200).write(to: folder.appendingPathComponent("New.iso"))
    #expect(watch.poll([(kind, folder)], now: start.addingTimeInterval(20)).isEmpty)  // still growing
    #expect(watch.poll([(kind, folder)], now: start.addingTimeInterval(50)).isEmpty)  // same size, not long enough
    let ready = watch.poll([(kind, folder)], now: start.addingTimeInterval(90))
    #expect(ready.map(\.entry.lastPathComponent) == ["New.iso"])
    #expect(watch.poll([(kind, folder)], now: start.addingTimeInterval(200)).isEmpty)  // only once

    // What it has seen survives a restart.
    var again = FolderWatch(file: base.appendingPathComponent("watch.json"))
    #expect(again.poll([(kind, folder)], now: start.addingTimeInterval(300)).isEmpty)
}

@Test func retriesOnlyNetworkFailures() {
    #expect(RetryPolicy.isTransient(PS3Error.unreachable(host: "10.0.1.35")))
    #expect(RetryPolicy.isTransient(PS3Error.timeout("väntar på svar från PS3:an")))
    #expect(RetryPolicy.isTransient(PS3Error.ftp(code: 426, message: "Connection closed; transfer aborted")))
    #expect(RetryPolicy.isTransient(PS3Error.ftpProtocol("storleken på /dev_hdd0/PS3ISO/A.iso.part stämmer inte efter uppladdningen")))
    #expect(!RetryPolicy.isTransient(PS3Error.notEnoughSpace(needed: 10, free: 1)))
    #expect(!RetryPolicy.isTransient(PS3Error.ftp(code: 550, message: "Permission denied")))
    #expect(!RetryPolicy.isTransient(CancellationError()))
}

@Test func neverUninstallsWhatHENNeeds() {
    #expect(UninstallGuard.refusal(titleID: "NP0APOLLO", title: "Apollo Save Tool", path: "/dev_hdd0/game/NP0APOLLO") == nil)
    #expect(UninstallGuard.refusal(titleID: "PS3XPLOIT", title: "PS3 Toolset", path: "/dev_hdd0/game/PS3XPLOIT") != nil)
    #expect(UninstallGuard.refusal(titleID: "HENTOOL01", title: "Enable HEN", path: "/dev_hdd0/game/HENTOOL01") != nil)
    #expect(UninstallGuard.refusal(titleID: nil, title: "Henrik's Game", path: "/dev_hdd0/game/ABCD12345") == nil)
    #expect(UninstallGuard.refusal(titleID: nil, title: "Root", path: "/dev_hdd0/game") != nil)
    #expect(UninstallGuard.refusal(titleID: nil, title: "Deep", path: "/dev_hdd0/game/ABC/USRDIR") != nil)
}
