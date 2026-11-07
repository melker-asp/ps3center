import ArgumentParser
import Foundation
import PS3Kit

struct Apps: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Homebrew on the PS3: versions, updates and package installation.",
        subcommands: [List.self, Available.self, Mac.self, Info.self, Update.self, Install.self, Uninstall.self, Ignore.self, Unignore.self],
        defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "Show installed apps and whether newer versions exist."
        )

        @OptionGroup var global: GlobalOptions

        @Flag(name: .long, help: "Print JSON.")
        var json = false

        func run() async throws {
            let asJSON = json || !UI.isTTY
            let host = try await Console.host(global, quiet: asJSON)
            if !asJSON { UI.progress("Checking versions on the PS3 and GitHub…") }
            let statuses = try await AppsService(host: host).check()
            if asJSON { UI.json(statuses); return }
            UI.endProgress()
            Apps.render(statuses)
            if statuses.contains(where: { $0.canInstall && !$0.ignored }) {
                print("\n  Run " + UI.paint("ps3 apps update", .bold) + " to review and install.")
            }
        }
    }

    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Review and install updates. Asks per app unless --yes is given.",
            discussion: "HEN and plugins are never installed automatically – they only show advice."
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Update only these (e.g. apollo pkgi), even ignored ones. Leave out for all except the ignored.")
        var names: [String] = []

        @Flag(name: [.short, .long], help: "Answer yes to all questions.")
        var yes = false

        @Flag(name: .long, help: "Show what would be installed without doing it.")
        var dryRun = false

        @Flag(name: .long, help: "Install even if a game is running.")
        var force = false

        func run() async throws {
            let host = try await Console.host(global)
            var entries = Catalog.entries
            if !names.isEmpty {
                entries = try names.map(Apps.resolve)
            }
            UI.progress("Checking versions on the PS3 and GitHub…")
            let statuses = try await AppsService(host: host).check(entries: entries)
            UI.endProgress()

            // The same plan as the app's Update All. An ignored update is left out unless it was named.
            let plan = UpdatePlan(statuses, includingIgnored: !names.isEmpty)
            for skip in plan.skipped {
                let status = skip.status
                if status.ignored {
                    UI.skip("\(status.name) \(status.latestForDisplay ?? "") is ignored  (ps3 apps unignore \(status.id))")
                    continue
                }
                UI.warn("\(status.name) \(status.versionChange): \(skip.reason)")
                if status.skip == .notAutomatic, let advice = status.note { print("      " + UI.paint(advice, .gray)) }
            }
            let installable = plan.installs
            guard !installable.isEmpty else {
                UI.ok("Everything that can be updated automatically is already up to date.")
                return
            }

            UI.header(dryRun ? "Preview" : "Updates", detail: "\(installable.count)")
            for status in installable where status.compatibility.verdict == .untested {
                UI.warn("\(status.name): \(status.compatibility.summary).")
            }
            guard let root = MirrorRoot.resolve() else {
                throw PS3Error.invalidFile("Cannot find the PS3 folder (with dev_hdd0/ and _Installed/). Set it with `ps3 config set root <path>`.")
            }
            let archive = MirrorRoot.packageArchive(in: root)
            var options = TransferOptions()
            options.force = force
            options.dryRun = dryRun
            let printer = TransferPrinter(dryRun: dryRun)
            var installed = 0
            for status in installable {
                let size = status.assetSize.map { " (\(Format.bytes($0)))" } ?? ""
                let line = "\(status.name) \(status.versionChange)\(size)"
                if dryRun {
                    UI.step(line + UI.paint("  \(status.assetName ?? "")", .gray))
                    continue
                }
                guard yes || UI.confirm("Install \(line)?", defaultYes: true) else {
                    UI.skip("\(status.name) skipped")
                    continue
                }
                try await AppsService(host: host).update(status, archive: archive, options: options) { printer.handle($0) }
                if let note = status.note { UI.warn(note) }
                installed += 1
            }
            if !dryRun, installed > 0 {
                try? await WebMAN(host: host).popup("\(UI.count(installed, "app")) updated from the Mac")
            }
        }
    }

    struct Available: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show homebrew that can be installed straight from GitHub, and what you already have."
        )

        @OptionGroup var global: GlobalOptions

        @Flag(name: .long, help: "Print JSON.")
        var json = false

        func run() async throws {
            let asJSON = json || !UI.isTTY
            let host = try await Console.host(global, quiet: asJSON)
            if !asJSON { UI.progress("Fetching the catalog…") }
            let statuses = try await AppsService(host: host).check().filter(\.isListed)
            if asJSON { UI.json(statuses); return }
            UI.endProgress()
            for category in CatalogEntry.Category.allCases {
                let rows = statuses.filter { $0.category == category }
                guard !rows.isEmpty else { continue }
                UI.header(category.label, detail: "\(rows.count)")
                for s in rows {
                    let name = s.name.padding(toLength: 24, withPad: " ", startingAt: 0)
                    let marker: String
                    let version: String
                    var plain: String
                    switch (s.installed, s.state) {
                    case (.none, _) where s.blocked:
                        marker = UI.paint("⊘", .red)
                        plain = "does not work"
                        version = UI.paint(plain, .red)
                    case (.some(let v), .updateAvailable) where s.ignored:
                        marker = UI.paint("↑", .gray)
                        plain = "\(v) → \(s.latestForDisplay ?? "?")"
                        version = UI.paint(plain, .gray)
                    case (.some(let v), .updateAvailable):
                        marker = UI.paint("↑", .yellow)
                        plain = "\(v) → \(s.latestForDisplay ?? "?")"
                        version = "\(v) → " + UI.paint(s.latestForDisplay ?? "?", .yellow)
                    case (.some(let v), _):
                        marker = UI.paint("✓", .green)
                        plain = v
                        version = UI.paint(v, .gray)
                    case (.none, _):
                        marker = UI.paint("↓", .cyan)
                        plain = s.latest ?? ""
                        version = UI.paint(plain, .cyan)
                    }
                    let pad = String(repeating: " ", count: max(1, 18 - plain.count))
                    let id = UI.paint(s.id.padding(toLength: 13, withPad: " ", startingAt: 0), .gray)
                    let detail = s.blocked ? s.compatibility.summary
                        : s.ignored ? "ignored: \(s.summary)"
                        : s.isNewRelease() ? "new version: \(s.summary)" : s.summary
                    print("  \(marker) \(name)\(id)\(version)\(pad)" + UI.paint(detail, .gray))
                }
                print()
            }
            print("  Install with " + UI.paint("ps3 apps install <name>", .bold) + ", e.g. " + UI.paint("ps3 apps install ezremote", .bold) + ".")
            print("  More about an app: " + UI.paint("ps3 apps info <name>", .bold) + ".")
        }
    }

    struct Install: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Install homebrew on the PS3 – by name from the catalog or from a .pkg file.",
            discussion: """
            ps3 apps install ezremote        Installs the latest version from GitHub
            ps3 apps install X.pkg           Installs a file of your own
            ps3 apps install RetroArch.pkg   A package in a package folder (see ps3 apps mac)
            Packages are archived in _Installed/Packages (older versions of the
            same app go to the Trash). Packages in the package folders (ps3
            config folder add PKG) stay where they are. See `ps3 apps
            available` for what is on offer.
            """
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "App names (see ps3 apps available), .pkg files or packages in the package folders (see ps3 apps mac).",
                  completion: .file(extensions: ["pkg"]))
        var items: [String]

        @Flag(name: .long, help: "Install even if the same version is already installed.")
        var reinstall = false

        @Flag(name: .long, help: "Leave your own .pkg files where they are instead of archiving them.")
        var keep = false

        @Flag(name: .long, help: "Show what would happen without doing it.")
        var dryRun = false

        @Flag(name: .long, help: "Install even if a game is running.")
        var force = false

        enum Item {
            case file(URL)
            case catalog(CatalogEntry)
        }

        func run() async throws {
            func catalogItem(_ entry: CatalogEntry) throws -> Item {
                guard entry.isInstallable else {
                    if case .notifyOnly(let note) = entry.action { throw PS3Error.invalidFile("\(entry.name) is not installed automatically. \(note)") }
                    throw PS3Error.invalidFile("\(entry.name) cannot be installed automatically. See \(entry.homepage)")
                }
                return .catalog(entry)
            }
            // A file, then a program in the catalog, then a package in the package folders.
            let resolved: [Item] = try items.map { item in
                let url = URL(fileURLWithPath: (item as NSString).expandingTildeInPath).standardizedFileURL
                if FileManager.default.fileExists(atPath: url.path) {
                    guard PKGInfo(url: url) != nil else { throw PS3Error.invalidFile("\(url.lastPathComponent) is not a valid PS3 package.") }
                    return .file(url)
                }
                let isFileName = item.lowercased().hasSuffix(".pkg")
                if !isFileName, case .found(let entry) = Catalog.lookup(item) { return try catalogItem(entry) }
                if let package = try Apps.localPackage(item) { return .file(package.url) }
                if isFileName { throw PS3Error.invalidFile("Cannot find \(item), neither as a file nor in the package folders (see ps3 apps mac).") }
                return try catalogItem(Apps.resolve(item))
            }

            let host = try await Console.host(global)
            let root = MirrorRoot.resolve()
            var options = TransferOptions()
            options.force = force
            options.dryRun = dryRun
            let printer = TransferPrinter(dryRun: dryRun)
            let apps = AppsService(host: host)
            UI.header(dryRun ? "Preview" : "Installing", detail: "\(resolved.count)")

            var installedNames: [String] = []
            var blocked = 0
            for item in resolved {
                switch item {
                case .file(let file):
                    // The same checks as the app's From Mac: a valid package, and a catalog app's
                    // requirements, as when it is installed by name.
                    do {
                        try await apps.installOwnPackage(file, options: options) { printer.handle($0) }
                    } catch PS3Error.incompatible(let message) {
                        UI.fail(message)
                        blocked += 1
                        continue
                    }
                    installedNames.append(file.deletingPathExtension().lastPathComponent)
                    guard !dryRun, !keep, let root, let moved = try apps.archiveLoosePackage(file, root: root) else { continue }
                    UI.skip("Archived in \(moved.path.replacingOccurrences(of: root.path + "/", with: ""))")

                case .catalog(let entry):
                    let compatibility = try await apps.compatibility(of: entry)
                    if compatibility.blocksInstall {
                        UI.fail("\(entry.name) does not work on your PS3: \(compatibility.summary).")
                        blocked += 1
                        continue
                    }
                    if !reinstall, let current = try await apps.check(entries: [entry]).first,
                       let version = current.installed, current.state == .upToDate {
                        UI.skip("\(entry.name) is already installed (\(version)). Use --reinstall to install again.")
                        continue
                    }
                    guard let root else {
                        throw PS3Error.invalidFile("Cannot find the PS3 folder (with dev_hdd0/ and _Installed/). Set it with `ps3 config set root <path>`.")
                    }
                    try await apps.install(entry, archive: MirrorRoot.packageArchive(in: root), options: options) { printer.handle($0) }
                    installedNames.append(entry.name)
                }
            }
            if !dryRun, !installedNames.isEmpty {
                try? await WebMAN(host: host).popup(installedNames.count == 1 ? "\(installedNames[0]) installed" : "\(installedNames.count) apps installed")
            }
            if blocked > 0 { throw ExitCode.failure }
        }
    }

    struct Info: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show everything about an app: version, whether it works on your PS3, and the README from GitHub.",
            discussion: """
            ps3 apps info apollo             Status, compatibility and README
            ps3 apps info pkgi --no-readme   Only status and compatibility
            """
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "App name (see ps3 apps available).")
        var name: String

        @Flag(name: .long, help: "Skip the README.")
        var noReadme = false

        @Flag(name: .long, help: "Print JSON.")
        var json = false

        struct Output: Encodable {
            let status: AppStatus
            let console: ConsoleProfile
            let repository: String?
            let readme: Readme?
            let readmeError: String?
        }

        func run() async throws {
            let asJSON = json || !UI.isTTY
            let entry = try Apps.resolve(name)
            let host = try await Console.host(global, quiet: asJSON)
            if !asJSON { UI.progress("Checking \(entry.name) on the PS3 and GitHub…") }
            let skipReadme = noReadme
            async let readmeResult = Self.fetchReadme(entry, skip: skipReadme)
            guard let status = try await AppsService(host: host).check(entries: [entry]).first else { return }
            let profile = ConsoleProfile(snapshot: try await WebMAN(host: host).snapshot())
            let readme = await readmeResult
            if asJSON {
                var readmeError: String?
                if case .failure(let error) = readme { readmeError = error.localizedDescription }
                UI.json(Output(status: status, console: profile, repository: entry.repository,
                               readme: try? readme?.get(), readmeError: readmeError))
                return
            }
            UI.endProgress()
            Apps.renderInfo(entry: entry, status: status, console: profile)
            switch readme {
            case .none:
                break
            case .some(.failure(let error)):
                print()
                UI.warn("README: \(error.localizedDescription)")
            case .some(.success(let readme)):
                print()
                UI.header("README", detail: readme.repo)
                Apps.render(readme)
            }
        }

        static func fetchReadme(_ entry: CatalogEntry, skip: Bool) async -> Result<Readme, Error>? {
            guard !skip, let repo = entry.repository else { return nil }
            do { return .success(try await GitHub.readme(repo: repo)) } catch { return .failure(error) }
        }
    }

    static func resolve(_ name: String) throws -> CatalogEntry {
        switch Catalog.lookup(name) {
        case .found(let entry): return entry
        case .ambiguous(let matches):
            throw PS3Error.invalidFile("\(name) could mean several: \(matches.map(\.id).joined(separator: ", ")).")
        case .missing:
            throw PS3Error.invalidFile("Unknown app: \(name). See `ps3 apps available` for what is on offer.")
        }
    }

    /// A package in the package folders by file name (with or without .pkg) or title ID.
    static func localPackage(_ name: String) throws -> LocalPackage? {
        let query = name.lowercased()
        let matches = PackageLibrary.scan().filter {
            $0.fileName.lowercased() == query || ($0.fileName as NSString).deletingPathExtension.lowercased() == query
                || $0.titleID?.lowercased() == query
        }
        guard matches.count <= 1 else {
            throw PS3Error.invalidFile("\(name) could mean several packages: \(matches.map(\.path).joined(separator: ", ")). Give the full path.")
        }
        return matches.first
    }

    struct Mac: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "mac",
            abstract: "The packages (.pkg) in the Mac's package folders and whether they are already installed on the PS3.",
            discussion: """
            Link a folder with `ps3 config folder add PKG ~/Packages`. PS3
            Center looks in the folder and the folders directly under it.
            Install with `ps3 apps install <file name>`; the package stays in
            the folder.
            """
        )

        @OptionGroup var global: GlobalOptions

        @Flag(name: .long, help: "Only packages that are not installed.")
        var missing = false

        @Flag(name: .long, help: "Do not ask the PS3.")
        var offline = false

        @Flag(name: .long, help: "Print JSON.")
        var json = false

        struct Row: Encodable {
            let package: LocalPackage
            /// APP_VER on the console ("" without one), nil when not installed or not asked.
            let installed: String?
        }

        func run() async throws {
            let asJSON = json || !UI.isTTY
            let folders = PackageFolders.linked()
            guard !folders.isEmpty else {
                if asJSON { UI.json([Row]()); return }
                UI.skip("No package folders. Link one with `ps3 config folder add PKG ~/Packages`.")
                return
            }
            if !asJSON { UI.progress("Reading the Mac's package folders…") }
            let packages = PackageLibrary.scan(folders: folders)
            var installed: [String: String]?
            if !offline, !packages.isEmpty {
                do {
                    let host = try await Console.host(global, quiet: true)
                    if !asJSON { UI.progress("Comparing with the PS3…") }
                    installed = try await AppsService(host: host).installedVersions(of: packages.compactMap(\.titleID))
                } catch {
                    if !asJSON { UI.endProgress(); UI.warn("The PS3 is not answering, so what is already installed cannot be shown.") }
                }
            }
            var rows = packages.map { package in
                Row(package: package, installed: package.titleID.flatMap { installed?[$0.uppercased()] })
            }
            if missing, installed != nil { rows = rows.filter { $0.installed == nil } }
            if asJSON { UI.json(rows); return }
            UI.endProgress()
            guard !packages.isEmpty else {
                UI.skip("No .pkg files in the package folders (\(folders.map { ($0.path as NSString).abbreviatingWithTildeInPath }.joined(separator: ", "))).")
                return
            }
            for folder in folders {
                let group = rows.filter { $0.package.folder == folder.path }
                guard !group.isEmpty else { continue }
                UI.header((folder.path as NSString).abbreviatingWithTildeInPath,
                          detail: "\(group.count) · \(Format.bytes(group.map(\.package.size).reduce(0, +)))")
                for row in group {
                    let marker = installed == nil ? " " : row.installed == nil ? UI.paint("↑", .cyan) : UI.paint("✓", .green)
                    let title = row.package.title.count > 34 ? String(row.package.title.prefix(33)) + "…" : row.package.title
                    print("  \(marker) \(title.padding(toLength: 36, withPad: " ", startingAt: 0))"
                          + UI.paint((row.package.titleID ?? "").padding(toLength: 12, withPad: " ", startingAt: 0), .gray)
                          + Format.bytes(row.package.size).padding(toLength: 11, withPad: " ", startingAt: 0)
                          + (installed == nil ? "" : UI.paint(PackageLibrary.installedLabel(row.installed), .gray)))
                    print("    " + UI.paint(String(row.package.path.dropFirst(folder.path.count + 1)), .gray))
                }
                print()
            }
            print("  Install with " + UI.paint("ps3 apps install <file name>", .bold) + ". The package stays in the folder.")
        }
    }

    static func renderInfo(entry: CatalogEntry, status: AppStatus, console: ConsoleProfile) {
        UI.header(entry.name, detail: entry.category.label)
        UI.row("About", entry.summary)
        if let repo = entry.repository { UI.row("Source", "https://github.com/\(repo)") } else { UI.row("Source", entry.homepage) }
        UI.row("Installed", status.installed ?? UI.paint("no", .gray))
        if let tag = status.latest {
            // "02.41 (v2.4.1)": the console's form first, the release tag after it when they differ.
            let shown = status.latestForDisplay ?? tag
            let release = shown == tag ? "" : UI.paint("  (release \(tag))", .gray)
            if status.ignored {
                UI.row("Latest", shown + release + UI.paint("  (ignored, show again with ps3 apps unignore \(entry.id))", .gray))
            } else {
                UI.row("Latest", (status.state == .updateAvailable ? UI.paint(shown, .bold, .yellow) : shown) + release)
            }
        }
        UI.row("Your PS3", console.label)
        let compatibility = status.compatibility
        switch compatibility.verdict {
        case .compatible: UI.row("Works", UI.paint("✓ ", .green) + compatibility.summary)
        case .untested: UI.row("Works", UI.paint("! ", .yellow) + compatibility.summary)
        case .incompatible, .unknown: UI.row("Works", UI.paint("✗ ", .red) + compatibility.summary + UI.paint("  (will not be installed)", .gray))
        }
        if let note = status.note { UI.row("Note", UI.paint(note, .gray)) }
        if status.installable, status.installed == nil {
            print("\n  Install with " + UI.paint("ps3 apps install \(entry.id)", .bold) + ".")
        } else if status.canInstall {
            print("\n  Update with " + UI.paint("ps3 apps update \(entry.id)", .bold) + ".")
        }
    }

    /// README as terminal text: bold headings, bullets, code in grey, images as links.
    static func render(_ readme: Readme) {
        let width = 92
        func wrap(_ text: String, indent: String, first: String? = nil) {
            for (index, paragraph) in Readme.plainText(text).components(separatedBy: "\n").enumerated() {
                var line = index == 0 ? (first ?? indent) : indent
                var lineLength = line.count
                for word in paragraph.split(separator: " ") {
                    if lineLength + word.count > width, lineLength > indent.count {
                        print(line)
                        line = indent
                        lineLength = indent.count
                    }
                    line += word + " "
                    lineLength += word.count + 1
                }
                print(line)
            }
        }
        for block in readme.blocks {
            switch block {
            case .heading(let level, let text):
                print()
                let title = Readme.plainText(text)
                print("  " + (level <= 2 ? UI.paint(title, .bold, .cyan) : UI.paint(title, .bold)))
            case .paragraph(let text):
                wrap(text, indent: "  ")
                print()
            case .list(let items, let ordered):
                for (index, item) in items.enumerated() {
                    let pad = String(repeating: "  ", count: item.depth + 1)
                    let bullet = ordered && item.depth == 0 ? "\(index + 1). " : "• "
                    wrap(item.text, indent: pad + String(repeating: " ", count: bullet.count), first: pad + bullet)
                }
                print()
            case .quote(let text):
                wrap(text, indent: "  " + UI.paint("│ ", .gray))
                print()
            case .code(let code):
                for line in code.components(separatedBy: "\n") { print("    " + UI.paint(line, .gray)) }
                print()
            case .image(let image):
                print("  " + UI.paint("▣ \(image.alt.isEmpty ? "Image" : image.alt): \(image.url.absoluteString)", .gray))
            case .table(let rows):
                for (index, row) in rows.enumerated() {
                    let line = row.map(Readme.plainText).joined(separator: "  ·  ")
                    print("  " + (index == 0 ? UI.paint(line, .bold) : line))
                }
                print()
            case .rule:
                print("  " + UI.paint(String(repeating: "─", count: 40), .gray))
            }
        }
        if let url = readme.htmlURL { print("  " + UI.paint("Full README: \(url.absoluteString)", .gray)) }
    }

    static func render(_ statuses: [AppStatus]) {
        let groups = AppGroups(statuses)
        let (updates, ignored, current, manual, missing) = (groups.updates, groups.ignored, groups.current, groups.manual, groups.missing)

        func name(_ s: AppStatus) -> String { s.name.padding(toLength: 22, withPad: " ", startingAt: 0) }

        if !updates.isEmpty {
            UI.header("Updates", detail: "\(updates.count)")
            for s in updates {
                let arrow = "\(s.installed ?? "?") → " + UI.paint(s.latestForDisplay ?? "?", .bold, .yellow)
                let tag = s.canInstall ? "" : UI.paint("  manual", .gray)
                print("  " + UI.paint("↑", .yellow) + " " + name(s) + arrow + tag)
                if !s.canInstall, let note = s.note { print("      " + UI.paint(note, .gray)) }
            }
            print()
        }
        UI.header("Up to Date", detail: "\(current.count)")
        for s in current { UI.ok(name(s) + UI.paint(s.installed ?? "", .gray)) }
        if !manual.isEmpty {
            print()
            UI.header("Check Manually", detail: "\(manual.count)")
            for s in manual { UI.skip(name(s) + (s.installed ?? "") + "  " + (s.note ?? "")) }
        }
        if !ignored.isEmpty {
            print()
            UI.header("Ignored", detail: "\(ignored.count)")
            for s in ignored {
                UI.skip(name(s) + "\(s.versionChange)  ps3 apps unignore \(s.id)")
            }
        }
        if !missing.isEmpty {
            print()
            UI.header("Not Installed", detail: "\(missing.count)")
            for s in missing {
                UI.skip(name(s) + (s.blocked ? "does not work on your PS3: \(s.compatibility.summary)" : s.latest.map { "latest \($0)" } ?? ""))
            }
        }
    }
}

extension Apps {
    struct Uninstall: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Uninstall an app (its folder in /dev_hdd0/game). Not HEN, webMAN or plugins.",
            discussion: "The app's save files stay, and it can be installed again with `ps3 apps install`."
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "App name (see ps3 apps).")
        var name: String

        @Flag(name: [.short, .long], help: "Do not ask.")
        var yes = false

        @Flag(name: .long, help: "Show what would happen.")
        var dryRun = false

        func run() async throws {
            let entry = try Apps.resolve(name)
            let host = try await Console.host(global)
            var options = TransferOptions()
            options.dryRun = dryRun
            if !dryRun {
                guard yes || UI.confirm("Uninstall \(entry.name) from the PS3?") else { return }
            }
            let printer = TransferPrinter(dryRun: dryRun)
            try await AppsService(host: host).uninstall(entry, options: options) { printer.handle($0) }
        }
    }
}

extension Apps {
    struct Ignore: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Skip the latest version of an app. Without a name, shows what is ignored.",
            discussion: """
            ps3 apps ignore artemis          Stop showing Artemis's latest as an update
            ps3 apps ignore                  List what is ignored
            This only applies to that version: if a newer one comes out, the
            update shows again. Only the Mac's settings change (ignoredUpdates
            in config.json), never the console. `ps3 apps update` skips what
            is ignored, except when the app is given by name.
            """
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "App name (see ps3 apps).")
        var names: [String] = []

        func run() async throws {
            guard !names.isEmpty else {
                let ignored = IgnoredUpdates.load()
                guard !ignored.isEmpty else {
                    UI.ok("No updates are ignored.")
                    return
                }
                UI.header("Ignored", detail: "\(ignored.count)")
                for (id, version) in ignored.sorted(by: { $0.key < $1.key }) {
                    let name = Catalog.entries.first { $0.id == id }?.name ?? id
                    UI.skip(name.padding(toLength: 22, withPad: " ", startingAt: 0) + version)
                }
                print("\n  Show again with " + UI.paint("ps3 apps unignore <name>", .bold) + ".")
                return
            }
            let entries = try names.map(Apps.resolve)
            let host = try await Console.host(global)
            UI.progress("Checking versions on the PS3 and GitHub…")
            let statuses = try await AppsService(host: host).check(entries: entries)
            UI.endProgress()
            for status in statuses {
                guard status.state == .updateAvailable, let latest = status.latest else {
                    UI.skip("\(status.name) has no update to ignore.")
                    continue
                }
                try IgnoredUpdates.ignore(status.id, version: latest)
                UI.ok("\(status.name) \(latest) is ignored. If a newer version comes out, it shows again.")
            }
        }
    }

    struct Unignore: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show an app's updates again after ps3 apps ignore."
        )

        @Argument(help: "App name (see ps3 apps ignore).")
        var names: [String]

        func run() throws {
            for name in names {
                let entry = try Apps.resolve(name)
                if try IgnoredUpdates.unignore(entry.id) {
                    UI.ok("\(entry.name) shows again when there is an update.")
                } else {
                    UI.skip("\(entry.name) was not ignored.")
                }
            }
        }
    }
}
