import ArgumentParser
import Foundation
import PS3Kit

struct Send: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Ladda upp spel och filer till rätt mapp på PS3:an.",
        discussion: """
        Mappen väljs utifrån filen: PS3/PS2/PS1/PSP-ISO:er, spelmappar (PS3_GAME), .pkg och .rap.
        Filer i spegelmappen (dev_hdd0/...) får samma sökväg på konsolen.
        Avbrutna uppladdningar fortsätter där de slutade. Efteråt uppdateras spellistan och en
        popup visas på TV:n – men först när inget spel körs (eller direkt med --force).
        """
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Filer eller mappar att skicka.", completion: .file())
    var paths: [String]

    @Option(name: .long, help: "Skicka till en egen mapp på PS3:an, t.ex. /dev_hdd0/PS3ISO.")
    var to: String?

    @Flag(name: .long, help: "Visa vad som skulle hända utan att skicka något.")
    var dryRun = false

    @Flag(name: .long, help: "Kör även om ett spel körs eller utrymmet verkar för litet.")
    var force = false

    @Flag(name: .long, help: "Uppdatera inte spellistan efteråt.")
    var noRefresh = false

    @Flag(name: .long, help: "Visa ingen popup på TV:n.")
    var noPopup = false

    func run() async throws {
        let root = MirrorRoot.resolve()
        let inputs = paths.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        let routes = try FileRouter.routes(for: inputs, mirrorRoot: root, remoteFolder: to)
        guard !routes.isEmpty else {
            UI.skip("Inget att skicka.")
            return
        }
        let total = routes.reduce(Int64(0)) { $0 + $1.size }
        UI.header(dryRun ? "Förhandsvisning" : "Skickar till PS3", detail: "\(routes.count) fil\(routes.count == 1 ? "" : "er") · \(Format.bytes(total))")

        let host = try await Console.host(global)
        var options = TransferOptions()
        options.force = force
        options.refresh = !noRefresh
        options.popup = !noPopup
        options.dryRun = dryRun
        let printer = TransferPrinter(dryRun: dryRun)
        try await TransferService(host: host).send(routes, options: options) { printer.handle($0) }
        if dryRun {
            UI.skip("Inget skickades (--dry-run).")
        }
    }
}
