import ArgumentParser
import Foundation
import PS3Kit

struct Apps: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Homebrew på PS3:an: versioner, uppdateringar och installation av paket.",
        subcommands: [List.self, Available.self, Mac.self, Info.self, Update.self, Install.self, Uninstall.self, Ignore.self, Unignore.self],
        defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "Visa installerade program och om det finns nyare versioner (standard)."
        )

        @OptionGroup var global: GlobalOptions

        @Flag(name: .long, help: "Skriv ut JSON.")
        var json = false

        func run() async throws {
            let asJSON = json || !UI.isTTY
            let host = try await Console.host(global, quiet: asJSON)
            if !asJSON { UI.progress("Kollar versioner på PS3:an och GitHub…") }
            let statuses = try await AppsService(host: host).check()
            if asJSON { UI.json(statuses); return }
            UI.endProgress()
            Apps.render(statuses)
            if statuses.contains(where: { $0.canInstall && !$0.ignored }) {
                print("\n  Kör " + UI.paint("ps3 apps update", .bold) + " för att granska och installera.")
            }
        }
    }

    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Granska och installera uppdateringar. Frågar per program om inte --yes anges.",
            discussion: "HEN och plugins installeras aldrig automatiskt – de visas bara med råd."
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Uppdatera bara dessa (t.ex. apollo pkgi), även ignorerade. Utelämna för alla utom de ignorerade.")
        var names: [String] = []

        @Flag(name: [.short, .long], help: "Svara ja på alla frågor.")
        var yes = false

        @Flag(name: .long, help: "Visa vad som skulle installeras utan att göra det.")
        var dryRun = false

        @Flag(name: .long, help: "Installera även om ett spel körs.")
        var force = false

        func run() async throws {
            let host = try await Console.host(global)
            var entries = Catalog.entries
            if !names.isEmpty {
                entries = try names.map(Apps.resolve)
            }
            UI.progress("Kollar versioner på PS3:an och GitHub…")
            let statuses = try await AppsService(host: host).check(entries: entries)
            UI.endProgress()

            // An ignored update is left out unless it was named.
            let skipsIgnored = names.isEmpty
            for status in statuses where skipsIgnored && status.ignored {
                UI.skip("\(status.name) \(status.latest ?? "") ignoreras  (ps3 apps unignore \(status.id))")
            }
            let installable = statuses.filter { $0.canInstall && !(skipsIgnored && $0.ignored) }
            let advisories = statuses.filter { $0.state == .updateAvailable && !$0.canInstall && !(skipsIgnored && $0.ignored) }
            for status in advisories {
                UI.warn("\(status.name) \(status.installed ?? "?") → \(status.latest ?? "?"): \(status.note ?? "uppdatera manuellt")")
            }
            guard !installable.isEmpty else {
                UI.ok("Allt som kan uppdateras automatiskt är redan aktuellt.")
                return
            }

            UI.header(dryRun ? "Förhandsvisning" : "Uppdateringar", detail: "\(installable.count) st")
            for status in installable where status.compatibility.verdict == .untested {
                UI.warn("\(status.name): \(status.compatibility.summary).")
            }
            guard let root = MirrorRoot.resolve() else {
                throw PS3Error.invalidFile("Hittar inte PS3-mappen (med dev_hdd0/ och _Installerat/). Ange den med `ps3 config set root <sökväg>`.")
            }
            let archive = MirrorRoot.packageArchive(in: root)
            var options = TransferOptions()
            options.force = force
            options.dryRun = dryRun
            let printer = TransferPrinter(dryRun: dryRun)
            var installed = 0
            for status in installable {
                let size = status.assetSize.map { " (\(Format.bytes($0)))" } ?? ""
                let line = "\(status.name) \(status.installed ?? "?") → \(status.latest ?? "?")\(size)"
                if dryRun {
                    UI.step(line + UI.paint("  \(status.assetName ?? "")", .gray))
                    continue
                }
                guard yes || UI.confirm("Installera \(line)?", defaultYes: true) else {
                    UI.skip("\(status.name) hoppades över")
                    continue
                }
                try await AppsService(host: host).update(status, archive: archive, options: options) { printer.handle($0) }
                if let note = status.note { UI.warn(note) }
                installed += 1
            }
            if !dryRun, installed > 0 {
                try? await WebMAN(host: host).popup("\(installed) program uppdaterade från Macen")
            }
        }
    }

    struct Available: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Visa homebrew som kan installeras direkt från GitHub, och vad du redan har."
        )

        @OptionGroup var global: GlobalOptions

        @Flag(name: .long, help: "Skriv ut JSON.")
        var json = false

        func run() async throws {
            let asJSON = json || !UI.isTTY
            let host = try await Console.host(global, quiet: asJSON)
            if !asJSON { UI.progress("Hämtar katalogen…") }
            let statuses = try await AppsService(host: host).check().filter { $0.installable || $0.installed != nil || $0.blocked }
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
                        plain = "fungerar inte"
                        version = UI.paint(plain, .red)
                    case (.some(let v), .updateAvailable) where s.ignored:
                        marker = UI.paint("↑", .gray)
                        plain = "\(v) → \(s.latest ?? "?")"
                        version = UI.paint(plain, .gray)
                    case (.some(let v), .updateAvailable):
                        marker = UI.paint("↑", .yellow)
                        plain = "\(v) → \(s.latest ?? "?")"
                        version = "\(v) → " + UI.paint(s.latest ?? "?", .yellow)
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
                        : s.ignored ? "ignorerad: \(s.summary)"
                        : s.isNewRelease() ? "ny version: \(s.summary)" : s.summary
                    print("  \(marker) \(name)\(id)\(version)\(pad)" + UI.paint(detail, .gray))
                }
                print()
            }
            print("  Installera med " + UI.paint("ps3 apps install <namn>", .bold) + ", t.ex. " + UI.paint("ps3 apps install ezremote", .bold) + ".")
            print("  Mer om ett program: " + UI.paint("ps3 apps info <namn>", .bold) + ".")
        }
    }

    struct Install: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Installera homebrew på PS3:an – via namn från katalogen eller en .pkg-fil.",
            discussion: """
            ps3 apps install ezremote        Hämtar senaste versionen från GitHub och installerar den
            ps3 apps install X.pkg           Installerar en egen fil
            ps3 apps install RetroArch.pkg   Ett paket i paketmapparna, via filnamn eller title ID (se ps3 apps mac)
            Paketen arkiveras i _Installerat/Paket (äldre versioner av samma program läggs i papperskorgen).
            Paket i paketmapparna (ps3 config folder add PKG) ligger kvar där de är.
            Se `ps3 apps available` för vad som finns.
            """
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Programnamn (se ps3 apps available), .pkg-filer eller paket i paketmapparna (se ps3 apps mac).",
                  completion: .file(extensions: ["pkg"]))
        var items: [String]

        @Flag(name: .long, help: "Installera även om samma version redan är installerad.")
        var reinstall = false

        @Flag(name: .long, help: "Låt egna .pkg-filer ligga kvar där de är i stället för att arkivera dem.")
        var keep = false

        @Flag(name: .long, help: "Visa vad som skulle hända utan att göra det.")
        var dryRun = false

        @Flag(name: .long, help: "Installera även om ett spel körs.")
        var force = false

        enum Item {
            case file(URL)
            case catalog(CatalogEntry)
        }

        func run() async throws {
            func catalogItem(_ entry: CatalogEntry) throws -> Item {
                guard entry.isInstallable else {
                    if case .notifyOnly(let note) = entry.action { throw PS3Error.invalidFile("\(entry.name) installeras inte automatiskt. \(note)") }
                    throw PS3Error.invalidFile("\(entry.name) kan inte installeras automatiskt. Se \(entry.homepage)")
                }
                return .catalog(entry)
            }
            // A file, then a program in the catalog, then a package in the package folders.
            let resolved: [Item] = try items.map { item in
                let url = URL(fileURLWithPath: (item as NSString).expandingTildeInPath).standardizedFileURL
                if FileManager.default.fileExists(atPath: url.path) {
                    guard PKGInfo(url: url) != nil else { throw PS3Error.invalidFile("\(url.lastPathComponent) är inget giltigt PS3-paket.") }
                    return .file(url)
                }
                let isFileName = item.lowercased().hasSuffix(".pkg")
                if !isFileName, case .found(let entry) = Catalog.lookup(item) { return try catalogItem(entry) }
                if let package = try Apps.localPackage(item) { return .file(package.url) }
                if isFileName { throw PS3Error.invalidFile("Hittar inte \(item), varken som fil eller i paketmapparna (se ps3 apps mac).") }
                return try catalogItem(Apps.resolve(item))
            }

            let host = try await Console.host(global)
            let root = MirrorRoot.resolve()
            var options = TransferOptions()
            options.force = force
            options.dryRun = dryRun
            let printer = TransferPrinter(dryRun: dryRun)
            let apps = AppsService(host: host)
            UI.header(dryRun ? "Förhandsvisning" : "Installerar", detail: "\(resolved.count) st")

            var installedNames: [String] = []
            var blocked = 0
            for item in resolved {
                switch item {
                case .file(let file):
                    // A package from the catalog gets the same safety check as when installed by name.
                    if let known = try await apps.checkPackage(file) {
                        if known.compatibility.blocksInstall {
                            UI.fail("\(file.lastPathComponent) (\(known.entry.name)) fungerar inte på din PS3: \(known.compatibility.summary).")
                            blocked += 1
                            continue
                        }
                        if known.compatibility.verdict == .untested { UI.warn("\(known.entry.name): \(known.compatibility.summary).") }
                    }
                    try await TransferService(host: host).installPackage(file, options: options) { printer.handle($0) }
                    installedNames.append(file.deletingPathExtension().lastPathComponent)
                    // A package in a package folder belongs there, like a game in a game folder.
                    guard !dryRun, !keep, !PackageFolders.contains(file), let root else { continue }
                    let archive = MirrorRoot.packageArchive(in: root)
                    if file.deletingLastPathComponent().standardizedFileURL != archive.standardizedFileURL {
                        let moved = try apps.archivePackage(file, into: archive)
                        UI.skip("Arkiverad i \(moved.path.replacingOccurrences(of: root.path + "/", with: ""))")
                    }

                case .catalog(let entry):
                    let compatibility = try await apps.compatibility(of: entry)
                    if compatibility.blocksInstall {
                        UI.fail("\(entry.name) fungerar inte på din PS3: \(compatibility.summary).")
                        blocked += 1
                        continue
                    }
                    if !reinstall, let current = try await apps.check(entries: [entry]).first,
                       let version = current.installed, current.state == .upToDate {
                        UI.skip("\(entry.name) är redan installerad (\(version)). Använd --reinstall för att installera om.")
                        continue
                    }
                    guard let root else {
                        throw PS3Error.invalidFile("Hittar inte PS3-mappen (med dev_hdd0/ och _Installerat/). Ange den med `ps3 config set root <sökväg>`.")
                    }
                    try await apps.install(entry, archive: MirrorRoot.packageArchive(in: root), options: options) { printer.handle($0) }
                    installedNames.append(entry.name)
                }
            }
            if !dryRun, !installedNames.isEmpty {
                try? await WebMAN(host: host).popup(installedNames.count == 1 ? "\(installedNames[0]) installerat" : "\(installedNames.count) program installerade")
            }
            if blocked > 0 { throw ExitCode.failure }
        }
    }

    struct Info: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Visa allt om ett program: version, om det fungerar på din PS3 och README från GitHub.",
            discussion: """
            ps3 apps info apollo             Status, kompatibilitet och README
            ps3 apps info pkgi --no-readme   Bara status och kompatibilitet
            """
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Programnamn (se ps3 apps available).")
        var name: String

        @Flag(name: .long, help: "Hoppa över README.")
        var noReadme = false

        @Flag(name: .long, help: "Skriv ut JSON.")
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
            if !asJSON { UI.progress("Kollar \(entry.name) på PS3:an och GitHub…") }
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
            throw PS3Error.invalidFile("\(name) kan betyda flera: \(matches.map(\.id).joined(separator: ", ")).")
        case .missing:
            throw PS3Error.invalidFile("Okänt program: \(name). Se `ps3 apps available` för vad som finns.")
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
            throw PS3Error.invalidFile("\(name) kan betyda flera paket: \(matches.map(\.path).joined(separator: ", ")). Ange hela sökvägen.")
        }
        return matches.first
    }

    struct Mac: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "mac",
            abstract: "Paketen (.pkg) i Macens paketmappar och om de redan är installerade på PS3:an.",
            discussion: """
            Koppla en mapp med `ps3 config folder add PKG ~/Paket`. PS3 Center letar i mappen och
            mapparna direkt under den. Installera med `ps3 apps install <filnamn>`; paketet ligger
            kvar i mappen.
            """
        )

        @OptionGroup var global: GlobalOptions

        @Flag(name: .long, help: "Bara paket som inte är installerade.")
        var missing = false

        @Flag(name: .long, help: "Fråga inte PS3:an.")
        var offline = false

        @Flag(name: .long, help: "Skriv ut JSON.")
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
                UI.skip("Inga paketmappar. Koppla en med `ps3 config folder add PKG ~/Paket`.")
                return
            }
            if !asJSON { UI.progress("Läser Macens paketmappar…") }
            let packages = PackageLibrary.scan(folders: folders)
            var installed: [String: String]?
            if !offline, !packages.isEmpty {
                do {
                    let host = try await Console.host(global, quiet: true)
                    if !asJSON { UI.progress("Jämför med PS3:an…") }
                    installed = try await AppsService(host: host).installedVersions(of: packages.compactMap(\.titleID))
                } catch {
                    if !asJSON { UI.endProgress(); UI.warn("PS3:an svarar inte, så det syns inte vad som redan är installerat.") }
                }
            }
            var rows = packages.map { package in
                Row(package: package, installed: package.titleID.flatMap { installed?[$0.uppercased()] })
            }
            if missing, installed != nil { rows = rows.filter { $0.installed == nil } }
            if asJSON { UI.json(rows); return }
            UI.endProgress()
            guard !packages.isEmpty else {
                UI.skip("Inga .pkg-filer i paketmapparna (\(folders.map { ($0.path as NSString).abbreviatingWithTildeInPath }.joined(separator: ", "))).")
                return
            }
            for folder in folders {
                let group = rows.filter { $0.package.folder == folder.path }
                guard !group.isEmpty else { continue }
                UI.header((folder.path as NSString).abbreviatingWithTildeInPath,
                          detail: "\(group.count) st · \(Format.bytes(group.map(\.package.size).reduce(0, +)))")
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
            print("  Installera med " + UI.paint("ps3 apps install <filnamn>", .bold) + ". Paketet ligger kvar i mappen.")
        }
    }

    static func renderInfo(entry: CatalogEntry, status: AppStatus, console: ConsoleProfile) {
        UI.header(entry.name, detail: entry.category.label)
        UI.row("Om", entry.summary)
        if let repo = entry.repository { UI.row("Källa", "https://github.com/\(repo)") } else { UI.row("Källa", entry.homepage) }
        UI.row("Installerad", status.installed ?? UI.paint("nej", .gray))
        if let latest = status.latest {
            if status.ignored {
                UI.row("Senaste", latest + UI.paint("  (ignorerad, visa igen med ps3 apps unignore \(entry.id))", .gray))
            } else {
                UI.row("Senaste", status.state == .updateAvailable ? UI.paint(latest, .bold, .yellow) : latest)
            }
        }
        UI.row("Din PS3", console.label)
        let compatibility = status.compatibility
        switch compatibility.verdict {
        case .compatible: UI.row("Fungerar", UI.paint("✓ ", .green) + compatibility.summary)
        case .untested: UI.row("Fungerar", UI.paint("! ", .yellow) + compatibility.summary)
        case .incompatible, .unknown: UI.row("Fungerar", UI.paint("✗ ", .red) + compatibility.summary + UI.paint("  (installeras inte)", .gray))
        }
        if let note = status.note { UI.row("Obs", UI.paint(note, .gray)) }
        if status.installable, status.installed == nil {
            print("\n  Installera med " + UI.paint("ps3 apps install \(entry.id)", .bold) + ".")
        } else if status.canInstall {
            print("\n  Uppdatera med " + UI.paint("ps3 apps update \(entry.id)", .bold) + ".")
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
                print("  " + UI.paint("▣ \(image.alt.isEmpty ? "Bild" : image.alt): \(image.url.absoluteString)", .gray))
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
        if let url = readme.htmlURL { print("  " + UI.paint("Hela README: \(url.absoluteString)", .gray)) }
    }

    static func render(_ statuses: [AppStatus]) {
        let updates = statuses.filter(\.isPendingUpdate)
        let ignored = statuses.filter { $0.state == .updateAvailable && $0.ignored }
        let current = statuses.filter { $0.state == .upToDate }
        let manual = statuses.filter { $0.state == .manual || $0.state == .error }
        let missing = statuses.filter { $0.state == .notInstalled }

        func name(_ s: AppStatus) -> String { s.name.padding(toLength: 22, withPad: " ", startingAt: 0) }

        if !updates.isEmpty {
            UI.header("Uppdateringar", detail: "\(updates.count)")
            for s in updates {
                let arrow = "\(s.installed ?? "?") → " + UI.paint(s.latest ?? "?", .bold, .yellow)
                let tag = s.canInstall ? "" : UI.paint("  manuell", .gray)
                print("  " + UI.paint("↑", .yellow) + " " + name(s) + arrow + tag)
                if !s.canInstall, let note = s.note { print("      " + UI.paint(note, .gray)) }
            }
            print()
        }
        UI.header("Aktuella", detail: "\(current.count)")
        for s in current { UI.ok(name(s) + UI.paint(s.installed ?? "", .gray)) }
        if !manual.isEmpty {
            print()
            UI.header("Kolla manuellt", detail: "\(manual.count)")
            for s in manual { UI.skip(name(s) + (s.installed ?? "") + "  " + (s.note ?? "")) }
        }
        if !ignored.isEmpty {
            print()
            UI.header("Ignorerade", detail: "\(ignored.count)")
            for s in ignored {
                UI.skip(name(s) + "\(s.installed ?? "?") → \(s.latest ?? "?")  ps3 apps unignore \(s.id)")
            }
        }
        if !missing.isEmpty {
            print()
            UI.header("Inte installerade", detail: "\(missing.count)")
            for s in missing {
                UI.skip(name(s) + (s.blocked ? "fungerar inte på din PS3: \(s.compatibility.summary)" : s.latest.map { "senaste \($0)" } ?? ""))
            }
        }
    }
}

extension Apps {
    struct Uninstall: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Avinstallera ett program (mappen i /dev_hdd0/game). Inte HEN, webMAN eller plugins.",
            discussion: "Programmets sparfiler ligger kvar, och det går att installera igen med `ps3 apps install`."
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Programnamn (se ps3 apps).")
        var name: String

        @Flag(name: [.short, .long], help: "Fråga inte.")
        var yes = false

        @Flag(name: .long, help: "Visa vad som skulle hända.")
        var dryRun = false

        func run() async throws {
            let entry = try Apps.resolve(name)
            let host = try await Console.host(global)
            var options = TransferOptions()
            options.dryRun = dryRun
            if !dryRun {
                guard yes || UI.confirm("Avinstallera \(entry.name) från PS3:an?") else { return }
            }
            let printer = TransferPrinter(dryRun: dryRun)
            try await AppsService(host: host).uninstall(entry, options: options) { printer.handle($0) }
        }
    }
}

extension Apps {
    struct Ignore: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Hoppa över den senaste versionen av ett program. Utan namn visas vad som ignoreras.",
            discussion: """
            ps3 apps ignore artemis          Visa inte Artemis senaste version som en uppdatering
            ps3 apps ignore                  Lista det som ignoreras
            Det gäller bara den versionen: kommer en nyare visas uppdateringen igen. Bara Macens
            inställningar ändras (ignoredUpdates i config.json), aldrig konsolen. `ps3 apps update`
            hoppar över det som ignoreras, utom när programmet anges med namn.
            """
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Programnamn (se ps3 apps).")
        var names: [String] = []

        func run() async throws {
            guard !names.isEmpty else {
                let ignored = IgnoredUpdates.load()
                guard !ignored.isEmpty else {
                    UI.ok("Inga uppdateringar ignoreras.")
                    return
                }
                UI.header("Ignorerade", detail: "\(ignored.count)")
                for (id, version) in ignored.sorted(by: { $0.key < $1.key }) {
                    let name = Catalog.entries.first { $0.id == id }?.name ?? id
                    UI.skip(name.padding(toLength: 22, withPad: " ", startingAt: 0) + version)
                }
                print("\n  Visa igen med " + UI.paint("ps3 apps unignore <namn>", .bold) + ".")
                return
            }
            let entries = try names.map(Apps.resolve)
            let host = try await Console.host(global)
            UI.progress("Kollar versioner på PS3:an och GitHub…")
            let statuses = try await AppsService(host: host).check(entries: entries)
            UI.endProgress()
            for status in statuses {
                guard status.state == .updateAvailable, let latest = status.latest else {
                    UI.skip("\(status.name) har ingen uppdatering att ignorera.")
                    continue
                }
                try IgnoredUpdates.ignore(status.id, version: latest)
                UI.ok("\(status.name) \(latest) ignoreras. Kommer en nyare version visas den igen.")
            }
        }
    }

    struct Unignore: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Visa ett programs uppdateringar igen efter ps3 apps ignore."
        )

        @Argument(help: "Programnamn (se ps3 apps ignore).")
        var names: [String]

        func run() throws {
            for name in names {
                let entry = try Apps.resolve(name)
                if try IgnoredUpdates.unignore(entry.id) {
                    UI.ok("\(entry.name) visas igen när det finns en uppdatering.")
                } else {
                    UI.skip("\(entry.name) ignorerades inte.")
                }
            }
        }
    }
}
