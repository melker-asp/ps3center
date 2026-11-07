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
    PS3 Center reads a PS3 with PS3HEN and webMAN MOD on the home network. Start with ps3_status: it \
    shows temperatures, fan, free space, what is running, versions and a health score with \
    notes. ps3_apps compares installed homebrew with GitHub, ps3_games lists the games, \
    ps3_maintenance_report finds leftover packages, unfinished transfers and missing plugins, and \
    ps3_explain_error explains error codes such as 80010006. ps3_history shows what PS3 Center has changed. \
    No tool changes the console; changes are made with ps3 in the terminal or in the PS3 Center app. \
    If webMAN does not answer, HEN is usually not enabled after a restart.
    """

    let tools: [Tool]
    let version: String

    public init(tools: [Tool], version: String) {
        self.tools = tools
        self.version = version
    }

    /// Reads requests from stdin until it closes. Tool calls run one at a time, in order, since
    /// webMAN takes one FTP session at a time; everything else (ping, tools/list) is answered
    /// at once, also while a minute-long maintenance report runs. A tool call the client
    /// cancels (`notifications/cancelled`) stops and gets no answer, as MCP asks.
    public func run() async {
        let writer = LineWriter()
        let calls = CallQueue()
        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                let message = (line.data(using: .utf8)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
                switch message?["method"] as? String {
                case "tools/call" where message?["id"] != nil:
                    let key = "\(message?["id"] ?? "")"
                    await calls.enqueue(key) { [self] in
                        guard let reply = await handle(line: line), !Task.isCancelled else { return }
                        await writer.write(reply)
                    }
                case "notifications/cancelled":
                    let params = message?["params"] as? [String: Any]
                    if let id = params?["requestId"] { await calls.cancel("\(id)") }
                default:
                    if let reply = await handle(line: line) { await writer.write(reply) }
                }
            }
            await calls.finish()
        } catch {
            FileHandle.standardError.write(Data("ps3 mcp: \(error.localizedDescription)\n".utf8))
        }
    }

    /// Writes whole lines to stdout, one at a time, so answers from tool calls and from the
    /// read loop never interleave.
    actor LineWriter {
        func write(_ line: String) {
            FileHandle.standardOutput.write(Data((line + "\n").utf8))
        }
    }

    /// Tool calls in order, each after the one before, and cancellable by request id.
    actor CallQueue {
        private var tail: Task<Void, Never>?
        private var running: [String: Task<Void, Never>] = [:]

        func enqueue(_ key: String, _ work: @escaping @Sendable () async -> Void) {
            let previous = tail
            let task = Task {
                await previous?.value
                if !Task.isCancelled { await work() }
                self.done(key)
            }
            running[key] = task
            tail = task
        }

        func cancel(_ key: String) {
            running[key]?.cancel()
        }

        private func done(_ key: String) {
            running[key] = nil
        }

        /// Waits for the calls still running when stdin closes, so their answers are written.
        func finish() async {
            await tail?.value
        }
    }

    // MARK: JSON-RPC

    /// One line in, at most one line out (nothing for a notification).
    public func handle(line: String) async -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return Self.encode(Self.error(id: NSNull(), code: -32700, message: "Could not parse the JSON."))
        }
        guard let message = object as? [String: Any] else {
            return Self.encode(Self.error(id: NSNull(), code: -32600, message: "One message at a time."))
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
                return Self.error(id: id, code: -32602, message: "Unknown tool: \(params["name"] ?? "no name").")
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
            return Self.error(id: id, code: -32601, message: "Unknown method: \(method ?? "none").")
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
            return #"{"error":{"code":-32603,"message":"The answer could not be written."},"id":null,"jsonrpc":"2.0"}"#
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
        // For the tools that open an FTP session: not beside a transfer the app or `ps3 queue`
        // is sending, since webMAN's FTP takes one session at a time.
        let ftpHost: @Sendable () async throws -> String = {
            try checkNoTransfer()
            return try await host()
        }
        return [
            Tool(name: "ps3_status", title: "Status",
                 description: "The console's status right now: CPU and RSX temperature, fan, free space, network, what is running and mounted, firmware, HEN and webMAN version, and a health score 0–100 with notes. Never shows the PSID or IDPS.") { _ in
                try json(try await WebMAN(host: try await host()).snapshot())
            },
            Tool(name: "ps3_apps", title: "Homebrew and Updates",
                 description: "The apps in PS3 Center's catalog: the installed version compared with the latest release on GitHub, whether there is an update, whether it is ignored, and whether the app works on the console (HEN/CFW, firmware). HEN and plugins are never installed automatically.") { _ in
                try json(try await AppsService(host: try await ftpHost()).check())
            },
            Tool(name: "ps3_games", title: "Games on the PS3",
                 description: "The games on the console: PS3 ISOs, folders in GAMES, PSN games, PS2, PS1, PSP and movies on the hard drive and USB, with title, title ID, size, location and installed game update.") { _ in
                try json(try await GameLibraryService(host: try await ftpHost()).scan())
            },
            Tool(name: "ps3_maintenance_report", title: "Maintenance Report",
                 description: "Checks the console without changing anything: leftover packages, unfinished transfers (.part), duplicates, missing plugins in boot_plugins.txt, webMAN's cache, free space and whether system updates are blocked. Takes up to a minute.") { _ in
                try json(try await MaintenanceService(host: try await ftpHost()).check())
            },
            Tool(name: "ps3_history", title: "History",
                 description: "What PS3 Center has changed on the console (uploads, installs, uninstalls, cleanup), latest last. Read from the log on the Mac, so the console does not need to answer.",
                 inputSchema: ["type": "object", "properties": [
                     "limit": ["type": "integer", "description": "How many lines (default 20, at most 200)."],
                 ]]) { arguments in
                let limit = min(max((arguments["limit"] as? Int) ?? 20, 1), 200)
                return try json(OperationLog.read(limit: limit))
            },
            Tool(name: "ps3_explain_error", title: "Explain an Error Code",
                 description: "Explains an error code from the PS3, e.g. 80010006 or 8001003D, or every code in an error message: what it means and what can be done with HEN and webMAN.",
                 inputSchema: ["type": "object", "required": ["code"], "properties": [
                     "code": ["type": "string", "description": "The code (80010006, 0x80010006) or a whole error message."],
                 ]]) { arguments in
                try explainError(arguments["code"] as? String ?? "")
            },
        ]
    }

    /// Refuses while the queue is being sent, with what to do instead.
    static func checkNoTransfer(isHeld: Bool = QueueLock.isHeld) throws {
        guard isHeld else { return }
        throw PS3Error.refused("A transfer is running (the PS3 Center app or ps3 queue start), and webMAN's FTP takes one session at a time. Try again when it is done; ps3_status works meanwhile.")
    }

    static func explainError(_ text: String) throws -> String {
        var infos = ConsoleErrorCode.explain(in: text)
        if infos.isEmpty, let code = ConsoleErrorCode.parse(text), let info = ConsoleErrorCode.info(code) { infos = [info] }
        guard !infos.isEmpty else {
            throw PS3Error.refused("No known error code in \u{201C}\(text)\u{201D}. PS3 Center knows the system codes 0x8001xxxx and the most common codes for disc, Blu-ray, video, network and account.")
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
