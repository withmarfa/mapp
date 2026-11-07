import MarfaIcons
import SwiftUI

/// One chip of the item page's header, drawn in SwiftUI from the same looks as the note page's web header: the sizes
/// and fills of `ChipLooks.current` and the colors of `TypeTone`, scaled with the interface's text size (the design's
/// 13 points). A chip is 22 points tall whatever it holds, so chips side by side line up.
struct PageChip: View {
    enum Kind {
        /// The type's name, tinted in its tone, with its icon in color.
        case type(icon: String?)
        /// An item a row links to: its mark in color and its title on a grey fill, since a tint means a type. The title
        /// is underlined under the pointer.
        case link(icon: String?)
        /// A status: its group's mark in a chip with a fine edge, and a chevron where it opens a menu.
        case status(PageHeader.Mark, chevron: Bool)
        /// A choice or a word of a list: neutral, with a dot in its own color.
        case option(TypeTone)
        /// One of the item's tags, grey, after a number sign.
        case tag
        /// A word with no mark of its own, on the fill a choice has: a date, a number or a person's name.
        case plain
    }

    let text: String
    let kind: Kind

    @Environment(\.colorScheme) private var scheme
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize
    @State private var isHovering = false

    private var isPlain: Bool {
        if case .plain = kind { true } else { false }
    }

    private var isLink: Bool {
        if case .link = kind { true } else { false }
    }

    var body: some View {
        let looks = ChipLooks.current
        let scale = CGFloat(textSize) / 13
        let shape = RoundedRectangle(cornerRadius: looks.cornerRadius * scale)
        HStack(spacing: isPlain ? 0 : looks.gap * scale) {
            leading(looks: looks, scale: scale)
            Text(verbatim: text)
                .underline(isLink && isHovering)
                .lineLimit(1)
                .truncationMode(.tail)
            if case .status(_, true) = kind {
                Image(systemName: "chevron.down")
                    .font(.system(size: looks.textSize * scale * 0.6, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(looks.chevronOpacity)
                    .accessibilityHidden(true)
            }
        }
        .font(.system(size: looks.textSize * scale))
        .foregroundStyle(textStyle(looks: looks))
        .padding(.leading, start(looks: looks) * scale)
        .padding(.trailing, looks.padding * scale)
        .frame(height: looks.height * scale)
        .background(fill(looks: looks), in: shape)
        .onHover { if isLink { isHovering = $0 } }
        .overlay {
            if case .status = kind {
                shape.strokeBorder(looks.edge(for: scheme), lineWidth: looks.statusEdgeWidth)
            }
        }
    }

    /// A type's name takes its ink, as a list row's does; every other chip's text is the label color.
    private func textStyle(looks: ChipLooks) -> AnyShapeStyle {
        if case .type(let icon) = kind { AnyShapeStyle(TypeTone(icon: icon).ink(looks, for: scheme)) } else { AnyShapeStyle(.primary) }
    }

    private func start(looks: ChipLooks) -> CGFloat {
        switch kind {
        case .type, .status, .link: looks.typePaddingStart
        case .tag: looks.tagPaddingStart
        case .option, .plain: looks.padding
        }
    }

    private func fill(looks: ChipLooks) -> Color {
        switch kind {
        case .type(let icon): TypeTone(icon: icon).fill(scheme == .dark ? looks.typeTintOpacityDark : looks.typeTintOpacity, for: scheme)
        case .status: looks.statusFill(for: scheme)
        case .link, .option, .plain: looks.optionFill(for: scheme)
        case .tag: looks.tagFill(for: scheme)
        }
    }

    @ViewBuilder private func leading(looks: ChipLooks, scale: CGFloat) -> some View {
        switch kind {
        case .type(let icon), .link(let icon):
            Image(typeGlyph: icon)
                .resizable()
                .scaledToFit()
                .foregroundStyle(TypeTone(icon: icon).ink(looks, for: scheme))
                .frame(width: looks.chipMarkSize * scale, height: looks.chipMarkSize * scale)
                .accessibilityHidden(true)
        case .status(let mark, _):
            StatusRing(mark: mark, scale: scale)
        case .option(let tone):
            Circle()
                .fill(tone.color(for: scheme))
                .frame(width: 7 * scale, height: 7 * scale)
                .accessibilityHidden(true)
        case .tag:
            Text(verbatim: "#")
                .foregroundStyle(.secondary)
                // The number sign sits closer to the word than the chip's other parts.
                .padding(.trailing, -2 * scale)
                .accessibilityHidden(true)
        case .plain:
            EmptyView()
        }
    }
}

/// A status's ring: its group's color, with half or all of it filled, or a slash across it.
private struct StatusRing: View {
    let mark: PageHeader.Mark
    let scale: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let side = 12 * scale
        let color = TypeTone(rawValue: mark.tone.rawValue).map { $0.color(for: scheme) } ?? Color.secondary
        ZStack {
            switch mark.fill {
            case .none: EmptyView()
            case .full: Circle().fill(color)
            case .half:
                Rectangle().fill(color)
                    .frame(width: side / 2, height: side)
                    .frame(width: side, height: side, alignment: .leading)
                    .clipShape(Circle())
            case .slash:
                Rectangle().fill(color)
                    .frame(width: side - 2 * scale, height: 1.5 * scale)
                    .rotationEffect(.degrees(-45))
            }
            Circle().strokeBorder(color, lineWidth: 1.5 * scale)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// A person: initials in a pale circle, then the name, with no chip round it.
struct PagePerson: View {
    let name: String
    let initials: String?

    @Environment(\.colorScheme) private var scheme
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize

    var body: some View {
        let looks = ChipLooks.current
        let scale = CGFloat(textSize) / 13
        HStack(spacing: looks.personGap * scale) {
            // A name with no letters has no circle, not an empty one.
            if let initials {
                Text(verbatim: initials)
                    .font(.system(size: looks.personInitialsSize * scale, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: looks.personCircle * scale, height: looks.personCircle * scale)
                    .background(looks.optionFill(for: scheme), in: Circle())
                    .overlay { Circle().strokeBorder(looks.edge(for: scheme), lineWidth: looks.statusEdgeWidth) }
                    .accessibilityHidden(true)
            }
            Text(verbatim: name)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: looks.textSize * scale))
        .foregroundStyle(textStyle(looks: looks))
        .padding(.trailing, 2 * scale)
        .frame(height: looks.height * scale)
    }
}
