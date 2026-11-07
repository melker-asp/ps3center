import Foundation
import os
import Testing
@testable import PS3Kit

// The shared JSON files and the queue loop that the app and `ps3 queue start` both run.

private func temporaryFolder(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ps3center-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private struct Settings: Codable, Equatable, Sendable {
    var host: String?
    var folders: [String] = []
}

@Test func editsKeepWhatAnotherProcessSavedMeanwhile() throws {
    let folder = try temporaryFolder("jsonfile")
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = JSONFile(folder.appendingPathComponent("config.json"), empty: Settings())

    try file.edit { $0.host = "10.0.1.35" }
    let stale = file.load()  // the app's copy, read before the CLI's change
    try file.edit { $0.folders.append("/Games") }  // the CLI
    try file.edit { $0.host = stale.host == "10.0.1.35" ? "10.0.1.36" : nil }  // the app, later

    #expect(file.load() == Settings(host: "10.0.1.36", folders: ["/Games"]))
}

@Test func anUnreadableFileIsMovedAsideNotOverwritten() throws {
    let folder = try temporaryFolder("jsonfile")
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("config.json")
    try Data(#"{"host": "10.0.1.35", "folders": "not a list"#.utf8).write(to: url)
    let file = JSONFile(url, empty: Settings())

    #expect(file.load() == Settings())  // reading falls back, writes nothing
    #expect(try String(contentsOf: url, encoding: .utf8).contains("not a list"))

    try file.edit { $0.host = "10.0.1.40" }
    #expect(file.load().host == "10.0.1.40")
    let kept = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("config.json.unreadable-") }
    #expect(kept.count == 1)
    let original = try String(contentsOf: folder.appendingPathComponent(kept[0]), encoding: .utf8)
    #expect(original.contains("not a list"))
}

@Test func aFailedWriteThrowsInsteadOfBeingSwallowed() throws {
    let folder = try temporaryFolder("jsonfile")
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: folder)
    }
    let file = JSONFile(folder.appendingPathComponent("queue.json"), empty: Settings())
    try file.edit { $0.host = "a" }
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
    #expect(throws: (any Error).self) { try file.edit { $0.host = "b" } }
}

// MARK: The queue loop

private func route(_ name: String, size: Int64 = 100) -> Route {
    Route(local: URL(fileURLWithPath: "/m/\(name).iso"), remote: "/dev_hdd0/PS3ISO/\(name).iso", kind: .ps3ISO, size: size, title: name)
}

private final class Calls: Sendable {
    private let titles = OSAllocatedUnfairLock(initialState: [String]())
    func add(_ title: String) { titles.withLock { $0.append(title) } }
    var all: [String] { titles.withLock { $0 } }
}

@Test func theQueueLoopMarksEachItemAndKeepsProgressOfFailures() async throws {
    let folder = try temporaryFolder("queue")
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("queue.json")
    try TransferQueue.edit(at: file) { $0.add([route("A"), route("B"), route("C")]) }
    struct Dropped: Error {}
    let calls = Calls()

    let result = await QueueRunner(host: "test").run(file: file, events: { _ in }) { item, _, events in
        calls.add(item.title)
        let only = item.routes[0]
        if item.title == "B" {
            events(.progress(only, sent: 40, total: only.size, bytesPerSecond: 1))
            throw Dropped()
        }
        events(.finished(only, seconds: 1))
    }

    #expect(calls.all == ["A", "B", "C"])
    #expect(result.sent == ["A", "C"])
    #expect(result.failed == 1)
    #expect(result.refresh)
    let items = TransferQueue.load(from: file).items
    #expect(items.map(\.state) == [.done, .failed, .done])
    #expect(items[1].sent == 40)  // the next try continues the console's .part file
    #expect(items[1].message != nil)
}

@Test func eachItemIsTriedOnceEvenWhenTheQueueCannotBeSaved() async throws {
    let folder = try temporaryFolder("queue")
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: folder)
    }
    let file = folder.appendingPathComponent("queue.json")
    try TransferQueue.edit(at: file) { $0.add([route("A"), route("B")]) }
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
    struct Dropped: Error {}
    let calls = Calls()
    let warnings = Calls()

    let result = await QueueRunner(host: "test").run(file: file, events: { event in
        if case .notSaved = event { warnings.add("not saved") }
    }) { item, _, _ in
        calls.add(item.title)
        throw Dropped()
    }

    // Before, the app took `pending.first` again and again when "failed" could not be written.
    #expect(calls.all == ["A", "B"])
    #expect(result.failed == 2)
    #expect(!warnings.all.isEmpty)
}

@Test func progressCountsTheFilesBeforeTheOneBeingSent() {
    var queue = TransferQueue()
    let item = queue.add([route("Game", size: 500), Route(local: URL(fileURLWithPath: "/m/Game.bin"),
                                                         remote: "/dev_hdd0/PSXISO/Game.bin", kind: .psxISO, size: 300, title: "Game")])[0]
    let progress = QueueRunner.Progress(item: item)
    #expect(progress.note(.note("hello")) == nil)
    #expect(progress.note(.progress(item.routes[1], sent: 100, total: 300, bytesPerSecond: 1)) == 600)
    #expect(progress.note(.finished(item.routes[1], seconds: 1)) == 800)
    #expect(progress.sent == 800)
    #expect(!progress.isDueForSave(now: Date()))
    #expect(progress.isDueForSave(now: Date().addingTimeInterval(6)))
}
