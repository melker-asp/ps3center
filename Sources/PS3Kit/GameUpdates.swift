import CryptoKit
import Foundation
import Security

/// One official update package for a game, from Sony's update list
/// (https://a0.ww.np.dl.playstation.net/tpl/np/<ID>/<ID>-ver.xml), the same list RPCS3 reads.
public struct GamePatch: Codable, Equatable, Sendable {
    public let titleID: String
    public let version: String
    public let size: Int64
    public let sha1: String
    /// The lowest system software the patch needs, e.g. "3.55" (ps3_system_ver "03.5500").
    public let systemVersion: String?
    public let url: URL

    public var fileName: String { url.lastPathComponent }
}

/// Official game updates (patches) from Sony's update server. Only game packages: never system
/// software, and nothing logs in to PSN. The packages are downloaded on the Mac, checked
/// against the SHA-1 in the list and installed like any other package, so the console itself
/// never talks to Sony. A patch that needs newer system software than the console has is
/// refused, as the safety check refuses apps.
public struct GameUpdateService: Sendable {
    public let host: String

    public init(host: String) { self.host = host }

    static func listURL(for titleID: String) -> URL? {
        URL(string: "https://a0.ww.np.dl.playstation.net/tpl/np/\(titleID)/\(titleID)-ver.xml")
    }

    /// The version a game has now: its installed update, else the disc's own APP_VER.
    public static func currentVersion(of game: Game) -> String? {
        game.updateVersion ?? game.version
    }

    /// Whether Sony publishes updates for this kind of game at all.
    public static func canHaveUpdates(_ game: Game) -> Bool {
        (game.platform == .ps3 || game.platform == .psn) && game.titleID.map(TitleID.isOfficial) == true
    }

    // MARK: Check

    /// Every patch Sony lists for `titleID`, oldest first. An empty list when there are none.
    public static func patches(for titleID: String) async throws -> [GamePatch] {
        guard let url = listURL(for: titleID) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await SonyTrust.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // Titles without updates answer 404 or an empty body.
        guard status == 200, !data.isEmpty else { return [] }
        return parse(data)
    }

    /// Patches newer than what each game has, by game id. Results are cached for a day.
    public func check(_ games: [Game], refresh: Bool = false) async -> [String: [GamePatch]] {
        var cache = refresh ? [:] : UpdateCache.load()
        var result: [String: [GamePatch]] = [:]
        for game in games where Self.canHaveUpdates(game) {
            guard let titleID = game.titleID else { continue }
            var patches = cache[titleID].flatMap { $0.isFresh ? $0.patches : nil }
            if patches == nil, let fetched = try? await Self.patches(for: titleID) {
                patches = fetched
                cache[titleID] = UpdateCache.Entry(checkedAt: Date(), patches: fetched)
            }
            let newer = Self.newer(patches ?? [], than: Self.currentVersion(of: game))
            if !newer.isEmpty { result[game.id] = newer }
        }
        UpdateCache.save(cache)
        return result
    }

    /// Patches newer than `installed`, oldest first: PS3 patches are installed one after another.
    static func newer(_ patches: [GamePatch], than installed: String?) -> [GamePatch] {
        let current = installed.flatMap { Version($0, style: .appVer) }
        let versioned = patches.compactMap { patch in Version(patch.version, style: .appVer).map { (patch: patch, version: $0) } }
        return versioned
            .filter { item in current.map { $0 < item.version } ?? true }
            .sorted { $0.version < $1.version }
            .map { $0.patch }
    }

    /// Sony's list: <titlepatch><tag><package version="01.03" size="…" sha1sum="…" url="…"
    /// ps3_system_ver="03.5500"/>…</tag></titlepatch>.
    static func parse(_ data: Data) -> [GamePatch] {
        let reader = PatchListReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        return reader.patches
    }

    /// "03.5500" -> "3.55"
    static func firmware(fromSystemVersion raw: String?) -> String? {
        guard let raw, let value = Double(raw), value > 0 else { return nil }
        return String(format: "%.2f", value)
    }

    // MARK: Install

    /// Downloads, checks and installs `patches` in order. Refuses before downloading anything when
    /// one needs newer system software than the console has (or the firmware cannot be read).
    public func install(_ patches: [GamePatch], for game: Game, options: TransferOptions, events: TransferHandler) async throws {
        guard !patches.isEmpty else { return }
        let snapshot = try await WebMAN(host: host).snapshot()
        let needed = patches.compactMap { Self.firmware(fromSystemVersion: $0.systemVersion) }
            .compactMap { Version($0, style: .dotted) }.max()
        if let needed {
            guard let firmware = snapshot.firmware, let console = Version(firmware, style: .dotted) else {
                throw PS3Error.incompatible("The console's system software version cannot be read, so the update for \(game.title) will not be installed.")
            }
            if console < needed {
                throw PS3Error.incompatible("The update for \(game.title) requires system software \(needed.raw); the console has \(firmware). It will not be installed.")
            }
        }
        let folder = GameLibraryService.cacheDirectory("updates")
        for patch in patches {
            let file = folder.appendingPathComponent(patch.fileName)
            let route = Route(local: file, remote: patch.url.absoluteString, kind: .package, size: patch.size, title: game.title)
            if options.dryRun {
                events(.note("Would download and install \(game.title) \(patch.version) (\(Format.bytes(patch.size)))"))
                continue
            }
            if FileRouter.fileSize(file) != patch.size || !Self.matches(file, sha1: patch.sha1) {
                try await Self.download(patch, to: file, route: route, events: events)
                guard Self.matches(file, sha1: patch.sha1) else {
                    try? FileManager.default.removeItem(at: file)
                    throw PS3Error.invalidFile("\(patch.fileName) does not match Sony's checksum. Nothing was installed.")
                }
            }
            try await TransferService(host: host).installPackage(file, options: options, events: events)
            OperationLog.record("update", "\(game.title) \(patch.version) (\(patch.titleID))")
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func download(_ patch: GamePatch, to file: URL, route: Route, events: TransferHandler) async throws {
        events(.started(route, resumingFrom: 0))
        let start = Date()
        let download = PatchDownload()
        async let downloaded = download.run(patch.url)
        // Progress is polled, so `events` never has to outlive this call.
        while !download.state.done {
            try await Task.sleep(nanoseconds: 250_000_000)
            let state = download.state
            let elapsed = max(Date().timeIntervalSince(start), 0.001)
            events(.progress(route, sent: state.written, total: state.expected > 0 ? state.expected : patch.size,
                             bytesPerSecond: Double(state.written) / elapsed))
        }
        let temp = try await downloaded
        let fm = FileManager.default
        if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
        try fm.moveItem(at: temp, to: file)
        events(.finished(route, seconds: Date().timeIntervalSince(start)))
    }

    /// Sony's SHA-1 covers the package; some lists give it without the 32-byte digest at the
    /// end of the file, so both are accepted.
    static func matches(_ file: URL, sha1 expected: String) -> Bool {
        guard !expected.isEmpty, let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        let size = FileRouter.fileSize(file)
        guard size > 32 else { return false }
        var body = Insecure.SHA1()
        var remaining = size - 32
        while remaining > 0 {
            guard let chunk = try? handle.read(upToCount: Int(min(remaining, 4 << 20))), !chunk.isEmpty else { return false }
            body.update(data: chunk)
            remaining -= Int64(chunk.count)
        }
        var whole = body
        whole.update(data: (try? handle.readToEnd()) ?? Data())
        func hex(_ digest: Insecure.SHA1.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }
        let want = expected.lowercased()
        return hex(whole.finalize()) == want || hex(body.finalize()) == want
    }
}

final class PatchListReader: NSObject, XMLParserDelegate {
    private(set) var patches: [GamePatch] = []
    private var titleID = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "titlepatch":
            titleID = attributes["titleid"] ?? ""
        case "package":
            guard let version = attributes["version"], let link = attributes["url"], let url = URL(string: link) else { return }
            patches.append(GamePatch(titleID: titleID, version: version, size: Int64(attributes["size"] ?? "") ?? 0,
                                     sha1: attributes["sha1sum"] ?? "",
                                     systemVersion: GameUpdateService.firmware(fromSystemVersion: attributes["ps3_system_ver"]),
                                     url: url))
        default:
            break
        }
    }
}

/// Patch checks per title ID in ~/Library/Caches/ps3center/updates.json, fresh for a day.
enum UpdateCache {
    struct Entry: Codable {
        let checkedAt: Date
        let patches: [GamePatch]

        var isFresh: Bool { Date().timeIntervalSince(checkedAt) < 24 * 3600 }
    }

    static var file: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/ps3center/updates.json")
    }

    static func load() -> [String: Entry] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: Entry].self, from: data)) ?? [:]
    }

    static func save(_ cache: [String: Entry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(cache).write(to: file, options: .atomic)
    }
}

/// Sony's update servers (a0 and b0.ww.np.dl.playstation.net) present certificates from Sony's
/// own CA ("SCEI"), which macOS does not trust. For those hosts only, a chain that the system
/// rejects is accepted when it comes from Sony's CA, and that CA's fingerprint is remembered on
/// first use (~/.config/ps3center/sony-ca.sha256): a different one later is refused.
/// Every package is also checked against the SHA-1 in the update list.
final class SonyTrust: NSObject, URLSessionDelegate, @unchecked Sendable {
    static let session = URLSession(configuration: .ephemeral, delegate: SonyTrust(), delegateQueue: nil)

    static var pinFile: URL { ConfigStore.directory.appendingPathComponent("sony-ca.sha256") }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              space.host.hasSuffix(".np.dl.playstation.net"), let trust = space.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if SecTrustEvaluateWithError(trust, nil) {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let authority = chain.dropFirst().last(where: Self.isSony) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let fingerprint = SHA256.hash(data: SecCertificateCopyData(authority) as Data).map { String(format: "%02x", $0) }.joined()
        if let pinned = try? String(contentsOf: Self.pinFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !pinned.isEmpty {
            completionHandler(pinned == fingerprint ? .useCredential : .cancelAuthenticationChallenge,
                              pinned == fingerprint ? URLCredential(trust: trust) : nil)
            return
        }
        try? FileManager.default.createDirectory(at: ConfigStore.directory, withIntermediateDirectories: true)
        try? fingerprint.write(to: Self.pinFile, atomically: true, encoding: .utf8)
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    static func isSony(_ certificate: SecCertificate) -> Bool {
        let subject = (SecCertificateCopySubjectSummary(certificate) as String?) ?? ""
        return subject.contains("SCEI") || subject.contains("Sony")
    }
}

/// A download whose progress can be read while it runs, trusting Sony's servers like `SonyTrust`.
final class PatchDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var written: Int64 = 0
    private var expected: Int64 = 0
    private var done = false

    /// Bytes so far, bytes expected (0 when unknown) and whether the download has ended.
    var state: (written: Int64, expected: Int64, done: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (written, expected, done)
    }

    /// Downloads `url` to a temporary file and returns it.
    func run(_ url: URL) async throws -> URL {
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            session.downloadTask(with: url).resume()
        }
    }

    private func resume(_ result: Result<URL, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        done = true
        lock.unlock()
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        SonyTrust().urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        lock.lock()
        written = totalBytesWritten
        expected = max(totalBytesExpectedToWrite, 0)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The file at `location` is removed when this returns, so it is moved first.
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            resume(.failure(PS3Error.http(status: status, command: downloadTask.originalRequest?.url?.lastPathComponent ?? "")))
            return
        }
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("ps3center-\(UUID().uuidString).pkg")
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            resume(.success(kept))
        } catch {
            resume(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { resume(.failure(error)) }
    }
}
