import PS3Kit
import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case status, games, apps, maintenance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: return "Status"
        case .games: return "Spel"
        case .apps: return "Appar"
        case .maintenance: return "Underhåll"
        }
    }
}

struct ContentView: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(AppearanceStore.self) private var appearance
    @Environment(TransferStore.self) private var transfers
    @Environment(NetServerStore.self) private var netServer
    @Environment(MaintenanceStore.self) private var maintenance
    @Environment(\.openWindow) private var openWindow
    @State private var tab: MainTab = .status
    @State private var showsAppearance = false
    @State private var showsTransfers = false
    @State private var dropped: SendReview?

    var body: some View {
        ZStack {
            Group {
                if console.connection == .online {
                    Theme.background(for: tab, theme: appearance.theme)
                } else {
                    SplashBackground()
                }
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.35), value: tab)
            .animation(.easeInOut(duration: 0.35), value: appearance.theme)
            .animation(.easeInOut(duration: 0.5), value: console.connection == .online)

            VStack(spacing: 0) {
                TopBar(selection: $tab, openTransfers: { showsTransfers = true }) { showsAppearance = true }
                    .padding(.top, 14)
                    .padding(.bottom, 20)

                switch console.connection {
                case .online:
                    Group {
                        switch tab {
                        case .status: StatusView()
                        case .games: GamesView()
                        case .apps: AppsView()
                        case .maintenance: MaintenanceView()
                        }
                    }
                    .transition(.opacity)
                default:
                    ConnectionView()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .sheet(isPresented: $showsAppearance) { AppearanceView() }
        .sheet(isPresented: $showsTransfers) { TransfersView() }
        .sheet(item: $dropped) { SendReviewView(review: $0) }
        .task(id: console.host) {
            transfers.host = console.host
            netServer.host = console.host
            maintenance.host = console.host
        }
        // The weekly backup of the saves, a while after the console shows up.
        .task(id: console.connection == .online) {
            guard console.connection == .online else { return }
            try? await Task.sleep(for: .seconds(90))
            maintenance.autoBackupIfDue(gameRunning: console.snapshot?.isGameRunning ?? true, transfersRunning: transfers.isRunning)
        }
        .onChange(of: console.snapshot?.mountedGamePath) { _, path in netServer.consoleMounted(path) }
        // Files from Finder's "Skicka till PS3", the menu bar and Shortcuts.
        // They wait until the console is online.
        .onChange(of: Inbox.shared.revision * 2 + (console.connection == .online ? 1 : 0), initial: true) {
            WindowOpener.shared.openWindow = openWindow
            guard console.connection == .online, !Inbox.shared.files.isEmpty else { return }
            _ = review(Inbox.shared.take())
        }
        // Files dragged onto the window go to the review, then the queue.
        .dropDestination(for: URL.self) { urls, _ in review(urls) }
    }

    private func review(_ urls: [URL]) -> Bool {
        guard console.connection == .online,
              let routes = try? FileRouter.routes(for: urls, mirrorRoot: MirrorRoot.resolve()), !routes.isEmpty else { return false }
        dropped = SendReview(routes: routes)
        return true
    }
}

/// The tabs centred; the transfers and settings buttons on the right.
struct TopBar: View {
    @Environment(TransferStore.self) private var transfers
    @Binding var selection: MainTab
    var openTransfers: () -> Void = {}
    let openAppearance: () -> Void

    var body: some View {
        TabBar(selection: $selection)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                HStack(spacing: 10) {
                    Button(action: openTransfers) {
                        Image(systemName: transfers.isRunning ? "arrow.up.circle" : "arrow.up.arrow.down")
                    }
                    .buttonStyle(CircleIconButtonStyle())
                    .overlay(alignment: .topTrailing) {
                        if !transfers.pending.isEmpty {
                            CountBadge(count: transfers.pending.count).offset(x: 6, y: -6)
                        }
                    }
                    .help("Överföringar")
                    Button(action: openAppearance) { Image(systemName: "gearshape.fill") }
                        .buttonStyle(CircleIconButtonStyle())
                        .help("Utseende")
                }
            }
    }
}

/// Centered pill tabs as in Mole, styled like the PS app's segmented control: a dark
/// capsule with a lighter pill for the selection, the logo on a PlayStation-blue disc with
/// a green presence dot while the console answers, and a green count on Appar.
struct TabBar: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(AppsStore.self) private var apps
    @Binding var selection: MainTab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle().fill(Theme.psBlue)
                    Image(systemName: "playstation.logo")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
                if console.connection == .online {
                    // Yellow while webMAN is slow to answer, before the console counts as gone.
                    Circle()
                        .fill(console.missedPolls > 0 ? Theme.warm : Theme.good)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 2))
                        .offset(x: 1, y: 1)
                }
            }
            .padding(.trailing, 6)

            ForEach(MainTab.allCases) { tab in
                Button {
                    withAnimation(.spring(duration: 0.3)) { selection = tab }
                } label: {
                    HStack(spacing: 7) {
                        Text(tab.title)
                        if tab == .apps, !apps.updates.isEmpty {
                            CountBadge(count: apps.updates.count)
                        }
                    }
                    .font(.system(size: 14, weight: selection == tab ? .bold : .semibold))
                    .foregroundStyle(selection == tab ? Theme.primaryText : Theme.primaryText.opacity(0.7))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background {
                        if selection == tab {
                            Capsule().fill(Color.white.opacity(0.14)).matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.06)))
    }
}

/// Shown until webMAN answers, on the PS app's splash screen: the white logo on PlayStation
/// blue, then connecting, scanning or offline with a way out.
struct ConnectionView: View {
    @Environment(ConsoleStore.self) private var console

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "playstation.logo")
                .font(.system(size: 96, weight: .regular))
                .foregroundStyle(.white)
                .opacity(isOffline ? 0.6 : 1)
                .padding(.bottom, 18)
            Text(title)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.primaryText)
            Text(detail)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            if isOffline {
                Button("Försök igen") { console.retry() }
                    .buttonStyle(PillButtonStyle())
            } else {
                Spinner(size: 20)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var isOffline: Bool {
        switch console.connection {
        case .offline, .henOff: return true
        default: return false
        }
    }

    private var title: String {
        switch console.connection {
        case .connecting: return "Ansluter till PS3:an…"
        case .scanning: return "Letar efter PS3:an på nätverket…"
        case .offline: return "Ingen kontakt med PS3:an"
        case .henOff: return "PS3:an är på, men HEN är inte aktiverat"
        case .online: return ""
        }
    }

    private var detail: String {
        switch console.connection {
        case .offline(let message): return message
        case .henOff: return "webMAN startar först när HEN är aktiverat. Välj \u{201D}Enable HEN\u{201D} under Spel på PS3:an, så ansluter PS3 Center av sig själv."
        case .scanning: return "Den sparade adressen svarade inte. Det här tar upp till en halv minut."
        default: return "webMAN måste vara igång, så aktivera HEN efter varje omstart."
        }
    }
}
