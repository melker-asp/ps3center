import Foundation
import Observation

/// The tab PS3 Center opens in: one of the tabs, or the one it was on when it was closed.
enum StartTab: String, CaseIterable, Identifiable {
    case lastUsed, status, games, apps, maintenance

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lastUsed: return "Last Used"
        case .status: return MainTab.status.title
        case .games: return MainTab.games.title
        case .apps: return MainTab.apps.title
        case .maintenance: return MainTab.maintenance.title
        }
    }

    static let key = "startTab"
    static let lastTabKey = "lastTab"

    /// Read straight from UserDefaults, for the window's first `@State`, before any environment.
    static func launchTab(_ defaults: UserDefaults = .standard) -> MainTab {
        let choice = defaults.string(forKey: key).flatMap(StartTab.init(rawValue:)) ?? .status
        if choice == .lastUsed {
            return defaults.string(forKey: lastTabKey).flatMap(MainTab.init(rawValue:)) ?? .status
        }
        return MainTab(rawValue: choice.rawValue) ?? .status
    }
}

/// What only the app uses, in UserDefaults. What the CLI reads too (address, folders, FTP, theme)
/// is in config.json instead (DESIGN.md, Settings).
@MainActor
@Observable
final class AppPreferences {
    var startTab: StartTab {
        didSet { store(startTab.rawValue, StartTab.key) }
    }

    /// Bound to `MenuBarExtra(isInserted:)`; ⌘-dragging the icon out of the menu bar turns it off too.
    var showsMenuBarIcon: Bool {
        didSet { store(showsMenuBarIcon, Self.menuBarKey) }
    }

    var mutedNotifications: Set<NotificationKind> {
        didSet { if persists { NotificationKind.muted = mutedNotifications } }
    }

    static let menuBarKey = "showsMenuBarIcon"

    /// False for snapshots, which show the defaults and must not change the user's settings.
    private let persists: Bool
    private let defaults = UserDefaults.standard

    init(previewing: Bool = false) {
        persists = !previewing
        if previewing {
            startTab = .status
            showsMenuBarIcon = true
            mutedNotifications = []
        } else {
            startTab = defaults.string(forKey: StartTab.key).flatMap(StartTab.init(rawValue:)) ?? .status
            showsMenuBarIcon = defaults.object(forKey: Self.menuBarKey) as? Bool ?? true
            mutedNotifications = NotificationKind.muted
        }
    }

    func notifies(_ kind: NotificationKind) -> Bool { !mutedNotifications.contains(kind) }

    func setNotifies(_ kind: NotificationKind, _ on: Bool) {
        if on { mutedNotifications.remove(kind) } else { mutedNotifications.insert(kind) }
    }

    /// The tab the window was on, for "Last Used".
    func remember(_ tab: MainTab) {
        store(tab.rawValue, StartTab.lastTabKey)
    }

    private func store(_ value: Any, _ key: String) {
        guard persists else { return }
        defaults.set(value, forKey: key)
    }
}

/// Opens sheets from places that are not the window: ⌘, in the menu and the menu bar panel.
@MainActor
@Observable
final class AppRouter {
    var showsSettings = false
    var settingsSection: SettingsSection = .general

    func openSettings(_ section: SettingsSection = .general) {
        settingsSection = section
        showsSettings = true
        WindowOpener.shared.showMain()
    }
}
