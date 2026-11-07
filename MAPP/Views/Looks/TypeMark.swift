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
                    .foregroundStyle(tone.ink(ChipLooks.current.inkDepth, for: scheme))
                    .frame(width: metrics.icon, height: metrics.icon)
            }
            .accessibilityHidden(true)
    }
}

/// A type's name in a small pill of its tone, the page's type chip at the size of a list row's line of facts. It reads
/// a table and two constants, as the mark does, so it is cheap in a row.
struct TypePill: View {
    let icon: String?
    let label: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tone = TypeTone(icon: icon)
        HStack(spacing: 3) {
            Image(typeGlyph: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(verbatim: label).lineLimit(1)
        }
        .foregroundStyle(tone.ink(ChipLooks.current.inkDepth, for: scheme))
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .padding(.vertical, 1.5)
        .background(tone.fill(ChipLooks.current.typeTintOpacity, for: scheme), in: .rect(cornerRadius: 4, style: .continuous))
    }
}
