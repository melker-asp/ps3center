import AppKit
import PS3Kit
import SwiftUI

/// Fjärrkontroll: webMAN's virtual pad, with a picture of the XMB fetched every few seconds.
/// The keyboard works too: arrows, Return for OK and Esc for back.
struct RemoteView: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(\.dismiss) private var dismiss
    /// False when rendered for a snapshot: no polling and no pad.
    var live = true
    @State private var image: NSImage?
    @State private var note: String?
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
            screen.padding(.top, 16)
            pad.padding(.top, 22)
            Spacer(minLength: 12)
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(CircleIconButtonStyle(size: 44, filled: true))
                    .keyboardShortcut("w")
                    .help("Stäng (⌘W)")
                Spacer()
                Button { Task { await refresh() } } label: { Label("Uppdatera bilden", systemImage: "arrow.clockwise") }
                    .buttonStyle(PillButtonStyle(prominent: false))
            }
        }
        .padding(32)
        .frame(width: 720, height: 780, alignment: .topLeading)
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
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        .onDisappear {
            // Not left connected as a second controller.
            guard live else { return }
            Task { await console.padOff() }
        }
    }

    // MARK: The TV

    private var screen: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "playstation.logo")
                        .font(.system(size: 54))
                        .foregroundStyle(Color.white.opacity(0.25))
                    Text(note ?? "Hämtar bilden av XMB:n…")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cardStroke))
        .overlay(alignment: .bottomLeading) {
            if image != nil, let note {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .padding(10)
            }
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
        Task {
            await console.press(button)
            // The XMB needs a moment to move before the picture shows it.
            try? await Task.sleep(nanoseconds: 700_000_000)
            await refresh()
        }
    }

    private func refresh() async {
        guard live else { return }
        if console.snapshot?.isGameRunning == true {
            note = "Bilden av TV:n går bara att ta i XMB:n, inte under ett spel."
            return
        }
        if let next = await console.screenshot() {
            image = next
            note = nil
        } else {
            note = "Ingen bild från PS3:an just nu."
        }
    }
}
