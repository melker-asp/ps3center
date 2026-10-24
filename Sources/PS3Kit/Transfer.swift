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
    public init() {}
}

/// Uploads files over FTP and runs the follow-up web commands.
public struct TransferService: Sendable {
    public let host: String
    public var webman: WebMAN { WebMAN(host: host) }

    public init(host: String) { self.host = host }

    // MARK: Send

    /// Uploads `routes`; afterwards refreshes the game list and shows a popup on the TV.
    /// Already complete files are skipped, partial ones are resumed.
    public func send(_ routes: [Route], options: TransferOptions, events: TransferHandler) async throws {
        try await withFTP { ftp in try await send(routes, ftp: ftp, options: options, events: events) }
    }

    private func send(_ routes: [Route], ftp: FTPClient, options: TransferOptions, events: TransferHandler) async throws {
        var pending: [(Route, Int64)] = []
        routeLoop: for route in routes {
            events(.checking(route.remote))
            // A game may already be on the console at another depth (flat in PS3ISO/ vs one
            // folder per game, as in the local mirror).
            for alternative in Self.alternativeLocations(for: route) where try await ftp.size(alternative) == route.size {
                events(.skipped(route, reason: "finns redan på PS3:an (\(alternative))"))
                continue routeLoop
            }
            let remoteSize = try await ftp.size(route.remote) ?? 0
            if remoteSize == route.size {
                events(.skipped(route, reason: "finns redan på PS3:an"))
            } else if remoteSize > route.size {
                events(.skipped(route, reason: "en större fil med samma namn finns redan på PS3:an"))
            } else {
                pending.append((route, remoteSize))
            }
        }

        let needed = pending.reduce(Int64(0)) { $0 + $1.0.size - $1.1 }
        if needed > 0, !options.force, let free = try? await webman.snapshot().freeBytes, needed + 1_000_000_000 > free {
            throw PS3Error.notEnoughSpace(needed: needed, free: free)
        }
        if options.dryRun {
            for (route, offset) in pending { events(.started(route, resumingFrom: offset)) }
            return
        }

        var sentAny = false
        for (route, offset) in pending {
            try await upload(route, offset: offset, ftp: ftp, events: events)
            OperationLog.record("send", "\(route.remote) (\(Format.bytes(route.size)))")
            sentAny = true
        }

        let needsRefresh = routes.contains { $0.refreshesGameList }
        guard sentAny, options.refresh, needsRefresh else { return }
        try await waitUntilIdle(force: options.force, events: events)
        try await webman.refreshGames()
        events(.refreshed)
        if options.popup {
            let titles = Array(Set(pending.map { $0.0 }.filter { $0.refreshesGameList }.map { $0.title ?? GameName.clean($0.local.lastPathComponent) })).sorted()
            let message = titles.count == 1 ? "\(titles[0]) finns nu under Spel" : "\(titles.count) nya spel finns under Spel"
            try? await webman.popup(message)
        }
    }

    /// Other places webMAN would find the same game: flat in its folder, or in a folder named after it.
    static func alternativeLocations(for route: Route) -> [String] {
        guard route.kind.needsRefresh, route.kind != .ps3Folder, let folder = route.kind.remoteFolder else { return [] }
        let file = route.local.lastPathComponent
        let named = folder + "/" + route.local.deletingPathExtension().deletingPathExtension().lastPathComponent + "/" + file
        return [folder + "/" + file, named].filter { $0 != route.remote }
    }

    func upload(_ route: Route, offset: Int64, ftp: FTPClient, events: TransferHandler) async throws {
        events(.started(route, resumingFrom: offset))
        let directory = (route.remote as NSString).deletingLastPathComponent
        try await ftp.makeDirectories(directory)
        let start = Date()
        var lastReport = Date.distantPast
        try await ftp.upload(file: route.local, to: route.remote, offset: offset) { sent in
            let now = Date()
            guard now.timeIntervalSince(lastReport) >= 0.25 || sent == route.size else { return }
            lastReport = now
            let elapsed = max(now.timeIntervalSince(start), 0.001)
            events(.progress(route, sent: sent, total: route.size, bytesPerSecond: Double(sent - offset) / elapsed))
        }
        guard let size = try await ftp.size(route.remote), size == route.size else {
            throw PS3Error.ftpProtocol("storleken på \(route.remote) stämmer inte efter uppladdningen")
        }
        events(.finished(route, seconds: Date().timeIntervalSince(start)))
    }

    // MARK: Install

    /// Uploads a .pkg to /dev_hdd0/packages and installs it through webMAN.
    /// webMAN deletes the package when it is done, which is how completion is detected.
    public func installPackage(_ local: URL, options: TransferOptions, events: TransferHandler) async throws {
        let name = local.lastPathComponent
        let route = Route(local: local, remote: "/dev_hdd0/packages/" + name, kind: .package,
                          size: FileRouter.fileSize(local), title: nil)
        try await withFTP { ftp in try await installPackage(route, ftp: ftp, options: options, events: events) }
    }

    private func installPackage(_ route: Route, ftp: FTPClient, options: TransferOptions, events: TransferHandler) async throws {
        let name = route.local.lastPathComponent
        let remoteSize = try await ftp.size(route.remote) ?? 0
        if options.dryRun {
            events(.started(route, resumingFrom: remoteSize))
            return
        }
        if remoteSize != route.size {
            try await upload(route, offset: remoteSize < route.size ? remoteSize : 0, ftp: ftp, events: events)
        } else {
            events(.skipped(route, reason: "ligger redan i /dev_hdd0/packages"))
        }

        try await waitUntilIdle(force: options.force, events: events)

        // webMAN's docs say /install.ps3 deletes the package afterwards, but on this console it
        // does not. Completion is therefore read from the installed app's folder: PARAM.SFO gets
        // a new timestamp, then the folder stops changing.
        let gameDir = PKGInfo(url: route.local)?.titleID.map { "/dev_hdd0/game/\($0)" }
        let sfoBefore = try await gameDir.asyncMap { try await ftp.modificationTime($0 + "/PARAM.SFO") } ?? nil

        events(.installing(name))
        do {
            try await webman.installPackage(remotePath: route.remote)
        } catch PS3Error.unreachable {
            // The install request can block while the XMB installs; keep polling below.
        }

        let deadline = Date().addingTimeInterval(20 * 60)
        var lastSignature: String?
        var stableRounds = 0
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 3_000_000_000)
            if try await ftp.size(route.remote) == nil { break }  // webMAN removed it: done
            guard let gameDir else { continue }
            let sfoNow = try await ftp.modificationTime(gameDir + "/PARAM.SFO")
            guard let sfoNow, sfoNow != sfoBefore else { continue }
            let signature = try await folderSignature(gameDir, ftp: ftp)
            stableRounds = signature == lastSignature ? stableRounds + 1 : 0
            lastSignature = signature
            if stableRounds >= 2 {
                try? await ftp.delete(route.remote)  // our uploaded copy; the original stays on the Mac
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
