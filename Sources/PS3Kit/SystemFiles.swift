import Foundation

/// Copies of the console's settings and plugin lists, read only: the system settings
/// (xRegistry.sys), webMAN's settings and the boot_plugins lists. Each backup is a dated folder
/// in System Files with the console's paths inside. The files are never read or shown.
public enum SystemFiles {
    public static let paths = [
        "/dev_flash2/etc/xRegistry.sys",
        "/dev_hdd0/tmp/wm_config.bin",
        "/dev_hdd0/boot_plugins.txt",
        "/dev_hdd0/boot_plugins_kernel.txt",
        "/dev_hdd0/boot_plugins_nocobra.txt",
        "/dev_hdd0/boot_plugins_nocobra_dex.txt",
    ]

    public static var root: URL {
        _ = migration
        return BackupFolder.url(rootName)
    }

    static let rootName = "System Files"

    /// Once per process: the folder's Swedish name from before (Systemfiler) becomes the English one.
    private static let migration: Void = migrateNames(in: BackupFolder.base)

    static func migrateNames(in base: URL) {
        BackupFolder.migrate("Systemfiler", to: rootName, in: base)
    }

    /// The paths that existed and were copied, and the folder they went to.
    public static func backup(host: String) async throws -> (folder: URL, saved: [String]) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let folder = root.appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
        let saved = try await TransferService(host: host).withFTP { ftp -> [String] in
            var saved: [String] = []
            for path in Self.paths {
                guard let data = try await ftp.download(path, limit: 16 << 20) else { continue }
                let target = folder.appendingPathComponent(String(path.dropFirst()))
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: target)
                saved.append(path)
            }
            return saved
        }
        return (folder, saved)
    }

    /// The backups, newest first.
    public static func backups() -> [URL] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return folders.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}
