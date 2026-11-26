import SwiftUI

/// A sound's waveform, the part already played darker, as many bars as the width has room for. A click or a drag on it
/// moves the file there. While `envelope` is still being worked out the bars stand at their lowest.
struct WaveformView: View {
    static let height: CGFloat = 120
    private static let gap: CGFloat = 3
    private static let barPitch: CGFloat = 6
    private static let lowest: CGFloat = 10

    let playback: MediaPlayback
    let envelope: WaveformEnvelope?
    @State private var width: CGFloat = 0

    var body: some View {
        let share = playback.duration > 0 ? min(max(playback.position / playback.duration, 0), 1) : 0
        Canvas { context, size in
            let count = max(Int((size.width + Self.gap) / Self.barPitch), 1)
            let levels = envelope?.bars(count) ?? []
            let barWidth = (size.width - Self.gap * CGFloat(count - 1)) / CGFloat(count)
            for bar in 0..<count {
                let level = bar < levels.count ? CGFloat(levels[bar]) : 0
                let height = (Self.lowest + level * (size.height - 16)).rounded(.down)
                let rect = CGRect(x: CGFloat(bar) * (barWidth + Self.gap), y: (size.height - height) / 2, width: barWidth, height: height)
                let played = Double(bar) / Double(count) < share
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(.primary.opacity(played ? 0.6 : 0.16)))
            }
        }
        .frame(height: Self.height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { playback.scrub(to: time(at: $0.location.x)) }
                .onEnded { playback.endScrub(at: time(at: $0.location.x)) })
        // The bar's scrubber is the control; the waveform only shows where the sound is loud.
        .accessibilityHidden(true)
    }

    private func time(at x: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1)) * playback.duration
    }
}
