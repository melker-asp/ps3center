import ArgumentParser
import Foundation
import PS3Kit

struct Apps: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Homebrew på PS3:an: versioner, uppdateringar och installation av paket.",
        subcommands: [List.self, Available.self, Update.self, Install.self],
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
            let statuses = try await AppsService(host: host).check().filter { $0.installable || $0.installed != nil }
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
                    print("  \(marker) \(name)\(id)\(version)\(pad)" + UI.paint(s.summary, .gray))
                }
                print()
            }
            print("  Installera med " + UI.paint("ps3 apps install <namn>", .bold) + ", t.ex. " + UI.paint("ps3 apps install ezremote", .bold) + ".")
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
            for item in resolved {
                switch item {
                case .file(let file):
                    try await TransferService(host: host).installPackage(file, options: options) { printer.handle($0) }
                    installedNames.append(file.deletingPathExtension().lastPathComponent)
                    guard !dryRun, !keep, let root else { continue }
                    let archive = MirrorRoot.packageArchive(in: root)
                    if file.deletingLastPathComponent().standardizedFileURL != archive.standardizedFileURL {
                        let moved = try apps.archivePackage(file, into: archive)
                        UI.skip("Arkiverad i \(moved.path.replacingOccurrences(of: root.path + "/", with: ""))")
                    }

                case .catalog(let entry):
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
            for s in missing { UI.skip(name(s) + (s.latest.map { "senaste \($0)" } ?? "")) }
        }
    }
}
