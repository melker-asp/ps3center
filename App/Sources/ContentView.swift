import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case status, apps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: return "Status"
        case .apps: return "Appar"
        }
    }
}

struct ContentView: View {
    @Environment(ConsoleStore.self) private var console
    @State private var tab: MainTab = .status

    var body: some View {
        ZStack {
            Theme.background(for: tab)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.35), value: tab)

            VStack(spacing: 0) {
                TabBar(selection: $tab)
                    .padding(.top, 14)
                    .padding(.bottom, 20)

                switch console.connection {
                case .online:
                    Group {
                        switch tab {
                        case .status: StatusView()
                        case .apps: AppsView()
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
    }
}

/// Centered pill tabs with the logo on the left, as in Mole.
struct TabBar: View {
    @Binding var selection: MainTab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle().fill(Color.white)
                Image(systemName: "playstation.logo")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
            }
            .frame(width: 34, height: 34)
            .padding(.trailing, 6)

            ForEach(MainTab.allCases) { tab in
                Button {
                    withAnimation(.spring(duration: 0.3)) { selection = tab }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selection == tab ? Color.black : Theme.primaryText.opacity(0.8))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 9)
                        .background {
                            if selection == tab {
                                Capsule().fill(Color.white).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.06)))
    }
}

/// Shown until webMAN answers: connecting, scanning or offline with a way out.
struct ConnectionView: View {
    @Environment(ConsoleStore.self) private var console

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            HealthOrb(color: orbColor)
                .opacity(isOffline ? 0.55 : 1)
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
            Text(detail)
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            if isOffline {
                Button("Försök igen") { console.retry() }
                    .buttonStyle(PillButtonStyle(tint: Theme.warm))
            } else {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var isOffline: Bool {
        if case .offline = console.connection { return true }
        return false
    }

    private var orbColor: Color { isOffline ? Theme.hot : Theme.warm }

    private var title: String {
        switch console.connection {
        case .connecting: return "Ansluter till PS3:an…"
        case .scanning: return "Letar efter PS3:an på nätverket…"
        case .offline: return "Ingen kontakt med PS3:an"
        case .online: return ""
        }
    }

    private var detail: String {
        switch console.connection {
        case .offline(let message): return message
        case .scanning: return "Den sparade adressen svarade inte. Det här tar upp till en halv minut."
        default: return "webMAN måste vara igång, så aktivera HEN efter varje omstart."
        }
    }
}
