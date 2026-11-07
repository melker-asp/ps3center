import ArgumentParser
import Testing
@testable import ps3

// ArgumentParser checks a command's options (duplicate names, a flag and an option with the
// same name, a bad default) only when that command runs. These parse every subcommand's help
// and a few real invocations, so a mistake shows in `swift test` rather than for the user.

/// Every command path below `ps3`: ["games"], ["games", "play"], …
private func paths(_ command: ParsableCommand.Type = PS3.self, prefix: [String] = []) -> [[String]] {
    command.configuration.subcommands.flatMap { sub -> [[String]] in
        let name = sub.configuration.commandName ?? sub._commandName
        let path = prefix + [name]
        return [path] + paths(sub, prefix: path)
    }
}

@Test func thereAreSubcommandsToCheck() {
    #expect(paths().count >= 33)
}

/// The command type at `path`.
private func command(at path: [String]) -> ParsableCommand.Type? {
    var current: ParsableCommand.Type = PS3.self
    for name in path {
        guard let next = current.configuration.subcommands.first(where: { ($0.configuration.commandName ?? $0._commandName) == name })
        else { return nil }
        current = next
    }
    return current
}

@Test(arguments: paths())
func everySubcommandParsesItsHelp(_ path: [String]) throws {
    let type = try #require(command(at: path))
    // Building the help walks every option, as running the command would.
    #expect(PS3.helpMessage(for: type).contains("USAGE"))
    // `--help` parses into ArgumentParser's own help command, or stops with a clean exit.
    do {
        let parsed = try PS3.parseAsRoot(path + ["--help"])
        #expect(String(describing: Swift.type(of: parsed)).contains("Help"), "\(path.joined(separator: " ")) ran instead of showing help")
    } catch {
        #expect(PS3.exitCode(for: error) == .success, "\(path.joined(separator: " ")): \(PS3.message(for: error))")
    }
}

@Test(arguments: [
    ["status", "--json"],
    ["apps", "update", "--dry-run", "--yes"],
    ["apps", "install", "apollo", "--dry-run"],
    ["queue", "start", "--when-done", "popup"],
    ["games", "unmount", "--dry-run"],
    ["refresh", "--force"],
    ["history"],
])
func commonInvocationsParse(_ arguments: [String]) throws {
    _ = try PS3.parseAsRoot(arguments)
}

@Test func aMistypedOptionIsAnErrorNotACrash() {
    #expect(throws: (any Error).self) { try PS3.parseAsRoot(["status", "--jsno"]) }
}
