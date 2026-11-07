import Foundation

/// A Model Context Protocol server over stdio (`ps3 mcp`), so an assistant such as Claude can read
/// the console's state and help troubleshoot it. This first version only reads: no tool changes the
/// console, so nothing here needs `OperationLog` or a dry run. The same rules as everywhere apply:
/// `ConsoleSnapshot` never carries PSID/IDPS.
///
/// The transport is JSON-RPC 2.0, one message per line on stdin and stdout. Nothing else may be
/// written to stdout while the server runs (FTP debugging goes to stderr).
public final class MCPServer: @unchecked Sendable {
    public struct Tool {
        public let name: String
        public let title: String
        public let description: String
        public let inputSchema: [String: Any]
        /// The text Claude reads back; usually JSON.
        public let run: ([String: Any]) async throws -> String

        public init(name: String, title: String, description: String,
                    inputSchema: [String: Any] = ["type": "object", "properties": [String: Any]()],
                    run: @escaping ([String: Any]) async throws -> String) {
            self.name = name
            self.title = title
            self.description = description
            self.inputSchema = inputSchema
            self.run = run
        }
    }

    /// Newest first; the client's version is used when it is one of these.
    public static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    public static let instructions = """
    PS3 Center läser en PS3 med PS3HEN och webMAN MOD på hemnätverket. Börja med ps3_status: den \
    visar temperaturer, fläkt, ledigt utrymme, vad som körs, versioner och en hälsopoäng med \
    anmärkningar. ps3_apps jämför installerad homebrew med GitHub, ps3_games listar spelen, \
    ps3_maintenance_report hittar kvarglömda paket, avbrutna överföringar och saknade plugins, och \
    ps3_explain_error förklarar felkoder som 80010006. ps3_history visar vad PS3 Center har ändrat. \
    Inget verktyg ändrar konsolen; ändringar görs med ps3 i terminalen eller i appen PS3 Center. \
    Svarar inte webMAN är HEN oftast inte aktiverat efter en omstart.
    """

    let tools: [Tool]
    let version: String

    public init(tools: [Tool], version: String) {
        self.tools = tools
        self.version = version
    }

    /// Reads requests from stdin until it closes.
    public func run() async {
        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                guard let reply = await handle(line: line) else { continue }
                FileHandle.standardOutput.write(Data((reply + "\n").utf8))
            }
        } catch {
            FileHandle.standardError.write(Data("ps3 mcp: \(error.localizedDescription)\n".utf8))
        }
    }

    // MARK: JSON-RPC

    /// One line in, at most one line out (nothing for a notification).
    public func handle(line: String) async -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return Self.encode(Self.error(id: NSNull(), code: -32700, message: "Kunde inte tolka JSON."))
        }
        guard let message = object as? [String: Any] else {
            return Self.encode(Self.error(id: NSNull(), code: -32600, message: "Ett meddelande i taget."))
        }
        return await handle(message).map(Self.encode)
    }

    func handle(_ message: [String: Any]) async -> [String: Any]? {
        let method = message["method"] as? String
        guard let id = message["id"], !(id is NSNull) else { return nil }  // a notification or a response
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String
            let version = asked.flatMap { Self.protocolVersions.contains($0) ? $0 : nil } ?? Self.protocolVersions[0]
            return Self.result(id: id, [
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "ps3center", "title": "PS3 Center", "version": self.version],
                "instructions": Self.instructions,
            ])
        case "ping":
            return Self.result(id: id, [:])
        case "tools/list":
            return Self.result(id: id, ["tools": tools.map { tool in
                [
                    "name": tool.name,
                    "title": tool.title,
                    "description": tool.description,
                    "inputSchema": tool.inputSchema,
                    "annotations": ["readOnlyHint": true, "destructiveHint": false],
                ] as [String: Any]
            }])
        case "tools/call":
            guard let name = params["name"] as? String, let tool = tools.first(where: { $0.name == name }) else {
                return Self.error(id: id, code: -32602, message: "Okänt verktyg: \(params["name"] ?? "inget namn").")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                let text = try await tool.run(arguments)
                return Self.result(id: id, ["content": [["type": "text", "text": text]], "isError": false])
            } catch {
                // A tool's failure is part of the answer, so Claude can explain it.
                return Self.result(id: id, ["content": [["type": "text", "text": error.localizedDescription]], "isError": true])
            }
        default:
            return Self.error(id: id, code: -32601, message: "Okänd metod: \(method ?? "ingen").")
        }
    }

    static func result(id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func error(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    static func encode(_ message: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else {
            return #"{"error":{"code":-32603,"message":"Svaret gick inte att skriva."},"id":null,"jsonrpc":"2.0"}"#
        }
        return text
    }

    /// Pretty JSON for a tool's text.
    public static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

// MARK: The console's tools

extension MCPServer {
    /// The read-only tools `ps3 mcp` offers. `explicit` is `--host`.
    public static func consoleTools(host explicit: String? = nil) -> [Tool] {
        let host: @Sendable () async throws -> String = { try await consoleHost(explicit) }
        return [
            Tool(name: "ps3_status", title: "Status",
                 description: "Konsolens status just nu: CPU- och RSX-temperatur, fläkt, ledigt utrymme, nätverk, vad som körs och är monterat, firmware, HEN- och webMAN-version, och en hälsopoäng 0–100 med anmärkningar. Visar aldrig PSID eller IDPS.") { _ in
                try json(try await WebMAN(host: try await host()).snapshot())
            },
            Tool(name: "ps3_apps", title: "Homebrew och uppdateringar",
                 description: "Programmen i PS3 Centers katalog: installerad version jämförd med senaste releasen på GitHub, om det finns en uppdatering, om den är ignorerad och om programmet fungerar på konsolen (HEN/CFW, firmware). HEN och plugins installeras aldrig automatiskt.") { _ in
                try json(try await AppsService(host: try await host()).check())
            },
            Tool(name: "ps3_games", title: "Spelen på PS3:an",
                 description: "Spelen på konsolen: PS3-ISO:er, mappar i GAMES, PSN-spel, PS2, PS1, PSP och filmer på hårddisken och USB, med titel, title ID, storlek, plats och installerad uppdatering.") { _ in
                try json(try await GameLibraryService(host: try await host()).scan())
            },
            Tool(name: "ps3_maintenance_report", title: "Underhållsrapport",
                 description: "Kontrollerar konsolen utan att ändra något: kvarglömda paket, avbrutna överföringar (.part), dubbletter, saknade plugins i boot_plugins.txt, webMAN:s cache, ledigt utrymme och om systemuppdateringar är blockerade. Tar upp till en minut.") { _ in
                try json(try await MaintenanceService(host: try await host()).check())
            },
            Tool(name: "ps3_history", title: "Historik",
                 description: "Vad PS3 Center har ändrat på konsolen (uppladdningar, installationer, avinstallationer, städning), senaste sist. Läses från loggen på Macen, så konsolen behöver inte svara.",
                 inputSchema: ["type": "object", "properties": [
                     "limit": ["type": "integer", "description": "Hur många rader (standard 20, högst 200)."],
                 ]]) { arguments in
                let limit = min(max((arguments["limit"] as? Int) ?? 20, 1), 200)
                return try json(OperationLog.read(limit: limit))
            },
            Tool(name: "ps3_explain_error", title: "Förklara en felkod",
                 description: "Förklarar en felkod från PS3:an, t.ex. 80010006 eller 8001003D, eller alla koder i ett felmeddelande: vad den betyder och vad man kan göra med HEN och webMAN.",
                 inputSchema: ["type": "object", "required": ["code"], "properties": [
                     "code": ["type": "string", "description": "Koden (80010006, 0x80010006) eller ett helt felmeddelande."],
                 ]]) { arguments in
                try explainError(arguments["code"] as? String ?? "")
            },
        ]
    }

    static func explainError(_ text: String) throws -> String {
        var infos = ConsoleErrorCode.explain(in: text)
        if infos.isEmpty, let code = ConsoleErrorCode.parse(text), let info = ConsoleErrorCode.info(code) { infos = [info] }
        guard !infos.isEmpty else {
            throw PS3Error.refused("Ingen känd felkod i \u{201D}\(text)\u{201D}. PS3 Center känner till systemkoderna 0x8001xxxx och de vanligaste koderna för skiva, Blu-ray, video, nätverk och konto.")
        }
        return infos.map(ConsoleErrorCode.describe).joined(separator: "\n")
    }

    /// The console's address as the CLI finds it. When webMAN does not answer but the console does,
    /// the error says that HEN is off, which is the usual reason after a restart.
    static func consoleHost(_ explicit: String?) async throws -> String {
        do {
            return try await ConsoleLocator.resolve(explicit: explicit)
        } catch {
            let saved = explicit ?? ProcessInfo.processInfo.environment["PS3_HOST"] ?? ConfigStore.load().host
            if let saved, await Reachability.probe(saved) == .henOff {
                throw PS3Error.refused(Reachability.henOffAdvice(host: saved))
            }
            throw error
        }
    }
}
