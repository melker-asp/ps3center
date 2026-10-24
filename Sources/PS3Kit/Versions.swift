import Foundation

/// Projects number versions differently from the APP_VER ("02.40") stored on the console,
/// so each catalog entry says how to read its release tags.
public enum VersionStyle: String, Codable, Sendable {
    /// "02.40" as stored in PARAM.SFO.
    case appVer
    /// Tags like "v2.4.0", whose PARAM.SFO says "02.40" (minor and patch fused).
    case semverAsAppVer
    /// Artemis: tag "r6.4" ships as APP_VER "00.64".
    case artemis
    /// Plain dotted numbers, letters ignored: "1.47.50c", "3.5.0", "1.15".
    case dotted
}

public struct Version: Comparable, CustomStringConvertible, Sendable, Codable {
    public let parts: [Int]
    public let raw: String

    public var description: String { raw }

    public init?(_ raw: String, style: VersionStyle) {
        let numbers = raw.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard !numbers.isEmpty else { return nil }
        self.raw = raw
        switch style {
        case .appVer, .dotted:
            parts = numbers
        case .semverAsAppVer:
            if numbers.count >= 3, numbers[1] < 10, numbers[2] < 10 {
                parts = [numbers[0], numbers[1] * 10 + numbers[2]]
            } else if numbers.count == 2, numbers[1] < 10 {
                parts = [numbers[0], numbers[1] * 10]
            } else {
                parts = numbers
            }
        case .artemis:
            parts = numbers.count == 2 && numbers[1] < 10 ? [0, numbers[0] * 10 + numbers[1]] : numbers
        }
    }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for i in 0..<count {
            let a = i < lhs.parts.count ? lhs.parts[i] : 0
            let b = i < rhs.parts.count ? rhs.parts[i] : 0
            if a != b { return a < b }
        }
        return false
    }

    public static func == (lhs: Version, rhs: Version) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}
