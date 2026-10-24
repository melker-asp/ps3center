import Foundation

/// What the console runs, read from webMAN's firmware line: "4.93 CEX PS3HEN 3.5.0" on HEN,
/// "4.92 CEX Cobra 8.4" or "4.92 DEX Mamba 8.4" on CFW.
public struct ConsoleProfile: Codable, Equatable, Sendable {
    public enum Exploit: String, Codable, Sendable, CaseIterable {
        case hen, cfw

        public var label: String { self == .hen ? "HEN" : "CFW" }
    }

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case cex, dex

        public var label: String { rawValue.uppercased() }
    }

    public var firmware: String?
    public var kind: Kind?
    public var exploit: Exploit?
    /// "PS3HEN 3.5.0", "Cobra 8.4"
    public var payload: String?

    public init(firmware: String? = nil, kind: Kind? = nil, exploit: Exploit? = nil, payload: String? = nil) {
        self.firmware = firmware
        self.kind = kind
        self.exploit = exploit
        self.payload = payload
    }

    /// webMAN only runs on HEN or CFW, so a readable firmware line without PS3HEN means CFW.
    public init(snapshot s: ConsoleSnapshot) {
        firmware = s.firmware
        kind = Self.kind(fromFirmwareType: s.firmwareType)
        if let hen = s.henVersion {
            exploit = .hen
            payload = "PS3HEN \(hen)"
        } else if s.firmware != nil {
            exploit = .cfw
            payload = s.payload
        }
    }

    /// webMAN replaces the first letter with P on Evilnat's PEX and D-PEX, so "PEX" can be either kind.
    static func kind(fromFirmwareType type: String?) -> Kind? {
        switch type?.uppercased() {
        case "CEX", "D-CEX": return .cex
        case "DEX", "DECR": return .dex
        default: return nil
        }
    }

    /// "4.93 CEX · PS3HEN 3.5.0"
    public var label: String {
        let firmwarePart = [firmware, kind?.label].compactMap { $0 }.joined(separator: " ")
        let exploitPart = payload ?? exploit?.label
        let parts = [firmwarePart.isEmpty ? nil : firmwarePart, exploitPart].compactMap { $0 }
        return parts.isEmpty ? "okänd firmware" : parts.joined(separator: " · ")
    }
}

/// What a catalog entry needs from the console. Empty sets mean "any".
public struct Requirements: Sendable {
    public var exploits: Set<ConsoleProfile.Exploit>
    public var kinds: Set<ConsoleProfile.Kind>
    public var minFirmware: String?
    public var maxFirmware: String?
    /// Expected to run, but the author has not tested it there: warn, never block.
    public var untestedOn: Set<ConsoleProfile.Exploit>
    /// Shown with a block or warning, e.g. what the README says.
    public var note: String?

    public init(exploits: Set<ConsoleProfile.Exploit> = [], kinds: Set<ConsoleProfile.Kind> = [],
                minFirmware: String? = nil, maxFirmware: String? = nil,
                untestedOn: Set<ConsoleProfile.Exploit> = [], note: String? = nil) {
        self.exploits = exploits
        self.kinds = kinds
        self.minFirmware = minFirmware
        self.maxFirmware = maxFirmware
        self.untestedOn = untestedOn
        self.note = note
    }

    public static let any = Requirements()
    public static let cfwOnly = Requirements(exploits: [.cfw])
    public static let dexOnly = Requirements(kinds: [.dex])

    public var isUnrestricted: Bool {
        exploits.isEmpty && kinds.isEmpty && minFirmware == nil && maxFirmware == nil && untestedOn.isEmpty
    }

    /// "Kräver HEN · firmware 4.80 eller senare"
    public var summary: String {
        var parts: [String] = []
        if !exploits.isEmpty { parts.append("Kräver " + exploits.map(\.label).sorted().joined(separator: " eller ")) }
        if !kinds.isEmpty { parts.append("Bara " + kinds.map(\.label).sorted().joined(separator: " eller ")) }
        switch (minFirmware, maxFirmware) {
        case let (min?, max?): parts.append("firmware \(min)–\(max)")
        case let (min?, nil): parts.append("firmware \(min) eller senare")
        case let (nil, max?): parts.append("firmware till och med \(max)")
        case (nil, nil): break
        }
        if !untestedOn.isEmpty { parts.append("otestad på " + untestedOn.map(\.label).sorted().joined(separator: " och ")) }
        return parts.isEmpty ? "Inga krav på HEN, CFW eller firmware" : parts.joined(separator: " · ")
    }
}

/// The safety check run before anything is installed: does this program work on this console?
public struct Compatibility: Codable, Equatable, Sendable {
    public enum Verdict: String, Codable, Sendable {
        case compatible
        /// Runs, but untested on this kind of console.
        case untested
        case incompatible
        /// The program has requirements and the console's firmware could not be read.
        case unknown
    }

    public var verdict: Verdict
    public var reasons: [String]

    public init(verdict: Verdict, reasons: [String] = []) {
        self.verdict = verdict
        self.reasons = reasons
    }

    public static let compatible = Compatibility(verdict: .compatible)

    /// Unknown blocks too: a program with requirements is only installed when they are known to hold.
    public var blocksInstall: Bool { verdict == .incompatible || verdict == .unknown }

    public var summary: String {
        reasons.isEmpty ? "Fungerar på din PS3" : reasons.joined(separator: ". ")
    }

    /// Short text for a chip next to the name, nil when there is nothing to say.
    public var badge: String? {
        switch verdict {
        case .compatible: return nil
        case .untested: return "Otestad"
        case .incompatible: return "Fungerar inte"
        case .unknown: return "Okänd firmware"
        }
    }

    public static func check(_ r: Requirements, on p: ConsoleProfile) -> Compatibility {
        guard !r.isUnrestricted else { return .compatible }
        var blocked: [String] = []
        var unknown: [String] = []
        var warnings: [String] = []

        if !r.exploits.isEmpty {
            if let exploit = p.exploit {
                if !r.exploits.contains(exploit) {
                    blocked.append("Kräver \(list(r.exploits.map(\.label))), din PS3 kör \(exploit.label)")
                }
            } else {
                unknown.append("Kunde inte avgöra om konsolen kör HEN eller CFW")
            }
        }
        if !r.kinds.isEmpty {
            if let kind = p.kind {
                if !r.kinds.contains(kind) {
                    blocked.append("Fungerar bara på \(list(r.kinds.map(\.label))), din PS3 är \(kind.label)")
                }
            } else {
                unknown.append("Kunde inte avgöra om konsolen är CEX eller DEX")
            }
        }
        if r.minFirmware != nil || r.maxFirmware != nil {
            if let raw = p.firmware, let firmware = Version(raw, style: .dotted) {
                if let min = r.minFirmware, let minimum = Version(min, style: .dotted), firmware < minimum {
                    blocked.append("Kräver firmware \(min) eller senare, din har \(raw)")
                }
                if let max = r.maxFirmware, let maximum = Version(max, style: .dotted), maximum < firmware {
                    blocked.append("Fungerar bara till och med firmware \(max), din har \(raw)")
                }
            } else {
                unknown.append("Kunde inte läsa konsolens firmwareversion")
            }
        }
        if let exploit = p.exploit, r.untestedOn.contains(exploit) {
            warnings.append("Inte testad på \(exploit.label)")
        }

        let note = r.note.map { [$0] } ?? []
        if !blocked.isEmpty { return Compatibility(verdict: .incompatible, reasons: blocked + note) }
        if !unknown.isEmpty { return Compatibility(verdict: .unknown, reasons: unknown + note) }
        if !warnings.isEmpty { return Compatibility(verdict: .untested, reasons: warnings + note) }
        return .compatible
    }

    /// Throws when the install must not go ahead.
    public func enforce(_ name: String) throws {
        guard blocksInstall else { return }
        throw PS3Error.incompatible("\(name) installeras inte: \(summary).")
    }

    /// Stable order regardless of Set iteration: "HEN eller CFW".
    private static func list(_ labels: [String]) -> String {
        labels.sorted().joined(separator: " eller ")
    }
}
