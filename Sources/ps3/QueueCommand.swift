import ArgumentParser
import Foundation
import PS3Kit

struct Queue: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "The queue of games to send, shared with the app. Survives interruptions and resumes where it stopped.",
        discussion: """
        ps3 queue                        Show the queue
        ps3 queue add Game.iso           Add files or games from the Mac to the queue
        ps3 queue start                  Send the queue, one game at a time
        ps3 queue start --when-done shutdown   Shut down the PS3 afterwards
        ps3 queue clear                  Remove what is done
        Ctrl-C stops cleanly: the file on the PS3 stays and the next start
        resumes there. The Mac stays awake as long as the queue runs.
        """,
        subcommands: [List.self, Add.self, Start.self, Remove.self, Clear.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "Show the queue.")

        @Flag(name: .long, help: "Print JSON.")
        var json = false

        func run() throws {
            let queue = TransferQueue.load()
            if json || !UI.isTTY { UI.json(queue); return }
            guard !queue.items.isEmpty else {
                UI.skip("The queue is empty. Add with `ps3 queue add <files or games>`.")
                return
            }
            UI.header("Queue", detail: "\(queue.pending.count) left · \(Format.bytes(queue.remainingBytes))"
                      + (SpeedTest.estimate(bytes: queue.remainingBytes).map { " · about \(Format.duration($0))" } ?? ""))
            for (index, item) in queue.items.enumerated() {
                let number = UI.paint(String(format: "%2d", index + 1), .gray)
                let marker: String
                switch item.state {
                case .done: marker = UI.paint("✓", .green)
                case .failed: marker = UI.paint("✗", .red)
                case .paused, .sending: marker = UI.paint("‖", .yellow)
                case .waiting: marker = UI.paint("·", .gray)
                }
                let progress = item.state == .done ? "" : "  " + UI.bar(item.fraction, width: 12) + " \(Int(item.fraction * 100)) %"
                print("  \(number) \(marker) \(item.title.padding(toLength: 40, withPad: " ", startingAt: 0))\(Format.bytes(item.total))\(progress)")
                if let message = item.message, item.state == .failed { print("        " + UI.paint(message, .gray)) }
            }
            print("\n  When the queue is done: " + queue.whenDone.label + (queue.verify ? " · MD5 check" : ""))
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add files, folders or games from the Mac's game folders to the queue.",
            discussion: "A path is sent as with `ps3 send`; otherwise the name is looked up among the games in `ps3 games mac`."
        )

        @Argument(help: "Files, folders or names of games in the Mac's game folders.", completion: .file())
        var items: [String] = []

        @Option(name: .long, help: "Send to a custom folder on the PS3, e.g. /dev_hdd0/PS3ISO.")
        var to: String?

        func validate() throws {
            guard !items.isEmpty else { throw ValidationError("Give files or games to add to the queue.") }
        }

        func run() throws {
            var routes: [Route] = []
            var names: [String] = []
            for item in items {
                let url = URL(fileURLWithPath: (item as NSString).expandingTildeInPath)
                if FileManager.default.fileExists(atPath: url.path) {
                    routes += try FileRouter.routes(for: [url], mirrorRoot: MirrorRoot.resolve(), remoteFolder: to)
                } else {
                    names.append(item)
                }
            }
            if !names.isEmpty {
                let games = LocalLibrary().scan()
                switch Game.lookup(names.joined(separator: " "), in: games) {
                case .found(let game): routes += try game.routes()
                case .ambiguous(let matches):
                    throw PS3Error.invalidFile("\(names.joined(separator: " ")) could mean several: \(matches.prefix(8).map(\.title).joined(separator: ", ")).")
                case .missing:
                    throw PS3Error.invalidFile("Found neither the file nor the game \(names.joined(separator: " ")) in the Mac's game folders (see `ps3 games mac`).")
                }
            }
            let added = TransferQueue.edit { $0.add(routes) }
            guard !added.isEmpty else {
                UI.skip("It is already in the queue.")
                return
            }
            for item in added { UI.ok("\(item.title) (\(Format.bytes(item.total))) is in the queue") }
            print("\n  Send with " + UI.paint("ps3 queue start", .bold) + ".")
        }
    }

    struct Start: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Send everything in the queue, one game at a time.")

        @OptionGroup var global: GlobalOptions

        @Option(name: .long, help: "When the queue is done: nothing, popup or shutdown. Remembered for next time.")
        var whenDone: String?

        @Flag(name: .long, inversion: .prefixedNo, help: "Compare the PS3's MD5 with the Mac's after each large file. Remembered for next time.")
        var verify: Bool?

        func run() async throws {
            guard let lock = QueueLock() else {
                throw PS3Error.refused("The queue is already being sent, from the app or another `ps3 queue start`.")
            }
            var choice: TransferQueue.WhenDone?
            if let whenDone {
                guard let parsed = TransferQueue.WhenDone(rawValue: whenDone) else {
                    throw ValidationError("--when-done takes nothing, popup or shutdown.")
                }
                choice = parsed
            }
            var queue = TransferQueue.edit { latest -> TransferQueue in
                if let choice { latest.whenDone = choice }
                if let verify { latest.verify = verify }
                return latest
            }
            guard !queue.pending.isEmpty else {
                UI.skip("Nothing in the queue to send.")
                return
            }
            let host = try await Console.host(global)
            let awake = KeepAwake(reason: "Sending games to the PS3")
            defer { withExtendedLifetime(awake) {} }
            UI.header("Sending the queue", detail: "\(queue.pending.count) item\(queue.pending.count == 1 ? "" : "s") · \(Format.bytes(queue.remainingBytes))")
            if KeepAwake.isOnBattery { UI.warn(KeepAwake.batteryTip) }
            let runner = QueueRunner(host: host)
            let printer = TransferPrinter(dryRun: false)
            var sentTitles: [String] = []
            var refreshes = false
            // Read again each round, since the app and `ps3 queue add` may have changed the queue.
            // Each item gets one try per run, even if queue.json cannot be written.
            var tried = Set<UUID>()
            while let item = queue.pending.first(where: { !tried.contains($0.id) }) {
                tried.insert(item.id)
                TransferQueue.edit { $0.update(item.id) { $0.state = .sending } }
                UI.step(item.title)
                do {
                    try await runner.send(item, verify: queue.verify) { printer.handle($0) }
                    TransferQueue.edit {
                        $0.update(item.id) {
                            $0.state = .done
                            $0.sent = $0.total
                            $0.finishedAt = Date()
                            $0.message = nil
                        }
                    }
                    sentTitles.append(item.title)
                    refreshes = refreshes || item.routes.contains(where: \.refreshesGameList)
                } catch {
                    TransferQueue.edit {
                        $0.update(item.id) {
                            $0.state = .failed
                            $0.message = error.localizedDescription
                        }
                    }
                    UI.fail("\(item.title): \(error.localizedDescription)")
                }
                queue = TransferQueue.load()
            }
            try await runner.finish(sent: sentTitles, refresh: refreshes, whenDone: queue.whenDone) { printer.handle($0) }
            withExtendedLifetime(lock) {}
            UI.ok("The queue is done: \(sentTitles.count) sent")
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove a row from the queue (the number from `ps3 queue`). Files on the PS3 are not touched.")

        @Argument(help: "The row number.")
        var number: Int

        func run() throws {
            let item = try TransferQueue.edit { queue -> TransferQueue.Item in
                guard queue.items.indices.contains(number - 1) else { throw ValidationError("The queue has no row \(number).") }
                return queue.items.remove(at: number - 1)
            }
            UI.ok("\(item.title) was removed from the queue")
        }
    }

    struct Clear: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove what is done from the queue, or everything with --all.")

        @Flag(name: .long, help: "Empty the whole queue.")
        var all = false

        func run() throws {
            TransferQueue.edit { queue in
                if all { queue.items.removeAll() } else { queue.removeFinished() }
            }
            UI.ok(all ? "The queue is emptied" : "Finished rows are removed")
        }
    }
}

struct Speedtest: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "speedtest",
        abstract: "Measure how fast files go to and from the PS3. The result gives time estimates in the queue and the app."
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Seconds to send.")
    var seconds = 5

    @Option(name: .long, help: "At most this many megabytes.")
    var mb = 256

    func run() async throws {
        let host = try await Console.host(global)
        UI.header("Speed Test", detail: "\(seconds) seconds to /dev_hdd0/tmp, then back")
        let result = try await SpeedTest.run(host: host, seconds: TimeInterval(seconds), megabytes: mb) { event in
            switch event {
            case .progress(_, let sent, let total, let rate):
                UI.progress("\(UI.bar(total > 0 ? Double(sent) / Double(total) : 0)) Sending  \(Format.rate(rate))")
            case .note(let text):
                UI.endProgress()
                UI.step(text)
            default:
                break
            }
        }
        UI.endProgress()
        UI.row("To the PS3", Format.rate(result.upload))
        if let down = result.download { UI.row("From the PS3", Format.rate(down)) }
        if let network = result.network { UI.row("Network", network) }
        let tenGB: Int64 = 10_000_000_000
        UI.row("10 GB takes", Format.duration(Double(tenGB) / result.upload))
        if result.network == "Wi-Fi" {
            print()
            UI.warn("The PS3 is on Wi-Fi (2.4 GHz only). With a network cable it is usually several times faster.")
        }
    }
}

struct Power: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Shut down or restart the PS3.",
        discussion: "On HEN, HEN has to be enabled again after a restart, and the PS3 cannot be started from the Mac.",
        subcommands: [Off.self, Restart.self]
    )

    struct Off: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Shut down the PS3 (does not wait for games; quit first if you want to save).")

        @OptionGroup var global: GlobalOptions

        @Flag(name: [.short, .long], help: "Do not ask.")
        var yes = false

        @Flag(name: .long, help: "Show what would happen.")
        var dryRun = false

        func run() async throws {
            let host = try await Console.host(global)
            if let running = try await WebMAN(host: host).snapshot().mountedGameName, try await WebMAN(host: host).isGameRunning() {
                UI.warn("\(running) is running. Save first, unsaved progress will be lost.")
            }
            if dryRun { UI.step("Would shut down the PS3 at \(host)"); return }
            guard yes || UI.confirm("Shut down the PS3?") else { return }
            try await WebMAN(host: host).shutdown()
            UI.ok("The PS3 is shutting down")
        }
    }

    struct Restart: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Restart the PS3. On HEN, HEN has to be enabled again afterwards.")

        @OptionGroup var global: GlobalOptions

        @Flag(name: [.short, .long], help: "Do not ask.")
        var yes = false

        @Flag(name: .long, help: "Show what would happen.")
        var dryRun = false

        func run() async throws {
            let host = try await Console.host(global)
            let profile = ConsoleProfile(snapshot: try await WebMAN(host: host).snapshot())
            if profile.exploit == .hen { UI.warn("The PS3 runs HEN: after the restart, HEN has to be enabled again before PS3 Center can reach it.") }
            if dryRun { UI.step("Would restart the PS3 at \(host)"); return }
            guard yes || UI.confirm("Restart the PS3?") else { return }
            try await WebMAN(host: host).restart()
            UI.ok("The PS3 is restarting")
        }
    }
}

struct USB: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "usb",
        abstract: "Prepare a USB drive with games from the Mac's game folders (fastest for many games).",
        subcommands: [Prepare.self]
    )

    struct Prepare: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Copy games to a FAT32 drive in webMAN's folders. ISOs over 4 GB are split into .iso.0, .iso.1 …",
            discussion: """
            ps3 usb prepare /Volumes/PS3 gran demon     Two games from the Mac
            ps3 usb prepare /Volumes/PS3 --missing      All that are not on the PS3
            A game folder with a file over 4 GB, which FAT32 cannot hold,
            becomes a PS3 ISO in parts (PS3ISO). Format the drive as "MS-DOS
            (FAT)" in Disk Utility first; macOS cannot write NTFS. Then plug
            the drive into the PS3: the games show up under webMAN's games
            after a game list refresh.
            """
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "The drive's folder, e.g. /Volumes/PS3.", completion: .directory)
        var volume: String

        @Argument(help: "Games (part of the title or title ID) from the Mac's game folders.")
        var names: [String] = []

        @Flag(name: .long, help: "All games in the Mac's game folders that are not on the PS3.")
        var missing = false

        @Flag(name: .long, help: "Show what would be copied.")
        var dryRun = false

        func validate() throws {
            guard missing || !names.isEmpty else { throw ValidationError("Give games, or --missing for all that are not on the PS3.") }
        }

        func run() async throws {
            let root = URL(fileURLWithPath: (volume as NSString).expandingTildeInPath)
            guard let info = USBDrive.volume(root) else { throw ValidationError("No drive found at \(root.path).") }
            guard info.isFAT32 else {
                throw PS3Error.refused("\(root.path) is \(info.format), not FAT32. Format it as \"MS-DOS (FAT)\" in Disk Utility (this erases the drive).")
            }
            let library = LocalLibrary().scan()
            var games: [Game]
            if missing {
                let host = try await Console.host(global)
                let console = try await GameLibraryService(host: host).scan()
                let states = LibraryMatch.states(mac: library, console: console)
                games = library.filter { states[$0.id] != .onConsole }
            } else {
                games = try names.map { name in
                    switch Game.lookup(name, in: library) {
                    case .found(let game): return game
                    case .ambiguous(let matches): throw PS3Error.invalidFile("\(name) could mean several: \(matches.prefix(8).map(\.title).joined(separator: ", ")).")
                    case .missing: throw PS3Error.invalidFile("No game matches \(name) in the Mac's game folders.")
                    }
                }
            }
            let plan = USBDrive.plan(games, on: root)
            for (game, reason) in plan.skipped { UI.skip("\(game.title): \(reason)") }
            let total = plan.total
            UI.header(dryRun ? "Preview" : "Copying", detail: "\(plan.copies.count) file\(plan.copies.count == 1 ? "" : "s") · \(Format.bytes(total)) · free \(Format.bytes(info.free))")
            guard total < info.free else { throw PS3Error.notEnoughSpace(needed: total, free: info.free) }
            for copy in plan.copies {
                let notes = [copy.kind == .isoFromFolder ? "converted to an ISO" : nil, copy.parts > 1 ? "\(copy.parts) parts" : nil].compactMap { $0 }
                UI.step("\(copy.game.title) → \(copy.destination.path)" + (notes.isEmpty ? "" : UI.paint("  (\(notes.joined(separator: ", ")))", .gray)))
            }
            guard !dryRun else { return }
            let printer = TransferPrinter(dryRun: false, done: "copied")
            try await USBDrive.copy(plan.copies) { printer.handle($0) }
            UI.ok("Done. Eject the drive, plug it into the PS3 and run `ps3 refresh`.")
        }
    }
}

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Run the Game Server: the PS3 plays ISOs straight from the Mac's game folders through webMAN (/net0).",
        discussion: """
        A ps3netsrv of our own that is read-only, on port 38008. Set it up
        once in webMAN: Settings (http://<ps3>/setup.ps3) → network server 1 =
        the Mac's address and 38008. The games then show up under webMAN's
        games and start as usual, or with `ps3 games play` on the /net0 path.
        Ctrl-C stops the server. Only the PS3 is let in, so the console must
        be findable when the server starts (or given with --host). PS3 games
        should go over a cable. PS2 ISOs are copied to the hard drive when
        they start, and game folders (GAMES) do not go over the network, only
        ISOs.
        """
    )

    @OptionGroup var global: GlobalOptions

    @Flag(name: .long, help: "Let everyone on the network in, not just the PS3.")
    var anyClient = false

    func run() async throws {
        let folders = GameFolders.linked()
        guard !folders.isEmpty else {
            throw PS3Error.refused("No game folders are linked. Link one with `ps3 config folder add PS3ISO ~/Games/PS3`.")
        }
        var console: String?
        if !anyClient {
            do {
                console = try await Console.host(global, quiet: true)
            } catch {
                // Only the console is let in, so without its address the server does not start.
                throw PS3Error.refused("Cannot find the PS3, so the Game Server does not know who to let in. Turn the PS3 on and enable HEN, give --host <ip>, or let everyone on the network in with --any-client.")
            }
        }
        let server = NetServer(folders: folders, allowedHost: console) { status in
            if let error = status.error { UI.fail(error) }
        }
        try server.start()
        let awake = KeepAwake(reason: "Game Server for the PS3")
        defer { withExtendedLifetime(awake) {}; server.stop() }
        UI.header("Game Server", detail: "port \(NetServer.defaultPort)" + (console.map { " · only \($0)" } ?? ""))
        for address in NetServer.macAddresses() { UI.row("Address", "\(address):\(NetServer.defaultPort)") }
        for (kind, url) in folders { UI.row(kind.name, url.path) }
        print("\n  Ctrl-C stops. The Mac stays awake as long as the server runs.")
        // Polled, so the output stays calm: one line per game file the console opens.
        var last: String?
        while true {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            if let file = server.currentStatus.lastFile, file != last {
                last = file
                UI.step("The PS3 is reading \(file)")
            }
        }
    }
}

struct WatchFolders: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Watch the folders and add new games to the queue once they stop growing. Ctrl-C quits.",
        discussion: """
        Which folders are watched is chosen with `ps3 config folder watch
        <folder>` or in the app's Game Folders. The app watches by itself
        while it is open. With --send the queue is sent right away.
        """
    )

    @OptionGroup var global: GlobalOptions

    @Flag(name: .long, help: "Send the queue when something new has been added.")
    var send = false

    func run() async throws {
        let folders = FolderWatch.watched()
        guard !folders.isEmpty else {
            throw PS3Error.refused("No folders are watched. Turn it on with `ps3 config folder watch <folder>`.")
        }
        UI.header("Watching", detail: "\(folders.count) folder\(folders.count == 1 ? "" : "s")")
        for (kind, url) in folders { UI.row(kind.name, url.path) }
        print("\n  New games are added to the queue once they have stopped growing for a minute. Ctrl-C quits.")
        var watch = FolderWatch()
        while true {
            let games = FolderWatch.routes(for: watch.poll(FolderWatch.watched()))
            if !games.isEmpty {
                TransferQueue.edit { queue in
                    for game in games { queue.add(game.routes) }
                }
                for game in games { UI.ok("\(game.title) is in the queue") }
                if send {
                    // The app or another `ps3 queue start` may already be sending; keep watching.
                    do {
                        let start = try Queue.Start.parse(global.host.map { ["--host", $0] } ?? [])
                        try await start.run()
                    } catch {
                        UI.warn(error.localizedDescription)
                    }
                }
            }
            try await Task.sleep(nanoseconds: 20_000_000_000)
        }
    }
}
