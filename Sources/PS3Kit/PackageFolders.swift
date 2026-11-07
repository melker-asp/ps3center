import Foundation

/// The Mac's package folders: where the user keeps .pkg files, linked in the app (Apps → From
/// Mac → Package Folders) or with `ps3 config folder add PKG ~/Packages`, saved as `packageFolders`
/// in config.json. Packages are installed from there and stay where they are, unlike a single .pkg
/// given to `ps3 apps install`, which is archived in _Installed/Packages.
public enum PackageFolders {
    /// The type `ps3 config folder add` takes for a package folder, beside PS3ISO, GAMES …
    public static let kindName = "PKG"

    public static func isKind(_ name: String) -> Bool {
        name.caseInsensitiveCompare(kindName) == .orderedSame
    }

    /// Every linked folder, also one on a drive that is not plugged in: `PackageLibrary` skips
    /// what it cannot read.
    public static func linked(config: PS3Config = ConfigStore.load()) -> [URL] {
        var seen = Set<String>()
        return (config.packageFolders ?? []).map(standardized).filter { seen.insert($0.path).inserted }
    }

    /// Whether `file` lies in a linked folder or in a folder below it.
    public static func contains(_ file: URL, config: PS3Config = ConfigStore.load()) -> Bool {
        let path = file.standardizedFileURL.path
        return linked(config: config).contains { path.hasPrefix($0.path + "/") }
    }

    public static func add(_ folder: URL) throws {
        var config = ConfigStore.load()
        let path = folder.standardizedFileURL.path
        var folders = config.packageFolders ?? []
        if !folders.contains(where: { standardized($0).path == path }) { folders.append(path) }
        config.packageFolders = folders
        try ConfigStore.save(config)
    }

    /// Unlinks `folder`; the files in it are not touched.
    public static func remove(_ folder: URL) throws {
        var config = ConfigStore.load()
        let path = folder.standardizedFileURL.path
        config.packageFolders?.removeAll { standardized($0).path == path }
        if config.packageFolders?.isEmpty == true { config.packageFolders = nil }
        try ConfigStore.save(config)
    }

    static func standardized(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    }
}

/// A PS3 package in one of the Mac's package folders.
public struct LocalPackage: Codable, Sendable, Identifiable, Hashable {
    public let path: String
    /// The linked folder it was found in; the file may lie in a folder below it.
    public let folder: String
    /// From the package header, e.g. "UP0001-NP0APOLLO_00-0000000000000000".
    public let contentID: String
    public let titleID: String?
    public let size: Int64
    /// When the file was put in its folder (Finder's Date Added), else when it was created.
    public let added: Date?
    /// The catalog program with the same title ID: its name, icon and requirements apply.
    public let catalogID: String?
    /// The catalog program's name, else the file name without .pkg. A package's own title lies
    /// in its encrypted part, which PS3 Center does not open.
    public let title: String

    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }
    public var fileName: String { (path as NSString).lastPathComponent }

    public init(path: String, folder: String, contentID: String, size: Int64, added: Date? = nil) {
        self.path = path
        self.folder = folder
        self.contentID = contentID
        self.size = size
        self.added = added
        titleID = PKGInfo(contentID: contentID).titleID
        let entry = titleID.flatMap(Catalog.entry(titleID:))
        catalogID = entry?.id
        title = entry?.name ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}

public enum PackageLibrary {
    /// The PS3 packages in `folders` and the folders right below them: files ending in .pkg
    /// that start with the package magic. Sorted by title. A folder that cannot be read (a
    /// drive that is not plugged in) is skipped, and a file found through two linked folders
    /// is listed once.
    public static func scan(folders: [URL] = PackageFolders.linked()) -> [LocalPackage] {
        var seen = Set<String>()
        var result: [LocalPackage] = []
        for folder in folders {
            for file in packageFiles(in: folder) where seen.insert(file.path).inserted {
                guard let info = PKGInfo(url: file) else { continue }
                let values = try? file.resourceValues(forKeys: [.fileSizeKey, .addedToDirectoryDateKey, .creationDateKey])
                result.append(LocalPackage(path: file.path, folder: folder.path, contentID: info.contentID,
                                           size: Int64(values?.fileSize ?? 0),
                                           added: values?.addedToDirectoryDate ?? values?.creationDate))
            }
        }
        return result.sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
        }
    }

    /// The .pkg files in `folder` and one level down, hidden files left out.
    static func packageFiles(in folder: URL) -> [URL] {
        let fm = FileManager.default
        func list(_ url: URL) -> [URL] {
            (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        }
        func isDirectory(_ url: URL) -> Bool { (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        func isPackage(_ url: URL) -> Bool { url.pathExtension.lowercased() == "pkg" && !isDirectory(url) }
        var files: [URL] = []
        for url in list(folder.standardizedFileURL) {
            if isDirectory(url) {
                files += list(url).filter(isPackage)
            } else if isPackage(url) {
                files.append(url)
            }
        }
        return files.map(\.standardizedFileURL)
    }

    /// "Installed 01.30", "Installed" (no APP_VER) or "Not installed", from an entry in
    /// `AppsService.installedVersions`.
    public static func installedLabel(_ version: String?) -> String {
        guard let version else { return "Not installed" }
        return version.isEmpty ? "Installed" : "Installed \(version)"
    }
}
