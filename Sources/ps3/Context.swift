import ArgumentParser
import Foundation
import PS3Kit

struct GlobalOptions: ParsableArguments {
    @Option(name: .long, help: "The PS3's IP address (otherwise from settings or PS3_HOST).")
    var host: String?
}

enum Console {
    static func host(_ options: GlobalOptions, quiet: Bool = false) async throws -> String {
        try await ConsoleLocator.resolve(explicit: options.host) { event in
            guard !quiet else { return }
            switch event {
            case .scanning(let previous):
                UI.step(previous.map { "No contact with \($0), looking for the PS3 on the network…" } ?? "Looking for the PS3 on the network…")
            case .found(let host):
                UI.ok("Found the PS3 at \(host) (saved)")
            }
        }
    }
}
