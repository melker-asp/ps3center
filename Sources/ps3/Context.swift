import ArgumentParser
import Foundation
import PS3Kit

struct GlobalOptions: ParsableArguments {
    @Option(name: .long, help: "PS3:ans IP-adress (annars från inställningarna eller PS3_HOST).")
    var host: String?
}

enum Console {
    static func host(_ options: GlobalOptions, quiet: Bool = false) async throws -> String {
        try await ConsoleLocator.resolve(explicit: options.host) { event in
            guard !quiet else { return }
            switch event {
            case .scanning(let previous):
                UI.step(previous.map { "Ingen kontakt med \($0), letar efter PS3:an på nätverket…" } ?? "Letar efter PS3:an på nätverket…")
            case .found(let host):
                UI.ok("Hittade PS3:an på \(host) (sparad)")
            }
        }
    }
}
