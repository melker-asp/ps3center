import ArgumentParser
import Foundation
import PS3Kit

struct MCP: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "MCP server over stdio, so that Claude, for example, can read and troubleshoot the PS3. Changes nothing.",
        discussion: """
        Claude Code:     claude mcp add ps3 -- ~/.local/bin/ps3 mcp
        Claude Desktop:  add to claude_desktop_config.json under "mcpServers":
                         "ps3": { "command": "/Users/<you>/.local/bin/ps3", "args": ["mcp"] }

        Tools: ps3_status, ps3_apps, ps3_games, ps3_maintenance_report, ps3_history and
        ps3_explain_error. All are read-only; changes are made with ps3 or in the app.
        """
    )

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        let version = PS3.configuration.version
        await MCPServer(tools: MCPServer.consoleTools(host: global.host), version: version.isEmpty ? "0.1.0" : version).run()
    }
}
