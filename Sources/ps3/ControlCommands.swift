import ArgumentParser
import Foundation
import PS3Kit

struct Disc: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Eject or insert the disc in the PS3's drive.",
        subcommands: [Eject.self, Insert.self]
    )

    struct Eject: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Eject the disc (/eject.ps3).")

        @OptionGroup var global: GlobalOptions

        @Flag(name: .long, help: "Show what would happen.")
        var dryRun = false

        func run() async throws {
            let host = try await Console.host(global)
            if dryRun { UI.step("Would eject the disc on \(host)"); return }
            try await WebMAN(host: host).ejectDisc()
            UI.ok("Ejecting the disc")
        }
    }

    struct Insert: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Insert the disc (/insert.ps3).")

        @OptionGroup var global: GlobalOptions

        @Flag(name: .long, help: "Show what would happen.")
        var dryRun = false

        func run() async throws {
            let host = try await Console.host(global)
            if dryRun { UI.step("Would insert the disc on \(host)"); return }
            try await WebMAN(host: host).insertDisc()
            UI.ok("Inserting the disc")
        }
    }
}

struct Fan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show the fan, or change webMAN's target temperature (dynamic mode only, 60–75 °C).",
        discussion: """
        ps3 fan              The fan's speed, mode and target
        ps3 fan 70           Keep the PS3 under 70 °C (the fan spins up when needed)
        A fixed low speed is never set: it could let the console get too hot.
        The mode (SYSCON, dynamic, AUTO) is chosen in webMAN's settings.
        """
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "New target temperature in °C (60–75).")
    var target: Int?

    @Flag(name: .long, help: "Show what would happen.")
    var dryRun = false

    func run() async throws {
        let host = try await Console.host(global)
        let snapshot = try await WebMAN(host: host).snapshot()
        UI.header("Fan", detail: host)
        UI.row("Speed", snapshot.fanPercent.map { "\($0) %" } ?? "–")
        UI.row("Mode", snapshot.fanTargetMax.map { "dynamic, holding max \($0) °C" } ?? "no target (SYSCON, AUTO or fixed)")
        UI.row("CPU / RSX", "\(snapshot.cpuTemp.map(String.init) ?? "–") / \(snapshot.rsxTemp.map(String.init) ?? "–") °C")
        guard let target else { return }
        if let refusal = FanControl.refusal(target: target, snapshot: snapshot) { throw PS3Error.refused(refusal) }
        if dryRun { UI.step("Would set the target to \(target) °C (from \(snapshot.fanTargetMax ?? 0) °C)"); return }
        try await WebMAN(host: host).setFanTarget(target)
        UI.ok("The fan now holds max \(target) °C")
    }
}

struct Pad: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Press buttons with webMAN's virtual controller.",
        discussion: """
        ps3 pad down down ok         Two steps down, then select
        ps3 pad back                 ◯ (or ✕ on Asian consoles)
        ps3 pad ps                   The PS button
        ps3 pad off                  Disconnect the virtual controller
        Buttons: \(PadButton.allCases.map(\.rawValue).joined(separator: ", "))
        (also x, o, ok, back, and the Swedish names upp, ner, vänster, höger, tillbaka).
        Half a second between presses.
        """
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Buttons to press, in order.")
    var buttons: [String]

    func validate() throws {
        guard !buttons.isEmpty else { throw ValidationError("Give at least one button, e.g. `ps3 pad down ok`.") }
        for name in buttons where name.lowercased() != "off" && PadButton(name: name) == nil {
            throw ValidationError("Unknown button: \(name)")
        }
    }

    func run() async throws {
        let host = try await Console.host(global)
        let webMAN = WebMAN(host: host)
        for (index, name) in buttons.enumerated() {
            if index > 0 { try await Task.sleep(nanoseconds: 500_000_000) }
            if name.lowercased() == "off" {
                try await webMAN.padOff()
                UI.ok("The virtual controller is disconnected")
            } else if let button = PadButton(name: name) {
                try await webMAN.press(button)
                UI.ok(button.label)
            }
        }
    }
}

struct Screenshot: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Save a picture of the XMB (what the TV shows) on the Mac.",
        discussion: "Works in the XMB, not during a game."
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "File to save to (default: the Desktop).")
    var file: String?

    @Flag(name: .long, help: "Full size instead of the smaller, faster picture.")
    var full = false

    func run() async throws {
        let host = try await Console.host(global)
        let data = try await WebMAN(host: host).screenshot(fast: !full)
        let kind = ImageKind(data) ?? .bmp
        let url: URL
        if let file {
            url = URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let stamp = formatter.string(from: Date())
            url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop/PS3 \(stamp).\(kind.fileExtension)")
        }
        try data.write(to: url)
        UI.ok("Saved \(url.path) (\(Format.bytes(Int64(data.count))))")
    }
}
