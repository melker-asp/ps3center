import ArgumentParser
import Foundation
import PS3Kit

struct Apps: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Homebrew på PS3:an: versioner, uppdateringar och installation av paket.",
        subcommands: [List.self, Available.self, Info.self, Update.self, Install.self],
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
            if statuses.contains(where: \.canInstall) {
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

        @Argument(help: "Uppdatera bara dessa (t.ex. apollo pkgi). Utelämna för alla.")
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

            let installable = statuses.filter(\.canInstall)
            let advisories = statuses.filter { $0.state == .updateAvailable && !$0.canInstall }
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
                let line = "\(status.name) \(status.installed ?? "?") → \(status.latest ?? "?")"
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
                    print("  \(marker) \(name)\(id)\(version)\(pad)" + UI.paint(s.blocked ? s.compatibility.summary : s.summary, .gray))
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
            Paketen arkiveras i _Installerat/Paket (äldre versioner av samma program läggs i papperskorgen).
            Se `ps3 apps available` för vad som finns.
            """
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Programnamn (se ps3 apps available) eller .pkg-filer.", completion: .file(extensions: ["pkg"]))
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
            let resolved: [Item] = try items.map { item in
                let url = URL(fileURLWithPath: (item as NSString).expandingTildeInPath).standardizedFileURL
                if item.lowercased().hasSuffix(".pkg") || FileManager.default.fileExists(atPath: url.path) {
                    guard PKGInfo(url: url) != nil else { throw PS3Error.invalidFile("\(url.lastPathComponent) är inget giltigt PS3-paket.") }
                    return .file(url)
                }
                let entry = try Apps.resolve(item)
                guard entry.isInstallable else {
                    if case .notifyOnly(let note) = entry.action { throw PS3Error.invalidFile("\(entry.name) installeras inte automatiskt. \(note)") }
                    throw PS3Error.invalidFile("\(entry.name) kan inte installeras automatiskt. Se \(entry.homepage)")
                }
                return .catalog(entry)
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
                    guard !dryRun, !keep, let root else { continue }
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

    static func renderInfo(entry: CatalogEntry, status: AppStatus, console: ConsoleProfile) {
        UI.header(entry.name, detail: entry.category.label)
        UI.row("Om", entry.summary)
        if let repo = entry.repository { UI.row("Källa", "https://github.com/\(repo)") } else { UI.row("Källa", entry.homepage) }
        UI.row("Installerad", status.installed ?? UI.paint("nej", .gray))
        if let latest = status.latest {
            UI.row("Senaste", status.state == .updateAvailable ? UI.paint(latest, .bold, .yellow) : latest)
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
        let updates = statuses.filter { $0.state == .updateAvailable }
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
        if !missing.isEmpty {
            print()
            UI.header("Inte installerade", detail: "\(missing.count)")
            for s in missing {
                UI.skip(name(s) + (s.blocked ? "fungerar inte på din PS3: \(s.compatibility.summary)" : s.latest.map { "senaste \($0)" } ?? ""))
            }
        }
    }
}
