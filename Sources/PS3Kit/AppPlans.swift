import Foundation

// How the catalog is grouped and how "Update All" decides, for the Apps tab and `ps3 apps`
// alike. These lived in AppsStore and AppsCommand separately and had started to differ.

extension AppStatus {
    /// Shown in Browse and `ps3 apps available`: can be installed, is installed, or is blocked
    /// on this console (so the user sees why it can't be).
    public var isListed: Bool { installable || installed != nil || blocked }

    /// Why "Update All" and `ps3 apps update` leave this update alone.
    public var skip: UpdateSkip {
        if ignored { return .ignored }
        if compatibility.blocksInstall { return .incompatible(compatibility.summary) }
        if let entry = Catalog.entries.first(where: { $0.id == id }), case .notifyOnly = entry.action { return .notAutomatic }
        return .noPackage(note)
    }

    /// `skip` in words, short enough for one line.
    public var skipReason: String { skip.text }
}

/// Why an update is left out of "Update All". A case, so code never has to read the words.
public enum UpdateSkip: Equatable, Sendable {
    case ignored
    case incompatible(String)
    /// HEN and plugins: the catalog's advice in `AppStatus.note` says what to do by hand.
    case notAutomatic
    case noPackage(String?)

    public var text: String {
        switch self {
        case .ignored: return "Ignored"
        case .incompatible(let summary): return summary
        case .notAutomatic: return "Never installed automatically"
        case .noPackage(let note): return note ?? "The release has no package"
        }
    }
}

/// The groups of the Apps tab's Updates list and of `ps3 apps`.
public struct AppGroups: Sendable {
    /// Updates the user has not ignored: what the badges count and "Update All" offers.
    public let updates: [AppStatus]
    public let ignored: [AppStatus]
    public let current: [AppStatus]
    /// Checked by hand (no release to compare), or the check failed.
    public let manual: [AppStatus]
    public let missing: [AppStatus]

    public init(_ statuses: [AppStatus]) {
        updates = statuses.filter(\.isPendingUpdate)
        ignored = statuses.filter { $0.state == .updateAvailable && $0.ignored }
        current = statuses.filter { $0.state == .upToDate }
        manual = statuses.filter { $0.state == .manual || $0.state == .error }
        missing = statuses.filter { $0.state == .notInstalled }
    }
}

/// What "Update All" (or `ps3 apps update`) is about to do: the updates it can install, and the
/// ones it leaves alone and why. The app shows it for review before anything happens.
public struct UpdatePlan: Identifiable, Sendable {
    public struct Skip: Identifiable, Sendable {
        public let status: AppStatus
        public let reason: String
        public var id: String { status.id }
    }

    public let id = UUID()
    public let installs: [AppStatus]
    public let skipped: [Skip]

    /// `includingIgnored` for apps named on the command line: naming one means wanting it.
    public init(_ statuses: [AppStatus], includingIgnored: Bool = false) {
        let updates = statuses.filter { $0.state == .updateAvailable && (includingIgnored || !$0.ignored) }
        installs = updates.filter(\.canInstall)
        let left = updates.filter { !$0.canInstall } + (includingIgnored ? [] : statuses.filter { $0.state == .updateAvailable && $0.ignored })
        skipped = left.map { Skip(status: $0, reason: $0.skipReason) }
    }
}

/// The outcome of "Update All" once its queue is empty: Done, Failed and Skipped, each with
/// a reason.
public struct UpdateReport: Equatable, Sendable {
    public struct Line: Equatable, Identifiable, Sendable {
        public let id: String
        public let name: String
        public let detail: String

        public init(id: String, name: String, detail: String) {
            self.id = id
            self.name = name
            self.detail = detail
        }
    }

    public var done: [Line]
    public var failed: [Line]
    public var skipped: [Line]
    public let finished: Date

    public init(done: [Line], failed: [Line], skipped: [Line], finished: Date = Date()) {
        self.done = done
        self.failed = failed
        self.skipped = skipped
        self.finished = finished
    }
}

/// A running "Update All": what it queued, and what it left out and why.
public struct UpdateBatch: Sendable {
    public enum Outcome: Sendable {
        case done
        case failed(String)
    }

    public let installs: [UpdateReport.Line]
    public let skipped: [UpdateReport.Line]
    /// What is installed now, in the order chosen.
    public let queued: [AppStatus]

    /// Starts from the reviewed `plan` and what the user `chosen`. `pending` are the ids that
    /// still need updating now: the plan is what the sheet showed when it opened, and an app
    /// that finished meanwhile (its own Update button) must not be installed again.
    public init(plan: UpdatePlan, chosen: [AppStatus], pending: Set<String>) {
        let chosenIDs = Set(chosen.map(\.id))
        let unchecked = plan.installs.filter { !chosenIDs.contains($0.id) }
            .map { UpdateReport.Line(id: $0.id, name: $0.name, detail: "Unchecked in the review") }
        let skipped = plan.skipped.map { UpdateReport.Line(id: $0.id, name: $0.status.name, detail: $0.reason) }
        queued = chosen.filter { pending.contains($0.id) }
        let outdated = chosen.filter { !pending.contains($0.id) }
            .map { UpdateReport.Line(id: $0.id, name: $0.name, detail: "Already updated") }
        installs = queued.map { UpdateReport.Line(id: $0.id, name: $0.name, detail: $0.versionChange) }
        self.skipped = outdated + unchecked + skipped
    }

    /// The report, from how each queued install ended; one without an outcome didn't run.
    public func report(_ outcomes: [String: Outcome], finished: Date = Date()) -> UpdateReport {
        var done: [UpdateReport.Line] = []
        var failed: [UpdateReport.Line] = []
        var skipped = self.skipped
        for line in installs {
            switch outcomes[line.id] {
            case .done: done.append(line)
            case .failed(let message): failed.append(UpdateReport.Line(id: line.id, name: line.name, detail: message))
            case nil: skipped.append(UpdateReport.Line(id: line.id, name: line.name, detail: "Didn't run"))
            }
        }
        return UpdateReport(done: done, failed: failed, skipped: skipped, finished: finished)
    }
}
