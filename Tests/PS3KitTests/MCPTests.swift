import CryptoKit
import Foundation
import Testing
@testable import PS3Kit

// MARK: ps3 mcp

private func reply(_ server: MCPServer, _ line: String) async throws -> [String: Any] {
    let text = try #require(await server.handle(line: line))
    #expect(!text.contains("\n"))  // one message per line
    return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

@Test func mcpServerSpeaksJSONRPC() async throws {
    let server = MCPServer(tools: MCPServer.consoleTools(host: "192.0.2.1"), version: "0.1.0")

    let initialized = try await reply(server, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#)
    let result = try #require(initialized["result"] as? [String: Any])
    #expect(result["protocolVersion"] as? String == "2025-03-26")
    #expect((result["capabilities"] as? [String: Any])?["tools"] != nil)
    #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "ps3center")
    // An unknown version gets the newest one.
    let newer = try await reply(server, #"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#)
    #expect(newer["id"] as? String == "a")
    #expect((newer["result"] as? [String: Any])?["protocolVersion"] as? String == MCPServer.protocolVersions[0])

    // Notifications get no answer.
    #expect(await server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    #expect(await server.handle(line: "  ") == nil)

    let listed = try await reply(server, #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
    let tools = try #require((listed["result"] as? [String: Any])?["tools"] as? [[String: Any]])
    #expect(tools.map { $0["name"] as? String } == ["ps3_status", "ps3_apps", "ps3_games", "ps3_maintenance_report", "ps3_history", "ps3_explain_error"])
    #expect(tools.allSatisfy { ($0["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool == true })
    #expect(tools.allSatisfy { ($0["inputSchema"] as? [String: Any])?["type"] as? String == "object" })

    let explained = try await reply(server, #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"ps3_explain_error","arguments":{"code":"Fel 0x8001003D vid start"}}}"#)
    let call = try #require(explained["result"] as? [String: Any])
    #expect(call["isError"] as? Bool == false)
    let text = try #require((call["content"] as? [[String: Any]])?.first?["text"] as? String)
    #expect(text.hasPrefix("8001003D (ENOLICDISC):"))
    #expect(text.contains("webMAN"))

    // A tool that fails answers with isError, not a protocol error.
    let unknownCode = try await reply(server, #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"ps3_explain_error","arguments":{"code":"hej"}}}"#)
    #expect((unknownCode["result"] as? [String: Any])?["isError"] as? Bool == true)

    let noTool = try await reply(server, #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"ps3_install"}}"#)
    #expect((noTool["error"] as? [String: Any])?["code"] as? Int == -32602)
    let noMethod = try await reply(server, #"{"jsonrpc":"2.0","id":6,"method":"resources/list"}"#)
    #expect((noMethod["error"] as? [String: Any])?["code"] as? Int == -32601)
    let broken = try await reply(server, "{not json")
    #expect((broken["error"] as? [String: Any])?["code"] as? Int == -32700)
    #expect(broken["id"] is NSNull)
    let pong = try await reply(server, #"{"jsonrpc":"2.0","id":7,"method":"ping"}"#)
    #expect(pong["result"] is [String: Any])
}

// MARK: Ideas from ps3.world

@Test func explainsCommonXMBCodes() {
    #expect(ConsoleErrorCode.info(0x80010514)?.name == "SKIVA")
    #expect(ConsoleErrorCode.info(0x80710102)?.advice?.contains("DNS") == true)
    // Codes outside 0x8001xxxx are found in messages too, and unknown ones are left out.
    let found = ConsoleErrorCode.explain(in: "Fel 80029519, sedan 0x8002990C och 80021234")
    #expect(found.map(\.code) == [0x80029519, 0x8002990C])
    #expect(ConsoleErrorCode.describe(found[1]).hasPrefix("8002990C (VIDEO):"))
}

@Test func checksDownloadsAgainstGitHub() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ps3center-verify-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let bytes = Data((0..<3000).map { UInt8($0 % 251) })
    let sha = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    func file() throws -> URL {
        let url = folder.appendingPathComponent("app.pkg")
        try bytes.write(to: url)
        return url
    }

    #expect(try GitHub.verify(file(), size: 3000, digest: "sha256:" + sha))
    #expect(try GitHub.verify(file(), size: 3000, digest: "SHA256:" + sha.uppercased()))
    // Older assets have no digest: only the size is checked.
    #expect(try GitHub.verify(file(), size: 3000, digest: nil) == false)

    let wrongSize = try file()
    #expect(throws: PS3Error.self) { try GitHub.verify(wrongSize, size: 2999, digest: nil) }
    #expect(!FileManager.default.fileExists(atPath: wrongSize.path))
    let wrongHash = try file()
    #expect(throws: PS3Error.self) { try GitHub.verify(wrongHash, size: 3000, digest: "sha256:" + String(repeating: "0", count: 64)) }
    #expect(!FileManager.default.fileExists(atPath: wrongHash.path))
}

@Test func marksReleasesFromTheLastMonthAsNew() throws {
    let byID = Dictionary(uniqueKeysWithValues: Fixtures.appStatuses().map { ($0.id, $0) })
    #expect(byID["apollo"]?.isNewRelease() == true)
    #expect(byID["ezremote"]?.isNewRelease() == true)
    #expect(byID["pkgi"]?.isNewRelease() == false)
    // webMAN's add-ons follow someone else's release, so their date says nothing.
    #expect(byID["ps2launcher"]?.releaseDate == nil)

    var status = try #require(byID["apollo"])
    status.releaseDate = "2026-10-01T12:00:00Z"
    let now = try #require(ISO8601DateFormatter().date(from: "2026-10-30T12:00:00Z"))
    #expect(status.isNewRelease(now: now))
    #expect(!status.isNewRelease(now: now.addingTimeInterval(2 * 86_400)))
    status.releaseDate = nil
    #expect(!status.isNewRelease(now: now))
}
