import ArgumentParser
import Foundation
import PS3Kit

struct Send: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Upload games and files to the right folder on the PS3.",
        discussion: """
        The folder is chosen from the file: PS3/PS2/PS1/PSP ISOs, game folders
        (PS3_GAME), .pkg and .rap. Files in the mirror folder (dev_hdd0/...)
        get the same path on the console. Interrupted uploads resume where
        they stopped. Afterwards the game list is refreshed and a popup is
        shown on the TV, but only once no game is running (or right away with
        --force).
        """
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Files or folders to send.", completion: .file())
    var paths: [String]

    @Option(name: .long, help: "Send to a custom folder on the PS3, e.g. /dev_hdd0/PS3ISO.")
    var to: String?

    @Flag(name: .long, help: "Show what would happen without sending anything.")
    var dryRun = false

    @Flag(name: .long, help: "Go ahead even if a game is running or free space looks too small.")
    var force = false

    @Flag(name: .long, help: "Do not refresh the game list afterwards.")
    var noRefresh = false

    @Flag(name: .long, help: "Do not show a popup on the TV.")
    var noPopup = false

    @Flag(name: .long, help: "Compare the PS3's MD5 with the Mac's after each large file (takes a few minutes per game).")
    var verify = false

    @Flag(name: .long, help: "Shut down the PS3 when everything is sent (waits until no game is running).")
    var shutdownWhenDone = false

    func run() async throws {
        let root = MirrorRoot.resolve()
        let inputs = paths.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        let routes = try FileRouter.routes(for: inputs, mirrorRoot: root, remoteFolder: to)
        guard !routes.isEmpty else {
            UI.skip("Nothing to send.")
            return
        }
        let total = routes.reduce(Int64(0)) { $0 + $1.size }
        UI.header(dryRun ? "Preview" : "Sending to PS3", detail: "\(routes.count) file\(routes.count == 1 ? "" : "s") · \(Format.bytes(total))")

        let host = try await Console.host(global)
        // A plain PS2 ISO does not start on HEN; say so before sending gigabytes.
        if routes.contains(where: { $0.kind == .ps2ISO && !PS2Classic.isClassic($0.remote) }),
           let snapshot = try? await WebMAN(host: host).snapshot(), ConsoleProfile(snapshot: snapshot).exploit == .hen {
            UI.warn(PlayCheck.Finding.ps2NeedsClassic.message)
        }
        var options = TransferOptions()
        options.force = force
        options.refresh = !noRefresh
        options.popup = !noPopup
        options.dryRun = dryRun
        options.verify = verify
        let printer = TransferPrinter(dryRun: dryRun)
        // The Mac stays awake while the files go; an interrupted file resumes next time.
        let awake = KeepAwake(reason: "Sending to the PS3")
        defer { withExtendedLifetime(awake) {} }
        if !dryRun, KeepAwake.isOnBattery { UI.warn(KeepAwake.batteryTip) }
        // Network failures get new tries, like the queue (RetryPolicy).
        try await RetryPolicy.run(events: { printer.handle($0) }) {
            try await TransferService(host: host).send(routes, options: options) { printer.handle($0) }
        }
        if dryRun {
            UI.skip("Nothing was sent (--dry-run).")
        } else if shutdownWhenDone {
            try await TransferService(host: host).waitUntilIdle(force: false) { printer.handle($0) }
            try await WebMAN(host: host).shutdown()
            UI.ok("The PS3 is shutting down")
        }
    }
}
