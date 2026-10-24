import CryptoKit
import Foundation

/// Progress events for uploads and installs. The CLI prints them; the app will bind to them.
public enum TransferEvent: Sendable {
    case checking(String)
    case skipped(Route, reason: String)
    case started(Route, resumingFrom: Int64)
    case progress(Route, sent: Int64, total: Int64, bytesPerSecond: Double)
    case finished(Route, seconds: Double)
    case waitingForGame(String)
    case installing(String)
    case installed(String)
    case refreshed
    case note(String)
}

public typealias TransferHandler = @Sendable (TransferEvent) -> Void

public struct TransferOptions: Sendable {
    /// Run console-affecting steps even while a game is running.
    public var force = false
    public var refresh = true
    public var popup = true
    public var dryRun = false
    /// Compare the console's MD5 of each large file with the Mac's after sending.
    public var verify = false
    public init() {}
}

/// Keeps the Mac from idle sleep while transfers run, like `caffeinate -i`; the display may
/// still sleep. A Mac on battery with its lid closed sleeps anyway.
public final class KeepAwake: @unchecked Sendable {
    private let activity: NSObjectProtocol

    public init(reason: String) {
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: reason)
    }

    deinit { ProcessInfo.processInfo.endActivity(activity) }
}

/// Uploads files over FTP and runs the follow-up web commands.
public struct TransferService: Sendable {
    public let host: String
    public var webman: WebMAN { WebMAN(host: host) }

    public init(host: String) { self.host = host }

    // MARK: Send

    /// Uploads `routes`; afterwards refreshes the game list and shows a popup on the TV.
    /// Already complete files are skipped, partial ones are resumed. Files go to <name>.part and
    /// are renamed when complete, so webMAN never lists half a game.
    public func send(_ routes: [Route], options: TransferOptions, events: TransferHandler) async throws {
        let sent = try await withFTP { ftp in try await upload(routes, ftp: ftp, options: options, events: events) }
        guard !options.dryRun, !sent.isEmpty else { return }
        // The FTP session is closed first: webMAN drops one that stays idle for a minute, and
        // both the MD5 check and waiting for a game can take longer.
        if options.verify { try await verify(sent, events: events) }
        guard options.refresh, sent.contains(where: \.refreshesGameList) else { return }
        try await waitUntilIdle(force: options.force, events: events)
        try await webman.refreshGames()
        events(.refreshed)
        if options.popup {
            let titles = Array(Set(sent.filter(\.refreshesGameList).map { $0.title ?? GameName.clean($0.local.lastPathComponent) })).sorted()
            let message = titles.count == 1 ? "\(titles[0]) finns nu under Spel" : "\(titles.count) nya spel finns under Spel"
            try? await webman.popup(message)
        }
    }

    struct PendingUpload {
        let route: Route
        /// The .part file, or the real name for an upload interrupted before .part files.
        let path: String
        let offset: Int64
    }

    /// Uploads what is missing of `routes` and returns the routes that were sent.
    private func upload(_ routes: [Route], ftp: FTPClient, options: TransferOptions, events: TransferHandler) async throws -> [Route] {
        var pending: [PendingUpload] = []
        routeLoop: for route in routes {
            events(.checking(route.remote))
            // A game may already be on the console at another depth (flat in PS3ISO/ vs one
            // folder per game, as in the local mirror).
            for alternative in Self.alternativeLocations(for: route) where try await ftp.size(alternative) == route.size {
                events(.skipped(route, reason: "finns redan på PS3:an (\(alternative))"))
                continue routeLoop
            }
            switch try await remoteState(of: route, ftp: ftp) {
            case .complete:
                events(.skipped(route, reason: "finns redan på PS3:an"))
            case .larger:
                events(.skipped(route, reason: "en större fil med samma namn finns redan på PS3:an"))
            case .resume(let path, let offset):
                pending.append(PendingUpload(route: route, path: path, offset: offset))
            }
        }

        let needed = pending.reduce(Int64(0)) { $0 + $1.route.size - $1.offset }
        if needed > 0, !options.force, let free = try? await webman.snapshot().freeBytes, needed + 1_000_000_000 > free {
            throw PS3Error.notEnoughSpace(needed: needed, free: free)
        }
        if options.dryRun {
            for item in pending { events(.started(item.route, resumingFrom: item.offset)) }
            return []
        }
        for item in pending {
            try await upload(item.route, to: item.path, offset: item.offset, ftp: ftp, events: events)
            OperationLog.record("send", "\(item.route.remote) (\(Format.bytes(item.route.size)))")
        }
        return pending.map(\.route)
    }

    /// Where an upload stands on the console.
    enum RemoteState: Equatable {
        case complete
        /// A bigger file has the name: not ours to overwrite.
        case larger
        /// Continue in `path` at `offset` (0 starts over).
        case resume(path: String, offset: Int64)
    }

    static func partPath(_ remote: String) -> String { remote + ".part" }

    func remoteState(of route: Route, ftp: FTPClient) async throws -> RemoteState {
        if let size = try await ftp.size(route.remote) {
            if size == route.size { return .complete }
            if size > route.size { return .larger }
            return .resume(path: route.remote, offset: size)  // interrupted before .part files existed
        }
        let part = Self.partPath(route.remote)
        if let size = try await ftp.size(part), size <= route.size { return .resume(path: part, offset: size) }
        return .resume(path: part, offset: 0)
    }

    /// Other places webMAN would find the same game: flat in its folder, or in a folder named after it.
    static func alternativeLocations(for route: Route) -> [String] {
        guard route.kind.needsRefresh, route.kind != .ps3Folder, let folder = route.kind.remoteFolder else { return [] }
        let file = route.local.lastPathComponent
        let named = folder + "/" + route.local.deletingPathExtension().deletingPathExtension().lastPathComponent + "/" + file
        return [folder + "/" + file, named].filter { $0 != route.remote }
    }

    func upload(_ route: Route, offset: Int64, ftp: FTPClient, events: TransferHandler) async throws {
        try await upload(route, to: route.remote, offset: offset, ftp: ftp, events: events)
    }

    /// Uploads `route` into `path` from `offset`, then renames a .part to the real name.
    func upload(_ route: Route, to path: String, offset: Int64, ftp: FTPClient, events: TransferHandler) async throws {
        events(.started(route, resumingFrom: offset))
        let directory = (route.remote as NSString).deletingLastPathComponent
        try await ftp.makeDirectories(directory)
        let start = Date()
        var lastReport = Date.distantPast
        if offset < route.size || offset == 0 {
            try await ftp.upload(file: route.local, to: path, offset: offset) { sent in
                let now = Date()
                guard now.timeIntervalSince(lastReport) >= 0.25 || sent == route.size else { return }
                lastReport = now
                let elapsed = max(now.timeIntervalSince(start), 0.001)
                events(.progress(route, sent: sent, total: route.size, bytesPerSecond: Double(sent - offset) / elapsed))
            }
        }
        guard let size = try await ftp.size(path), size == route.size else {
            throw PS3Error.ftpProtocol("storleken på \(path) stämmer inte efter uppladdningen")
        }
        if path != route.remote { try await ftp.rename(path, to: route.remote) }
        events(.finished(route, seconds: Date().timeIntervalSince(start)))
    }

    // MARK: Verify

    /// Compares the console's MD5 (webMAN's /md5.ps3) of each sent file of 64 MB or more with
    /// the Mac's. A file that differs is removed from the console, so the next try sends it again.
    public func verify(_ routes: [Route], events: TransferHandler) async throws {
        for route in routes where route.size >= 64 << 20 {
            events(.note("Kontrollerar \(route.local.lastPathComponent) med MD5 (det tar en stund på PS3:an)…"))
            let local = try Self.md5(of: route.local)
            let page = try await webman.get("/md5.ps3" + route.remote, timeout: 1800)
            guard let remote = ConsoleSnapshot.firstMatch("([0-9a-fA-F]{32})", in: page)?[1].lowercased() else {
                throw PS3Error.ftpProtocol("webMAN gav ingen MD5 för \(route.remote).")
            }
            guard remote == local else {
                try? await withFTP { ftp in try await ftp.delete(route.remote) }
                throw PS3Error.invalidFile("\(route.local.lastPathComponent) blev fel på vägen (MD5 stämmer inte) och togs bort från PS3:an. Skicka den igen.")
            }
            events(.note("\(route.local.lastPathComponent): MD5 stämmer"))
        }
    }

    static func md5(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = Insecure.MD5()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Install

    /// Uploads a .pkg to /dev_hdd0/packages and installs it through webMAN, after any running
    /// game has ended. The FTP session is closed while waiting, since webMAN drops idle ones.
    public func installPackage(_ local: URL, options: TransferOptions, events: TransferHandler) async throws {
        let route = Route(local: local, remote: "/dev_hdd0/packages/" + local.lastPathComponent, kind: .package,
                          size: FileRouter.fileSize(local), title: nil)
        let uploaded = try await withFTP { ftp -> Bool in
            let remoteSize = try await ftp.size(route.remote) ?? 0
            if options.dryRun {
                events(.started(route, resumingFrom: remoteSize))
                return false
            }
            if remoteSize != route.size {
                try await upload(route, offset: remoteSize < route.size ? remoteSize : 0, ftp: ftp, events: events)
            } else {
                events(.skipped(route, reason: "ligger redan i /dev_hdd0/packages"))
            }
            return true
        }
        guard uploaded else { return }
        try await waitUntilIdle(force: options.force, events: events)
        try await install(route, events: events)
    }

    /// What the console shows of an install: the package still there, PARAM.SFO's date and the
    /// folder's listing.
    struct InstallState: Equatable {
        var packagePresent: Bool
        var paramSFO: String?
        var folder: String?
    }

    private func installState(_ route: Route, gameDir: String?) async throws -> InstallState {
        try await withFTP { ftp in
            let size = try await ftp.size(route.remote)
            var state = InstallState(packagePresent: size != nil)
            if let gameDir {
                state.paramSFO = try await ftp.modificationTime(gameDir + "/PARAM.SFO")
                state.folder = try await folderSignature(gameDir, ftp: ftp)
            }
            return state
        }
    }

    /// Asks webMAN to install, then follows the app's folder: PARAM.SFO gets a new date, then the
    /// folder stops changing. webMAN's docs say /install.ps3 deletes the package afterwards, but on
    /// this console it does not. Each check opens its own FTP session, since the install request
    /// can take a minute and webMAN drops a session that is quiet that long, and a check that fails
    /// (the network hiccups) is just tried again. If nothing on the console changes, the request is
    /// sent once more, and then it gives up with advice instead of waiting for 20 minutes.
    private func install(_ route: Route, events: TransferHandler) async throws {
        let name = route.local.lastPathComponent
        let gameDir = PKGInfo(url: route.local)?.titleID.map { "/dev_hdd0/game/\($0)" }
        let before = try await installState(route, gameDir: gameDir)

        events(.installing(name))
        var requests = 0
        var requestedAt = Date()
        func request() async {
            requests += 1
            requestedAt = Date()
            // The answer may only come when the XMB is done, or never: the folder tells.
            try? await webman.installPackage(remotePath: route.remote)
        }
        await request()

        let deadline = Date().addingTimeInterval(20 * 60)
        var started = false
        var last: InstallState?
        var stableRounds = 0
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 4_000_000_000)
            guard let now = try? await installState(route, gameDir: gameDir) else { continue }
            if !now.packagePresent { break }  // webMAN removed it: done
            guard gameDir != nil else {
                // No title ID in the package header to follow: give the XMB a minute.
                if Date().timeIntervalSince(requestedAt) > 60 { break } else { continue }
            }
            if now.paramSFO != before.paramSFO || now.folder != before.folder { started = true }
            if !started {
                guard Date().timeIntervalSince(requestedAt) > 75 else { continue }
                if requests < 2 {
                    events(.note("PS3:an har inte börjat installera \(name); ber webMAN igen"))
                    await request()
                    continue
                }
                throw PS3Error.timeout("PS3:an började aldrig installera \(name). Paketet ligger kvar i /dev_hdd0/packages: installera det i XMB:n (Spel → Package Manager → Installera paket → Standard) eller försök igen.")
            }
            stableRounds = now == last ? stableRounds + 1 : 0
            last = now
            // Done when PARAM.SFO is new and the folder has stood still for two checks (or five,
            // if the date never moved).
            if stableRounds >= (now.paramSFO != before.paramSFO ? 2 : 5) {
                _ = try? await withFTP { try await $0.delete(route.remote) }  // our uploaded copy; the original stays on the Mac
                break
            }
        }
        guard Date() < deadline else {
            throw PS3Error.timeout("installationen av \(name) blev inte klar inom 20 minuter. Kolla på konsolen; paketet ligger kvar i /dev_hdd0/packages.")
        }
        OperationLog.record("install", name)
        events(.installed(name))
    }

    /// Names, sizes and dates of a folder and its USRDIR, to see when an install stops writing.
    private func folderSignature(_ dir: String, ftp: FTPClient) async throws -> String {
        var parts: [String] = []
        for path in [dir, dir + "/USRDIR"] {
            for entry in try await ftp.list(path) {
                parts.append("\(path)/\(entry.name):\(entry.size)")
            }
        }
        return parts.sorted().joined(separator: "|")
    }

    /// Opens one FTP session for `body` and always closes it.
    public func withFTP<T>(_ body: (FTPClient) async throws -> T) async throws -> T {
        let ftp = FTPClient(host: host)
        try await ftp.connect()
        do {
            let result = try await body(ftp)
            await ftp.close()
            return result
        } catch {
            await ftp.close()
            throw error
        }
    }

    // MARK: Game guard

    /// "Varna och vänta": blocks until no game/app is running, unless forced.
    public func waitUntilIdle(force: Bool, events: TransferHandler, pollSeconds: UInt64 = 10) async throws {
        guard !force else { return }
        var announced = false
        while let process = try? await webman.runningProcess() {
            if !announced {
                let mounted = try? await webman.snapshot().mountedGameName
                events(.waitingForGame((mounted ?? nil) ?? process))
                announced = true
            }
            try await Task.sleep(nanoseconds: pollSeconds * 1_000_000_000)
        }
    }
}
