import Observation
import PS3Kit
import SwiftUI

/// The PS app's themes. "Match Tab" (the default) gives each tab its own colour, as the PS
/// app's "Match Device" follows the device; the others colour every tab the same.
enum AppTheme: String, CaseIterable, Identifiable {
    case perTab, starlightBlue, novaPink, cosmicRed, galacticPurple, midnightBlack

    var id: String { rawValue }

    var label: String {
        switch self {
        case .perTab: return "Match Tab"
        case .starlightBlue: return "Starlight Blue"
        case .novaPink: return "Nova Pink"
        case .cosmicRed: return "Cosmic Red"
        case .galacticPurple: return "Galactic Purple"
        case .midnightBlack: return "Midnight Black"
        }
    }

    var detail: String? {
        self == .perTab ? "Each tab gets its own color: Status Starlight Blue, Games Nova Pink, Apps Galactic Purple, Maintenance Cosmic Red." : nil
    }
}

/// The chosen theme, saved in ~/.config/ps3center/config.json next to host and root.
@MainActor
@Observable
final class AppearanceStore {
    var theme: AppTheme {
        didSet {
            guard persists else { return }
            let saved = theme == .perTab ? nil : theme.rawValue
            // A preference: if config.json can't be written the theme still applies until quit.
            try? ConfigStore.edit { $0.theme = saved }
        }
    }

    /// False for snapshots, which must not change the user's settings.
    private let persists: Bool

    init(previewing preview: AppTheme? = nil) {
        persists = preview == nil
        theme = preview ?? ConfigStore.load().theme.flatMap(AppTheme.init(rawValue:)) ?? .perTab
    }
}

/// The PS app's Appearance rows, in Settings → Appearance: one row per theme with a colour
/// square and a radio button.
struct ThemePicker: View {
    @Environment(AppearanceStore.self) private var appearance

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(AppTheme.allCases) { theme in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { appearance.theme = theme }
                } label: {
                    row(theme)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(appearance.theme == theme ? .isSelected : [])
            }
        }
    }

    private func row(_ theme: AppTheme) -> some View {
        HStack(spacing: 18) {
            swatch(theme)
            VStack(alignment: .leading, spacing: 4) {
                Text(theme.label)
                    .font(.ui(.title3, weight: .light))
                    .foregroundStyle(Theme.primaryText)
                if let detail = theme.detail {
                    Text(detail)
                        .font(.ui(.body))
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

    /// A colour square; "Match Tab" is split between the tab colours.
    private func swatch(_ theme: AppTheme) -> some View {
        Group {
            switch theme {
            case .perTab:
                HStack(spacing: 0) {
                    Theme.hue(for: .status)
                    Theme.hue(for: .games)
                    Theme.hue(for: .apps)
                    Theme.hue(for: .maintenance)
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
