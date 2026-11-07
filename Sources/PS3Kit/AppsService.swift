import CryptoKit
import Foundation

/// One row in `ps3 apps`, like a row in Mole's Apps → Updates list.
public struct AppStatus: Codable, Sendable {
    public enum State: String, Codable, Sendable {
        case upToDate, updateAvailable, notInstalled, manual, error
    }

    public let id: String
    public let name: String
    public let summary: String
    public let category: CatalogEntry.Category
    public var installed: String?
    public var latest: String?
    public var state: State
    public var note: String?
    public var homepage: String
    public var assetURL: URL?
    public var assetName: String?
    /// True when `ps3 apps update` may install it (packages only, never HEN or plugins).
    public var canInstall: Bool
    /// True when `ps3 apps install <id>` can fetch and install it at all.
    public var installable: Bool
    /// Whether it works on this console (HEN/CFW, CEX/DEX, firmware). A block clears both flags above.
    public var compatibility: Compatibility = .compatible
    /// Could be installed from the catalog, but the console does not meet its requirements.
    public var blocked = false
    /// Size of the release package in bytes, for the review before "Update All".
    public var assetSize: Int64?
    /// When the latest release came out, as GitHub writes it ("2026-11-02T18:04:11Z").
    public var releaseDate: String?
    /// An update to exactly this release was skipped (`IgnoredUpdates`). It still counts as
    /// `updateAvailable`, but lists and "Update All" leave it out.
    public var ignored = false

    /// An update the user has not skipped: what the badges count and "Update All" offers.
    public var isPendingUpdate: Bool { state == .updateAvailable && !ignored }

    /// A value-type parse: no formatter is made per call, though every tile in Browse asks.
    public var releasedAt: Date? { releaseDate.flatMap { try? Date($0, strategy: .iso8601) } }

    /// The release tag in the console's own APP_VER form when the catalog knows how they map
    /// ("v2.4.1" → "02.41"), so "02.40 → 02.41" compares like with like; else the tag itself.
    /// The Updates list, the review before Update All, its report and the CLI all show this.
    public var latestForDisplay: String? {
        guard let latest else { return nil }
        guard let entry = Catalog.entries.first(where: { $0.id == id }), entry.installedStyle == .appVer,
              entry.releaseStyle == .semverAsAppVer || entry.releaseStyle == .artemis,
              let version = Version(latest, style: entry.releaseStyle), version.parts.count == 2 else { return latest }
        return String(format: "%02d.%02d", version.parts[0], version.parts[1])
    }

    /// "02.40 → 02.41".
    public var versionChange: String { "\(installed ?? "?") → \(latestForDisplay ?? "?")" }

    /// "New" in Browse: the latest release came out in the last `days` days.
    public func isNewRelease(now: Date = Date(), days: Int = 30) -> Bool {
        guard let releasedAt else { return false }
        return now.timeIntervalSince(releasedAt) < Double(days) * 86_400
    }
}

public struct AppsService: Sendable {
    public let host: String

    public init(host: String) { self.host = host }

    struct LatestInfo: Sendable {
        let version: String
        let assetURL: URL?
        let assetName: String?
        /// Downloaded release asset, only for plugin files that are compared byte for byte.
        let assetData: Data?
        var assetSize: Int64? = nil
        var releaseDate: String? = nil
    }

    // MARK: Check

    /// Reads installed versions from the console and latest versions from GitHub.
    public func check(entries: [CatalogEntry] = Catalog.entries) async throws -> [AppStatus] {
        async let latest = latestVersions(for: entries)

        var installedFiles: [String: Data] = [:]
        try await TransferService(host: host).withFTP { ftp in
            for entry in entries {
                switch entry.installed {
                case .paramSFO(let titleID):
                    installedFiles[entry.id] = try await ftp.download("/dev_hdd0/game/\(titleID)/PARAM.SFO", limit: 64 << 10)
                case .pluginFile(let path):
                    installedFiles[entry.id] = try await ftp.download(path, limit: 8 << 20)
                case .webman, .hen:
                    break
                }
            }
        }
        let needsSnapshot = entries.contains {
            if case .webman = $0.installed { return true }
            if case .hen = $0.installed { return true }
            return !$0.requirements.isUnrestricted
        }
        let console = needsSnapshot ? try await WebMAN(host: host).snapshot() : ConsoleSnapshot()
        let releases = await latest
        let ignored = IgnoredUpdates.load()

        return entries.map { entry in
            status(for: entry, installedFile: installedFiles[entry.id], console: console, release: releases[entry.id], ignored: ignored)
        }
    }

    func status(for entry: CatalogEntry, installedFile: Data?, console: ConsoleSnapshot,
                release: Result<LatestInfo, Error>?, ignored: [String: String] = [:]) -> AppStatus {
        var status = versionStatus(for: entry, installedFile: installedFile, console: console, release: release)
        status.ignored = status.state == .updateAvailable && IgnoredUpdates.skips(entry.id, latest: status.latest, in: ignored)
        let compatibility = Compatibility.check(entry.requirements, on: ConsoleProfile(snapshot: console))
        status.compatibility = compatibility
        guard compatibility.blocksInstall else { return status }
        status.blocked = entry.isInstallable
        status.canInstall = false
        status.installable = false
        var notifyOnly = false
        if case .notifyOnly = entry.action { notifyOnly = true }
        // HEN and plugins keep their own advice; for the rest the block is the news.
        if status.state == .updateAvailable, !notifyOnly { status.note = compatibility.summary }
        return status
    }

    private func versionStatus(for entry: CatalogEntry, installedFile: Data?, console: ConsoleSnapshot,
                               release: Result<LatestInfo, Error>?) -> AppStatus {
        var status = AppStatus(id: entry.id, name: entry.name, summary: entry.summary, category: entry.category,
                               installed: nil, latest: nil, state: .notInstalled, note: nil, homepage: entry.homepage,
                               assetURL: nil, assetName: nil, canInstall: false, installable: false)
        var sfoVersion: String?
        switch entry.installed {
        case .paramSFO:
            if let file = installedFile {
                sfoVersion = ParamSFO(data: file)?.appVersion
                status.installed = sfoVersion ?? "installed"
            }
        case .webman: status.installed = console.webmanVersion
        case .hen: status.installed = console.henVersion
        case .pluginFile: status.installed = installedFile == nil ? nil : "installed"
        }

        switch release {
        case .none:
            break
        case .some(.failure(let error)):
            status.state = status.installed == nil ? .notInstalled : .error
            status.note = error.localizedDescription
            return status
        case .some(.success(let info)):
            status.latest = info.version
            status.assetURL = info.assetURL
            status.assetName = info.assetName
            status.assetSize = info.assetSize
            // An untracked release is someone else's (webMAN's add-ons), so its date says nothing.
            if entry.tracksUpdates { status.releaseDate = info.releaseDate }
            status.installable = entry.isInstallable && info.assetURL != nil
            if !entry.tracksUpdates { status.latest = nil }
            if let assetData = info.assetData, let installedData = installedFile {
                status.installed = Self.md5(installedData) == Self.md5(assetData) ? info.version : "other version"
            }
        }

        if case .manual = entry.source {
            status.state = status.installed == nil ? .notInstalled : .manual
            status.note = "Check manually: \(entry.homepage)"
            return status
        }
        guard let installed = status.installed else { return status }
        guard entry.tracksUpdates, let latest = status.latest else {
            status.state = .upToDate
            if !entry.tracksUpdates { status.latest = nil }  // the release tag is someone else's version
            return status
        }

        let newer: Bool
        if case .pluginFile = entry.installed {
            newer = installed != latest
        } else if let sfoVersion, let knownTag = InstalledRegistry.tag(for: entry.id, installedAppVersion: sfoVersion),
                  let a = Version(knownTag, style: entry.releaseStyle), let b = Version(latest, style: entry.releaseStyle) {
            // Installed by PS3 Center: compare release tags directly, no numbering guesswork.
            newer = a < b
        } else if let a = Version(installed, style: entry.installedStyle), let b = Version(latest, style: entry.releaseStyle) {
            newer = a < b
        } else {
            newer = false
        }
        status.state = newer ? .updateAvailable : .upToDate
        if newer {
            switch entry.action {
            case .installPackage:
                status.canInstall = status.assetURL != nil
            case .installPackageThenManual(let note):
                status.canInstall = status.assetURL != nil
                status.note = note
            case .notifyOnly(let note):
                status.note = note
            }
        }
        return status
    }

    /// One GitHub request per distinct release, shared by entries from the same release.
    private func latestVersions(for entries: [CatalogEntry]) async -> [String: Result<LatestInfo, Error>] {
        var releaseKeys: [String: (repo: String, tag: String?)] = [:]
        var needsHEN = false
        for entry in entries {
            switch entry.source {
            case .github(let repo, _, let tag): releaseKeys["\(repo)@\(tag ?? "latest")"] = (repo, tag)
            case .henSource: needsHEN = true
            case .manual: break
            }
        }

        let fetched: [String: Result<GitHubRelease, Error>] = await withTaskGroup(of: (String, Result<GitHubRelease, Error>).self) { group in
            for (key, source) in releaseKeys {
                group.addTask {
                    do { return (key, .success(try await GitHub.release(repo: source.repo, tag: source.tag))) }
                    catch { return (key, .failure(error)) }
                }
            }
            var results: [String: Result<GitHubRelease, Error>] = [:]
            for await (key, result) in group { results[key] = result }
            return results
        }
        let henVersion: Result<String, Error>? = needsHEN ? await Result(catching: { try await GitHub.latestHENVersion() }) : nil

        var results: [String: Result<LatestInfo, Error>] = [:]
        for entry in entries {
            switch entry.source {
            case .manual:
                continue
            case .henSource:
                results[entry.id] = henVersion?.map { LatestInfo(version: $0, assetURL: nil, assetName: nil, assetData: nil) }
            case .github(let repo, let pattern, let tag):
                switch fetched["\(repo)@\(tag ?? "latest")"] {
                case .some(.success(let release)):
                    let asset = release.asset(matching: pattern)
                    var data: Data?
                    if case .pluginFile = entry.installed, let asset {
                        data = try? await GitHub.data(asset.browserDownloadURL)
                    }
                    results[entry.id] = .success(LatestInfo(version: release.tagName, assetURL: asset?.browserDownloadURL,
                                                            assetName: asset?.name, assetData: data, assetSize: asset?.size,
                                                            releaseDate: release.publishedAt))
                case .some(.failure(let error)):
                    results[entry.id] = .failure(error)
                case .none:
                    break
                }
            }
        }
        return results
    }

    static func md5(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Compatibility

    /// Reads the console's firmware only when `entry` has requirements.
    public func compatibility(of entry: CatalogEntry) async throws -> Compatibility {
        guard !entry.requirements.isUnrestricted else { return .compatible }
        let profile = ConsoleProfile(snapshot: try await WebMAN(host: host).snapshot())
        return Compatibility.check(entry.requirements, on: profile)
    }

    /// The safety check for a user's own .pkg: if its title ID is in the catalog, the same
    /// requirements apply as when installing it by name. Unknown packages pass.
    public func checkPackage(_ file: URL) async throws -> (entry: CatalogEntry, compatibility: Compatibility)? {
        guard let titleID = PKGInfo(url: file)?.titleID, let entry = Catalog.entry(titleID: titleID) else { return nil }
        return (entry, try await compatibility(of: entry))
    }

    // MARK: Icons

    /// XMB icons (ICON0.PNG) of installed apps, keyed by catalog id. Cached on disk, since they
    /// rarely change; pass `refresh` after an install.
    public func icons(for entries: [CatalogEntry], refresh: Bool = false) async -> [String: Data] {
        let pairs = entries.compactMap { entry in entry.titleID.map { (entry.id, $0) } }
        let byTitleID = await icons(titleIDs: pairs.map(\.1), refresh: refresh)
        return Dictionary(pairs.compactMap { id, titleID in byTitleID[titleID].map { (id, $0) } }, uniquingKeysWith: { a, _ in a })
    }

    /// The same icons keyed by title ID, for apps that may not be in the catalog (the Mac's own
    /// packages).
    public func icons(titleIDs: [String], refresh: Bool = false) async -> [String: Data] {
        let cache = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/ps3center/icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        var result: [String: Data] = [:]
        var missing: [String] = []
        for titleID in Set(titleIDs) {
            let file = cache.appendingPathComponent("\(titleID).png")
            if !refresh, let data = try? Data(contentsOf: file) { result[titleID] = data } else { missing.append(titleID) }
        }
        guard !missing.isEmpty else { return result }
        _ = try? await TransferService(host: host).withFTP { ftp in
            for titleID in missing {
                guard let data = try await ftp.download("/dev_hdd0/game/\(titleID)/ICON0.PNG", limit: 2 << 20) else { continue }
                result[titleID] = data
                try? data.write(to: cache.appendingPathComponent("\(titleID).png"))
            }
        }
        return result
    }

    // MARK: The Mac's packages

    /// APP_VER on the console per title ID, for those of `titleIDs` installed in /dev_hdd0/game
    /// (an empty string when PARAM.SFO has none). One listing, then a PARAM.SFO per installed one.
    public func installedVersions(of titleIDs: [String]) async throws -> [String: String] {
        let wanted = Set(titleIDs.map { $0.uppercased() })
        guard !wanted.isEmpty else { return [:] }
        return try await TransferService(host: host).withFTP { ftp in
            var result: [String: String] = [:]
            for folder in try await ftp.list("/dev_hdd0/game") where folder.isDirectory && wanted.contains(folder.name.uppercased()) {
                guard let data = try await ftp.download("/dev_hdd0/game/\(folder.name)/PARAM.SFO", limit: 64 << 10) else { continue }
                result[folder.name.uppercased()] = ParamSFO(data: data)?.appVersion ?? ""
            }
            return result
        }
    }

    /// Installs the user's own .pkg from where it lies; the file is not moved or archived. If its
    /// title ID is in the catalog, the console must meet that program's requirements, as when it
    /// is installed by name. Logged by `TransferService.installPackage`.
    public func installOwnPackage(_ file: URL, options: TransferOptions, events: TransferHandler) async throws {
        guard PKGInfo(url: file) != nil else { throw PS3Error.invalidFile("\(file.lastPathComponent) is not a valid PS3 package.") }
        if let known = try await checkPackage(file) {
            try known.compatibility.enforce("\(file.lastPathComponent) (\(known.entry.name))")
            if known.compatibility.verdict == .untested { events(.note("Note: \(known.compatibility.summary).")) }
        }
        try await TransferService(host: host).installPackage(file, options: options, events: events)
    }

    /// The XMB background (PIC1.PNG, 1920×1080) of an installed app, cached on disk like the icons.
    public func background(for entry: CatalogEntry) async -> Data? {
        guard let titleID = entry.titleID else { return nil }
        let cache = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/ps3center/backgrounds", isDirectory: true)
        let file = cache.appendingPathComponent("\(titleID).png")
        if let data = try? Data(contentsOf: file) { return data }
        let downloaded = try? await TransferService(host: host).withFTP { ftp in
            try await ftp.download("/dev_hdd0/game/\(titleID)/PIC1.PNG", limit: 8 << 20)
        }
        guard let data = downloaded ?? nil else { return nil }
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try? data.write(to: file)
        return data
    }

    // MARK: Install and update

    /// Fetches the release package for `entry`, archives it in _Installed/Packages (older copies
    /// of the same app go to the Trash), installs it and remembers which tag is installed.
    /// Refuses before downloading anything when the console does not meet the entry's requirements.
    public func install(_ entry: CatalogEntry, archive: URL, options: TransferOptions, events: TransferHandler) async throws {
        guard entry.isInstallable, case .github(let repo, let pattern, let tag) = entry.source else {
            if case .notifyOnly(let note) = entry.action { throw PS3Error.unsupportedFile("\(entry.name) is not installed automatically. \(note)") }
            throw PS3Error.unsupportedFile("\(entry.name) cannot be installed automatically. See \(entry.homepage)")
        }
        let compatibility = try await self.compatibility(of: entry)
        try compatibility.enforce(entry.name)
        if compatibility.verdict == .untested { events(.note("Note: \(compatibility.summary).")) }
        let release = try await GitHub.release(repo: repo, tag: tag)
        guard let asset = release.asset(matching: pattern) else {
            throw PS3Error.github("Release \(release.tagName) of \(repo) has no package for \(entry.name).")
        }
        if options.dryRun {
            events(.note("Would download \(asset.name) (\(Format.bytes(asset.size)), \(release.tagName)) and install it"))
            return
        }
        events(.note("Downloading \(asset.name) \(release.tagName) (\(Format.bytes(asset.size)))…"))
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("ps3center-\(UUID().uuidString)/\(asset.name)")
        try await GitHub.download(asset.browserDownloadURL, to: staging)
        // Size and SHA-256 as GitHub lists them, before anything is archived or sent.
        if try GitHub.verify(staging, size: asset.size, digest: asset.digest) {
            events(.note("\(asset.name) matches GitHub's checksum (SHA-256)."))
        }
        let local = try archivePackage(staging, into: archive)
        try? FileManager.default.removeItem(at: staging.deletingLastPathComponent())

        let transfer = TransferService(host: host)
        try await transfer.installPackage(local, options: options, events: events)

        if let titleID = entry.titleID,
           let version = try? await transfer.withFTP({ try await $0.download("/dev_hdd0/game/\(titleID)/PARAM.SFO", limit: 64 << 10) })
            .flatMap(ParamSFO.init(data:))?.appVersion {
            InstalledRegistry.record(entry.id, tag: release.tagName, appVersion: version)
        }
        if case .installPackageThenManual(let note) = entry.action { events(.note(note)) }
    }

    /// Removes an app installed from a package: its folder in /dev_hdd0/game. Not HEN, webMAN or
    /// plugins (they are not installed that way), and not while a game or app runs. Logged.
    public func uninstall(_ entry: CatalogEntry, options: TransferOptions, events: TransferHandler) async throws {
        guard entry.category != .system, let titleID = entry.titleID else {
            throw PS3Error.refused("\(entry.name) is not uninstalled from here.")
        }
        let path = "/dev_hdd0/game/" + titleID
        if let refusal = UninstallGuard.refusal(titleID: titleID, title: entry.name, path: path) { throw PS3Error.refused(refusal) }
        guard try await WebMAN(host: host).runningProcess() == nil else { throw PS3Error.gameRunning }
        if options.dryRun {
            events(.note("Would delete \(path)"))
            return
        }
        try await TransferService(host: host).withFTP { ftp in
            guard try await ftp.size(path + "/PARAM.SFO") != nil else {
                throw PS3Error.refused("\(entry.name) is not installed (\(path) is missing).")
            }
            try await ftp.removeTree(path)
        }
        InstalledRegistry.forget(entry.id)
        OperationLog.record("uninstall", "\(entry.name) (\(path))")
        let reload = await XMBReload.afterRemoval(host: host)
        events(.note("\(entry.name) is uninstalled. \(reload)"))
    }

    public func update(_ status: AppStatus, archive: URL, options: TransferOptions, events: TransferHandler) async throws {
        guard status.canInstall, let entry = Catalog.entries.first(where: { $0.id == status.id }) else {
            throw PS3Error.unsupportedFile("\(status.name) cannot be updated automatically.")
        }
        try await install(entry, archive: archive, options: options, events: events)
    }

    /// Moves `file` into the archive. Archived packages with the same title ID are trashed first.
    public func archivePackage(_ file: URL, into archive: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: archive, withIntermediateDirectories: true)
        let titleID = PKGInfo(url: file)?.titleID
        let destination = archive.appendingPathComponent(file.lastPathComponent)
        let existing = (try? fm.contentsOfDirectory(at: archive, includingPropertiesForKeys: nil)) ?? []
        for old in existing where old.pathExtension.lowercased() == "pkg" && old.standardizedFileURL != file.standardizedFileURL {
            let sameApp = titleID != nil && PKGInfo(url: old)?.titleID == titleID
            if sameApp || old.lastPathComponent == destination.lastPathComponent {
                try fm.trashItem(at: old, resultingItemURL: nil)
            }
        }
        if file.standardizedFileURL != destination.standardizedFileURL {
            try fm.moveItem(at: file, to: destination)
        }
        return destination
    }
}

extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
