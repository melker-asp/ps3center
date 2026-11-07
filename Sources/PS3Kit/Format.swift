import Foundation

public enum Format {
    /// Decimal units (1 KB = 1000 bytes) with the decimals Finder shows: none for KB, one for
    /// MB, up to two for GB and TB; trailing zeros are dropped and halves round up. Always
    /// English, whatever the Mac's language: "355.8 GB", "13.48 GB", "529.2 MB", "0 KB".
    private static let byteUnits: [(name: String, step: UInt64, decimals: Int)] = [
        ("KB", 1_000, 0),
        ("MB", 100_000, 1),
        ("GB", 10_000_000, 2),
        ("TB", 10_000_000_000, 2),
    ]

    public static func bytes(_ count: Int64) -> String {
        let magnitude = count.magnitude
        for (index, unit) in byteUnits.enumerated() {
            // The size in steps of the last decimal shown, rounded half up.
            let scaled = magnitude / unit.step + (magnitude % unit.step >= unit.step / 2 ? 1 : 0)
            let divisor: UInt64 = unit.decimals == 0 ? 1 : (unit.decimals == 1 ? 10 : 100)
            let whole = scaled / divisor
            if whole >= 1000, index < byteUnits.count - 1 { continue }
            var fraction = ""
            if unit.decimals > 0 {
                let digits = String(scaled % divisor)
                fraction = String(repeating: "0", count: unit.decimals - digits.count) + digits
                while fraction.hasSuffix("0") { fraction.removeLast() }
            }
            let sign = count < 0 && scaled > 0 ? "-" : ""
            return sign + grouped(whole) + (fraction.isEmpty ? "" : "." + fraction) + " " + unit.name
        }
        return "0 KB"
    }

    /// "1,234": a comma between thousands.
    private static func grouped(_ value: UInt64) -> String {
        var digits = String(value)
        var groups: [String] = []
        while digits.count > 3 {
            groups.insert(String(digits.suffix(3)), at: 0)
            digits.removeLast(3)
        }
        groups.insert(digits, at: 0)
        return groups.joined(separator: ",")
    }

    public static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return "–" }
        return bytes(Int64(bytesPerSecond)) + "/s"
    }

    public static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "–" }
        let s = Int(seconds.rounded())
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Time still to go, in words and rounded to the minute: "under a minute", "4 min",
    /// "51 min", "1 h 48 min". Estimates use this, so "about 51:17" never reads like a clock
    /// next to "4–17 min"; a running clock or elapsed time keeps `duration`.
    public static func estimate(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "–" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    /// Play time in words: "14 h 20 min", "35 min", "under a minute".
    public static func playTime(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    /// The one language dates and numbers are written in, whatever the Mac's language. The
    /// app's `Theme.locale` is this one too.
    public static let locale = Locale(identifier: "en_US")

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// "Oct 12, 2026", in English whatever the Mac's language.
    public static func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    /// "18:12": the time of day, 24-hour.
    public static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
}

extension Optional {
    /// `map` for async transforms.
    func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let value = self else { return nil }
        return try await transform(value)
    }
}
