import Observation
import PS3Kit
import SwiftUI

/// The PS app's themes. "Följ fliken" (the default) gives each tab its own colour, as the PS
/// app's "Matcha enhet" follows the device; the others colour every tab the same.
enum AppTheme: String, CaseIterable, Identifiable {
    case perTab, starlightBlue, novaPink, cosmicRed, galacticPurple, midnightBlack

    var id: String { rawValue }

    var label: String {
        switch self {
        case .perTab: return "Följ fliken"
        case .starlightBlue: return "Starlight Blue"
        case .novaPink: return "Nova Pink"
        case .cosmicRed: return "Cosmic Red"
        case .galacticPurple: return "Galactic Purple"
        case .midnightBlack: return "Midnight Black"
        }
    }

    var detail: String? {
        self == .perTab ? "Varje flik får sin egen färg: Status Starlight Blue, Spel Nova Pink, Appar Galactic Purple." : nil
    }
}

/// The chosen theme, saved in ~/.config/ps3center/config.json next to host and root.
@MainActor
@Observable
final class AppearanceStore {
    var theme: AppTheme {
        didSet {
            guard persists else { return }
            var config = ConfigStore.load()
            config.theme = theme == .perTab ? nil : theme.rawValue
            try? ConfigStore.save(config)
        }
    }

    /// False for snapshots, which must not change the user's settings.
    private let persists: Bool

    init(previewing preview: AppTheme? = nil) {
        persists = preview == nil
        theme = preview ?? ConfigStore.load().theme.flatMap(AppTheme.init(rawValue:)) ?? .perTab
    }
}

/// The PS app's Utseende screen: a title in light weight, one row per theme with a colour
/// square and a radio button, and the round white back button.
struct AppearanceView: View {
    @Environment(AppearanceStore.self) private var appearance
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Utseende")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.primaryText)
            Text("Anpassa PS3 Center genom att välja ett utseende.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 8)
                .padding(.bottom, 14)
            ForEach(AppTheme.allCases) { theme in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { appearance.theme = theme }
                } label: {
                    row(theme)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 20)
            Button { dismiss() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(CircleIconButtonStyle(size: 44, filled: true))
                .keyboardShortcut(.cancelAction)
                .help("Tillbaka")
        }
        .padding(32)
        .frame(width: 460, height: 640, alignment: .topLeading)
        .background(Theme.base)
    }

    private func row(_ theme: AppTheme) -> some View {
        HStack(spacing: 18) {
            swatch(theme)
            VStack(alignment: .leading, spacing: 4) {
                Text(theme.label)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Theme.primaryText)
                if let detail = theme.detail {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            ZStack {
                Circle().strokeBorder(Theme.primaryText, lineWidth: 2)
                if appearance.theme == theme {
                    Circle().fill(Theme.primaryText).frame(width: 10, height: 10)
                }
            }
            .frame(width: 24, height: 24)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    /// A colour square; "Följ fliken" is split between the tab colours.
    private func swatch(_ theme: AppTheme) -> some View {
        Group {
            switch theme {
            case .perTab:
                HStack(spacing: 0) {
                    Theme.hue(for: .status)
                    Theme.hue(for: .games)
                    Theme.hue(for: .apps)
                }
            case .midnightBlack:
                Color.black
            default:
                Theme.hue(for: .status, theme: theme)
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
    }
}
