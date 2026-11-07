import Foundation

/// Everything `ps3 status` shows. Codable so `--json`/`--watch` and the app share one shape.
/// Deliberately leaves out PSID/IDPS, which webMAN's status page also exposes.
public struct ConsoleSnapshot: Codable, Equatable, Sendable {
    public var host: String = ""
    public var firmware: String?
    /// "CEX", "DEX", "DECR" or "PEX" (Evilnat's PEX/D-PEX), as webMAN prints it.
    public var firmwareType: String?
    public var henVersion: String?
    /// The CFW payload, e.g. "Cobra 8.4" or "Mamba 8.4". Nil on HEN, which reports henVersion instead.
    public var payload: String?
    public var webmanVersion: String?
    public var cpuTemp: Int?
    public var rsxTemp: Int?
    public var fanPercent: Int?
    public var fanTargetMax: Int?
    public var freeBytes: Int64?
    /// Size of /dev_hdd0 from PS3MAPI GETHDDINFO; nil on webMAN versions without it.
    public var totalBytes: Int64?
    public var network: String?
    public var ip: String?
    public var playTime: String?
    public var mountedGamePath: String?
    public var mountedGameName: String?
    public var runningProcess: String?
    public var health: Int = 0
    public var healthLabel: String = ""
    public var healthNotes: [String] = []

    public var isGameRunning: Bool { runningProcess != nil }

    public init() {}

    static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }

    /// `sysInfo` is PS3MAPI "PS3 GETSYSINFO", e.g.
    /// "CPU: 60°C RSX: 67°C FAN: 31% Play: 00:28:50 MAX: 68°C Firmware : 4.93 CEX PS3HEN 3.5.0 IP: 10.0.1.35 WLAN System storage: 355.8 GB free ..."
    /// On CFW the firmware part reads "4.92 CEX Cobra 8.4" or "4.92 DEX Mamba 8.4" (webMAN's
    /// get_cobra_version in include/cpursx.h).
    /// `statusPage` is the HTML of /cpursx.ps3 (webMAN version and mounted game).
    public static func parse(sysInfo: String, statusPage: String) -> ConsoleSnapshot {
        var s = ConsoleSnapshot()
        s.cpuTemp = firstMatch(#"CPU:\s*(\d+)\s*°C"#, in: sysInfo).flatMap { Int($0[1]) }
        s.rsxTemp = firstMatch(#"RSX:\s*(\d+)\s*°C"#, in: sysInfo).flatMap { Int($0[1]) }
        s.fanPercent = firstMatch(#"FAN:\s*(\d+)\s*%"#, in: sysInfo).flatMap { Int($0[1]) }
        s.fanTargetMax = firstMatch(#"MAX:\s*(\d+)\s*°C"#, in: sysInfo).flatMap { Int($0[1]) }
        s.playTime = firstMatch(#"Play:\s*([\d:]+)"#, in: sysInfo)?[1]
        if let fw = firstMatch(#"Firmware\s*:\s*([\d.]+)\s+([\w-]+)"#, in: sysInfo) {
            s.firmware = fw[1]
            s.firmwareType = fw[2]
        }
        s.henVersion = firstMatch(#"PS3HEN\s+([\d.]+)"#, in: sysInfo)?[1]
        s.payload = firstMatch(#"\b(Cobra|Mamba|qCFW)\s+([\d.]+)"#, in: sysInfo).map { "\($0[1]) \($0[2])" }
        if let ip = firstMatch(#"IP:\s*([\d.]+)\s+(\w+)"#, in: sysInfo) {
            s.ip = ip[1]
            s.network = ip[2] == "WLAN" ? "Wi-Fi" : ip[2]
        }
        if let free = firstMatch(#"storage:\s*([\d.]+)\s*(KB|MB|GB|TB)\s*free"#, in: sysInfo),
           let value = Double(free[1]) {
            let scale: Double = ["KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12][free[2]] ?? 1
            s.freeBytes = Int64(value * scale)
        }

        s.webmanVersion = firstMatch(#"webMAN (\d+\.\d+\.\d+[a-z]?)"#, in: statusPage)?[1]
        if let mount = firstMatch(#"/dev_bdvd</a>\s*-&gt;|/dev_bdvd</a>\s*->"#, in: statusPage),
           let start = statusPage.range(of: mount[0]),
           let link = firstMatch(#"<a href="/mount\.ps3(/[^"]+)">([^<]+)</a>"#, in: String(statusPage[start.upperBound...])) {
            s.mountedGamePath = link[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? link[1]
            s.mountedGameName = GameName.clean(link[2])
        }
        // Fall back to the HTML if PS3MAPI did not answer some fields.
        if s.henVersion == nil { s.henVersion = firstMatch(#"PS3HEN\s+([\d.]+)"#, in: statusPage)?[1] }
        if s.firmware == nil, let fw = firstMatch(#"Firmware:\s*([\d.]+)\s+([\w-]+)"#, in: statusPage) {
            s.firmware = fw[1]
            s.firmwareType = fw[2]
        }
        return s
    }

    /// 0–100 score in the spirit of Mole's health card.
    public mutating func computeHealth() {
        var score = 100
        var notes: [String] = []
        if let cpu = cpuTemp, cpu > 70 {
            score -= min(30, (cpu - 70) * 2)
            notes.append("CPU hot (\(cpu) °C)")
        }
        if let rsx = rsxTemp, rsx > 75 {
            score -= min(30, (rsx - 75) * 2)
            notes.append("RSX hot (\(rsx) °C)")
        }
        if let free = freeBytes {
            if free < 20_000_000_000 {
                score -= 40
                notes.append("hard drive almost full")
            } else if free < 50_000_000_000 {
                score -= 15
                notes.append("low on free space")
            }
        }
        health = max(0, score)
        switch health {
        case 85...: healthLabel = "Excellent"
        case 65..<85: healthLabel = "Good"
        case 45..<65: healthLabel = "OK"
        default: healthLabel = "Warning"
        }
        healthNotes = notes
    }
}

public enum GameName {
    /// "Test Drive Unlimited 2 (Europe) (En,Fr,De,Es,It).dec.iso" -> "Test Drive Unlimited 2",
    /// "Shadow of the Colossus [SCES-53326].iso" -> "Shadow of the Colossus",
    /// "BLUS30443-[Demon's Souls]" (multiMAN's folder names) -> "Demon's Souls"
    public static func clean(_ fileName: String) -> String {
        var name = (fileName as NSString).lastPathComponent
        for ext in [".dec.iso", ".iso.0", ".bin.enc", ".iso", ".pkg", ".bin", ".cue", ".cso", ".img", ".mdf"]
            where name.lowercased().hasSuffix(ext) {
            name.removeLast(ext.count)
            break
        }
        if let folder = ConsoleSnapshot.firstMatch(#"^[A-Z]{4}\d{5}-\[(.+)\]$"#, in: name) { return folder[1] }
        if name.hasPrefix("["), let close = name.range(of: "] ") { name = String(name[close.upperBound...]) }
        if let tag = name.range(of: #" [(\[]"#, options: .regularExpression) { name = String(name[..<tag.lowerBound]) }
        return name.trimmingCharacters(in: .whitespaces)
    }
}
