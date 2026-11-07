import Foundation
import Testing
@testable import PS3Kit

// The folders on the Mac that had Swedish names before PS3 Center was in English: renamed once
// when only the old one exists, left alone when both do.

private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ps3center-migration-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func touch(_ url: URL, _ text: String = "x") throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

private func read(_ url: URL) -> String? { (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) } }

@Test func renamesTheSaveBackupFromItsSwedishNames() throws {
    let base = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let old = base.appendingPathComponent("Sparfiler")
    try touch(old.appendingPathComponent("senaste.json"), "date")
    try touch(old.appendingPathComponent("00000001/BCES00569-GT5PROFILE/SAVE.DAT"), "save")
    try touch(old.appendingPathComponent("00000001/.tidigare/BCES00569-GT5PROFILE/SAVE.DAT"), "older")
    try touch(old.appendingPathComponent("00000001/.innan-aterstallning/BCES00569-GT5PROFILE/SAVE.DAT"), "before")

    SaveBackupService.migrateNames(in: base)

    let saves = base.appendingPathComponent("Saves")
    #expect(!exists(old))
    #expect(read(saves.appendingPathComponent("last-backup.json")) == "date")
    #expect(read(saves.appendingPathComponent("00000001/BCES00569-GT5PROFILE/SAVE.DAT")) == "save")
    #expect(read(saves.appendingPathComponent("00000001/.previous/BCES00569-GT5PROFILE/SAVE.DAT")) == "older")
    #expect(read(saves.appendingPathComponent("00000001/.before-restore/BCES00569-GT5PROFILE/SAVE.DAT")) == "before")
    #expect(!exists(saves.appendingPathComponent("00000001/.tidigare")))
    #expect(!exists(saves.appendingPathComponent("senaste.json")))

    // A second run changes nothing.
    SaveBackupService.migrateNames(in: base)
    #expect(read(saves.appendingPathComponent("last-backup.json")) == "date")
}

@Test func keepsBothWhenTheEnglishFolderIsAlreadyThere() throws {
    let base = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    try touch(base.appendingPathComponent("Sparfiler/senaste.json"), "old")
    try touch(base.appendingPathComponent("Saves/last-backup.json"), "new")
    try touch(base.appendingPathComponent("Saves/00000001/.tidigare/A/SAVE.DAT"), "old previous")
    try touch(base.appendingPathComponent("Saves/00000001/.previous/A/SAVE.DAT"), "new previous")
    try touch(base.appendingPathComponent("Systemfiler/2026-10-01 12.00/dev_hdd0/boot_plugins.txt"), "old")
    try touch(base.appendingPathComponent("System Files/2026-11-01 12.00/dev_hdd0/boot_plugins.txt"), "new")

    SaveBackupService.migrateNames(in: base)
    SystemFiles.migrateNames(in: base)

    #expect(read(base.appendingPathComponent("Saves/last-backup.json")) == "new")
    #expect(read(base.appendingPathComponent("Sparfiler/senaste.json")) == "old")
    #expect(read(base.appendingPathComponent("Saves/00000001/.previous/A/SAVE.DAT")) == "new previous")
    #expect(read(base.appendingPathComponent("Saves/00000001/.tidigare/A/SAVE.DAT")) == "old previous")
    #expect(exists(base.appendingPathComponent("Systemfiler/2026-10-01 12.00")))
    #expect(!exists(base.appendingPathComponent("System Files/2026-10-01 12.00")))
}

@Test func renamesSystemFilesAndImportFolders() throws {
    let base = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    try touch(base.appendingPathComponent("Systemfiler/2026-10-01 12.00/dev_hdd0/boot_plugins.txt"), "plugins")
    SystemFiles.migrateNames(in: base)
    #expect(read(base.appendingPathComponent("System Files/2026-10-01 12.00/dev_hdd0/boot_plugins.txt")) == "plugins")
    #expect(!exists(base.appendingPathComponent("Systemfiler")))

    let imports = base.appendingPathComponent("PS3 Center")
    try touch(imports.appendingPathComponent("Filmer/BCES00569.mp4"), "video")
    try touch(imports.appendingPathComponent("Bilder/old.jpg"), "old photo")
    try touch(imports.appendingPathComponent("Photos/new.jpg"), "new photo")
    MediaImport.migrateNames(in: imports)
    #expect(read(imports.appendingPathComponent("Videos/BCES00569.mp4")) == "video")
    #expect(!exists(imports.appendingPathComponent("Filmer")))
    // Photos was already there, so Bilder stays as it is.
    #expect(read(imports.appendingPathComponent("Photos/new.jpg")) == "new photo")
    #expect(read(imports.appendingPathComponent("Bilder/old.jpg")) == "old photo")
}

@Test func renamesTheMirrorsSwedishFolders() throws {
    let root = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appendingPathComponent("dev_hdd0"), withIntermediateDirectories: true)
    try touch(root.appendingPathComponent("_Installerat/Paket/apollo-ps3.pkg"), "pkg")
    try touch(root.appendingPathComponent("_Säkerhetskopior/notes.txt"), "backup")
    try touch(root.appendingPathComponent("_Nödläge/boot_plugins.txt"), "plugins")

    // Still found as a mirror before anything is renamed.
    #expect(MirrorRoot.looksLikeMirror(root))
    let archive = MirrorRoot.packageArchive(in: root)
    #expect(archive.standardizedFileURL == root.appendingPathComponent("_Installed/Packages").standardizedFileURL)
    #expect(read(archive.appendingPathComponent("apollo-ps3.pkg")) == "pkg")
    #expect(read(root.appendingPathComponent("_Backups/notes.txt")) == "backup")
    #expect(read(root.appendingPathComponent("_Emergency/boot_plugins.txt")) == "plugins")
    #expect(!exists(root.appendingPathComponent("_Installerat")))
    #expect(MirrorRoot.looksLikeMirror(root))

    // resolve() renames too, and leaves an old folder alone once the new one exists.
    let other = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: other) }
    try FileManager.default.createDirectory(at: other.appendingPathComponent("dev_hdd0"), withIntermediateDirectories: true)
    try touch(other.appendingPathComponent("_Installerat/Paket/a.pkg"), "old")
    try touch(other.appendingPathComponent("_Installed/Packages/b.pkg"), "new")
    try touch(other.appendingPathComponent("_Nödläge/boot_plugins.txt"), "plugins")
    let resolved = MirrorRoot.resolve(config: PS3Config(root: other.path))
    #expect(resolved?.standardizedFileURL == other.standardizedFileURL)
    #expect(exists(other.appendingPathComponent("_Installerat/Paket/a.pkg")))
    #expect(exists(other.appendingPathComponent("_Installed/Packages/b.pkg")))
    #expect(read(other.appendingPathComponent("_Emergency/boot_plugins.txt")) == "plugins")
}

@Test func formatsSizesAndDatesInEnglish() {
    #expect(Format.bytes(0) == "0 KB")
    #expect(Format.bytes(499) == "0 KB")
    #expect(Format.bytes(1_500) == "2 KB")
    #expect(Format.bytes(999_499) == "999 KB")
    #expect(Format.bytes(999_500) == "1 MB")
    #expect(Format.bytes(529_200_000) == "529.2 MB")
    #expect(Format.bytes(529_250_000) == "529.3 MB")
    #expect(Format.bytes(1_000_000_000) == "1 GB")
    #expect(Format.bytes(1_005_000_000) == "1.01 GB")
    #expect(Format.bytes(13_400_000_000) == "13.4 GB")
    #expect(Format.bytes(13_480_000_000) == "13.48 GB")
    #expect(Format.bytes(355_800_000_000) == "355.8 GB")
    #expect(Format.bytes(999_995_000_000) == "1 TB")
    #expect(Format.bytes(1_234_567_890_123) == "1.23 TB")
    #expect(Format.bytes(1_234_567_890_123_456) == "1,234.57 TB")
    #expect(Format.rate(3_250_000) == "3.3 MB/s")

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 18, minute: 12))!
    #expect(Format.day(date) == "Oct 12, 2026")
    #expect(Format.time(date) == "18:12")
}
