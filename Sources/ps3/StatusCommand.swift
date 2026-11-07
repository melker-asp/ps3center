import ArgumentParser
import Foundation
import PS3Kit

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show the console's status: health, temperatures, fan, free space and what is running.",
        discussion: "Prints JSON automatically when the output is piped to another program, like `mo status`."
    )

    @OptionGroup var global: GlobalOptions

    @Flag(name: .long, help: "Print JSON.")
    var json = false

    @Flag(name: .long, help: "Keep updating. With --json, prints one line of JSON per reading (NDJSON).")
    var watch = false

    @Option(name: .long, help: "Seconds between readings with --watch.")
    var interval: Double = 3

    func run() async throws {
        let asJSON = json || !UI.isTTY
        let host: String
        do {
            host = try await Console.host(global, quiet: asJSON)
        } catch {
            // Off, or on with HEN not enabled? Only the second answers on the network.
            if let known = global.host ?? ConfigStore.load().host, await Reachability.probe(known) == .henOff {
                throw PS3Error.refused(Reachability.henOffAdvice(host: known))
            }
            throw error
        }
        let webman = WebMAN(host: host)

        guard watch else {
            let snapshot = try await webman.snapshot()
            asJSON ? UI.json(snapshot) : Self.render(snapshot)
            return
        }
        while true {
            do {
                let snapshot = try await webman.snapshot()
                if asJSON {
                    UI.json(snapshot, pretty: false)
                    fflush(stdout)
                } else {
                    print("\u{1B}[H\u{1B}[2J", terminator: "")
                    Self.render(snapshot)
                    print(UI.paint("\n  Updating every \(Int(interval)) s · Ctrl-C quits", .gray))
                }
            } catch {
                if !asJSON { UI.fail(error.localizedDescription) }
            }
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    static func render(_ s: ConsoleSnapshot) {
        let chips = [s.firmware.map { "\($0) \(s.firmwareType ?? "")".trimmingCharacters(in: .whitespaces) },
                     s.henVersion.map { "PS3HEN \($0)" } ?? s.payload,
                     s.webmanVersion.map { "webMAN \($0)" }].compactMap { $0 }
        UI.header("PS3", detail: chips.joined(separator: " · "))

        let healthColor: UI.Color = s.health >= 85 ? .green : s.health >= 65 ? .cyan : s.health >= 45 ? .yellow : .red
        let notes = s.healthNotes.isEmpty ? "" : UI.paint("  " + s.healthNotes.joined(separator: ", "), .gray)
        UI.row("Health", UI.paint("\(s.health)", .bold, healthColor) + " " + s.healthLabel + notes)

        if let cpu = s.cpuTemp {
            UI.row("CPU", "\(UI.bar(Double(cpu) / 90, width: 16, color: tempColor(cpu, warn: 70))) \(cpu) °C")
        }
        if let rsx = s.rsxTemp {
            UI.row("RSX", "\(UI.bar(Double(rsx) / 90, width: 16, color: tempColor(rsx, warn: 75))) \(rsx) °C")
        }
        if let fan = s.fanPercent {
            let target = s.fanTargetMax.map { UI.paint("  holding max \($0) °C", .gray) } ?? ""
            UI.row("Fan", "\(UI.bar(Double(fan) / 100, width: 16, color: .blue)) \(fan) %" + target)
        }
        if let free = s.freeBytes {
            UI.row("Free", Format.bytes(free) + UI.paint("  on /dev_hdd0", .gray))
        }
        if let ip = s.ip {
            UI.row("Network", "\(s.network ?? "") · \(ip)")
        }
        if s.isGameRunning {
            let name = s.mountedGameName ?? s.runningProcess ?? "Unknown"
            let time = s.playTime.map { UI.paint("  played \($0)", .gray) } ?? ""
            UI.row("Now Playing", UI.paint(name, .bold) + time)
        } else {
            UI.row("Now Playing", UI.paint("Nothing – XMB", .gray))
            if let mounted = s.mountedGameName { UI.row("Mounted", mounted) }
        }
    }

    static func tempColor(_ value: Int, warn: Int) -> UI.Color {
        value >= warn + 10 ? .red : value >= warn ? .yellow : .green
    }
}
