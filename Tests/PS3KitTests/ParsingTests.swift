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

@Test func encodesWebCommands() {
    #expect(WebMAN.encodeCommand("/install.ps3/dev_hdd0/packages/a b.pkg") == "/install.ps3/dev_hdd0/packages/a%20b.pkg")
    #expect(WebMAN.encodeText("Klart & klart") == "Klart%20%26%20klart")
    #expect(WebMAN.encodeText("Spel är klart") == "Spel%20%C3%A4r%20klart")
}

@Test func parsesFTPListLines() {
    let line = "-rwxrwxrwx 1 root  root     9642180608 Jun 05 18:33 Test Drive Unlimited 2 (Europe) (En,Fr,De,Es,It).dec.iso"
    #expect(FTPClient.parseListLine(line) == FTPClient.Entry(name: "Test Drive Unlimited 2 (Europe) (En,Fr,De,Es,It).dec.iso", size: 9_642_180_608, isDirectory: false))
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
func makeSFO(_ values: [String: String]) -> Data {
    let keys = values.keys.sorted()
    var keyTable = Data()
    var dataTable = Data()
    var index = Data()
    func le16(_ v: Int) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)]) }
    func le32(_ v: Int) -> Data { le16(v & 0xFFFF) + le16(v >> 16) }
    for key in keys {
        let value = Data(values[key]!.utf8) + Data([0])
        index += le16(keyTable.count) + le16(0x0204) + le32(value.count) + le32(value.count) + le32(dataTable.count)
        keyTable += Data(key.utf8) + Data([0])
        dataTable += value
    }
    let keyStart = 20 + index.count
    let dataStart = keyStart + keyTable.count
    var header = Data([0x00, 0x50, 0x53, 0x46]) + le32(0x101)
    header += le32(keyStart) + le32(dataStart) + le32(keys.count)
    return header + index + keyTable + dataTable
}

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
