import SwiftUI

/// The one playback bar of an audio or a video page: back and forward, Play or Pause, where the file is, a scrubber,
/// its length and its speed, in one capsule at the window's foot (`PlaybackFoot`). Before the file is here it says
/// Getting File…, and where it could not be had, Can’t Get This File with Try Again.
struct PlaybackBar: View {
    enum Mode {
        case player(MediaPlayback)
        case gettingFile
        case failed(retry: () -> Void)
    }

    let mode: Mode
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        HStack(spacing: 11 * scale) {
            switch mode {
            case .player(let playback):
                PlayerControls(playback: playback)
            case .gettingFile:
                Controls(isEnabled: false, isPlaying: false, back: {}, toggle: {}, forward: {})
                Text("Getting File…").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                speedLabel(1)
            case .failed(let retry):
                Controls(isEnabled: false, isPlaying: false, back: {}, toggle: {}, forward: {})
                Text("Can’t Get This File").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                Button("Try Again", action: retry)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .accessibilityIdentifier("PlaybackTryAgain")
            }
        }
        .font(.system(size: 12 * scale))
        .monospacedDigit()
        .padding(.leading, 14 * scale)
        .padding(.trailing, 16 * scale)
        .frame(height: 44 * scale)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Playback")
        .accessibilityIdentifier("PlaybackBar")
    }

    private func speedLabel(_ speed: Double) -> some View {
        Text(verbatim: PlaybackClock.speedLabel(speed)).fontWeight(.medium).foregroundStyle(.primary.opacity(0.4))
    }
}

/// Back, Play or Pause, and forward.
private struct Controls: View {
    let isEnabled: Bool
    let isPlaying: Bool
    let back: () -> Void
    let toggle: () -> Void
    let forward: () -> Void
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        HStack(spacing: 11 * scale) {
            Button("Back 15 Seconds", systemImage: "arrow.counterclockwise", action: back)
                .labelStyle(.iconOnly)
                .buttonStyle(SkipStyle())
                .help("Back 15 Seconds")
                .accessibilityIdentifier("PlaybackBack")
            Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill", action: toggle)
                .labelStyle(.iconOnly)
                .buttonStyle(PlayStyle())
                .help(isPlaying ? "Pause" : "Play")
                .accessibilityIdentifier("PlaybackPlay")
            Button("Forward 15 Seconds", systemImage: "arrow.clockwise", action: forward)
                .labelStyle(.iconOnly)
                .buttonStyle(SkipStyle())
                .help("Forward 15 Seconds")
                .accessibilityIdentifier("PlaybackForward")
        }
        .disabled(!isEnabled)
    }
}

private struct SkipStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.interfaceTextSize) private var textSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15 * InterfaceStyle.scale(for: textSize)))
            .foregroundStyle(.primary.opacity(isEnabled ? (configuration.isPressed ? 0.9 : 0.62) : 0.3))
            .contentShape(.rect)
    }
}

/// The 32 point circle with the glyph in it.
private struct PlayStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.interfaceTextSize) private var textSize

    func makeBody(configuration: Configuration) -> some View {
        let scale = InterfaceStyle.scale(for: textSize)
        configuration.label
            .font(.system(size: 13 * scale))
            .foregroundStyle(.primary.opacity(isEnabled ? 1 : 0.35))
            .frame(width: 32 * scale, height: 32 * scale)
            .background(.primary.opacity(configuration.isPressed ? 0.16 : isEnabled ? 0.08 : 0.04), in: .circle)
            .contentShape(.circle)
    }
}

/// The bar while a file is open: its place, scrubber, length and speed come from `playback`.
private struct PlayerControls: View {
    let playback: MediaPlayback

    var body: some View {
        let isReady = playback.state == .ready
        Controls(
            isEnabled: isReady, isPlaying: playback.isPlaying,
            back: { playback.skip(by: -PlaybackClock.skip) }, toggle: { playback.togglePlaying() },
            forward: { playback.skip(by: PlaybackClock.skip) })
        Text(verbatim: PlaybackClock.label(playback.position))
            .foregroundStyle(.secondary)
        PlaybackScrubber(playback: playback)
        Text(verbatim: PlaybackClock.label(playback.duration))
            .foregroundStyle(.secondary)
        Menu {
            ForEach(PlaybackClock.speeds, id: \.self) { speed in
                Toggle(isOn: Binding { playback.speed == speed } set: { _ in playback.setSpeed(speed) }) {
                    Text(verbatim: PlaybackClock.speedLabel(speed))
                }
            }
        } label: {
            Text(verbatim: PlaybackClock.speedLabel(playback.speed)).fontWeight(.medium).frame(minWidth: 22, alignment: .trailing)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!isReady)
        .help("Speed")
        .accessibilityLabel("Speed")
        .accessibilityValue(PlaybackClock.speedLabel(playback.speed))
        .accessibilityIdentifier("PlaybackSpeed")
    }
}

/// The track, drawn as the board draws it: a 4 point line with the played part darker and a knob. A click or a drag
/// moves the file to that place; VoiceOver and the keyboard see an ordinary slider.
private struct PlaybackScrubber: View {
    let playback: MediaPlayback

    var body: some View {
        let share = playback.duration > 0 ? min(max(playback.position / playback.duration, 0), 1) : 0
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.1)).frame(height: 4)
                Capsule().fill(.primary.opacity(0.55)).frame(width: width * share, height: 4)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                    .overlay { Circle().strokeBorder(.black.opacity(0.18), lineWidth: 0.5) }
                    .frame(width: 12, height: 12)
                    .offset(x: width * share - 6)
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in playback.scrub(to: time(at: drag.location.x, in: width)) }
                    .onEnded { drag in playback.endScrub(at: time(at: drag.location.x, in: width)) })
        }
        .frame(minWidth: 40, maxWidth: .infinity, minHeight: 20, maxHeight: 20)
        .opacity(playback.state == .ready ? 1 : 0.35)
        .accessibilityRepresentation {
            // A step longer than the file is not a step a slider takes.
            let span = max(playback.duration, 1)
            Slider(
                value: Binding { playback.position } set: { playback.seek(to: $0) },
                in: 0...span, step: min(5, span / 2)
            ) { Text("Position") }
            .accessibilityValue(Text("\(PlaybackClock.label(playback.position)) of \(PlaybackClock.label(playback.duration))"))
            .disabled(playback.state != .ready)
        }
        .accessibilityIdentifier("PlaybackScrubber")
    }

    private func time(at x: CGFloat, in width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1)) * playback.duration
    }
}

/// Puts a bar along the foot of the page's pane, centered on it and beside the corner's buttons at the width of the
/// design's 500 points where there is room. In a pane too narrow to hold the bar beside them it rises above them, as the
/// formats bar does. It lifts above a toast as the corner does (`WindowCorner.lift`).
struct PlaybackFoot<Bar: View>: View {
    @ViewBuilder var bar: Bar
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    @Environment(SelectionSummary.self) private var summary: SelectionSummary?
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        let inset = WindowCorner<EmptyView, EmptyView>.inset
        // What the corner's buttons take at the trailing edge at the default text size: Open and Focus, with the gap between.
        let cornerRoom: CGFloat = 72 + 8
        let lift = WindowCorner<EmptyView, EmptyView>.lift(summary: summary, details: details, scale: scale)
        PlaybackFootLayout(
            leading: inset, trailing: cornerRoom * scale + inset * 2, ideal: 500 * scale, least: 300 * scale,
            raise: CornerMetrics.height * scale + inset
        ) { bar.pointerStyle(.default) }
            .padding(.bottom, inset + lift)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(.smooth(duration: 0.25), value: lift)
    }
}

private struct PlaybackFootLayout: Layout {
    var leading: CGFloat
    var trailing: CGFloat
    var ideal: CGFloat
    /// The narrowest the bar is drawn beside the buttons.
    var least: CGFloat
    /// How far the bar rises when it cannot sit beside the buttons: their height and the gap above them.
    var raise: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.first?.sizeThatFits(.unspecified).height ?? 0
        return CGSize(width: proposal.width ?? ideal, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let bar = subviews.first else { return }
        let beside = bounds.width - leading - trailing
        let lifted = beside < least
        let room = lifted ? max(bounds.width - leading * 2, 1) : beside
        let width = min(ideal, room)
        let end = lifted ? bounds.maxX - leading : bounds.maxX - trailing
        let x = min(max(bounds.midX - width / 2, bounds.minX + leading), end - width)
        bar.place(
            at: CGPoint(x: x, y: bounds.maxY - (lifted ? raise : 0)), anchor: .bottomLeading,
            proposal: ProposedViewSize(width: width, height: nil))
    }
}
