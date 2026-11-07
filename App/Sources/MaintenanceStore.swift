import Foundation
import Observation
import PS3Kit

/// The Maintenance tab: save and system file backups, the maintenance check, the storage map and
/// copying the disc. Like `ps3 saves`, `ps3 backup`, `ps3 maintain`, `ps3 analyze` and `ps3 rip`.
@MainActor
@Observable
final class MaintenanceStore {
    var host: String?

    private(set) var localSaves = SaveBackupService.local()
    /// The saves on the console, read when the Saves sheet asks.
    private(set) var consoleSaves: [SaveGame]?
    private(set) var lastSaveBackup = SaveBackupService.lastBackup()
    private(set) var systemBackups = SystemFiles.backups().compactMap(MaintenanceStore.date(of:))
    private(set) var report: MaintenanceReport?
    private(set) var storage: StorageMap?
    private(set) var disc: DiscInfo?
    private(set) var discNote: String?
    private(set) var ripped: Int64?
    /// Recordings and photos on the console not copied to the Mac yet, nil until looked for.
    private(set) var media: [MediaImport.Item]?
    /// What is running ("Kopierar Gran Turismo 5"), one thing at a time.
    private(set) var busy: String?
    /// The outcome of the last action, or why it failed.
    private(set) var note: String?
    /// The weekly backup of the saves (on unless turned off).
    private(set) var autoBackup = UserDefaults.standard.object(forKey: "autoSaveBackup") as? Bool ?? true

    private var isFixture = false
    private var ripTask: Task<Void, Never>?
    /// While the disc is being copied (the view used to compare `busy` with its text).
    private(set) var isRipping = false

    /// "2026-10-22 21.40" (a backup folder's name) → a date.
    nonisolated static func date(of folder: URL) -> Date? {
        let formatter = DateFormatter()
        // The same fixed format SystemFiles.backup writes: the user's 12-hour setting must not
        // change how "21.40" is read.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return formatter.date(from: folder.lastPathComponent)
    }

    func loadFixture() {
        isFixture = true
        localSaves = Fixtures.saves
        consoleSaves = Fixtures.saves
        lastSaveBackup = Date(timeIntervalSince1970: 1_792_670_400)
        systemBackups = [Date(timeIntervalSince1970: 1_792_670_400), Date(timeIntervalSince1970: 1_791_000_000)]
        report = Fixtures.maintenanceReport
        storage = Fixtures.storageMap
        disc = Fixtures.disc
        media = Fixtures.mediaItems
    }

    func setAutoBackup(_ on: Bool) {
        autoBackup = on
        UserDefaults.standard.set(on, forKey: "autoSaveBackup")
    }

    // MARK: Backups

    func backupSaves() {
        run("Backing up the saves") { host in
            let report = try await SaveBackupService(host: host).backup { step in
                Task { @MainActor in self.busy = step }
            }
            await MainActor.run {
                self.localSaves = SaveBackupService.local()
                self.lastSaveBackup = SaveBackupService.lastBackup()
            }
            return "Saves: \(report.copied.count) copied, \(report.unchanged) unchanged"
                + (report.failed.isEmpty ? "" : ", \(report.failed.count) failed")
        }
    }

    func backupSystem() {
        run("Backing up the system files") { host in
            let result = try await SystemFiles.backup(host: host)
            await MainActor.run { self.systemBackups = SystemFiles.backups().compactMap(MaintenanceStore.date(of:)) }
            return "System files: \(result.saved.count) files copied"
        }
    }

    func loadConsoleSaves() {
        run("Reading the saves on the PS3") { host in
            let saves = try await SaveBackupService(host: host).list()
            await MainActor.run { self.consoleSaves = saves }
            return "\(saves.count) saves on the PS3"
        }
    }

    /// Removes a save from the console; a copy goes to the backup first, so it can be put back.
    func deleteSave(_ save: SaveGame) {
        run("Deleting \(save.title)") { host in
            try await SaveBackupService(host: host).delete(save)
            await MainActor.run {
                self.consoleSaves?.removeAll { $0.id == save.id }
                self.localSaves = SaveBackupService.local()
            }
            return "\(save.title) is deleted from the PS3. A copy is under On Mac."
        }
    }

    func restore(_ save: SaveGame) {
        run("Restoring \(save.title)") { host in
            try await SaveBackupService(host: host).restore(save)
            return "\(save.title) is back on the PS3"
        }
    }

    /// Once a week when the console is on and idle; reads only.
    func autoBackupIfDue(gameRunning: Bool, transfersRunning: Bool) {
        guard autoBackup, !isFixture, busy == nil, !gameRunning, !transfersRunning, let host else { return }
        if let last = lastSaveBackup, Date().timeIntervalSince(last) < 7 * 24 * 3600 { return }
        busy = "Backing up the saves (weekly)"
        Task {
            if let report = try? await SaveBackupService(host: host).backup() {
                localSaves = SaveBackupService.local()
                lastSaveBackup = SaveBackupService.lastBackup()
                if !report.copied.isEmpty {
                    Notifier.post(title: "Saves backed up", body: "\(report.copied.count) saves changed since last week.")
                }
            }
            busy = nil
        }
    }

    // MARK: Check and clean

    func check() {
        run("Checking") { host in
            let report = try await MaintenanceService(host: host).check { step in
                Task { @MainActor in self.busy = step }
            }
            await MainActor.run { self.report = report }
            return report.findings.isEmpty ? "Everything looks good" : "\(report.findings.count) things to look at"
        }
    }

    var fixable: [MaintenanceFinding] { report?.findings.filter(\.canFix) ?? [] }

    func fix() {
        let findings = fixable
        guard !findings.isEmpty else { return }
        run("Deleting") { host in
            let results = try await MaintenanceService(host: host).fix(findings)
            let removed = Set(results.filter { $0.skipped == nil }.map { $0.finding.id })
            await MainActor.run { self.report?.findings.removeAll { removed.contains($0.id) } }
            return "\(removed.count) of \(findings.count) deleted"
        }
    }

    /// Puts webMAN MOD's ps3-updatelist.txt on the console, so the XMB cannot fetch a system update.
    func blockUpdates() {
        run("Blocking system updates") { host in
            try await UpdateBlock.set(true, host: host)
            await MainActor.run {
                self.report?.findings.removeAll { $0.kind == .updates }
                self.report?.passed.append("System updates are blocked")
            }
            return "System updates are blocked from the next start."
        }
    }

    // MARK: Films and pictures

    func loadMedia() {
        guard !isFixture, let host else { return }
        Task { media = try? await MediaImport(host: host).newItems() }
    }

    /// Copies new recordings and photos to ~/Pictures/PS3 Center. Nothing is removed from the console.
    func importMedia() {
        guard let items = media, !items.isEmpty else { return }
        run("Importing videos and photos") { host in
            let written = try await MediaImport(host: host).copy(items) { done, total in
                Task { @MainActor in self.busy = "Importing \(min(done + 1, total)) of \(total)" }
            }
            await MainActor.run { self.media = [] }
            return "\(written.count) files in Pictures/PS3 Center"
        }
    }

    // MARK: Storage and disc

    func analyze() {
        run("Counting") { host in
            let map = try await StorageAnalyzer(host: host).analyze { step in
                Task { @MainActor in self.busy = "Counting \(step)" }
            }
            await MainActor.run { self.storage = map }
            return "Storage counted"
        }
    }

    func loadDisc() {
        guard !isFixture, let host else { return }
        Task {
            do {
                disc = try await DiscRipper(host: host).disc()
                discNote = disc == nil ? "No PS3 disc in the drive." : nil
            } catch {
                disc = nil
                discNote = error.localizedDescription
            }
        }
    }

    func rip() {
        guard let disc, let host, busy == nil, !isFixture else { return }
        busy = "Copying the disc"
        isRipping = true
        ripped = 0
        note = nil
        ripTask = Task {
            do {
                try await DiscRipper(host: host).rip(disc) { copied in
                    Task { @MainActor in self.ripped = copied }
                }
                note = "\(disc.title) is in \(disc.destination). Refresh the game list to see it."
            } catch is CancellationError {
                note = "Stopped following the copy; it keeps going on the PS3 until it is stopped."
            } catch {
                note = error.localizedDescription
            }
            busy = nil
            isRipping = false
            ripTask = nil
        }
    }

    func abortRip() {
        guard let host else { return }
        ripTask?.cancel()
        Task {
            try? await DiscRipper(host: host).abort()
            note = "The copy was stopped"
        }
    }

    // MARK: Running

    private func run(_ label: String, _ work: @escaping @Sendable (String) async throws -> String) {
        guard !isFixture, busy == nil, let host else { return }
        busy = label
        note = nil
        Task {
            do {
                note = try await work(host)
            } catch {
                note = error.localizedDescription
            }
            busy = nil
        }
    }
}
