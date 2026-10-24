import Foundation

public enum Format {
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        f.allowsNonnumericFormatting = false  // "0 KB", not "Zero KB"
        return f
    }()

    public static func bytes(_ count: Int64) -> String {
        byteFormatter.string(fromByteCount: count)
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

    /// Play time in words: "14 h 20 min", "35 min", "under en minut".
    public static func playTime(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "under en minut" }
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    /// "12 okt. 2026"
    public static func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }
}

extension Optional {
    /// `map` for async transforms.
    func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let value = self else { return nil }
        return try await transform(value)
    }
}
