import SwiftUI

/// Mole's layout (cards with an uppercase label, a chip in the corner, one big number and a
/// grey footnote) in the PlayStation app's colours: a blue-black base, PlayStation blue for
/// what you can act on, white pill buttons, and the splash screen's angled light planes
/// tinted per tab with the PS app's theme colours.
enum Theme {
    /// PlayStation blue, for fills (the logo disc, selected states).
    static let psBlue = Color(red: 0.00, green: 0.44, blue: 0.82)
    /// A lighter PlayStation blue that reads on the dark base: links, counts, icons.
    static let accent = Color(red: 0.33, green: 0.63, blue: 1.00)
    static let cool = accent
    /// The PS app's presence green.
    static let good = Color(red: 0.18, green: 0.80, blue: 0.44)
    static let warm = Color(red: 0.96, green: 0.70, blue: 0.27)
    static let hot = Color(red: 0.94, green: 0.33, blue: 0.38)

    // The PS app's theme colours, one per tab.
    static let starlightBlue = Color(red: 0.31, green: 0.74, blue: 0.95)
    static let galacticPurple = Color(red: 0.36, green: 0.24, blue: 0.72)
    static let novaPink = Color(red: 0.93, green: 0.25, blue: 0.59)
    static let cosmicRed = Color(red: 0.66, green: 0.12, blue: 0.30)

    /// The dark mode base of the PS app.
    static let base = Color(red: 0.07, green: 0.08, blue: 0.10)

    /// A lighter red for text on the dark base: 7.3:1 on a card, where `hot` is 4.8:1.
    static let hotText = Color(red: 1.00, green: 0.55, blue: 0.58)

    static let primaryText = Color.white.opacity(0.95)
    static let secondaryText = Color.white.opacity(0.62)
    /// 0.50 gives 5.1:1 on a card, above WCAG AA's 4.5:1 for small text (0.40 was 3.75:1).
    static let tertiaryText = Color.white.opacity(0.50)
    static let cardFill = Color.white.opacity(0.05)
    static let cardStroke = Color.white.opacity(0.07)

    static func hue(for tab: MainTab, theme: AppTheme = .perTab) -> Color {
        switch theme {
        case .perTab:
            switch tab {
            case .status: return starlightBlue
            case .games: return novaPink
            case .apps: return galacticPurple
            case .maintenance: return cosmicRed
            }
        case .starlightBlue: return starlightBlue
        case .novaPink: return novaPink
        case .cosmicRed: return cosmicRed
        case .galacticPurple: return galacticPurple
        case .midnightBlack: return Color(white: 0.55)
        }
    }

    static func background(for tab: MainTab, theme: AppTheme = .perTab) -> some View {
        FacetBackground(tint: hue(for: tab, theme: theme), intensity: theme == .midnightBlack ? 0.12 : 0.35)
    }

    static func healthColor(_ score: Int) -> Color {
        switch score {
        case 85...: return good
        case 65..<85: return warm
        default: return hot
        }
    }

    static func temperatureColor(_ value: Int, warnAt: Int) -> Color {
        value >= warnAt + 10 ? hot : value >= warnAt ? warm : good
    }

    /// The type scale. Every text size in the app is one of these (icons may be any size).
    enum TextSize: CGFloat {
        case caption = 11, footnote = 12, body = 13, callout = 14, headline = 15
        case title3 = 17, title2 = 20, title = 26, display = 30, largeTitle = 34, hero = 40
    }

    /// Dates and times are always English and never follow the system language, so a Mac set to
    /// Swedish does not mix "7 nov." into an English interface.
    static let locale = Locale(identifier: "en_US")

    /// "18:12": 24-hour, like the History table.
    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

extension Font {
    /// A size from `Theme.TextSize`: `.font(.ui(.body, weight: .semibold))`.
    static func ui(_ size: Theme.TextSize, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size.rawValue, weight: weight, design: design)
    }
}

extension View {
    /// The tooltip and the VoiceOver label for a button that only shows an icon.
    func iconLabel(_ text: String) -> some View {
        help(text).accessibilityLabel(text)
    }
}

struct Card<Content: View>: View {
    let icon: String
    let title: String
    var chip: String?
    var chipColor: Color = Theme.secondaryText
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.ui(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(title.uppercased())
                    .font(.ui(.caption, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(Theme.primaryText.opacity(0.85))
                Spacer()
                if let chip { Chip(text: chip, color: chipColor) }
            }
            // A chip's height even without one, so card titles line up across a row.
            .frame(minHeight: Chip.height)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardStroke))
    }
}

/// The PS app's platform tag ("PS5"): bold text on a small black plate.
struct Chip: View {
    let text: String
    var color: Color = Theme.primaryText.opacity(0.8)
    /// Caption text plus 3 pt above and below; a card header without a chip keeps this height.
    static let height: CGFloat = 20

    var body: some View {
        Text(text)
            .font(.ui(.caption, weight: .bold))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.black.opacity(0.5)))
    }
}

/// The splash screen of the PS app: a base colour with large angled planes of light.
/// `intensity` 1 is the full splash (connection screen); the tabs use a faint version.
struct FacetBackground: View {
    let tint: Color
    var intensity: Double = 0.35

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack {
                Theme.base
                LinearGradient(colors: [tint.opacity(0.55 * intensity), tint.opacity(0.10 * intensity), .clear],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                facet([(0, 0), (0.58 * w, 0), (0.12 * w, h), (0, h)], from: .top, to: .bottom, opacity: 0.22)
                facet([(0.40 * w, 0), (w, 0), (w, 0.42 * h)], from: .topLeading, to: .trailing, opacity: 0.16)
                facet([(w, 0.50 * h), (w, h), (0.30 * w, h)], from: .bottomTrailing, to: .topLeading, opacity: 0.12)
            }
        }
    }

    private func facet(_ points: [(CGFloat, CGFloat)], from: UnitPoint, to: UnitPoint, opacity: Double) -> some View {
        Path { path in
            path.move(to: CGPoint(x: points[0].0, y: points[0].1))
            points.dropFirst().forEach { path.addLine(to: CGPoint(x: $0.0, y: $0.1)) }
            path.closeSubpath()
        }
        .fill(LinearGradient(colors: [Color.white.opacity(opacity * intensity), tint.opacity(opacity * intensity * 0.6), .clear],
                             startPoint: from, endPoint: to))
    }
}

/// The PS app's splash screen: PlayStation blue, lighter at the top left, with angled planes.
struct SplashBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack {
                LinearGradient(colors: [Color(red: 0.19, green: 0.45, blue: 0.85), Color(red: 0.11, green: 0.27, blue: 0.62),
                                        Color(red: 0.03, green: 0.09, blue: 0.36)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                plane([(0.18 * w, 0), (0.30 * w, 0), (0, h), (0, 0.72 * h)], opacity: 0.07)
                plane([(0.32 * w, 0), (w, 0), (w, 0.19 * h)], opacity: 0.10)
                plane([(w, 0.52 * h), (w, h), (0.13 * w, h)], opacity: 0.06)
            }
        }
    }

    private func plane(_ points: [(CGFloat, CGFloat)], opacity: Double) -> some View {
        Path { path in
            path.move(to: CGPoint(x: points[0].0, y: points[0].1))
            points.dropFirst().forEach { path.addLine(to: CGPoint(x: $0.0, y: $0.1)) }
            path.closeSubpath()
        }
        .fill(Color.white.opacity(opacity))
    }
}

/// A thin ring that turns, like the PS app's loading indicator. Unlike ProgressView it also
/// renders in ImageRenderer (snapshots), as a still arc.
struct Spinner: View {
    var size: CGFloat = 16
    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0.08, to: 0.78)
            .stroke(Theme.primaryText.opacity(0.75), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: turning)
            .onAppear { turning = true }
    }
}

/// The PS app's storage bar: a white fill with a PlayStation-blue tip on a dark track.
struct PSProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                HStack(spacing: 0) {
                    Rectangle().fill(Color.white)
                    Rectangle().fill(Theme.accent).frame(width: min(4, width))
                }
                .frame(width: max(width, 4))
                .clipShape(Capsule())
            }
        }
        .frame(height: 6)
    }
}

/// "58 %" style: a big rounded number with a smaller unit.
struct BigValue: View {
    let value: String
    var unit: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.ui(.hero, weight: .light))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let unit {
                Text(unit)
                    .font(.ui(.headline, weight: .regular))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

struct Footnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.ui(.body))
            .foregroundStyle(Theme.secondaryText)
            .lineLimit(1)
    }
}

/// Smooth line with a faded fill underneath, like Mole's GPU and memory cards.
struct Sparkline: View {
    let values: [Double]
    var range: ClosedRange<Double>
    var color: Color

    var body: some View {
        GeometryReader { proxy in
            let points = normalized(in: proxy.size)
            ZStack {
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points.last!.x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func normalized(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let span = max(range.upperBound - range.lowerBound, 0.001)
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let clamped = min(max(value, range.lowerBound), range.upperBound)
            let y = size.height * (1 - CGFloat((clamped - range.lowerBound) / span))
            return CGPoint(x: CGFloat(index) * step, y: y)
        }
    }
}

struct BarGauge: View {
    let fraction: Double
    var color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 8)
    }
}

/// Mole shows a planet that reflects system health; here it is a glowing orb in the health colour.
struct HealthOrb: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .blur(radius: 18)
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.9), color, color.opacity(0.55), Color.black.opacity(0.6)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 2, endRadius: 70))
            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            Image(systemName: "playstation.logo")
                .font(.ui(.display, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .shadow(color: .black.opacity(0.4), radius: 4)
        }
        .frame(width: 112, height: 112)
    }
}

/// Pill buttons as in the PS app: white with black text for the main action ("Buy Now"),
/// an outlined pill for secondary ones, and a tinted pill inside coloured banners.
/// At most one white pill per screen: everything else is outlined or tinted.
struct PillButtonStyle: ButtonStyle {
    /// Banner colour; nil is the white main action.
    var tint: Color?
    var prominent = true
    /// Delete, Uninstall: a red outline and red text, so it never looks like the other buttons.
    var destructive = false
    /// A disabled button is faded, so the white main action never looks clickable when it is not.
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(.body, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background {
                if destructive {
                    Capsule().fill(Theme.hot.opacity(configuration.isPressed ? 0.18 : 0.06))
                    Capsule().strokeBorder(Theme.hot.opacity(configuration.isPressed ? 0.9 : 0.65), lineWidth: 1.5)
                } else if !prominent {
                    Capsule().strokeBorder(Color.white.opacity(configuration.isPressed ? 0.6 : 0.35), lineWidth: 1.5)
                } else if let tint {
                    // White text on a stronger tint: the tint's own colour as text was 4.4:1 at best.
                    Capsule().fill(tint.opacity(configuration.isPressed ? 0.5 : 0.36))
                } else {
                    Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.8 : 1))
                }
            }
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(Capsule())
    }

    private var foreground: Color {
        if destructive { return Theme.hotText }
        if !prominent { return Theme.primaryText }
        return tint == nil ? .black : Theme.primaryText
    }
}

/// The PS app's round outlined icon buttons (refresh, settings).
struct CircleIconButtonStyle: ButtonStyle {
    var size: CGFloat = 34
    /// The white disc with a black icon, like the PS app's back button.
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(filled ? Color.black : Theme.primaryText)
            .frame(width: size, height: size)
            .background {
                if filled {
                    Circle().fill(Color.white.opacity(configuration.isPressed ? 0.8 : 1))
                } else {
                    Circle().strokeBorder(Color.white.opacity(configuration.isPressed ? 0.7 : 0.4), lineWidth: 1.5)
                }
            }
            .contentShape(Circle())
    }
}

/// Closes a sheet that only shows or sets things: bottom right, where the review sheets have
/// Cancel and their main button, and on Esc. Every sheet closes the same way.
struct DoneButton: View {
    @Environment(\.dismiss) private var dismiss
    /// Outlined when the sheet has a white main button of its own.
    var prominent = true
    /// False where Esc means something else (the remote sends it to the PS3 as Back): ⌘W instead.
    var closesOnEscape = true

    var body: some View {
        Button("Done") { dismiss() }
            .buttonStyle(PillButtonStyle(prominent: prominent))
            .keyboardShortcut(closesOnEscape ? .cancelAction : KeyboardShortcut("w"))
    }
}

/// A count in a green disc, like "Friends 2" in the PS app.
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.ui(.caption, weight: .bold))
            .foregroundStyle(.black)
            .monospacedDigit()
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, count > 9 ? 4 : 0)
            .background(Capsule().fill(Theme.good))
    }
}
