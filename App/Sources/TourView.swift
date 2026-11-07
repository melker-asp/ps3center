import PS3Kit
import SwiftUI

// MARK: The tour

/// The tour after the setup guide (or from Help and Settings → Help): six steps that point at the
/// real window, switching tab when a step needs to.
enum TourStep: Int, CaseIterable, Identifiable {
    case tabs, statusCards, games, apps, transfers, helpAndSettings

    var id: Int { rawValue }

    var anchor: TourAnchor {
        switch self {
        case .tabs: return .tabs
        case .statusCards: return .statusCards
        case .games: return .gamesSource
        case .apps: return .appsSections
        case .transfers: return .transfers
        case .helpAndSettings: return .helpAndSettings
        }
    }

    /// The tab the step is about; nil leaves the tab as it is.
    var tab: MainTab? {
        switch self {
        case .statusCards: return .status
        case .games: return .games
        case .apps: return .apps
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .tabs: return "Four Tabs"
        case .statusCards: return "How the PS3 Is Doing"
        case .games: return "Your Games"
        case .apps: return "Homebrew"
        case .transfers: return "The Queue"
        case .helpAndSettings: return "Help and Settings"
        }
    }

    var text: String {
        switch self {
        case .tabs:
            return "Status, Games, Apps and Maintenance. The dot on the PlayStation logo is green while the PS3 answers, and yellow while webMAN is slow."
        case .statusCards:
            return "Temperatures, the fan, free space and what is playing, every few seconds. The ⓘ on a card explains it. Remote and the power buttons are below the cards."
        case .games:
            return "On PS3 shows the games on the console, On Mac the games in your game folders. Pick games On Mac to send them, or drag files from Finder onto the window."
        case .apps:
            return "Updates has new versions of what is installed, Browse more to install, From Mac your own .pkg files. Each one is checked against your console first."
        case .transfers:
            return "Games you send wait here. The queue continues where it stopped if the network drops, and waits while a game is running."
        case .helpAndSettings:
            return "? has a guide for each task (⌘?), and the gear the settings (⌘,), where you also find the setup guide and this tour again."
        }
    }
}

/// The parts of the window the tour points at, marked with `.tourAnchor(_:)`.
enum TourAnchor: Hashable {
    case tabs, statusCards, gamesSource, appsSections, transfers, helpAndSettings
}

struct TourAnchorKey: PreferenceKey {
    static var defaultValue: [TourAnchor: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [TourAnchor: Anchor<CGRect>], nextValue: () -> [TourAnchor: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Marks the view as what a tour step points at.
    func tourAnchor(_ anchor: TourAnchor) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [anchor: $0] }
    }
}

/// Dims the window except the step's part, with a bubble beside it. A step whose part isn't on
/// screen (the console offline, a detail page open) shows the bubble in the middle.
struct TourOverlay: View {
    @Environment(AppRouter.self) private var router
    let step: TourStep
    let rect: CGRect?
    let size: CGSize

    private let bubbleWidth: CGFloat = 380
    private let bubbleHeight: CGFloat = 210

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                if let hole { path.addRoundedRect(in: hole, cornerSize: CGSize(width: 16, height: 16)) }
            }
            .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
            // The window stays still while the tour runs.
            .contentShape(Rectangle())
            .onTapGesture {}
            if let hole {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 2)
                    .frame(width: hole.width, height: hole.height)
                    .position(x: hole.midX, y: hole.midY)
                    .allowsHitTesting(false)
            }
            bubble
                .frame(width: bubbleWidth)
                .fixedSize(horizontal: false, vertical: true)
                .position(bubbleCenter)
        }
        .frame(width: size.width, height: size.height)
    }

    private var hole: CGRect? { rect?.insetBy(dx: -8, dy: -8) }

    /// Below the part if there is room, else above it, else on top of it.
    private var bubbleCenter: CGPoint {
        guard let hole else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        let margin: CGFloat = 16
        let x = min(max(hole.midX, bubbleWidth / 2 + margin), size.width - bubbleWidth / 2 - margin)
        if size.height - hole.maxY >= bubbleHeight + margin * 2 {
            return CGPoint(x: x, y: hole.maxY + margin + bubbleHeight / 2)
        }
        if hole.minY >= bubbleHeight + margin * 2 {
            return CGPoint(x: x, y: hole.minY - margin - bubbleHeight / 2)
        }
        return CGPoint(x: x, y: hole.midY)
    }

    private var bubble: some View {
        let steps = TourStep.allCases
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(step.rawValue + 1) of \(steps.count)")
                .font(.ui(.caption, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(Theme.tertiaryText)
            Text(step.title)
                .font(.ui(.title3, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
            Text(step.text)
                .font(.ui(.body))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Skip Tour") { router.tourStep = nil }
                    .buttonStyle(.plain)
                    .font(.ui(.body, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if step.rawValue > 0 {
                    Button("Back") { move(-1) }
                        .buttonStyle(PillButtonStyle(prominent: false))
                }
                Button(step == steps.last ? "Done" : "Next") { move(1) }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.base))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
    }

    private func move(_ by: Int) {
        withAnimation(.easeInOut(duration: 0.3)) {
            router.tourStep = TourStep(rawValue: step.rawValue + by)
        }
    }
}

// MARK: Tips

/// Short tips in the tabs, each shown until Got It (Settings → Help turns them off or back on).
enum AppTip: String, CaseIterable, Identifiable {
    case cardInfo, remote, dragToSend, ignoreUpdate, queueResumes

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .cardInfo: return "info.circle"
        case .remote: return "dpad"
        case .dragToSend: return "square.and.arrow.down.on.square"
        case .ignoreUpdate: return "eye.slash"
        case .queueResumes: return "arrow.clockwise"
        }
    }

    var title: String {
        switch self {
        case .cardInfo: return "What a card shows"
        case .remote: return "Steer the XMB from the Mac"
        case .dragToSend: return "Drag games onto the window"
        case .ignoreUpdate: return "Not this version"
        case .queueResumes: return "The queue picks up where it stopped"
        }
    }

    var text: String {
        switch self {
        case .cardInfo:
            return "Press ⓘ on a card to see what it measures and when a value is too high."
        case .remote:
            return "Remote below the cards moves around the XMB with the arrow keys, Return and Esc. Watch the TV while you use it."
        case .dragToSend:
            return "Drop games or packages from Finder anywhere on the window. PS3 Center shows where each one goes before anything is sent."
        case .ignoreUpdate:
            return "Ignore skips just that version. When a newer one comes out, it shows up again."
        case .queueResumes:
            return "If the network drops or the Mac sleeps, the queue continues from what has already arrived instead of starting over."
        }
    }
}

/// A tip at the top of a tab or sheet. Without `AppPreferences` in the environment (a sheet in a
/// snapshot) it shows nothing.
struct TipCard: View {
    @Environment(AppPreferences.self) private var preferences: AppPreferences?
    /// The first of these that isn't closed, so a place shows one tip at a time.
    let tips: [AppTip]

    init(_ tips: AppTip...) {
        self.tips = tips
    }

    var body: some View {
        if let preferences, let tip = tips.first(where: preferences.shows) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: tip.symbol)
                    .font(.ui(.title3))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tip.title)
                        .font(.ui(.body, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text(tip.text)
                        .font(.ui(.footnote))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button("Got It") {
                    withAnimation(.easeInOut(duration: 0.2)) { preferences.dismiss(tip) }
                }
                .buttonStyle(PillButtonStyle(prominent: false))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.accent.opacity(0.3)))
            .transition(.opacity)
        }
    }
}

// MARK: Explanations

/// What an ⓘ says: a few sentences, and where to read more.
struct InfoText {
    let title: String
    let text: String
    var term: Glossary.TermID?
    var guide: GuideID?
}

/// An ⓘ that shows a short explanation in a popover, with a way into Help.
struct InfoButton: View {
    @Environment(\.openHelp) private var openHelp
    let info: InfoText
    @State private var shows = false

    var body: some View {
        Button {
            shows.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.ui(.footnote, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .iconLabel("About \(info.title)")
        .popover(isPresented: $shows, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(info.title)
                    .font(.ui(.headline, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(info.text)
                    .font(.ui(.body))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if info.term != nil || info.guide != nil {
                    HStack(spacing: 14) {
                        if let term = info.term, let entry = Glossary.term(term) {
                            Button("What is \(entry.term)?") {
                                shows = false
                                openHelp(.term(term))
                            }
                        }
                        if let guide = info.guide, let entry = Guides.guide(guide) {
                            Button("Read \u{201C}\(entry.title)\u{201D}") {
                                shows = false
                                openHelp(guide)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.ui(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                }
            }
            .padding(16)
            .frame(width: 320, alignment: .leading)
            .background(Theme.base)
            .environment(\.colorScheme, .dark)
        }
    }
}
