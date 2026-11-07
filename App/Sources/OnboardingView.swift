import AppKit
import PS3Kit
import PS3KitFixtures
import SwiftUI

/// The setup guide's state: shown once, on a launch with no console saved.
@MainActor
enum Onboarding {
    /// Raised when the guide gets a page that people who finished it should see.
    static let version = 1
    static let key = "onboardingVersion"

    static var isNeeded: Bool {
        guard !Snapshot.usesFixtures, Snapshot.directory == nil else { return false }
        guard UserDefaults.standard.integer(forKey: key) < version else { return false }
        // Someone with a console saved (or PS3_HOST set) is past the first launch.
        return ConfigStore.load().host == nil && ProcessInfo.processInfo.environment["PS3_HOST"] == nil
    }

    static func finish() {
        guard !Snapshot.usesFixtures, Snapshot.directory == nil else { return }
        UserDefaults.standard.set(version, forKey: key)
    }
}

enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome, prepare, find, folders, preferences, done

    var id: Int { rawValue }
}

/// The setup guide over the whole window on the PS app's blue splash: what is needed, getting
/// the PS3 ready, finding it (or typing its address), the folders and a few preferences, then the
/// tour. Skip Setup on every page; Settings → Help shows it again.
struct OnboardingView: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(AppRouter.self) private var router
    @Environment(\.openHelp) private var openHelp
    @State private var page: OnboardingPage
    /// False when rendered for a snapshot: Fixtures, nothing read from or written to disk, no text field.
    private let live: Bool

    init(page: OnboardingPage = .welcome, live: Bool = true) {
        _page = State(initialValue: page)
        self.live = live
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page != .done {
                    Button("Skip Setup") { router.finishOnboarding(takeTour: false) }
                        .buttonStyle(.plain)
                        .font(.ui(.callout, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .help("Close the setup guide. Settings → Help shows it again.")
                }
            }
            .frame(height: 28)
            Spacer(minLength: 12)
            Group {
                switch page {
                case .welcome: WelcomePage()
                case .prepare: PreparePage()
                case .find: FindPage(live: live)
                case .folders: OnboardingFolders(live: live)
                case .preferences: OnboardingPreferences(live: live)
                case .done: DonePage()
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .transition(.opacity)
            .id(page)
            Spacer(minLength: 12)
            footer
                .frame(maxWidth: 640)
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(OnboardingPage.allCases) { item in
                    Circle()
                        .fill(Color.white.opacity(item == page ? 0.95 : 0.3))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(page.rawValue + 1) of \(OnboardingPage.allCases.count)")
            Spacer()
            if page != .welcome {
                Button("Back") { go(-1) }
                    .buttonStyle(PillButtonStyle(prominent: false))
            }
            switch page {
            case .done:
                Button("Start Using PS3 Center") { router.finishOnboarding(takeTour: false) }
                    .buttonStyle(PillButtonStyle(prominent: false))
                Button("Take the Tour") { router.finishOnboarding(takeTour: true) }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
            default:
                Button("Continue") { go(1) }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func go(_ step: Int) {
        guard let next = OnboardingPage(rawValue: page.rawValue + step) else { return }
        withAnimation(.easeInOut(duration: 0.25)) { page = next }
    }
}

// MARK: Pages

private struct WelcomePage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            OnboardingHeader(symbol: "playstation.logo", title: "Welcome to PS3 Center",
                             text: "See how your PS3 is doing, send it your games, play them straight from the Mac and keep its homebrew up to date, all from the Mac.")
            VStack(alignment: .leading, spacing: 14) {
                feature("gauge.with.dots.needle.33percent", "Status", "Temperatures, the fan, free space and what is playing.")
                feature("square.stack", "Games", "Your games on the PS3 and on the Mac, sent with one click.")
                feature("shippingbox", "Apps", "Homebrew installed and updated, checked against your console first.")
                feature("wrench.and.screwdriver", "Maintenance", "Saves backed up to the Mac, cleanup and storage.")
            }
            OnboardingCard(title: "What You Need") {
                VStack(alignment: .leading, spacing: 8) {
                    bullet("A PS3 with PS3HEN or custom firmware (CFW).")
                    bullet("webMAN MOD installed on the PS3.")
                    bullet("The Mac and the PS3 on the same network, or a network cable between them.")
                }
            }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol)
                .font(.ui(.title3))
                .foregroundStyle(.white)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(.headline, weight: .semibold)).foregroundStyle(.white)
                Text(text).font(.ui(.body)).foregroundStyle(Color.white.opacity(0.75))
            }
        }
    }
}

private struct PreparePage: View {
    @Environment(\.openHelp) private var openHelp

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            OnboardingHeader(symbol: "power", title: "Get the PS3 Ready",
                             text: "PS3 Center talks to webMAN MOD on the PS3, and webMAN MOD only runs once HEN is enabled.")
            VStack(alignment: .leading, spacing: 18) {
                step(1, "Turn on the PS3 and connect it.",
                     "To the same network as the Mac, or with a cable straight to the Mac. A cable is faster: the PS3's Wi-Fi only does 2.4 GHz.")
                step(2, "Enable HEN.",
                     "Under Game on the PS3, choose Enable HEN. Do it after every restart. On custom firmware there is nothing to do.")
                step(3, "Wait for webMAN MOD.",
                     "It usually shows a message on the TV when it starts. Then PS3 Center can reach the PS3.")
            }
            Button("What are HEN and webMAN MOD?") { openHelp(.term(.hen)) }
                .buttonStyle(OnboardingLinkStyle())
        }
    }

    private func step(_ number: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.ui(.callout, weight: .bold))
                .foregroundStyle(Theme.psBlue)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.ui(.headline, weight: .semibold)).foregroundStyle(.white)
                Text(text)
                    .font(.ui(.body))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct FindPage: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(\.openHelp) private var openHelp
    let live: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeader(symbol: "antenna.radiowaves.left.and.right", title: "Find Your PS3",
                             text: "PS3 Center looks for webMAN MOD on the network by itself. If it doesn't find the PS3, type its address below.")
            OnboardingCard(title: "Connection") {
                status
            }
            OnboardingCard(title: "Know Its Address?") {
                AddressEntry(live: live)
            }
            Button("Why can't it find my PS3?") { openHelp(.troubleshooting) }
                .buttonStyle(OnboardingLinkStyle())
        }
    }

    @ViewBuilder private var status: some View {
        switch console.connection {
        case .online:
            statusLine(symbol: "checkmark.circle.fill", color: Theme.good,
                       title: "Found your PS3\(console.host.map { " at \($0)" } ?? "")", detail: versions)
        case .henOff:
            statusLine(symbol: "exclamationmark.circle.fill", color: Theme.warm, title: "The PS3 is on, but HEN isn't enabled",
                       detail: "Choose Enable HEN under Game on the PS3, and PS3 Center connects by itself.")
        case .offline(let message):
            HStack(alignment: .top) {
                statusLine(symbol: "xmark.circle.fill", color: Theme.hotText, title: "Can't find the PS3", detail: message)
                Spacer()
                Button("Try Again") { console.retry() }
                    .buttonStyle(PillButtonStyle(prominent: false))
            }
        case .scanning:
            spinnerLine("Looking for the PS3 on the network…", detail: "This takes up to half a minute.")
        case .connecting:
            spinnerLine("Connecting…", detail: nil)
        }
    }

    /// "Firmware 4.93 CEX · PS3HEN 3.5.0 · webMAN MOD 1.47.48".
    private var versions: String? {
        guard let s = console.snapshot else { return nil }
        var parts: [String] = []
        if let firmware = s.firmware { parts.append("Firmware \(firmware)\(s.firmwareType.map { " \($0)" } ?? "")") }
        if let hen = s.henVersion { parts.append("PS3HEN \(hen)") }
        if let webman = s.webmanVersion { parts.append("webMAN MOD \(webman)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func statusLine(symbol: String, color: Color, title: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.ui(.headline, weight: .semibold)).foregroundStyle(.white)
                if let detail {
                    Text(detail)
                        .font(.ui(.body))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.ui(.headline))
    }

    private func spinnerLine(_ title: String, detail: String?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Spinner(size: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.ui(.headline, weight: .semibold)).foregroundStyle(.white)
                if let detail { Text(detail).font(.ui(.body)).foregroundStyle(Color.white.opacity(0.75)) }
            }
        }
    }
}

/// A typed address on the blue splash (the setup guide and the connection screen): checked,
/// tried, and saved when webMAN answers there.
struct AddressEntry: View {
    @Environment(ConsoleStore.self) private var console
    /// False when rendered for a snapshot: ImageRenderer can't draw a text field.
    var live = true
    @State private var address = ""
    @State private var isConnecting = false
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                field
                if isConnecting {
                    Spinner()
                } else {
                    Button("Connect") { connect() }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .disabled(live && address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let note {
                Text(note)
                    .font(.ui(.footnote))
                    .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("On the PS3: Settings → Network Settings → Settings and Connection Status List.")
                .font(.ui(.footnote))
                .foregroundStyle(Color.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var field: some View {
        Group {
            if live {
                TextField("", text: $address, prompt: Text("192.168.1.20").foregroundStyle(Color.white.opacity(0.45)))
                    .textFieldStyle(.plain)
                    .onSubmit(connect)
            } else {
                Text("192.168.1.20").foregroundStyle(Color.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.ui(.body))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.3)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.25)))
        .frame(maxWidth: 260)
        .accessibilityLabel("The PS3's address")
    }

    private func connect() {
        guard live, !isConnecting, !address.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isConnecting = true
        note = nil
        Task {
            note = await console.connect(to: address)
            isConnecting = false
        }
    }
}

private struct OnboardingFolders: View {
    @Environment(AppsStore.self) private var apps
    @Environment(GamesStore.self) private var games
    @Environment(NetServerStore.self) private var netServer
    let live: Bool
    @State private var root: URL?
    @State private var folderCount: Int
    @State private var note: String?
    @State private var showsGameFolders = false

    init(live: Bool) {
        self.live = live
        let config = live ? ConfigStore.load() : PS3Config()
        _root = State(initialValue: live ? MirrorRoot.resolve(config: config) : nil)
        _folderCount = State(initialValue: config.folders?.values.reduce(0) { $0 + $1.count } ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeader(symbol: "folder", title: "Your Folders",
                             text: "Both are optional, and you can change them later in Settings → Folders.")
            OnboardingCard(title: "PS3 Folder") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Installing apps needs a folder on the Mac to keep the packages in, laid out like the PS3's drive.")
                        .font(.ui(.body)).foregroundStyle(Color.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        if let root {
                            Label((root.path as NSString).abbreviatingWithTildeInPath, systemImage: "checkmark.circle.fill")
                                .font(.ui(.body, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("Not set up yet").font(.ui(.body, weight: .semibold)).foregroundStyle(.white)
                        }
                        Spacer()
                        if root == nil {
                            Button("Create…") { if live { apply(PS3FolderPicker.create()) } }
                                .buttonStyle(PillButtonStyle(prominent: false))
                                .help("Makes an empty PS3 folder with dev_hdd0 and _Installed in a place you choose")
                        }
                        Button(root == nil ? "Choose…" : "Change…") { if live { apply(PS3FolderPicker.choose()) } }
                            .buttonStyle(PillButtonStyle(prominent: false))
                    }
                    if let note {
                        Text(note).font(.ui(.footnote)).foregroundStyle(Color(red: 1, green: 0.85, blue: 0.6))
                    }
                }
            }
            OnboardingCard(title: "Game Folders") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Where you keep your games. They show up under Mac in the Games tab and go to the PS3 with one click.")
                        .font(.ui(.body)).foregroundStyle(Color.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text(folderCount == 0 ? "None yet" : "\(folderCount) folder\(folderCount == 1 ? "" : "s")")
                            .font(.ui(.body, weight: .semibold)).foregroundStyle(.white)
                        Spacer()
                        Button("Add Game Folders…") { showsGameFolders = live }
                            .buttonStyle(PillButtonStyle(prominent: false))
                    }
                }
            }
        }
        .sheet(isPresented: $showsGameFolders, onDismiss: reload) {
            FoldersView {
                netServer.restart()
                Task { await games.loadMac() }
            }
        }
    }

    private func apply(_ outcome: PS3FolderPicker.Outcome) {
        switch outcome {
        case .set:
            note = nil
            reload()
            apps.mirrorFolderChanged()
        case .failed(let message): note = message
        case .cancelled: break
        }
    }

    private func reload() {
        guard live else { return }
        let config = ConfigStore.load()
        root = MirrorRoot.resolve(config: config)
        folderCount = config.folders?.values.reduce(0) { $0 + $1.count } ?? 0
    }
}

private struct OnboardingPreferences: View {
    @Environment(AppearanceStore.self) private var appearance
    @Environment(AppPreferences.self) private var preferences
    let live: Bool
    @State private var startsAtLogin = false
    @State private var permission: Notifier.Permission?

    init(live: Bool) {
        self.live = live
        _startsAtLogin = State(initialValue: live && LoginItem.isEnabled)
        _permission = State(initialValue: live ? nil : .notAsked)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeader(symbol: "paintpalette", title: "Make It Yours",
                             text: "Pick a look and how PS3 Center keeps you posted. All of it is in Settings too.")
            OnboardingCard(title: "Theme") {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(AppTheme.allCases) { theme in
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) { appearance.theme = theme }
                        } label: {
                            VStack(spacing: 8) {
                                ThemeSwatch(theme: theme, size: 44)
                                    .padding(3)
                                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(Color.white.opacity(appearance.theme == theme ? 0.95 : 0), lineWidth: 2))
                                Text(theme.label)
                                    .font(.ui(.caption, weight: appearance.theme == theme ? .bold : .regular))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(width: 80)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(appearance.theme == theme ? .isSelected : [])
                    }
                }
            }
            OnboardingCard(title: "Staying Informed") {
                VStack(alignment: .leading, spacing: 14) {
                    toggleRow("Launch at Login", "Opens PS3 Center when you log in to the Mac.", isOn: startsAtLogin) { on in
                        guard live else { return }
                        _ = LoginItem.set(on)
                        startsAtLogin = LoginItem.isEnabled
                    }
                    toggleRow("Show in Menu Bar", "Status, the queue and quick buttons, also with the window closed.",
                              isOn: preferences.showsMenuBarIcon) { preferences.showsMenuBarIcon = $0 }
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notifications").font(.ui(.body, weight: .semibold)).foregroundStyle(.white)
                            Text(permissionText).font(.ui(.footnote)).foregroundStyle(Color.white.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        switch permission {
                        case .notAsked?:
                            Button("Allow…") { if live { Task { permission = await Notifier.requestPermission() } } }
                                .buttonStyle(PillButtonStyle(prominent: false))
                        case .denied?:
                            Button("Open System Settings") { Notifier.openSystemSettings() }
                                .buttonStyle(PillButtonStyle(prominent: false))
                        case .allowed?:
                            Image(systemName: "checkmark.circle.fill").font(.ui(.title3)).foregroundStyle(Theme.good)
                        case nil:
                            Spinner()
                        }
                    }
                }
            }
        }
        .task { if live { permission = await Notifier.permission() } }
    }

    private var permissionText: String {
        switch permission {
        case .allowed?: return "Allowed. Settings → Notifications chooses which ones."
        case .denied?: return "Turned off for PS3 Center in System Settings."
        default: return "When the queue is done, an app has an update, or the PS3 runs hot."
        }
    }

    private func toggleRow(_ title: String, _ detail: String, isOn: Bool, change: @escaping (Bool) -> Void) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(.body, weight: .semibold)).foregroundStyle(.white)
                Text(detail).font(.ui(.footnote)).foregroundStyle(Color.white.opacity(0.75))
            }
            Spacer()
            PillToggle(isOn: isOn, label: title, change: change)
        }
    }
}

private struct DonePage: View {
    @Environment(ConsoleStore.self) private var console

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeader(symbol: "checkmark.circle", title: "You're All Set",
                             text: "The tour shows where everything is in a minute. Help (⌘?) has a guide for each task, and the ⓘ buttons explain the words.")
            OnboardingCard(title: "Your PS3") {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: console.connection == .online ? "checkmark.circle.fill" : "clock")
                        .foregroundStyle(console.connection == .online ? Theme.good : .white)
                    Text(console.connection == .online
                         ? "Connected\(console.host.map { " at \($0)" } ?? ""). PS3 Center keeps an eye on it from now on."
                         : "Not connected yet. PS3 Center keeps looking and connects as soon as webMAN MOD answers.")
                        .font(.ui(.body))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: Building blocks

private struct OnboardingHeader: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.white)
                .padding(.bottom, 6)
            Text(title)
                .font(.ui(.hero, weight: .light))
                .foregroundStyle(.white)
            Text(text)
                .font(.ui(.title3, weight: .light))
                .foregroundStyle(Color.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A translucent card on the blue splash, with a small uppercase heading like the app's cards.
private struct OnboardingCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.ui(.caption, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(Color.white.opacity(0.85))
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.22)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.14)))
    }
}

@MainActor
private func bullet(_ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
        Image(systemName: "checkmark")
            .font(.ui(.footnote, weight: .bold))
            .foregroundStyle(.white)
        Text(text)
            .font(.ui(.body))
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A text link on the splash: white, underlined, opens Help.
private struct OnboardingLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "questionmark.circle")
            configuration.label.underline()
        }
        .font(.ui(.body, weight: .semibold))
        .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.6 : 0.9))
        .contentShape(Rectangle())
    }
}
