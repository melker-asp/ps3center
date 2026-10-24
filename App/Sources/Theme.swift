import SwiftUI

/// Visual language borrowed from Mole: warm dark gradients that change per tab, translucent
/// cards with an uppercase label, a chip in the corner, one big number and a grey footnote.
enum Theme {
    static let good = Color(red: 0.31, green: 0.70, blue: 0.54)
    static let warm = Color(red: 0.88, green: 0.66, blue: 0.31)
    static let hot = Color(red: 0.88, green: 0.40, blue: 0.31)
    static let cool = Color(red: 0.36, green: 0.55, blue: 0.94)
    static let accent = Color(red: 0.93, green: 0.55, blue: 0.43)

    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.58)
    static let tertiaryText = Color.white.opacity(0.38)
    static let cardFill = Color.white.opacity(0.045)
    static let cardStroke = Color.white.opacity(0.07)

    static func background(for tab: MainTab) -> LinearGradient {
        let colors: [Color]
        switch tab {
        case .status:
            colors = [Color(red: 0.30, green: 0.24, blue: 0.08), Color(red: 0.17, green: 0.14, blue: 0.07)]
        case .apps:
            colors = [Color(red: 0.25, green: 0.10, blue: 0.10), Color(red: 0.14, green: 0.07, blue: 0.08)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
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
                    .foregroundStyle(Theme.warm)
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

struct Chip: View {
    let text: String
    var color: Color = Theme.secondaryText

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.07)))
    }
}

/// "58 %" style: a big rounded number with a smaller unit.
struct BigValue: View {
    let value: String
    var unit: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let unit {
                Text(unit)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
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

/// Small pill button used for row actions ("Uppdatera", "Installera").
struct PillButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? tint : Theme.secondaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Capsule().fill(prominent ? tint.opacity(configuration.isPressed ? 0.28 : 0.16) : Color.clear))
            .contentShape(Capsule())
    }
}
