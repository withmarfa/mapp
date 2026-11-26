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

/// The system slider, small and gray as the board's track: a click or a drag moves the file to that place, and it takes
/// the keyboard as any slider does. While it is dragged the player lands near each place, then exactly where it ends.
private struct PlaybackScrubber: View {
    let playback: MediaPlayback
    /// Where a drag has the knob, while one is under way.
    @State private var dragged: Double?

    var body: some View {
        Slider(
            value: Binding {
                dragged ?? playback.position
            } set: { time in
                if dragged != nil {
                    dragged = time
                    playback.scrub(to: time)
                } else {
                    playback.seek(to: time)
                }
            },
            in: 0...max(playback.duration, 0.001)
        ) {
            Text("Position")
        } onEditingChanged: { editing in
            if editing {
                dragged = playback.position
            } else if let time = dragged {
                dragged = nil
                playback.endScrub(at: time)
            }
        }
        .labelsHidden()
        .controlSize(.mini)
        .tint(.primary.opacity(0.55))
        .frame(minWidth: 40, maxWidth: .infinity)
        .disabled(playback.state != .ready)
        .accessibilityValue(Text("\(PlaybackClock.label(playback.position)) of \(PlaybackClock.label(playback.duration))"))
        .accessibilityIdentifier("PlaybackScrubber")
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
        let metrics = PlaybackFootMetrics(scale: InterfaceStyle.scale(for: textSize))
        let lift = WindowCorner<EmptyView, EmptyView>.lift(summary: summary, details: details, scale: metrics.scale)
        PlaybackFootLayout(metrics: metrics) { bar.pointerStyle(.default) }
            .padding(.bottom, metrics.inset + lift)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(.smooth(duration: 0.25), value: lift)
    }
}

/// Where the foot puts the bar, which the page also reads to keep its last part clear of the bar.
nonisolated struct PlaybackFootMetrics {
    let scale: CGFloat
    let inset: CGFloat
    var barHeight: CGFloat { 44 * scale }
    var ideal: CGFloat { 500 * scale }
    /// The narrowest the bar is drawn beside the buttons.
    var least: CGFloat { 300 * scale }
    /// What the corner's buttons take at the trailing edge: Open and Focus, with the gap between, and the gaps beside.
    var trailing: CGFloat { (72 + 8) * scale + inset * 2 }
    /// How far the bar rises when it cannot sit beside the buttons: their height and the gap above them.
    let raise: CGFloat

    @MainActor init(scale: CGFloat) {
        self.scale = scale
        inset = WindowCorner<EmptyView, EmptyView>.inset
        raise = CornerMetrics.height * scale + inset
    }

    func isRaised(in width: CGFloat) -> Bool { width - inset - trailing < least }

    /// What the page leaves under its content so its last part scrolls clear of the bar: the bar, how far it stands
    /// above the pane's foot, and a gap above it.
    @MainActor
    func reserve(in width: CGFloat, summary: SelectionSummary?, details: DetailsPresentation?) -> CGFloat {
        let lift = WindowCorner<EmptyView, EmptyView>.lift(summary: summary, details: details, scale: scale)
        return inset + lift + (isRaised(in: width) ? raise : 0) + barHeight + inset
    }
}

private struct PlaybackFootLayout: Layout {
    var metrics: PlaybackFootMetrics

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.first?.sizeThatFits(.unspecified).height ?? 0
        return CGSize(width: proposal.width ?? metrics.ideal, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let bar = subviews.first else { return }
        let leading = metrics.inset
        let lifted = metrics.isRaised(in: bounds.width)
        let room = lifted ? max(bounds.width - leading * 2, 1) : bounds.width - leading - metrics.trailing
        let width = min(metrics.ideal, room)
        let end = lifted ? bounds.maxX - leading : bounds.maxX - metrics.trailing
        let x = min(max(bounds.midX - width / 2, bounds.minX + leading), end - width)
        bar.place(
            at: CGPoint(x: x, y: bounds.maxY - (lifted ? metrics.raise : 0)), anchor: .bottomLeading,
            proposal: ProposedViewSize(width: width, height: nil))
    }
}
