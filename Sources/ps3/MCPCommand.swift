import ArgumentParser
import Foundation
import PS3Kit

struct MCP: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "MCP-server över stdio, så att t.ex. Claude kan läsa och felsöka PS3:an. Ändrar ingenting.",
        discussion: """
        Claude Code:     claude mcp add ps3 -- ~/.local/bin/ps3 mcp
        Claude Desktop:  lägg till i claude_desktop_config.json under "mcpServers":
                         "ps3": { "command": "/Users/<du>/.local/bin/ps3", "args": ["mcp"] }

        Verktyg: ps3_status, ps3_apps, ps3_games, ps3_maintenance_report, ps3_history och
        ps3_explain_error. Alla läser bara; ändringar görs med ps3 eller i appen.
        """
    )

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        let version = PS3.configuration.version
        await MCPServer(tools: MCPServer.consoleTools(host: global.host), version: version.isEmpty ? "0.1.0" : version).run()
    }
}
