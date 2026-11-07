import ArgumentParser
import Foundation
import PS3Kit

struct Popup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show a message on the TV.")

    @OptionGroup var global: GlobalOptions

    @Argument(help: "The text to show.")
    var text: [String]

    func run() async throws {
        let host = try await Console.host(global)
        try await WebMAN(host: host).popup(text.joined(separator: " "))
        UI.ok("Shown on the PS3")
    }
}

struct Refresh: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Refresh webMAN's game list (like SELECT + L3).",
        discussion: "With --xmb the XMB is reloaded too, so new and removed icons show right away. With a user signed in and Reload XMB installed, webMAN starts that app; otherwise it signs out and back in."
    )

    @OptionGroup var global: GlobalOptions

    @Flag(name: .long, help: "Go ahead even if a game is running.")
    var force = false

    @Flag(name: .long, help: "Reload the XMB too.")
    var xmb = false

    func run() async throws {
        let host = try await Console.host(global)
        let service = TransferService(host: host)
        let printer = TransferPrinter(dryRun: false)
        if xmb {
            try await service.waitUntilIdle(force: force) { printer.handle($0) }
            try await service.webman.reloadXMB()
            UI.ok("Game list refreshed and XMB reloaded")
            return
        }
        try await service.refreshGameList(whenGameRuns: .wait, force: force) { event in
            if case .refreshed = event { return }  // said once below
            printer.handle(event)
        }
        UI.ok("Game list refreshed")
    }
}

struct History: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show what PS3 Center has changed on the console.")

    @Option(name: .shortAndLong, help: "Number of rows.")
    var limit = 20

    @Flag(name: .long, help: "Print JSON.")
    var json = false

    func run() throws {
        let entries = OperationLog.read(limit: limit)
        if json || !UI.isTTY { UI.json(entries); return }
        guard !entries.isEmpty else { UI.skip("No history yet."); return }
        UI.header("History", detail: OperationLog.file.path)
        // As wide as the longest action ("uninstall", "webman-setup"), so none runs into its detail.
        let width = (entries.map(\.action.count).max() ?? 0) + 2
        for e in entries {
            print("  " + UI.paint(String(e.date.prefix(16)).replacingOccurrences(of: "T", with: " "), .gray) + "  "
                  + e.action.padding(toLength: width, withPad: " ", startingAt: 0) + e.detail)
        }
    }
}

struct Discover: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Look for PS3s running webMAN on the network and save the address.")

    func run() async throws {
        UI.step("Searching \(Discovery.localSubnets().map { "\($0).0/24" }.joined(separator: ", "))…")
        let found = await Discovery.scan()
        guard let first = found.first else { throw PS3Error.noHost }
        for host in found { UI.ok("webMAN answers at \(host)") }
        try ConfigStore.edit { $0.host = first }
        UI.ok("Saved \(first) as the PS3's address")
    }
}

struct Config: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show or change settings (~/.config/ps3center/config.json).",
        subcommands: [Show.self, Set.self, Folder.self],
        defaultSubcommand: Show.self
    )

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show the settings.")
        func run() throws {
            let config = ConfigStore.load()
            UI.header("Settings", detail: ConfigStore.file.path)
            UI.row("host", config.host ?? UI.paint("(found automatically)", .gray))
            UI.row("root", config.root ?? (MirrorRoot.resolve().map { $0.path + UI.paint("  (found automatically)", .gray) } ?? UI.paint("(missing)", .gray)))
            let linked = GameFolders.linked()
            if linked.isEmpty {
                UI.row("game folders", UI.paint("(none, see ps3 config folder add)", .gray))
            }
            for (kind, url) in linked {
                UI.row(kind.name, url.path + (FileManager.default.fileExists(atPath: url.path) ? "" : UI.paint("  (not connected)", .yellow)))
            }
            for url in PackageFolders.linked(config: config) {
                UI.row(PackageFolders.kindName, url.path + (FileManager.default.fileExists(atPath: url.path) ? "" : UI.paint("  (not connected)", .yellow)))
            }
        }
    }

    struct Folder: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "folder",
            abstract: "Link the Mac's game folders by type (PS3ISO, GAMES, PS2ISO, PSXISO, PSPISO, BDISO, DVDISO) and package folders (PKG).",
            discussion: """
            ps3 config folder add PS3ISO ~/Games/PS3
            ps3 config folder remove PS3ISO ~/Games/PS3
            ps3 config folder watch ~/Games/PS3      Send new games in it automatically
            ps3 config folder unwatch ~/Games/PS3
            ps3 config folder add PKG ~/Packages     A folder of .pkg files
            The mirror folder's dev_hdd0/<TYPE> is included automatically. The
            games in the folders are listed with `ps3 games mac` and sent with
            `ps3 queue add`. The packages are listed with `ps3 apps mac` and
            installed with `ps3 apps install`; they stay in the folder.
            """,
            subcommands: [List.self, Add.self, Remove.self, Watch.self, Unwatch.self],
            defaultSubcommand: List.self
        )

        static func kind(_ name: String) throws -> GameFolders.Kind {
            guard let kind = GameFolders.kind(named: name) else {
                throw ValidationError("Unknown type: \(name). Use \(GameFolders.kinds.map(\.name).joined(separator: ", ")).")
            }
            return kind
        }

        struct List: ParsableCommand {
            static let configuration = CommandConfiguration(commandName: "list", abstract: "Show the linked folders.")

            func run() throws {
                UI.header("Game Folders", detail: ConfigStore.file.path)
                let linked = GameFolders.linked()
                for kind in GameFolders.kinds {
                    let folders = linked.filter { $0.kind == kind }
                    let paths = folders.map {
                        $0.url.path + (FileManager.default.fileExists(atPath: $0.url.path) ? "" : UI.paint("  (not connected)", .yellow))
                            + (FolderWatch.isWatched($0.url) ? UI.paint("  watched", .green) : "")
                    }
                    UI.row(kind.name, paths.isEmpty ? UI.paint("–", .gray) : paths.joined(separator: "\n" + String(repeating: " ", count: 14)))
                }
                let packages = PackageFolders.linked().map {
                    $0.path + (FileManager.default.fileExists(atPath: $0.path) ? "" : UI.paint("  (not connected)", .yellow))
                }
                UI.row(PackageFolders.kindName, packages.isEmpty ? UI.paint("–", .gray) : packages.joined(separator: "\n" + String(repeating: " ", count: 14)))
            }
        }

        struct Add: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Link a folder, e.g. ps3 config folder add PS3ISO ~/Games/PS3.")

            @Argument(help: "PS3ISO, GAMES, PS2ISO, PSXISO, PSPISO, BDISO, DVDISO or PKG (packages).")
            var kind: String

            @Argument(help: "The folder on the Mac.", completion: .directory)
            var path: String

            func run() throws {
                let isPackages = PackageFolders.isKind(self.kind)
                let kind = isPackages ? nil : try Folder.kind(self.kind)
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                    throw ValidationError("\(url.path) is not a folder.")
                }
                if let kind {
                    try GameFolders.add(url, as: kind)
                    UI.ok("\(url.path) is linked as \(kind.label)")
                } else {
                    try PackageFolders.add(url)
                    UI.ok("\(url.path) is linked as a package folder. The packages are listed with `ps3 apps mac`.")
                }
            }
        }

        struct Watch: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Watch a linked folder: new games in it are added to the queue once they stop growing.",
                discussion: "What is already in the folder does not count as new. The app watches while it is open; without the app, `ps3 watch` does the same."
            )

            @Argument(help: "A linked folder on the Mac.", completion: .directory)
            var path: String

            func run() throws {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
                if PackageFolders.linked().contains(where: { $0.path == url.path }) {
                    throw ValidationError("Package folders are not watched: a package is only installed when you ask for it (`ps3 apps mac`).")
                }
                guard GameFolders.linked().contains(where: { $0.url.path == url.path }) else {
                    throw ValidationError("\(url.path) is not linked. Link it first with `ps3 config folder add <type> \(path)`.")
                }
                try FolderWatch.setWatched(url, true)
                UI.ok("\(url.path) is watched")
            }
        }

        struct Unwatch: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Stop watching a folder.")

            @Argument(help: "The folder on the Mac.", completion: .directory)
            var path: String

            func run() throws {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
                try FolderWatch.setWatched(url, false)
                UI.ok("\(url.path) is no longer watched")
            }
        }

        struct Remove: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Unlink a folder (the files are not touched).")

            @Argument(help: "PS3ISO, GAMES, PS2ISO, PSXISO, PSPISO, BDISO, DVDISO or PKG (packages).")
            var kind: String

            @Argument(help: "The folder on the Mac.", completion: .directory)
            var path: String

            func run() throws {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
                if PackageFolders.isKind(self.kind) {
                    try PackageFolders.remove(url)
                } else {
                    try GameFolders.remove(url, from: try Folder.kind(self.kind))
                }
                UI.ok("\(url.path) is unlinked")
            }
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Change a setting: host or root.")

        @Argument(help: "host or root")
        var key: String

        @Argument(help: "The value. An empty string removes the setting.")
        var value: String

        @Flag(help: "With root: make a new, empty PS3 folder (dev_hdd0/ and _Installed/Packages) inside the given folder and use it.")
        var create = false

        func run() throws {
            let cleaned = value.isEmpty ? nil : value
            var root: String?
            switch key {
            case "host":
                if create { throw ValidationError("--create only goes with root.") }
            case "root":
                if let path = cleaned {
                    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
                    if create {
                        root = try MirrorRoot.create(in: url).path
                    } else {
                        guard MirrorRoot.looksLikeMirror(url) else {
                            throw ValidationError("\(url.path) does not look like the PS3 folder (missing dev_hdd0/ or _Installed/). Add --create to make one inside it.")
                        }
                        root = url.path
                    }
                }
            default: throw ValidationError("Unknown setting: \(key). Use host or root.")
            }
            try ConfigStore.edit { config in
                if key == "host" { config.host = cleaned } else { config.root = root }
            }
            UI.ok("\(key) = \((key == "root" ? root : cleaned) ?? "(removed)")")
        }
    }
}
