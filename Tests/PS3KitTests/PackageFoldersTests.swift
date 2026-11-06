import Foundation
import Testing
@testable import PS3Kit

/// The first 0x60 bytes of a .pkg: the magic and the content ID at 0x30.
private func packageHeader(_ contentID: String) -> Data {
    var header = Data([0x7F, 0x50, 0x4B, 0x47]) + Data(count: 0x2C)
    header += Data(contentID.utf8)
    header += Data(count: 0x60 - header.count)
    return header
}

@Test func scansPackageFoldersAndTheFoldersRightBelow() throws {
    let fm = FileManager.default
    let folder = fm.temporaryDirectory.appendingPathComponent("ps3center-pkg-\(UUID().uuidString)").standardizedFileURL
    try fm.createDirectory(at: folder.appendingPathComponent("Sub/Deeper"), withIntermediateDirectories: true)
    try fm.createDirectory(at: folder.appendingPathComponent("Folder.pkg"), withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: folder) }

    try packageHeader("UP0001-NP0APOLLO_00-0000000000000000").write(to: folder.appendingPathComponent("apollo-ps3.pkg"))
    try (packageHeader("UP0001-SSNE10000_00-0000000000000002") + Data(count: 100))
        .write(to: folder.appendingPathComponent("Sub/RetroArch.PKG"))
    try packageHeader("UP0001-DEEP00001_00-0000000000000000").write(to: folder.appendingPathComponent("Sub/Deeper/deep.pkg"))
    try packageHeader("UP0001-HIDE00001_00-0000000000000000").write(to: folder.appendingPathComponent(".hidden.pkg"))
    try Data("not a package".utf8).write(to: folder.appendingPathComponent("broken.pkg"))
    try Data("notes".utf8).write(to: folder.appendingPathComponent("readme.txt"))

    // Deeper/deep.pkg is two levels down; linked twice, each file is listed once.
    let packages = PackageLibrary.scan(folders: [folder, folder])
    #expect(packages.map(\.fileName) == ["apollo-ps3.pkg", "RetroArch.PKG"])

    // Sub linked too: deep.pkg is one level below it, and RetroArch keeps the first folder.
    let sub = folder.appendingPathComponent("Sub")
    let nested = PackageLibrary.scan(folders: [folder, sub])
    #expect(nested.map(\.fileName) == ["apollo-ps3.pkg", "deep.pkg", "RetroArch.PKG"])
    #expect(nested.first { $0.fileName == "deep.pkg" }?.folder == sub.path)
    #expect(nested.first { $0.fileName == "RetroArch.PKG" }?.folder == folder.path)

    let apollo = try #require(packages.first)
    #expect(apollo.title == "Apollo Save Tool")  // the catalog's name for NP0APOLLO
    #expect(apollo.catalogID == "apollo")
    #expect(apollo.titleID == "NP0APOLLO")
    #expect(apollo.folder == folder.path)
    #expect(apollo.size == 0x60)

    let retroArch = packages[1]
    #expect(retroArch.title == "RetroArch")  // not in the catalog: the file name
    #expect(retroArch.catalogID == nil)
    #expect(retroArch.titleID == "SSNE10000")
    #expect(retroArch.folder == folder.path)
    #expect(retroArch.size == 0x60 + 100)

    // A folder that cannot be read (a drive not plugged in) gives nothing.
    #expect(PackageLibrary.scan(folders: [folder.appendingPathComponent("Missing")]).isEmpty)
}

@Test func packageFoldersComeFromConfig() {
    var config = PS3Config()
    config.packageFolders = ["~/Paket", "/Volumes/Spel/Paket/", "/Volumes/Spel/Paket"]
    let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    #expect(PackageFolders.linked(config: config).map(\.path) == [home + "/Paket", "/Volumes/Spel/Paket"])
    #expect(PackageFolders.contains(URL(fileURLWithPath: "/Volumes/Spel/Paket/Sub/x.pkg"), config: config))
    #expect(!PackageFolders.contains(URL(fileURLWithPath: "/Volumes/Spel/Paketen/x.pkg"), config: config))
    #expect(!PackageFolders.contains(URL(fileURLWithPath: "/Volumes/Spel/x.pkg"), config: config))
    #expect(PackageFolders.isKind("pkg") && !PackageFolders.isKind("PS3ISO"))
    #expect(PackageFolders.linked(config: PS3Config()).isEmpty)
}

@Test func labelsWhetherAPackageIsInstalled() {
    #expect(PackageLibrary.installedLabel("01.30") == "Installerad 01.30")
    #expect(PackageLibrary.installedLabel("") == "Installerad")
    #expect(PackageLibrary.installedLabel(nil) == "Inte installerad")
}

@Test func fixturePackagesMatchTheCatalog() {
    let byFile = Dictionary(uniqueKeysWithValues: Fixtures.packages.map { ($0.fileName, $0) })
    #expect(byFile["apollo-ps3.pkg"]?.catalogID == "apollo")
    #expect(byFile["PS3-Health-v2.2.1.pkg"]?.catalogID == "ps3health")
    #expect(byFile["RetroArch_1.19.1_CEX.pkg"]?.catalogID == nil)
    #expect(byFile["multiMAN_04.93.00_BASE.pkg"]?.title == "multiMAN_04.93.00_BASE")
    // Every fixture package lies in one of the fixture's package folders.
    let folders = Set(PackageFolders.linked(config: Fixtures.folderConfig).map(\.path))
    #expect(Fixtures.packages.allSatisfy { folders.contains($0.folder) && $0.path.hasPrefix($0.folder + "/") })
}
