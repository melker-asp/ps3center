import AppKit
import PS3Kit
import PS3KitFixtures
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, console, appearance, status, folders, transfers, notifications, help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .console: return "Console"
        case .appearance: return "Appearance"
        case .status: return "Status"
        case .folders: return "Folders"
        case .transfers: return "Transfers"
        case .notifications: return "Notifications"
        case .help: return "Help"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .console: return "playstation.logo"
        case .appearance: return "paintpalette"
        case .status: return "square.grid.2x2"
        case .folders: return "folder"
        case .transfers: return "arrow.up.arrow.down"
        case .notifications: return "bell"
        case .help: return "questionmark.circle"
        }
    }

    var summary: String {
        switch self {
        case .general: return "How PS3 Center starts, and whether it sits in the menu bar."
        case .console: return "Which PS3 PS3 Center talks to, and how the Mac reaches it."
        case .appearance: return "Choose how PS3 Center looks: the colors, the text size and how temperatures are shown."
        case .status: return "Which cards the Status tab shows, and in what order."
        case .folders: return "Where PS3 Center finds your games and packages on the Mac. ps3 in Terminal uses the same folders."
        case .transfers: return "How games are sent to the PS3, and the weekly backup of your saves."
        case .notifications: return "What PS3 Center tells you about while it is in the background."
        case .help: return "A guide for each task, the setup guide from the first launch, the tour and the tips."
        }
    }
}

/// Settings (the gear, ⌘, and the menu bar): every setting in one sheet, with the sections on the
/// left like the PS app's Settings and Done at the bottom right. The switches that also sit where
/// they are used (Launch at Login in the menu bar, Verify with MD5 in Transfers, the weekly backup
/// in Maintenance) read and write the same values.
struct SettingsView: View {
    @State private var section: SettingsSection
    /// False when rendered for a snapshot: Fixtures and defaults, nothing read from or written to disk.
    private let live: Bool
    /// False when rendered for a snapshot: ImageRenderer cannot draw scroll views.
    private let scrolls: Bool

    init(section: SettingsSection = .general, live: Bool = true, scrolls: Bool = true) {
        _section = State(initialValue: section)
        self.live = live
        self.scrolls = scrolls
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.ui(.display, weight: .light))
                .foregroundStyle(Theme.primaryText)
                .padding(.bottom, 22)
            HStack(alignment: .top, spacing: 28) {
                sidebar
                    .frame(width: 190, alignment: .topLeading)
                Group {
                    if scrolls {
                        ScrollView { content.padding(.bottom, 8) }.scrollIndicators(.hidden)
                    } else {
                        content
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: scrolls ? .infinity : nil, alignment: .topLeading)
            }
            Spacer(minLength: 20)
            HStack {
                Spacer()
                DoneButton()
            }
        }
        .padding(32)
        .frame(width: 860, height: scrolls ? 660 : nil, alignment: .topLeading)
        .background(Theme.base)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsSection.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { section = item }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol)
                            .font(.ui(.callout, weight: .semibold))
                            .foregroundStyle(section == item ? Theme.primaryText : Theme.accent)
                            .frame(width: 20)
                        Text(item.title)
                            .font(.ui(.callout, weight: section == item ? .bold : .semibold))
                            .foregroundStyle(section == item ? Theme.primaryText : Theme.primaryText.opacity(0.75))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(section == item ? Color.white.opacity(0.14) : .clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(section == item ? .isSelected : [])
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(section.summary)
                .font(.ui(.callout))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            switch section {
            case .general: GeneralSettings(live: live)
            case .console: ConsoleSettings()
            case .appearance: AppearanceSettings()
            case .status: StatusSettings()
            case .folders: FolderSettings(live: live)
            case .transfers: TransferSettings(live: live)
            case .notifications: NotificationSettings(live: live)
            case .help: HelpSettings()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: Sections

private struct GeneralSettings: View {
    @Environment(AppPreferences.self) private var preferences
    let live: Bool
    @State private var startsAtLogin: Bool
    @State private var loginNote: String?

    init(live: Bool) {
        self.live = live
        _startsAtLogin = State(initialValue: live && LoginItem.isEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(title: "Startup") {
                SettingsStackedRow(title: "Open In", detail: "The tab PS3 Center shows when it opens.") {
                    PillPicker(options: StartTab.allCases.filter { MainTab(rawValue: $0.rawValue).map(preferences.visibleTabs.contains) ?? true },
                               selection: preferences.startTab, label: \.label) { preferences.startTab = $0 }
                }
                SettingsDivider()
                SettingsRow(title: "Launch at Login", detail: "Opens PS3 Center when you log in to the Mac.", note: loginNote) {
                    PillToggle(isOn: startsAtLogin, label: "Launch at Login") { on in
                        guard live else { return }
                        loginNote = LoginItem.set(on)
                        startsAtLogin = LoginItem.isEnabled
                    }
                }
            }
            SettingsGroup(title: "Tabs", footer: "Status always shows. A hidden tab's work still happens: the queue, the weekly backup and the update check go on.") {
                ForEach(Array(MainTab.allCases.filter { $0 != .status }.enumerated()), id: \.element) { index, tab in
                    if index > 0 { SettingsDivider() }
                    SettingsRow(title: tab.title) {
                        PillToggle(isOn: !preferences.hiddenTabs.contains(tab), label: "Show \(tab.title)") { preferences.setShows(tab, $0) }
                    }
                }
            }
            SettingsGroup(title: "Menu Bar") {
                SettingsRow(title: "Show in Menu Bar",
                            detail: "The console's status, the queue and quick buttons, also with the window closed. Without it, PS3 Center keeps running in the Dock when you close the window.") {
                    PillToggle(isOn: preferences.showsMenuBarIcon, label: "Show in Menu Bar") { preferences.showsMenuBarIcon = $0 }
                }
                if preferences.showsMenuBarIcon {
                    ForEach(MenuBarAction.allCases) { action in
                        SettingsDivider()
                        SettingsRow(title: action.title, detail: action == .quitGame ? "Only while a game is running." : nil) {
                            PillToggle(isOn: !preferences.hiddenMenuBarActions.contains(action), label: action.title) { preferences.setShows(action, $0) }
                        }
                    }
                }
            }
        }
        // The menu bar has the same switch; it may have changed since.
        .onAppear { if live { startsAtLogin = LoginItem.isEnabled } }
    }
}

private struct ConsoleSettings: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(title: "PS3",
                          footer: "The address is saved in config.json, which ps3 in Terminal reads too. If the PS3 gets a new one, PS3 Center looks for it on the network by itself.") {
                SettingsRow(title: console.host ?? "Not found yet", detail: state) {
                    Button("Find PS3…") { router.openConnection() }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .help("Search the Mac's networks, enter the address yourself, or see how to connect a cable")
                }
            }
        }
    }

    private var state: String {
        switch console.connection {
        case .online:
            guard let s = console.snapshot else { return "Connected." }
            let parts = [s.firmware.map { "Firmware \($0)" }, s.henVersion.map { "PS3HEN \($0)" }, s.webmanVersion.map { "webMAN MOD \($0)" }].compactMap { $0 }
            return (["Connected"] + parts).joined(separator: " · ")
        case .henOff: return "The PS3 is on, but HEN isn't enabled."
        case .offline: return "Can't reach the PS3."
        case .connecting, .scanning: return "Connecting…"
        }
    }
}

private struct AppearanceSettings: View {
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(title: "Text") {
                SettingsStackedRow(title: "Text Size", detail: "Every text in the window grows; the layout stays the same.") {
                    PillPicker(options: TextScale.allCases, selection: preferences.textScale, label: \.label) { preferences.textScale = $0 }
                }
                SettingsDivider()
                SettingsStackedRow(title: "Temperatures", detail: "Only how they are shown. Terminal and Claude keep Celsius.") {
                    PillPicker(options: TemperatureUnit.allCases, selection: preferences.temperatureUnit, label: { $0 == .celsius ? "Celsius (°C)" : "Fahrenheit (°F)" }) {
                        preferences.temperatureUnit = $0
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("THEME")
                    .font(.ui(.caption, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(Theme.primaryText.opacity(0.85))
                ThemePicker()
            }
        }
    }
}

private struct StatusSettings: View {
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        let order = preferences.statusCardOrder
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(title: "Cards", footer: "The arrows move a card one place; the Status tab fills four cards to a row.") {
                ForEach(Array(order.enumerated()), id: \.element) { index, card in
                    if index > 0 { SettingsDivider() }
                    HStack(spacing: 12) {
                        Image(systemName: card.symbol)
                            .font(.ui(.callout, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 22)
                        Text(card.title)
                            .font(.ui(.body))
                            .foregroundStyle(preferences.hiddenStatusCards.contains(card) ? Theme.tertiaryText : Theme.primaryText)
                        Spacer()
                        HStack(spacing: 6) {
                            Button { withAnimation(.easeInOut(duration: 0.2)) { preferences.moveStatusCard(card, by: -1) } } label: {
                                Image(systemName: "chevron.up")
                            }
                            .disabled(index == 0)
                            .iconLabel("Move \(card.title) up")
                            Button { withAnimation(.easeInOut(duration: 0.2)) { preferences.moveStatusCard(card, by: 1) } } label: {
                                Image(systemName: "chevron.down")
                            }
                            .disabled(index == order.count - 1)
                            .iconLabel("Move \(card.title) down")
                        }
                        .buttonStyle(CircleIconButtonStyle(size: 28))
                        PillToggle(isOn: !preferences.hiddenStatusCards.contains(card), label: "Show \(card.title)") { preferences.setShows(card, $0) }
                            .padding(.leading, 6)
                    }
                    .padding(.vertical, 8)
                }
            }
            HStack {
                Spacer()
                Button("Reset Cards") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        preferences.statusCardOrder = StatusCard.allCases
                        preferences.hiddenStatusCards = []
                    }
                }
                .buttonStyle(PillButtonStyle(prominent: false))
                .disabled(order == StatusCard.allCases && preferences.hiddenStatusCards.isEmpty)
            }
        }
    }
}

private struct FolderSettings: View {
    @Environment(AppsStore.self) private var apps
    @Environment(GamesStore.self) private var games
    @Environment(NetServerStore.self) private var netServer
    @Environment(ConsoleStore.self) private var console
    let live: Bool
    @State private var config: PS3Config
    @State private var root: URL?
    @State private var note: String?
    @State private var showsGameFolders = false
    @State private var showsPackageFolders = false

    init(live: Bool) {
        self.live = live
        let config = live ? ConfigStore.load() : Fixtures.folderConfig
        _config = State(initialValue: config)
        _root = State(initialValue: live ? MirrorRoot.resolve(config: config) : URL(fileURLWithPath: Fixtures.mirrorRoot))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(title: "PS3 Folder",
                          footer: "Installed packages are archived in its _Installed/Packages, and games in its dev_hdd0 folders show up under Mac in the Games tab.") {
                SettingsRow(title: root.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "Not set up",
                            detail: rootDetail, note: note, titleIsPath: root != nil) {
                    HStack(spacing: 8) {
                        if let root {
                            Button("Show in Finder") { if live { NSWorkspace.shared.activateFileViewerSelecting([root]) } }
                                .buttonStyle(PillButtonStyle(prominent: false))
                            Button("Change…") { if live { apply(PS3FolderPicker.choose()) } }
                                .buttonStyle(PillButtonStyle(prominent: false))
                        } else {
                            Button("Create…") { if live { apply(PS3FolderPicker.create()) } }
                                .buttonStyle(PillButtonStyle(prominent: false))
                                .help("Makes an empty PS3 folder with dev_hdd0 and _Installed in a place you choose")
                            Button("Choose…") { if live { apply(PS3FolderPicker.choose()) } }
                                .buttonStyle(PillButtonStyle(prominent: false))
                        }
                    }
                }
            }
            SettingsGroup(title: "Games and Packages") {
                SettingsRow(title: "Game Folders", detail: gameFolderSummary) {
                    Button("Edit…") { showsGameFolders = live }
                        .buttonStyle(PillButtonStyle(prominent: false))
                }
                SettingsDivider()
                SettingsRow(title: "Package Folders", detail: packageFolderSummary) {
                    Button("Edit…") { showsPackageFolders = live }
                        .buttonStyle(PillButtonStyle(prominent: false))
                }
            }
        }
        .sheet(isPresented: $showsGameFolders, onDismiss: reload) {
            FoldersView {
                netServer.restart()
                Task { await games.loadMac() }
            }
        }
        .sheet(isPresented: $showsPackageFolders, onDismiss: reload) {
            PackageFoldersView {
                Task { await apps.loadPackages(host: console.host) }
            }
        }
    }

    private var rootDetail: String? {
        if root == nil {
            return "A folder on the Mac laid out like the PS3's drive, which installing apps needs. Create makes an empty one; Choose takes one you already have."
        }
        return config.root == nil && live ? "Found by itself next to PS3 Center." : nil
    }

    private var gameFolderSummary: String {
        let folders = config.folders ?? [:]
        // In the console's order (PS3ISO, GAMES, PS2ISO …), then any name PS3 Center doesn't know.
        let used = folders.filter { !$0.value.isEmpty }.keys
        let kinds = GameFolders.kinds.map(\.name).filter(used.contains) + used.filter { GameFolders.kind(named: $0) == nil }.sorted()
        let count = folders.values.reduce(0) { $0 + $1.count }
        guard count > 0 else { return "None yet. Add the folders where you keep your games, and they show up under Mac in the Games tab." }
        let watched = config.watchedFolders?.count ?? 0
        // English like the dates, never the system language ("PS3ISO och PS2ISO").
        let list = ListFormatter()
        list.locale = Format.locale
        let names = list.string(from: kinds) ?? kinds.joined(separator: ", ")
        return "\(plural(count, "folder")) for \(names)" + (watched > 0 ? ", \(watched) watched." : ".")
    }

    private var packageFolderSummary: String {
        let count = config.packageFolders?.count ?? 0
        guard count > 0 else { return "None yet. Add a folder with .pkg files to install them from the Mac." }
        return "\(plural(count, "folder")). Their .pkg files show up under From Mac in the Apps tab."
    }

    private func apply(_ outcome: PS3FolderPicker.Outcome) {
        switch outcome {
        case .set:
            note = nil
            reload()
            apps.mirrorFolderChanged()
        case .failed(let message):
            note = message
        case .cancelled:
            break
        }
    }

    private func reload() {
        guard live else { return }
        config = ConfigStore.load()
        root = MirrorRoot.resolve(config: config)
    }
}

private struct TransferSettings: View {
    @Environment(TransferStore.self) private var transfers
    @Environment(MaintenanceStore.self) private var maintenance
    let live: Bool
    @State private var chunkKB: Int
    @State private var window: Int

    init(live: Bool) {
        self.live = live
        let config = live ? ConfigStore.load() : PS3Config()
        _chunkKB = State(initialValue: FTPTuning.chunkKB(config.ftpChunkKB))
        _window = State(initialValue: FTPTuning.window(config.ftpWindow))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(title: "Queue") {
                SettingsStackedRow(title: "When the Queue Finishes", detail: "What happens on the PS3 once the last game is sent.") {
                    WhenDonePicker()
                }
                SettingsDivider()
                SettingsRow(title: "Verify with MD5", detail: "The PS3 computes a checksum for each large game; takes a few minutes per game.") {
                    PillToggle(isOn: transfers.queue.verify, label: "Verify with MD5") { transfers.setVerify($0) }
                }
            }
            SettingsGroup(title: "Backups") {
                SettingsRow(title: "Back Up Saves Weekly", detail: "Copies the saves to the Mac once a week while the PS3 is on and no game is running.") {
                    PillToggle(isOn: maintenance.autoBackup, label: "Back up saves weekly") { maintenance.setAutoBackup($0) }
                }
            }
            SettingsGroup(title: "Advanced",
                          footer: "How uploads are cut up. Change them only to compare with Measure Speed in Transfers; ps3 in Terminal uses the same values.") {
                SettingsStackedRow(title: "Piece Size", detail: "Default: \(Self.label(kb: FTPTuning.defaultChunkKB)).") {
                    PillPicker(options: chunkOptions, selection: chunkKB, label: { Self.label(kb: $0) }) { kb in
                        chunkKB = kb
                        save { $0.ftpChunkKB = kb == FTPTuning.defaultChunkKB ? nil : kb }
                    }
                }
                SettingsDivider()
                SettingsStackedRow(title: "Pieces in Flight", detail: "How many pieces are handed to the network at once. Default: \(FTPTuning.defaultWindow).") {
                    PillPicker(options: windowOptions, selection: window, label: { String($0) }) { count in
                        window = count
                        save { $0.ftpWindow = count == FTPTuning.defaultWindow ? nil : count }
                    }
                }
                SettingsDivider()
                HStack {
                    Spacer()
                    Button("Reset to Default") {
                        chunkKB = FTPTuning.defaultChunkKB
                        window = FTPTuning.defaultWindow
                        save {
                            $0.ftpChunkKB = nil
                            $0.ftpWindow = nil
                        }
                    }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .disabled(chunkKB == FTPTuning.defaultChunkKB && window == FTPTuning.defaultWindow)
                }
                .padding(.vertical, 12)
            }
        }
    }

    /// The usual choices, plus a value set by hand in config.json so it still shows as chosen.
    private var chunkOptions: [Int] { Array(Set([256, 512, 1024, 2048, 4096, chunkKB])).sorted() }
    private var windowOptions: [Int] { Array(Set([1, 2, 3, 4, window])).sorted() }

    static func label(kb: Int) -> String {
        kb >= 1024 && kb % 1024 == 0 ? "\(kb / 1024) MB" : "\(kb) KB"
    }

    private func save(_ change: (inout PS3Config) -> Void) {
        guard live else { return }
        // A preference: if config.json can't be written the uploads keep their current values.
        try? ConfigStore.edit(change)
    }
}

private struct NotificationSettings: View {
    @Environment(AppPreferences.self) private var preferences
    let live: Bool
    @State private var permission: Notifier.Permission?

    init(live: Bool) {
        self.live = live
        _permission = State(initialValue: live ? nil : .allowed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(title: "macOS") {
                permissionRow
            }
            SettingsGroup(title: "Notify About",
                          footer: "Notifications show while PS3 Center is in the background or its window is closed.") {
                ForEach(Array(NotificationKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { SettingsDivider() }
                    SettingsRow(title: kind.title, detail: kind.detail) {
                        PillToggle(isOn: preferences.notifies(kind), label: kind.title) { preferences.setNotifies(kind, $0) }
                    }
                }
            }
        }
        .task { await refresh() }
        // Back from System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
    }

    @ViewBuilder private var permissionRow: some View {
        switch permission {
        case nil:
            SettingsRow(title: "Asking macOS…") { Spinner() }
        case .allowed?:
            SettingsRow(title: "Allowed", detail: "macOS shows PS3 Center's notifications.") {
                Image(systemName: "checkmark.circle.fill")
                    .font(.ui(.title3))
                    .foregroundStyle(Theme.good)
                    .accessibilityLabel("Allowed")
            }
        case .notAsked?:
            SettingsRow(title: "Not Allowed Yet", detail: "macOS asks once. Allow them to hear when the queue is done or an app has an update.") {
                Button("Allow…") { Task { permission = await Notifier.requestPermission() } }
                    .buttonStyle(PillButtonStyle(prominent: false))
            }
        case .denied?:
            SettingsRow(title: "Turned Off in System Settings", detail: "macOS won't show PS3 Center's notifications until you turn them on there.") {
                Button("Open System Settings") { Notifier.openSystemSettings() }
                    .buttonStyle(PillButtonStyle(prominent: false))
            }
        }
    }

    private func refresh() async {
        permission = live ? await Notifier.permission() : .allowed
    }
}

private struct HelpSettings: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(title: "Guides") {
                SettingsRow(title: "Guides and Glossary", detail: "How to send games, install homebrew, back up saves and more, and what words like HEN mean. Also ps3 guide in Terminal.") {
                    Button("Open Help") { router.openHelp() }
                        .buttonStyle(PillButtonStyle(prominent: false))
                }
            }
            SettingsGroup(title: "Getting Started") {
                SettingsRow(title: "Setup Guide", detail: "The steps from the first launch: getting the PS3 ready, finding it, the folders.") {
                    Button("Show Again") { router.showOnboarding() }
                        .buttonStyle(PillButtonStyle(prominent: false))
                }
                SettingsDivider()
                SettingsRow(title: "Tour", detail: "Where everything is, in \(TourStep.allCases.count) steps.") {
                    Button("Take the Tour") { router.startTour() }
                        .buttonStyle(PillButtonStyle(prominent: false))
                }
            }
            SettingsGroup(title: "Tips") {
                SettingsRow(title: "Show Tips", detail: "Short tips in the tabs, each shown until you press Got It.") {
                    PillToggle(isOn: preferences.showsTips, label: "Show Tips") { preferences.showsTips = $0 }
                }
                SettingsDivider()
                SettingsRow(title: "Tips You Have Closed", detail: preferences.dismissedTips.isEmpty ? "None yet." : "\(preferences.dismissedTips.count) of \(AppTip.allCases.count).") {
                    Button("Show Them Again") { preferences.dismissedTips = [] }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .disabled(preferences.dismissedTips.isEmpty)
                }
            }
        }
    }
}

// MARK: The PS3 folder

/// Choosing or making the PS3 folder (`root` in config.json), for Settings and the banner in Apps.
@MainActor
enum PS3FolderPicker {
    enum Outcome {
        case set(URL)
        case cancelled
        case failed(String)
    }

    /// An existing PS3 folder. A folder that isn't one is offered a new PS3 folder inside it.
    static func choose() -> Outcome {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the PS3 folder (the one with dev_hdd0 and _Installed in it)."
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        if MirrorRoot.looksLikeMirror(url) { return save(url) }
        let alert = NSAlert()
        alert.messageText = "\u{201C}\(url.lastPathComponent)\u{201D} isn't a PS3 folder"
        alert.informativeText = "A PS3 folder has dev_hdd0 and _Installed in it. PS3 Center can make a new, empty one called PS3 inside \u{201C}\(url.lastPathComponent)\u{201D}."
        alert.addButton(withTitle: "Create PS3 Folder")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return .cancelled }
        return make(in: url)
    }

    /// A new, empty PS3 folder in a place the user picks (Documents to begin with).
    static func create() -> Outcome {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Create Here"
        panel.message = "Choose where to put the PS3 folder. PS3 Center makes a folder called PS3 in it, with dev_hdd0 and _Installed."
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        return make(in: url)
    }

    private static func make(in parent: URL) -> Outcome {
        do {
            return save(try MirrorRoot.create(in: parent))
        } catch {
            return .failed("Couldn't make the PS3 folder: \(error.localizedDescription)")
        }
    }

    private static func save(_ url: URL) -> Outcome {
        do {
            try ConfigStore.edit { $0.root = url.path }
            return .set(url)
        } catch {
            return .failed("Couldn't save the PS3 folder in config.json: \(error.localizedDescription)")
        }
    }
}

// MARK: Building blocks

/// A group of rows on a card, with a small uppercase heading like the cards' and an optional
/// grey footnote below.
struct SettingsGroup<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.ui(.caption, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(Theme.primaryText.opacity(0.85))
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardFill))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardStroke))
            if let footer {
                Text(footer)
                    .font(.ui(.caption))
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A title, an optional grey line on what it does, and the control on the right.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var detail: String?
    /// Why the last change failed, in red.
    var note: String?
    /// A path: one line, shortened in the middle.
    var titleIsPath = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.ui(.body))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(titleIsPath ? 1 : nil)
                    .truncationMode(.middle)
                if let detail {
                    Text(detail)
                        .font(.ui(.caption))
                        .foregroundStyle(Theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let note {
                    Text(note)
                        .font(.ui(.caption))
                        .foregroundStyle(Theme.hotText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.vertical, 12)
    }
}

/// A row whose control is too wide to sit beside the title (a row of pills): below it instead.
struct SettingsStackedRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.ui(.body))
                    .foregroundStyle(Theme.primaryText)
                if let detail {
                    Text(detail)
                        .font(.ui(.caption))
                        .foregroundStyle(Theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            control
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
    }
}

/// One choice out of a few, as pills in a dark capsule (the PS app's segmented control, like the
/// tabs). Drawn by SwiftUI, so snapshots can render it.
struct PillPicker<Value: Hashable>: View {
    let options: [Value]
    let selection: Value
    let label: (Value) -> String
    let change: (Value) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { change(option) }
                } label: {
                    Text(label(option))
                        .font(.ui(.body, weight: selection == option ? .bold : .semibold))
                        .foregroundStyle(selection == option ? Theme.primaryText : Theme.primaryText.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(selection == option ? Color.white.opacity(0.14) : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .fixedSize()
    }
}

private func plural(_ count: Int, _ word: String) -> String {
    "\(count) \(word)\(count == 1 ? "" : "s")"
}
