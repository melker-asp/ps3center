import Foundation

/// What changed the console: the action column of operations.log. The raw values are the log's
/// own words, which `ps3 history` and scripts read, so they never change. A new kind goes here
/// first; the app's history table then has to say how it looks (its switch is exhaustive).
public enum OperationKind: String, CaseIterable, Sendable {
    case install
    case installTheme = "install-theme"
    case send
    case update
    case uninstall
    case delete
    case deleteSave = "delete-save"
    case restore
    case play
    case mount
    case unmount
    case exit
    case refresh
    case reloadXMB = "reload-xmb"
    case eject
    case insert
    case restart
    case shutdown
    case record
    case gameMusic = "game-music"
    case screenshots
    case updateBlock = "update-block"
    case fan
    case covers
    case libcrypt
    case rip
    case ripAbort = "rip-abort"
    case webmanSetup = "webman-setup"
}

/// Append-only log of everything that changed the console, like Mole's operations.log.
/// Read back with `ps3 history`. Disable with PS3_NO_OPLOG=1.
public enum OperationLog {
    public static var file: URL { StatePaths.logs.appendingPathComponent("operations.log") }

    /// Appends one line: date, kind and detail, separated by tabs. Opened with O_APPEND, so lines
    /// from the app and `ps3` at the same moment never overwrite each other. A tab or line break
    /// in `detail` (a file name can have one) becomes a space, so every entry stays one line.
    public static func record(_ kind: OperationKind, _ detail: String) {
        guard ProcessInfo.processInfo.environment["PS3_NO_OPLOG"] != "1" else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = Data(self.line(kind, detail, at: Date()).utf8)
        let fd = open(file.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        defer { close(fd) }
        _ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }

    static func line(_ kind: OperationKind, _ detail: String, at date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        let flat = detail.components(separatedBy: CharacterSet(charactersIn: "\t\r\n")).joined(separator: " ")
        return "\(formatter.string(from: date))\t\(kind.rawValue)\t\(flat)\n"
    }

    public struct Entry: Codable, Sendable {
        public let date: String
        public let action: String
        public let detail: String

        package init(date: String, action: String, detail: String) {
            self.date = date
            self.action = action
            self.detail = detail
        }

        /// Nil for an action this version does not know (from a newer `ps3`).
        public var kind: OperationKind? { OperationKind(rawValue: action) }

        /// For the kinds that turn something on or off (record, game-music, update-block): which
        /// it was. "på"/"av" are how lines written before the English interface say it.
        public var switchedOn: Bool? {
            switch detail {
            case "on", "start", "på": return true
            case "off", "stop", "av": return false
            default: return nil
            }
        }
    }

    public static func read(limit: Int) -> [Entry] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return entries(in: text, limit: limit)
    }

    static func entries(in text: String, limit: Int) -> [Entry] {
        text.split(separator: "\n").suffix(limit).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 2).map(String.init)
            guard parts.count == 3 else { return nil }
            return Entry(date: parts[0], action: parts[1], detail: parts[2])
        }
    }
}
