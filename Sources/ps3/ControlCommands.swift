import ArgumentParser
import Foundation
import PS3Kit

struct Disc: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Mata ut eller mata in skivan i PS3:ans spelare.",
        subcommands: [Eject.self, Insert.self]
    )

    struct Eject: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Mata ut skivan (/eject.ps3).")

        @OptionGroup var global: GlobalOptions

        @Flag(name: .long, help: "Visa vad som skulle hända.")
        var dryRun = false

        func run() async throws {
            let host = try await Console.host(global)
            if dryRun { UI.step("Skulle mata ut skivan på \(host)"); return }
            try await WebMAN(host: host).ejectDisc()
            UI.ok("Skivan matas ut")
        }
    }

    struct Insert: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Mata in skivan (/insert.ps3).")

        @OptionGroup var global: GlobalOptions

        @Flag(name: .long, help: "Visa vad som skulle hända.")
        var dryRun = false

        func run() async throws {
            let host = try await Console.host(global)
            if dryRun { UI.step("Skulle mata in skivan på \(host)"); return }
            try await WebMAN(host: host).insertDisc()
            UI.ok("Skivan matas in")
        }
    }
}

struct Fan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Visa fläkten, eller ändra webMAN:s måltemperatur (bara i dynamiskt läge, 60–75 °C).",
        discussion: """
        ps3 fan              Fläktens hastighet, läge och mål
        ps3 fan 70           Håll PS3:an under 70 °C (fläkten varvar upp vid behov)
        En fast låg hastighet sätts aldrig: den kan låta konsolen bli för varm. Läget
        (SYSCON, dynamiskt, AUTO) väljs i webMAN:s inställningar.
        """
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Ny måltemperatur i °C (60–75).")
    var target: Int?

    @Flag(name: .long, help: "Visa vad som skulle hända.")
    var dryRun = false

    func run() async throws {
        let host = try await Console.host(global)
        let snapshot = try await WebMAN(host: host).snapshot()
        UI.header("Fläkten", detail: host)
        UI.row("Hastighet", snapshot.fanPercent.map { "\($0) %" } ?? "–")
        UI.row("Läge", snapshot.fanTargetMax.map { "dynamiskt, håller max \($0) °C" } ?? "inget mål (SYSCON, AUTO eller fast)")
        UI.row("CPU / RSX", "\(snapshot.cpuTemp.map(String.init) ?? "–") / \(snapshot.rsxTemp.map(String.init) ?? "–") °C")
        guard let target else { return }
        if let refusal = FanControl.refusal(target: target, snapshot: snapshot) { throw PS3Error.refused(refusal) }
        if dryRun { UI.step("Skulle sätta målet till \(target) °C (från \(snapshot.fanTargetMax ?? 0) °C)"); return }
        try await WebMAN(host: host).setFanTarget(target)
        UI.ok("Fläkten håller nu max \(target) °C")
    }
}

struct Pad: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Tryck på knappar med webMAN:s virtuella handkontroll.",
        discussion: """
        ps3 pad down down ok         Två steg ner och välj
        ps3 pad tillbaka             ◯ (eller ✕ på asiatiska konsoler)
        ps3 pad ps                   PS-knappen
        ps3 pad off                  Koppla bort den virtuella handkontrollen
        Knappar: \(PadButton.allCases.map(\.rawValue).joined(separator: ", "))
        (även upp, ner, vänster, höger, x, o, ok, tillbaka). Ett halvt
        sekunds mellanrum mellan trycken.
        """
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Knappar att trycka på, i tur och ordning.")
    var buttons: [String]

    func validate() throws {
        guard !buttons.isEmpty else { throw ValidationError("Ange minst en knapp, t.ex. `ps3 pad down ok`.") }
        for name in buttons where name.lowercased() != "off" && PadButton(name: name) == nil {
            throw ValidationError("Okänd knapp: \(name)")
        }
    }

    func run() async throws {
        let host = try await Console.host(global)
        let webMAN = WebMAN(host: host)
        for (index, name) in buttons.enumerated() {
            if index > 0 { try await Task.sleep(nanoseconds: 500_000_000) }
            if name.lowercased() == "off" {
                try await webMAN.padOff()
                UI.ok("Den virtuella handkontrollen är bortkopplad")
            } else if let button = PadButton(name: name) {
                try await webMAN.press(button)
                UI.ok(button.label)
            }
        }
    }
}

struct Screenshot: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Spara en bild av XMB:n (det TV:n visar) på Macen.",
        discussion: "Fungerar i XMB:n, inte under ett spel."
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Fil att spara i (standard: Skrivbordet).")
    var file: String?

    @Flag(name: .long, help: "Full storlek i stället för den mindre, snabbare bilden.")
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
            formatter.dateFormat = "yyyy-MM-dd 'kl.' HH.mm.ss"
            let stamp = formatter.string(from: Date())
            url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop/PS3 \(stamp).\(kind.fileExtension)")
        }
        try data.write(to: url)
        UI.ok("Sparade \(url.path) (\(Format.bytes(Int64(data.count))))")
    }
}
