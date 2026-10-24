import AppKit
import PS3Kit
import SwiftUI

/// Fjärrkontroll: webMAN's virtual pad, with the keyboard too: arrows, Return for OK and Esc for
/// back. Watch the TV; a picture of the XMB fetched from the console lagged behind the presses.
struct RemoteView: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(\.dismiss) private var dismiss
    /// False when rendered for a snapshot: no pad.
    var live = true
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Fjärrkontroll")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Text("Piltangenter · Retur = OK · Esc = tillbaka")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiaryText)
            }
            pad.padding(.top, 28)
            Spacer(minLength: 12)
            Button { dismiss() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(CircleIconButtonStyle(size: 44, filled: true))
                .keyboardShortcut("w")
                .help("Stäng (⌘W)")
        }
        .padding(32)
        .frame(width: 720, height: 420, alignment: .topLeading)
        .background(Theme.base)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { key(.up) }
        .onKeyPress(.downArrow) { key(.down) }
        .onKeyPress(.leftArrow) { key(.left) }
        .onKeyPress(.rightArrow) { key(.right) }
        .onKeyPress(.return) { key(.accept) }
        .onKeyPress(.escape) { key(.cancel) }
        .onKeyPress(.delete) { key(.cancel) }
        .task {
            guard live else { return }
            focused = true
        }
        .onDisappear {
            // Not left connected as a second controller.
            guard live else { return }
            Task { await console.padOff() }
        }
    }

    // MARK: The controller

    private var pad: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(spacing: 14) {
                HStack(spacing: 10) { button(.l2, size: 40); button(.l1, size: 40) }
                cross(up: .up, left: .left, right: .right, down: .down) { button($0, size: 46) }
            }
            Spacer()
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    button(.select, size: 52, font: 9)
                    button(.ps, size: 52, font: 13)
                    button(.start, size: 52, font: 9)
                }
                HStack(spacing: 10) {
                    Button("Tillbaka") { tap(.cancel) }
                        .buttonStyle(PillButtonStyle(prominent: false))
                    Button("OK") { tap(.accept) }
                        .buttonStyle(PillButtonStyle())
                }
            }
            Spacer()
            VStack(spacing: 14) {
                HStack(spacing: 10) { button(.r1, size: 40); button(.r2, size: 40) }
                cross(up: .triangle, left: .square, right: .circle, down: .cross) { face($0) }
            }
        }
        .disabled(!live)
    }

    /// Four buttons in a diamond, like the d-pad and the face buttons.
    private func cross<Content: View>(up: PadButton, left: PadButton, right: PadButton, down: PadButton,
                                      @ViewBuilder content: (PadButton) -> Content) -> some View {
        VStack(spacing: 4) {
            content(up)
            HStack(spacing: 46) { content(left); content(right) }
            content(down)
        }
    }

    private func button(_ button: PadButton, size: CGFloat, font: CGFloat? = nil) -> some View {
        Button { tap(button) } label: {
            Text(button.label).font(.system(size: font ?? size * 0.36, weight: .bold))
        }
        .buttonStyle(CircleIconButtonStyle(size: size))
        .help(button.rawValue)
    }

    /// ✕ ◯ △ □ in the controller's colours.
    private func face(_ button: PadButton) -> some View {
        let colors: [PadButton: Color] = [.triangle: Theme.good, .circle: Theme.hot, .cross: Theme.cool, .square: Theme.novaPink]
        return Button { tap(button) } label: {
            Text(button.label)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(colors[button] ?? Theme.primaryText)
        }
        .buttonStyle(CircleIconButtonStyle(size: 46))
    }

    // MARK: Pressing

    private func key(_ button: PadButton) -> KeyPress.Result {
        tap(button)
        return .handled
    }

    private func tap(_ button: PadButton) {
        guard live else { return }
        Task { await console.press(button) }
    }
}
