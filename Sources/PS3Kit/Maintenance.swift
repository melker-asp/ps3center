import Foundation

/// Something `ps3 maintain` found. Only leftover packages and unfinished uploads can be
/// removed by PS3 Center; the rest is advice.
public struct MaintenanceFinding: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case leftoverPackage, partialUpload, duplicate, cache, missingPlugin, henToggles, space, updates
        /// A folder on the Mac with its Swedish name beside the English one (`FolderMigration`).
        case oldFolder
    }

    public let kind: Kind
    public let title: String
    public let detail: String
    public var path: String?
    public var size: Int64?
    public var canFix = false

    public var id: String { kind.rawValue + ":" + (path ?? title) }

    public init(kind: Kind, title: String, detail: String, path: String? = nil, size: Int64? = nil, canFix: Bool = false) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.path = path
        self.size = size
        self.canFix = canFix
    }
}

public struct MaintenanceReport: Codable, Equatable, Sendable {
    public var findings: [MaintenanceFinding] = []
    /// The checks that found nothing, to show as done.
    public var passed: [String] = []

    public init(findings: [MaintenanceFinding] = [], passed: [String] = []) {
        self.findings = findings
        self.passed = passed
    }
}

public struct MaintenanceService: Sendable {
    public let host: String

    public init(host: String) { self.host = host }

    /// Reads the console and reports. Changes nothing.
    public func check(queue: TransferQueue = TransferQueue.load(), events: @Sendable (String) -> Void = { _ in }) async throws -> MaintenanceReport {
        // The game list first: it opens its own FTP session.
        events("Duplicates")
        let games = (try? await GameLibraryService(host: host).scan()) ?? []
        var report = try await TransferService(host: host).withFTP { ftp in
            try await check(ftp, queue: queue, games: games, events: events)
        }

        events("webMAN's cache")
        if let cache = try? await StorageAnalyzer(host: host).size(of: "/dev_hdd0/tmp/wmtmp"), cache.bytes > 1 << 30 {
            report.findings.append(MaintenanceFinding(
                kind: .cache, title: "webMAN's cache",
                detail: "/dev_hdd0/tmp/wmtmp is \(Format.bytes(cache.bytes)). webMAN builds it up again by itself if you empty it there.",
                path: "/dev_hdd0/tmp/wmtmp", size: cache.bytes))
        } else {
            report.passed.append("webMAN's cache is small")
        }

        if let free = try? await WebMAN(host: host).snapshot().freeBytes, free < 10_000_000_000 {
            report.findings.append(MaintenanceFinding(
                kind: .space, title: "Low on free space",
                detail: "\(Format.bytes(free)) free on /dev_hdd0. Running games and installing updates need room."))
        } else {
            report.passed.append("Plenty of free space")
        }

        // On the Mac: a Swedish folder name that came back beside the English one.
        for leftover in FolderMigration.leftovers() {
            let name = leftover.new.lastPathComponent
            report.findings.append(MaintenanceFinding(
                kind: .oldFolder, title: "\(leftover.old.lastPathComponent) on the Mac",
                detail: "\(leftover.old.path) still has its Swedish name beside \(name), so an older PS3 Center (the app or ps3) probably made it again. PS3 Center now only uses \(name): move what you need from the old folder, delete it, and update both the app and ps3.",
                path: leftover.old.path))
        }
        return report
    }

    private func check(_ ftp: FTPClient, queue: TransferQueue, games: [Game], events: @Sendable (String) -> Void) async throws -> MaintenanceReport {
        var report = MaintenanceReport()

        events("Packages and unfinished transfers")
        let queued = Set(queue.pending.flatMap { $0.files.map(\.remote) })
        let packages = try await ftp.list("/dev_hdd0/packages")
        for file in packages where !file.isDirectory && [".pkg", ".p3t"].contains(where: { file.name.lowercased().hasSuffix($0) }) {
            report.findings.append(MaintenanceFinding(
                kind: .leftoverPackage, title: file.name,
                detail: "A package or theme left in /dev_hdd0/packages. What it installed does not need it.",
                path: "/dev_hdd0/packages/" + file.name, size: file.size, canFix: true))
        }

        events("System updates")
        if try await ftp.size(UpdateBlock.remotePath) == nil {
            // Advice only: `fix` removes files and never adds one; `UpdateBlock.set` does that on request.
            report.findings.append(MaintenanceFinding(
                kind: .updates, title: "System updates are not blocked",
                detail: "If the PS3 updates its system software by mistake, HEN can stop working. Blocking takes effect from the next start."))
        } else {
            report.passed.append("System updates are blocked")
        }
        var parts: [(path: String, size: Int64)] = packages.filter { $0.name.hasSuffix(".part") }
            .map { ("/dev_hdd0/packages/" + $0.name, $0.size) }
        for folder in GameListing.folders {
            let base = "/dev_hdd0/" + folder.name
            for entry in try await ftp.list(base) {
                if !entry.isDirectory, entry.name.hasSuffix(".part") {
                    parts.append((base + "/" + entry.name, entry.size))
                } else if entry.isDirectory, !folder.holdsFolders {
                    for inner in try await ftp.list(base + "/" + entry.name) where !inner.isDirectory && inner.name.hasSuffix(".part") {
                        parts.append((base + "/" + entry.name + "/" + inner.name, inner.size))
                    }
                }
            }
        }
        for part in parts {
            let original = String(part.path.dropLast(".part".count))
            let waiting = queued.contains(original)
            report.findings.append(MaintenanceFinding(
                kind: .partialUpload, title: (original as NSString).lastPathComponent,
                detail: waiting ? "A transfer that resumes when the queue runs." : "A transfer that never finished. It does not show in the XMB.",
                path: part.path, size: part.size, canFix: !waiting))
        }
        if packages.isEmpty, parts.isEmpty { report.passed.append("No leftover packages or unfinished transfers") }

        let byID = Dictionary(grouping: games.filter { !$0.isInstalled && $0.platform == .ps3 && $0.titleID != nil }, by: { $0.titleID! })
        let duplicates = byID.filter { $0.value.count > 1 }.sorted { $0.key < $1.key }
        for (id, copies) in duplicates {
            report.findings.append(MaintenanceFinding(
                kind: .duplicate, title: copies[0].title,
                detail: "\(id) is there \(copies.count) times: " + copies.map(\.path).joined(separator: ", ") + ". Delete the one you don't need in the Games tab.",
                size: copies.dropFirst().compactMap(\.size).reduce(0, +)))
        }
        if duplicates.isEmpty { report.passed.append("No games that are there twice") }

        events("boot_plugins")
        var missing = 0
        for list in ["/dev_hdd0/boot_plugins.txt", "/dev_hdd0/boot_plugins_kernel.txt"] {
            guard let data = try await ftp.download(list, limit: 1 << 20) else { continue }
            for plugin in Self.pluginPaths(in: String(decoding: data, as: UTF8.self)) {
                guard try await ftp.size(plugin) == nil else { continue }
                missing += 1
                report.findings.append(MaintenanceFinding(
                    kind: .missingPlugin, title: (plugin as NSString).lastPathComponent,
                    detail: "\((list as NSString).lastPathComponent) points to \(plugin), which does not exist. PS3 Center never changes the list; remove the line yourself.",
                    path: plugin))
            }
        }
        if missing == 0 { report.passed.append("Every plugin in boot_plugins exists") }

        events("HEN")
        let toggles = try await ftp.list("/dev_hdd0/hen/toggles").filter { !$0.isDirectory }.map(\.name)
        if !toggles.isEmpty {
            report.findings.append(MaintenanceFinding(
                kind: .henToggles, title: "HEN settings",
                detail: "Files in /dev_hdd0/hen/toggles: " + toggles.joined(separator: ", ") + ". For information only.",
                path: "/dev_hdd0/hen/toggles"))
        }
        return report
    }

    /// The lines of a boot_plugins list that name a plugin file.
    static func pluginPaths(in text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("/") }
    }

    /// Removes what can be removed (`canFix`); the rest is skipped with the reason. Logged.
    public func fix(_ findings: [MaintenanceFinding], events: @Sendable (String) -> Void = { _ in }) async throws -> [(finding: MaintenanceFinding, skipped: String?)] {
        try await TransferService(host: host).withFTP { ftp in
            var results: [(finding: MaintenanceFinding, skipped: String?)] = []
            for finding in findings {
                guard finding.canFix, let path = finding.path else {
                    results.append((finding, "advice only"))
                    continue
                }
                events("Deleting \(finding.title)")
                do {
                    try await ftp.delete(path)
                    OperationLog.record(.delete, path)
                    results.append((finding, nil))
                } catch {
                    results.append((finding, error.localizedDescription))
                }
            }
            return results
        }
    }
}
