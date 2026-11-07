import Foundation
import Testing
@testable import PS3Kit
import PS3KitFixtures

// The review of Nov 7, 2026: ps3 mcp beside the app, error codes, versions, estimates and the
// folders that kept their Swedish names.

private func temporaryFolder(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ps3center-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func seesLongCommandsInOtherProcesses() throws {
    let folder = try temporaryFolder("busy")
    defer { try? FileManager.default.removeItem(at: folder) }
    let me = getpid()
    // Our own file never counts; launchd (pid 1) stands in for another living process.
    LongCommands.mark("running", in: folder, pid: me)
    #expect(!LongCommands.otherProcessIsBusy(in: folder, me: me))
    LongCommands.mark("running", in: folder, pid: 1)
    #expect(LongCommands.otherProcessIsBusy(in: folder, me: me))
    // Ended: busy for 20 seconds after, then not.
    LongCommands.mark("ended", in: folder, pid: 1)
    #expect(LongCommands.otherProcessIsBusy(in: folder, now: Date(), me: me))
    #expect(!LongCommands.otherProcessIsBusy(in: folder, now: Date().addingTimeInterval(30), me: me))
    // A process that is gone: its file is removed.
    let gone: Int32 = 99_999
    LongCommands.mark("running", in: folder, pid: gone)
    if kill(gone, 0) != 0, errno == ESRCH {
        #expect(!LongCommands.otherProcessIsBusy(in: folder, now: Date().addingTimeInterval(30), me: me))
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(gone)").path))
    }
}

@Test func keepsGitHubAnswersWithTheirETag() throws {
    let folder = try temporaryFolder("github")
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = URL(string: "https://api.github.com/repos/bucanero/apollo-ps3/releases/latest")!
    #expect(GitHub.APICache.load(url, in: folder) == nil)
    GitHub.APICache.save(GitHub.APICache.Entry(etag: "W/\"abc\"", data: Data("{}".utf8)), for: url, in: folder)
    let entry = try #require(GitHub.APICache.load(url, in: folder))
    #expect(entry.etag == "W/\"abc\"")
    #expect(entry.data == Data("{}".utf8))
    #expect(GitHub.APICache.load(URL(string: "https://api.github.com/repos/other/repo/releases/latest")!, in: folder) == nil)
}

@Test func mcpToolsWaitForTransfersAndCallsRunInOrder() async throws {
    #expect(throws: PS3Error.self) { try MCPServer.checkNoTransfer(isHeld: true) }
    try MCPServer.checkNoTransfer(isHeld: false)

    actor Log {
        var lines: [String] = []
        func add(_ line: String) { lines.append(line) }
    }
    let log = Log()
    let calls = MCPServer.CallQueue()
    await calls.enqueue("1") {
        try? await Task.sleep(nanoseconds: 50_000_000)
        await log.add("first")
    }
    await calls.enqueue("2") { await log.add("second") }
    await calls.enqueue("3") { await log.add("third") }
    await calls.cancel("2")  // cancelled while it waits: it never runs
    await calls.finish()
    #expect(await log.lines == ["first", "third"])
}

@Test func findsErrorCodesOnlyWhereTheyStandAlone() {
    #expect(ConsoleErrorCode.explain(in: "Error 0x80010006.").map(\.code) == [0x8001_0006])
    #expect(ConsoleErrorCode.explain(in: "(80010006)").map(\.code) == [0x8001_0006])
    #expect(ConsoleErrorCode.explain(in: "copied 1800100060 bytes").isEmpty)
    #expect(ConsoleErrorCode.explain(in: "sha256:aa80010006bb").isEmpty)
}

@Test func showsReleasesInTheConsolesOwnVersionForm() throws {
    let statuses = Fixtures.appStatuses()
    let apollo = try #require(statuses.first { $0.id == "apollo" })
    #expect(apollo.latest == "v2.4.1")
    #expect(apollo.latestForDisplay == "02.41")
    #expect(apollo.versionChange == "02.40 → 02.41")
    let artemis = try #require(statuses.first { $0.id == "artemis" })
    #expect(artemis.latestForDisplay == "00.65")
    // A dotted release stays as it is.
    let webman = try #require(statuses.first { $0.id == "webman" })
    #expect(webman.latestForDisplay == webman.latest)
}

@Test func writesEstimatesInWords() {
    #expect(Format.estimate(20) == "under a minute")
    #expect(Format.estimate(4 * 60 + 10) == "4 min")
    #expect(Format.estimate(51 * 60 + 17) == "51 min")
    #expect(Format.estimate(6510) == "1 h 49 min")
    #expect(Format.estimate(7200) == "2 h")
    #expect(Format.estimate(.infinity) == "–")
}

@Test func namesSwedishFoldersThatCameBackBesideTheEnglishOnes() throws {
    let root = try temporaryFolder("leftovers")
    defer { try? FileManager.default.removeItem(at: root) }
    let base = root.appendingPathComponent("support")
    let mirror = root.appendingPathComponent("mirror")
    let media = root.appendingPathComponent("media")
    for path in ["support/Saves", "support/Sparfiler", "support/System Files", "mirror/_Installed", "mirror/_Installerat",
                 "mirror/_Nödläge", "media/Videos"] {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
    }
    let leftovers = FolderMigration.leftovers(base: base, mirror: mirror, media: media)
    // Both names exist only for the saves and the mirror's _Installed; a lone old or new one is fine.
    #expect(leftovers.map(\.old.lastPathComponent) == ["Sparfiler", "_Installerat"])
    #expect(leftovers.map(\.new.lastPathComponent) == ["Saves", "_Installed"])
}
