import Foundation
import Observation
import PS3Kit

/// The Underhåll tab: save and system file backups, the maintenance check, the storage map and
/// copying the disc. Like `ps3 saves`, `ps3 backup`, `ps3 maintain`, `ps3 analyze` and `ps3 rip`.
@MainActor
@Observable
final class MaintenanceStore {
    var host: String?

    private(set) var localSaves = SaveBackupService.local()
    private(set) var lastSaveBackup = SaveBackupService.lastBackup()
    private(set) var systemBackups = SystemFiles.backups().compactMap(MaintenanceStore.date(of:))
    private(set) var report: MaintenanceReport?
    private(set) var storage: StorageMap?
    private(set) var disc: DiscInfo?
    private(set) var discNote: String?
    private(set) var ripped: Int64?
    /// What is running ("Kopierar Gran Turismo 5"), one thing at a time.
    private(set) var busy: String?
    /// The outcome of the last action, or why it failed.
    private(set) var note: String?
    /// The weekly backup of the saves (on unless turned off).
    private(set) var autoBackup = UserDefaults.standard.object(forKey: "autoSaveBackup") as? Bool ?? true

    private var isFixture = false
    private var ripTask: Task<Void, Never>?

    /// "2026-10-22 21.40" (a backup folder's name) → a date.
    nonisolated static func date(of folder: URL) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return formatter.date(from: folder.lastPathComponent)
    }

    func loadFixture() {
        isFixture = true
        localSaves = Fixtures.saves
        lastSaveBackup = Date(timeIntervalSince1970: 1_792_670_400)
        systemBackups = [Date(timeIntervalSince1970: 1_792_670_400), Date(timeIntervalSince1970: 1_791_000_000)]
        report = Fixtures.maintenanceReport
        storage = Fixtures.storageMap
        disc = Fixtures.disc
    }

    func setAutoBackup(_ on: Bool) {
        autoBackup = on
        UserDefaults.standard.set(on, forKey: "autoSaveBackup")
    }

    // MARK: Backups

    func backupSaves() {
        run("Kopierar sparfilerna") { host in
            let report = try await SaveBackupService(host: host).backup { step in
                Task { @MainActor in self.busy = step }
            }
            await MainActor.run {
                self.localSaves = SaveBackupService.local()
                self.lastSaveBackup = SaveBackupService.lastBackup()
            }
            return "Sparfiler: \(report.copied.count) kopierade, \(report.unchanged) oförändrade"
                + (report.failed.isEmpty ? "" : ", \(report.failed.count) gick inte")
        }
    }

    func backupSystem() {
        run("Kopierar systemfilerna") { host in
            let result = try await SystemFiles.backup(host: host)
            await MainActor.run { self.systemBackups = SystemFiles.backups().compactMap(MaintenanceStore.date(of:)) }
            return "Systemfiler: \(result.saved.count) filer kopierade"
        }
    }

    func restore(_ save: SaveGame) {
        run("Lägger tillbaka \(save.title)") { host in
            try await SaveBackupService(host: host).restore(save)
            return "\(save.title) är tillbaka på PS3:an"
        }
    }

    /// Once a week when the console is on and idle; reads only.
    func autoBackupIfDue(gameRunning: Bool, transfersRunning: Bool) {
        guard autoBackup, !isFixture, busy == nil, !gameRunning, !transfersRunning, let host else { return }
        if let last = lastSaveBackup, Date().timeIntervalSince(last) < 7 * 24 * 3600 { return }
        busy = "Kopierar sparfilerna (varje vecka)"
        Task {
            if let report = try? await SaveBackupService(host: host).backup() {
                localSaves = SaveBackupService.local()
                lastSaveBackup = SaveBackupService.lastBackup()
                if !report.copied.isEmpty {
                    Notifier.post(title: "Sparfilerna är kopierade", body: "\(report.copied.count) sparfiler har ändrats sedan förra veckan.")
                }
            }
            busy = nil
        }
    }

    // MARK: Check and clean

    func check() {
        run("Kontrollerar") { host in
            let report = try await MaintenanceService(host: host).check { step in
                Task { @MainActor in self.busy = step }
            }
            await MainActor.run { self.report = report }
            return report.findings.isEmpty ? "Allt ser bra ut" : "\(report.findings.count) saker att titta på"
        }
    }

    var fixable: [MaintenanceFinding] { report?.findings.filter(\.canFix) ?? [] }

    func fix() {
        let findings = fixable
        guard !findings.isEmpty else { return }
        run("Tar bort") { host in
            let results = try await MaintenanceService(host: host).fix(findings)
            let removed = Set(results.filter { $0.skipped == nil }.map { $0.finding.id })
            await MainActor.run { self.report?.findings.removeAll { removed.contains($0.id) } }
            return "\(removed.count) av \(findings.count) borttagna"
        }
    }

    // MARK: Storage and disc

    func analyze() {
        run("Räknar") { host in
            let map = try await StorageAnalyzer(host: host).analyze { step in
                Task { @MainActor in self.busy = "Räknar \(step.lowercased())" }
            }
            await MainActor.run { self.storage = map }
            return "Lagringen är räknad"
        }
    }

    func loadDisc() {
        guard !isFixture, let host else { return }
        Task {
            do {
                disc = try await DiscRipper(host: host).disc()
                discNote = disc == nil ? "Ingen PS3-skiva i spelaren." : nil
            } catch {
                disc = nil
                discNote = error.localizedDescription
            }
        }
    }

    func rip() {
        guard let disc, let host, busy == nil, !isFixture else { return }
        busy = "Kopierar skivan"
        ripped = 0
        note = nil
        ripTask = Task {
            do {
                try await DiscRipper(host: host).rip(disc) { copied in
                    Task { @MainActor in self.ripped = copied }
                }
                note = "\(disc.title) ligger i \(disc.destination). Uppdatera spellistan så syns det."
            } catch is CancellationError {
                note = "Slutade följa kopieringen; den fortsätter på PS3:an tills den stoppas."
            } catch {
                note = error.localizedDescription
            }
            busy = nil
            ripTask = nil
        }
    }

    func abortRip() {
        guard let host else { return }
        ripTask?.cancel()
        Task {
            try? await DiscRipper(host: host).abort()
            note = "Kopieringen stoppades"
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
