import Foundation
import Testing
@testable import PS3Kit

// Rules that used to be strings or numbers repeated in the CLI and the app, now in one place.

@Test func everyLogKindKeepsItsWordInTheLog() {
    // `ps3 history` and scripts read these words; renaming a case must not change them.
    #expect(OperationKind.installTheme.rawValue == "install-theme")
    #expect(OperationKind.reloadXMB.rawValue == "reload-xmb")
    #expect(OperationKind.webmanSetup.rawValue == "webman-setup")
    #expect(Set(OperationKind.allCases.map(\.rawValue)).count == OperationKind.allCases.count)
}

@Test func aLogLineStaysOneLineWhateverTheDetail() {
    let line = OperationLog.line(.send, "Game\tName\nwith breaks.iso", at: Date(timeIntervalSince1970: 0))
    #expect(line.hasSuffix("\tsend\tGame Name with breaks.iso\n"))
    let entries = OperationLog.entries(in: line + "garbage without tabs\n" + line, limit: 10)
    #expect(entries.count == 2)
    #expect(entries[0].kind == .send)
    #expect(entries[0].detail == "Game Name with breaks.iso")
}

@Test func onAndOffAreReadOnceForOldAndNewLines() {
    func entry(_ kind: String, _ detail: String) -> OperationLog.Entry { .init(date: "", action: kind, detail: detail) }
    #expect(entry("record", "start").switchedOn == true)
    #expect(entry("record", "stop").switchedOn == false)
    #expect(entry("game-music", "på").switchedOn == true)  // written before the English interface
    #expect(entry("update-block", "off").switchedOn == false)
    #expect(entry("send", "/dev_hdd0/x.iso").switchedOn == nil)
    #expect(entry("from-a-newer-ps3", "x").kind == nil)
}

@Test func theNetworkIsReadFromWebMANsWordsAndKeepsItsKey() throws {
    let wifi = ConsoleSnapshot.parse(sysInfo: "CPU: 60°C RSX: 67°C IP: 10.0.1.35 WLAN System storage: 1 GB free", statusPage: "")
    let lan = ConsoleSnapshot.parse(sysInfo: "CPU: 60°C RSX: 67°C IP: 10.0.1.35 LAN System storage: 1 GB free", statusPage: "")
    #expect(wifi.network == .wifi)
    #expect(lan.network == .lan)
    // speeds.json is keyed on these, and older files say exactly this.
    #expect(NetworkKind.wifi.rawValue == "Wi-Fi")
    let old = #"{"upload": 3250000, "network": "Wi-Fi", "measuredAt": "2026-10-24T18:00:00Z"}"#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    #expect(try decoder.decode(SpeedResult.self, from: Data(old.utf8)).network == .wifi)
}

@Test func healthBandsAreTheSameForEveryScreen() {
    #expect(HealthLevel(score: 100) == .excellent)
    #expect(HealthLevel(score: 85) == .excellent)
    #expect(HealthLevel(score: 84) == .good)
    #expect(HealthLevel(score: 65) == .good)
    #expect(HealthLevel(score: 64) == .ok)  // the app showed this as red before
    #expect(HealthLevel(score: 45) == .ok)
    #expect(HealthLevel(score: 44) == .warning)
    #expect(HealthLevel.ok.label == "OK")

    var hot = ConsoleSnapshot()
    hot.cpuTemp = 85
    hot.computeHealth()
    #expect(hot.health == 70)
    #expect(hot.healthLabel == hot.healthLevel.label)
}

@Test func temperatureLevelsWarnAndThenGetHotTenDegreesLater() {
    #expect(Thermal.cpu.level(69) == .normal)
    #expect(Thermal.cpu.level(70) == .warm)
    #expect(Thermal.cpu.level(80) == .hot)
    #expect(Thermal.rsx.level(79) == .warm)
    #expect(Thermal.rsx.level(85) == .hot)
}

@Test func theGameServerTakesItsOwnSlotOrAnEmptyOneNeverSomeoneElses() {
    typealias Slot = WebMANSettings.NetServerSlot
    let mac = "10.0.1.20"
    let slots = [Slot(enabled: true, host: "10.0.1.99", port: 38008), Slot(enabled: false, host: "", port: 38008),
                 Slot(enabled: false, host: mac, port: 38009)]
    #expect(WebMANSettings.readySlot(slots, address: mac, port: 38008) == nil)
    #expect(WebMANSettings.slotToFill(slots, address: mac) == 2)  // its own, on another port
    #expect(WebMANSettings.slotToFill(Array(slots.prefix(2)), address: mac) == 1)  // the empty one
    #expect(WebMANSettings.slotToFill(Array(slots.prefix(1)), address: mac) == nil)  // only another's
    let ready = [Slot(enabled: true, host: mac, port: 38008)]
    #expect(WebMANSettings.readySlot(ready, address: mac, port: 38008) == 0)
}

@Test func aRouteFromSonysServerIsADownload() {
    let patch = Route(local: URL(fileURLWithPath: "/tmp/p.pkg"), remote: "http://b0.ww.np.dl.playstation.net/x.pkg", kind: .package, size: 1, title: nil)
    let upload = Route(local: URL(fileURLWithPath: "/m/x.iso"), remote: "/dev_hdd0/PS3ISO/http stuff.iso", kind: .ps3ISO, size: 1, title: nil)
    #expect(patch.isDownload)
    #expect(!upload.isDownload)
}
