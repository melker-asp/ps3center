import Foundation

/// PS3 Center's own folder for backups: ~/Library/Application Support/ps3center/<name>.
enum BackupFolder {
    static var base: URL { StatePaths.support }

    static func url(_ name: String) -> URL {
        base.appendingPathComponent(name, isDirectory: true)
    }

    /// Renames a folder or file from the name it had before PS3 Center was in English: only
    /// when the old one exists and the new one does not. When both exist the new one is used
    /// and the old one is left alone. Returns true when something was moved.
    @discardableResult
    static func migrate(_ old: String, to new: String, in parent: URL) -> Bool {
        let fm = FileManager.default
        let source = parent.appendingPathComponent(old)
        let target = parent.appendingPathComponent(new)
        guard fm.fileExists(atPath: source.path), !fm.fileExists(atPath: target.path) else { return false }
        return (try? fm.moveItem(at: source, to: target)) != nil
    }
}

/// Folders that kept their Swedish name beside the English one. `BackupFolder.migrate` leaves
/// both alone, which happens when an older PS3 Center (the app or ps3 from before Nov 7, 2026)
/// makes the Swedish one again after the rename. What lies there is then not seen, so the
/// maintenance report names it; nothing is moved or merged by itself.
public enum FolderMigration {
    public struct Leftover: Equatable, Sendable {
        public let old: URL
        public let new: URL
    }

    public static func leftovers() -> [Leftover] {
        leftovers(base: BackupFolder.base, mirror: MirrorRoot.resolve(), media: MediaImport.defaultFolder)
    }

    static func leftovers(base: URL, mirror: URL?, media: URL) -> [Leftover] {
        var pairs: [(parent: URL, old: String, new: String)] = [
            (base, "Sparfiler", SaveBackupService.rootName),
            (base, "Systemfiler", SystemFiles.rootName),
            (media, "Filmer", MediaImport.videoFolderName),
            (media, "Bilder", MediaImport.photoFolderName),
        ]
        if let mirror {
            pairs += [(mirror, "_Installerat", MirrorRoot.installedFolder),
                      (mirror, "_Säkerhetskopior", MirrorRoot.backupsFolder),
                      (mirror, "_Nödläge", MirrorRoot.emergencyFolder)]
        }
        let fm = FileManager.default
        return pairs.compactMap { pair in
            let old = pair.parent.appendingPathComponent(pair.old, isDirectory: true)
            let new = pair.parent.appendingPathComponent(pair.new, isDirectory: true)
            return fm.fileExists(atPath: old.path) && fm.fileExists(atPath: new.path) ? Leftover(old: old, new: new) : nil
        }
    }
}
