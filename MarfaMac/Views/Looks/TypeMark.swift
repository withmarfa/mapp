import MarfaIcons
import SwiftUI

/// A type's icon in its tone on a pale rounded square of the same color, with no shadow. It reads a table and two
/// constants, so it is cheap in a list row. Sizes follow the design's `.m-tmark.is-*` and `tileSizes`.
struct TypeMark: View {
    enum Size: CaseIterable, Sendable {
        case row, side, large

        /// The square's side, its corner radius and the icon's side, in points.
        var metrics: (box: CGFloat, radius: CGFloat, icon: CGFloat) {
            switch self {
            case .row: (18, 5, 11)
            case .side: (20, 6, 12)
            case .large: (32, 8, 16)
            }
        }
    }

    let icon: String?
    var size: Size = .row

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
