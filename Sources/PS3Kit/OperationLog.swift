import Foundation

/// Append-only log of everything that changed the console, like Mole's operations.log.
/// Read back with `ps3 history`. Disable with PS3_NO_OPLOG=1.
public enum OperationLog {
    public static var file: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ps3center/operations.log")
    }

    public static func record(_ action: String, _ detail: String) {
        guard ProcessInfo.processInfo.environment["PS3_NO_OPLOG"] != "1" else { return }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        let stamp = formatter.string(from: Date())
        let line = "\(stamp)\t\(action)\t\(detail)\n"
        let fm = FileManager.default
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: file)
        }
    }

    public struct Entry: Codable, Sendable {
        public let date: String
        public let action: String
        public let detail: String
    }

    public static func read(limit: Int) -> [Entry] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").suffix(limit).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 2).map(String.init)
            guard parts.count == 3 else { return nil }
            return Entry(date: parts[0], action: parts[1], detail: parts[2])
        }
    }
}
