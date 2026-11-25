import MarfaIcons
import SwiftUI

/// A type's icon in its tone on a pale rounded square of the same color, with no shadow. It is only for a gallery cover
/// with no picture and the Settings type pages; everywhere else a type's mark is the bare `TonedGlyph`. Sizes follow the
/// design's `tileSizes` (Foundations F6).
struct TypeTile: View {
    enum Size: CaseIterable, Sendable {
        case side, large

        /// The square's side, its corner radius and the icon's side, in points.
        var metrics: (box: CGFloat, radius: CGFloat, icon: CGFloat) {
            switch self {
            case .side: (20, 6, 12)
            case .large: (32, 8, 16)
            }
        }
    }

    let icon: String?
    var size: Size = .side

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tone = TypeTone(icon: icon)
        let metrics = size.metrics
        RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
            .fill(tone.fill(ChipLooks.current.markOpacity, for: scheme))
            .frame(width: metrics.box, height: metrics.box)
            .overlay {
                Image(typeGlyph: icon)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(tone.ink(ChipLooks.current, for: scheme))
                    .frame(width: metrics.icon, height: metrics.icon)
            }
            .accessibilityHidden(true)
    }
}
