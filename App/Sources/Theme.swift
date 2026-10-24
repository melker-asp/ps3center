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

    static let primaryText = Color.white.opacity(0.95)
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.40)
    static let cardFill = Color.white.opacity(0.05)
    static let cardStroke = Color.white.opacity(0.07)

    static func hue(for tab: MainTab) -> Color {
        switch tab {
        case .status: return starlightBlue
        case .apps: return galacticPurple
        }
    }

    static func background(for tab: MainTab) -> some View {
        FacetBackground(tint: hue(for: tab))
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(Theme.primaryText.opacity(0.85))
                Spacer()
                if let chip { Chip(text: chip, color: chipColor) }
            }
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

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
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
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let unit {
                Text(unit)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

struct Footnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
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
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .shadow(color: .black.opacity(0.4), radius: 4)
        }
        .frame(width: 112, height: 112)
    }
}

/// Pill buttons as in the PS app: white with black text for the main action ("Köp nu"),
/// an outlined pill for secondary ones, and a tinted pill inside coloured banners.
struct PillButtonStyle: ButtonStyle {
    /// Banner colour; nil is the white main action.
    var tint: Color?
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background {
                if !prominent {
                    Capsule().strokeBorder(Color.white.opacity(configuration.isPressed ? 0.6 : 0.35), lineWidth: 1.5)
                } else if let tint {
                    Capsule().fill(tint.opacity(configuration.isPressed ? 0.32 : 0.2))
                } else {
                    Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.8 : 1))
                }
            }
            .contentShape(Capsule())
    }

    private var foreground: Color {
        if !prominent { return Theme.primaryText }
        return tint ?? .black
    }
}

/// The PS app's round outlined icon buttons (refresh, settings).
struct CircleIconButtonStyle: ButtonStyle {
    var size: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.primaryText)
            .frame(width: size, height: size)
            .background(Circle().strokeBorder(Color.white.opacity(configuration.isPressed ? 0.7 : 0.4), lineWidth: 1.5))
            .contentShape(Circle())
    }
}

/// A count in a green disc, like "Vänner 2" in the PS app.
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.black)
            .monospacedDigit()
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, count > 9 ? 4 : 0)
            .background(Capsule().fill(Theme.good))
    }
}
