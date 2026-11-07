import Foundation
import Testing
@testable import PS3Kit

// What the app's Settings builds on: a new PS3 folder for someone without a copy of the console's
// drive, and the limits of the FTP tuning that Settings and the uploads share.

private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ps3center-settings-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func isDirectory(_ url: URL) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
}

@Test func createsAnEmptyPS3Folder() throws {
    let parent = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: parent) }

    let root = try MirrorRoot.create(in: parent)

    #expect(root.lastPathComponent == "PS3")
    #expect(isDirectory(root.appendingPathComponent("dev_hdd0")))
    #expect(isDirectory(MirrorRoot.packageArchive(in: root)))
    #expect(MirrorRoot.looksLikeMirror(root))
}

@Test func usesAnExistingPS3FolderAsItIs() throws {
    let parent = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: parent) }
    let first = try MirrorRoot.create(in: parent)
    let marker = first.appendingPathComponent("dev_hdd0/game.txt")
    try Data("kept".utf8).write(to: marker)

    let second = try MirrorRoot.create(in: parent)

    #expect(second.standardizedFileURL == first.standardizedFileURL)
    #expect(FileManager.default.fileExists(atPath: marker.path))
    #expect(!FileManager.default.fileExists(atPath: parent.appendingPathComponent("PS3 2").path))
}

@Test func neverAddsToAFolderThatIsNotAPS3Folder() throws {
    let parent = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: parent) }
    // Someone's own folder called PS3, with music in it: left alone.
    let own = parent.appendingPathComponent("PS3", isDirectory: true)
    try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
    try Data("song".utf8).write(to: own.appendingPathComponent("song.mp3"))
    // And a file with the next name.
    try Data("note".utf8).write(to: parent.appendingPathComponent("PS3 2"))

    let root = try MirrorRoot.create(in: parent)

    #expect(root.lastPathComponent == "PS3 3")
    #expect(MirrorRoot.looksLikeMirror(root))
    #expect(!FileManager.default.fileExists(atPath: own.appendingPathComponent("dev_hdd0").path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: own.path) == ["song.mp3"])
}

@Test func clampsTheFTPTuningLikeTheUploads() {
    #expect(FTPTuning.chunkKB(nil) == FTPTuning.defaultChunkKB)
    #expect(FTPTuning.chunkKB(10) == 64)
    #expect(FTPTuning.chunkKB(512) == 512)
    #expect(FTPTuning.chunkKB(100_000) == 8192)
    #expect(FTPTuning.window(nil) == FTPTuning.defaultWindow)
    #expect(FTPTuning.window(0) == 1)
    #expect(FTPTuning.window(4) == 4)
    #expect(FTPTuning.window(20) == 8)
}

// The address field in the setup guide.

@Test func cleansTypedAddresses() {
    #expect(ConsoleAddress.clean("192.168.1.20") == "192.168.1.20")
    #expect(ConsoleAddress.clean("  192.168.2.2\n") == "192.168.2.2")
    #expect(ConsoleAddress.clean("http://192.168.1.20/setup.ps3") == "192.168.1.20")
    #expect(ConsoleAddress.clean("HTTP://10.0.1.35/") == "10.0.1.35")
    #expect(ConsoleAddress.clean("PS3.local") == "ps3.local")
    #expect(ConsoleAddress.clean("my-ps3") == "my-ps3")
}

@Test func refusesWhatCannotBeAnAddress() {
    #expect(ConsoleAddress.clean("") == nil)
    #expect(ConsoleAddress.clean("192.168.1") == nil)
    #expect(ConsoleAddress.clean("300.1.1.1") == nil)
    #expect(ConsoleAddress.clean("1.2.3.4.5") == nil)
    #expect(ConsoleAddress.clean("my ps3") == nil)
    #expect(ConsoleAddress.clean("-ps3.local") == nil)
    #expect(ConsoleAddress.clean("ps3..local") == nil)
    #expect(ConsoleAddress.clean("spelkonsol.lokal\u{00E5}") == nil)
}
