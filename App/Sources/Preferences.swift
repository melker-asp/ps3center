import Foundation
import Observation
import PS3Kit
import SwiftUI

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
        let tab: MainTab
        if choice == .lastUsed {
            tab = defaults.string(forKey: lastTabKey).flatMap(MainTab.init(rawValue:)) ?? .status
        } else {
            tab = MainTab(rawValue: choice.rawValue) ?? .status
        }
        // A hidden tab can't be opened in.
        let hidden = Set((defaults.stringArray(forKey: AppPreferences.hiddenTabsKey) ?? []).compactMap(MainTab.init(rawValue:)))
        return hidden.contains(tab) ? .status : tab
    }
}

/// The Status tab's cards, in the order Settings → Status puts them.
enum StatusCard: String, CaseIterable, Identifiable {
    case health, cpu, rsx, fan, free, network, nowPlaying, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .health: return "Health"
        case .cpu: return "CPU"
        case .rsx: return "RSX"
        case .fan: return "Fan"
        case .free: return "Free"
        case .network: return "Network"
        case .nowPlaying: return "Now Playing"
        case .system: return "System"
        }
    }

    var symbol: String {
        switch self {
        case .health: return "sun.max"
        case .cpu: return "cpu"
        case .rsx: return "square.stack.3d.up"
        case .fan: return "fan"
        case .free: return "internaldrive"
        case .network: return "network"
        case .nowPlaying: return "gamecontroller"
        case .system: return "shield.lefthalf.filled"
        }
    }
}

/// The quick buttons in the menu bar panel that can be hidden.
enum MenuBarAction: String, CaseIterable, Identifiable {
    case sendFiles, refreshGames, quitGame, shutDown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sendFiles: return "Send Files…"
        case .refreshGames: return "Refresh Game List"
        case .quitGame: return "Quit Game"
        case .shutDown: return "Shut Down PS3…"
        }
    }
}

/// Only how temperatures are shown: the fan target stays 60–75 °C inside, and the CLI and
/// `ps3 mcp` keep Celsius.
enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius, fahrenheit

    var id: String { rawValue }

    var symbol: String { self == .celsius ? "°C" : "°F" }

    func value(_ celsius: Int) -> Int {
        self == .celsius ? celsius : Int((Double(celsius) * 9 / 5 + 32).rounded())
    }

    func value(_ celsius: Double) -> Int { value(Int(celsius.rounded())) }

    /// "68 °C" or "154 °F".
    func format(_ celsius: Int) -> String { "\(value(celsius)) \(symbol)" }
}

/// Every text size goes through `Font.ui`, which multiplies by this.
enum TextScale: String, CaseIterable, Identifiable {
    case standard, large, larger

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Default"
        case .large: return "Large"
        case .larger: return "Larger"
        }
    }

    var factor: CGFloat {
        switch self {
        case .standard: return 1
        case .large: return 1.12
        case .larger: return 1.24
        }
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

    /// The tips in the tabs (Settings → Help → Show Tips).
    var showsTips: Bool {
        didSet { store(showsTips, Self.tipsKey) }
    }

    /// Tips closed with Got It; Show Them Again empties it.
    var dismissedTips: Set<AppTip> {
        didSet { store(dismissedTips.map(\.rawValue).sorted(), Self.dismissedTipsKey) }
    }

    /// The Status tab's cards in their order, and those turned off.
    var statusCardOrder: [StatusCard] {
        didSet { store(statusCardOrder.map(\.rawValue), Self.cardOrderKey) }
    }

    var hiddenStatusCards: Set<StatusCard> {
        didSet { store(hiddenStatusCards.map(\.rawValue).sorted(), Self.hiddenCardsKey) }
    }

    /// Never Status, which is where the app goes when a tab is hidden.
    var hiddenTabs: Set<MainTab> {
        didSet { store(hiddenTabs.map(\.rawValue).sorted(), Self.hiddenTabsKey) }
    }

    var hiddenMenuBarActions: Set<MenuBarAction> {
        didSet { store(hiddenMenuBarActions.map(\.rawValue).sorted(), Self.hiddenMenuBarKey) }
    }

    var temperatureUnit: TemperatureUnit {
        didSet { store(temperatureUnit.rawValue, Self.temperatureKey) }
    }

    /// Read by `Font.ui` on every text, so changing it redraws the whole window.
    var textScale: TextScale {
        didSet { store(textScale.rawValue, Self.textScaleKey) }
    }

    /// The app's own, which `Font.ui` and the stores read; snapshots get the defaults.
    static let shared = AppPreferences(previewing: Snapshot.directory != nil)

    nonisolated static let menuBarKey = "showsMenuBarIcon"
    nonisolated static let tipsKey = "showsTips"
    nonisolated static let dismissedTipsKey = "dismissedTips"
    nonisolated static let cardOrderKey = "statusCardOrder"
    nonisolated static let hiddenCardsKey = "hiddenStatusCards"
    nonisolated static let hiddenTabsKey = "hiddenTabs"
    nonisolated static let hiddenMenuBarKey = "hiddenMenuBarActions"
    nonisolated static let temperatureKey = "temperatureUnit"
    nonisolated static let textScaleKey = "textScale"

    /// False for snapshots, which show the defaults and must not change the user's settings.
    private let persists: Bool
    private let defaults = UserDefaults.standard

    init(previewing: Bool = false) {
        persists = !previewing
        if previewing {
            startTab = .status
            showsMenuBarIcon = true
            mutedNotifications = []
            showsTips = true
            dismissedTips = []
            statusCardOrder = StatusCard.allCases
            hiddenStatusCards = []
            hiddenTabs = []
            hiddenMenuBarActions = []
            temperatureUnit = .celsius
            textScale = .standard
        } else {
            startTab = defaults.string(forKey: StartTab.key).flatMap(StartTab.init(rawValue:)) ?? .status
            showsMenuBarIcon = defaults.object(forKey: Self.menuBarKey) as? Bool ?? true
            mutedNotifications = NotificationKind.muted
            showsTips = defaults.object(forKey: Self.tipsKey) as? Bool ?? true
            dismissedTips = Set((defaults.stringArray(forKey: Self.dismissedTipsKey) ?? []).compactMap(AppTip.init(rawValue:)))
            // A card added later goes last.
            let saved = (defaults.stringArray(forKey: Self.cardOrderKey) ?? []).compactMap(StatusCard.init(rawValue:))
            statusCardOrder = saved + StatusCard.allCases.filter { !saved.contains($0) }
            hiddenStatusCards = Set((defaults.stringArray(forKey: Self.hiddenCardsKey) ?? []).compactMap(StatusCard.init(rawValue:)))
            hiddenTabs = Set((defaults.stringArray(forKey: Self.hiddenTabsKey) ?? []).compactMap(MainTab.init(rawValue:))).subtracting([.status])
            hiddenMenuBarActions = Set((defaults.stringArray(forKey: Self.hiddenMenuBarKey) ?? []).compactMap(MenuBarAction.init(rawValue:)))
            temperatureUnit = defaults.string(forKey: Self.temperatureKey).flatMap(TemperatureUnit.init(rawValue:)) ?? .celsius
            textScale = defaults.string(forKey: Self.textScaleKey).flatMap(TextScale.init(rawValue:)) ?? .standard
        }
    }

    var visibleStatusCards: [StatusCard] { statusCardOrder.filter { !hiddenStatusCards.contains($0) } }

    var visibleTabs: [MainTab] { MainTab.allCases.filter { !hiddenTabs.contains($0) } }

    func moveStatusCard(_ card: StatusCard, by offset: Int) {
        guard let index = statusCardOrder.firstIndex(of: card) else { return }
        let target = index + offset
        guard statusCardOrder.indices.contains(target) else { return }
        statusCardOrder.swapAt(index, target)
    }

    func setShows(_ card: StatusCard, _ on: Bool) {
        if on { hiddenStatusCards.remove(card) } else { hiddenStatusCards.insert(card) }
    }

    func setShows(_ tab: MainTab, _ on: Bool) {
        guard tab != .status else { return }
        if on { hiddenTabs.remove(tab) } else { hiddenTabs.insert(tab) }
    }

    func setShows(_ action: MenuBarAction, _ on: Bool) {
        if on { hiddenMenuBarActions.remove(action) } else { hiddenMenuBarActions.insert(action) }
    }

    func notifies(_ kind: NotificationKind) -> Bool { !mutedNotifications.contains(kind) }

    func setNotifies(_ kind: NotificationKind, _ on: Bool) {
        if on { mutedNotifications.remove(kind) } else { mutedNotifications.insert(kind) }
    }

    /// A tip shows until Got It, while tips are on.
    func shows(_ tip: AppTip) -> Bool { showsTips && !dismissedTips.contains(tip) }

    func dismiss(_ tip: AppTip) { dismissedTips.insert(tip) }

    /// The tab the window was on, for "Last Used".
    func remember(_ tab: MainTab) {
        store(tab.rawValue, StartTab.lastTabKey)
    }

    private func store(_ value: Any, _ key: String) {
        guard persists else { return }
        defaults.set(value, forKey: key)
    }
}

/// Opens sheets and overlays from places that are not where they are drawn: ⌘, and ⌘? in the menu,
/// the menu bar panel, the setup guide and Help.
@MainActor
@Observable
final class AppRouter {
    var showsSettings = false
    var settingsSection: SettingsSection = .general
    /// The setup guide covers the window on the first launch (`Onboarding.isNeeded`).
    var showsOnboarding = Onboarding.isNeeded
    var showsHelp = false
    var helpItem: HelpItem = .guide(.gettingStarted)
    /// The connection sheet (Find PS3…): on the window, so it stays open when the console it
    /// switched to comes online and the splash screen gives way to the tabs.
    var showsConnection = false
    /// The tour's step while it runs, else nil.
    var tourStep: TourStep?

    func openSettings(_ section: SettingsSection = .general) {
        settingsSection = section
        showsSettings = true
        WindowOpener.shared.showMain()
    }

    func openHelp(_ item: HelpItem? = nil) {
        if let item { helpItem = item }
        present { $0.showsHelp = true }
    }

    func openConnection() {
        present { $0.showsConnection = true }
    }

    /// Shows a sheet on the window. From Settings or Help, those close first and the new sheet
    /// waits: AppKit drops a sheet presented while another one is still closing.
    private func present(_ show: @escaping (AppRouter) -> Void) {
        WindowOpener.shared.showMain()
        guard showsSettings || showsHelp else {
            show(self)
            return
        }
        showsSettings = false
        showsHelp = false
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            show(self)
        }
    }

    /// Settings → Help → Show Setup Again.
    func showOnboarding() {
        showsSettings = false
        showsHelp = false
        tourStep = nil
        showsOnboarding = true
    }

    func finishOnboarding(takeTour: Bool) {
        Onboarding.finish()
        showsOnboarding = false
        if takeTour { startTour() }
    }

    func startTour() {
        showsSettings = false
        showsHelp = false
        showsOnboarding = false
        tourStep = TourStep.allCases.first
    }
}

/// Opens a guide or a glossary term in Help. A no-op where there is no window (snapshots), so any
/// view can ask without checking.
struct OpenHelpAction {
    var run: (HelpItem) -> Void = { _ in }

    func callAsFunction(_ guide: GuideID) { run(.guide(guide)) }
    func callAsFunction(_ item: HelpItem) { run(item) }
}

extension EnvironmentValues {
    @Entry var openHelp = OpenHelpAction()
}
