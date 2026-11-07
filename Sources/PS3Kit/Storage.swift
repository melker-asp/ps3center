import Foundation

/// Where PS3 Center keeps its files on the Mac. The app, `ps3` and `ps3 mcp` share all of them,
/// so every path is built from these four folders and nowhere else.
public enum StatePaths {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Settings and small records: ~/.config/ps3center (config.json, installed.json, speed.json …).
    public static var config: URL { home.appendingPathComponent(".config/ps3center", isDirectory: true) }

    /// State that is not settings: ~/Library/Application Support/ps3center (the queue, watched
    /// folders, play time, backups).
    public static var support: URL {
        home.appendingPathComponent("Library/Application Support/ps3center", isDirectory: true)
    }

    /// What can be fetched or worked out again: ~/Library/Caches/ps3center.
    public static var caches: URL { home.appendingPathComponent("Library/Caches/ps3center", isDirectory: true) }

    /// ~/Library/Logs/ps3center (operations.log).
    public static var logs: URL { home.appendingPathComponent("Library/Logs/ps3center", isDirectory: true) }
}

/// A JSON file that several processes change: the app, `ps3` and `ps3 mcp`.
///
/// `edit` is the only way to change one. It takes an flock on `<file>.lock`, reads the file again,
/// applies the change and writes it atomically, so what another process saved in between is kept
/// instead of being overwritten by a stale copy. A failed write throws; nothing is swallowed.
///
/// A file that exists but cannot be decoded (a hand edit gone wrong) is never overwritten:
/// `edit` first moves it aside to `<name>.unreadable-<date>`, then starts from `empty`.
public struct JSONFile<Value: Codable & Sendable>: Sendable {
    public let url: URL
    let empty: Value

    public init(_ url: URL, empty: Value) {
        self.url = url
        self.empty = empty
    }

    /// The contents, or `empty` when the file is missing or cannot be read. For reading only:
    /// never save what this returns, change it with `edit`.
    public func load() -> Value {
        (try? read()) ?? empty
    }

    /// Reads the file again under the lock, applies `change` and writes the result. If `change`
    /// throws, nothing is written.
    @discardableResult
    public func edit<T>(_ change: (inout Value) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path + ".lock", O_CREAT | O_RDWR, 0o644)
        if fd >= 0 { flock(fd, LOCK_EX) }
        defer {
            if fd >= 0 {
                flock(fd, LOCK_UN)
                close(fd)
            }
        }
        var value: Value
        do {
            value = try read() ?? empty
        } catch {
            try moveAside()
            value = empty
        }
        let result = try change(&value)
        try Self.encoder.encode(value).write(to: url, options: .atomic)
        return result
    }

    /// Nil when there is no file; throws when there is one that cannot be decoded.
    func read() throws -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try Self.decoder.decode(Value.self, from: data)
    }

    /// Keeps an unreadable file for the user to look at, so a reset never loses it.
    func moveAside() throws {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let kept = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).unreadable-\(stamp)")
        try FileManager.default.moveItem(at: url, to: kept)
        FileHandle.standardError.write(Data("ps3center: \(url.path) could not be read and was moved to \(kept.lastPathComponent)\n".utf8))
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
