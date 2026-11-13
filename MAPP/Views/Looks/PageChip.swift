import MarfaIcons
import SwiftUI

/// One chip, for one kind of value, drawn in SwiftUI from the same looks as the note page's web header: the sizes
/// and fills of `ChipLooks.current` and the colors of `TypeTone`, scaled with the interface's text size (the design's
/// 13 points). It serves the page, the right sidebar and, at `.row` size, a list row. A chip is as tall as its size
/// says whatever it holds, so chips side by side line up.
struct PageChip: View {
    enum Kind {
        /// The type's name, tinted in its tone, with its icon in color.
        case type(icon: String?)
        /// An item a row links to: its mark in color and its title on a grey fill, since a tint means a type. The title
        /// is underlined under the pointer.
        case link(icon: String?)
        /// A status: its symbol in a chip with a fine edge, and a chevron where it opens a menu.
        case status(StatusSymbol, chevron: Bool)
        /// A choice or a word of a list: neutral, with a dot in its own color.
        case option(TypeTone)
        /// One of the item's tags, grey, after a number sign.
        case tag
        /// A word with no mark of its own, on the fill a choice has: a date or a number.
        case plain
    }

    /// The button a chip carries where the person can take its value away: a tag in the right sidebar.
    struct Removal {
        let help: LocalizedStringKey
        let label: LocalizedStringKey
        let identifier: String
        let action: () -> Void
    }

    let text: String
    let kind: Kind
    var size: ChipSize = .page
    var removal: Removal?

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
        // The chip's measures follow the interface's text size, and a row's chip is the page chip in proportion.
        let scale = CGFloat(textSize) / 13 * looks.unit(for: size)
        let shape = RoundedRectangle(cornerRadius: looks.cornerRadius * scale)
        HStack(spacing: isPlain ? 0 : looks.gap * scale) {
            leading(looks: looks, scale: scale)
            Text(verbatim: text)
                .underline(isLink && isHovering)
                .lineLimit(1)
                .truncationMode(.tail)
            if let removal {
                Button(action: removal.action) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9 * scale, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(removal.help)
                .accessibilityLabel(removal.label)
                .accessibilityIdentifier(removal.identifier)
            }
            if case .status(_, true) = kind {
                Image(systemName: "chevron.down")
                    .font(.system(size: looks.textSize(for: size) * CGFloat(textSize) / 13 * 0.6, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(looks.chevronOpacity)
                    .accessibilityHidden(true)
            }
        }
        .font(.system(size: looks.textSize(for: size) * CGFloat(textSize) / 13))
        .foregroundStyle(textStyle(looks: looks))
        .padding(.leading, start(looks: looks) * scale)
        .padding(.trailing, looks.padding * scale)
        .frame(height: looks.height(for: size) * CGFloat(textSize) / 13)
        .background(fill(looks: looks), in: shape)
        // Only a link underlines under the pointer, so only a link chip tracks it: a row of chips stays cheap.
        .background { if isLink { Color.clear.onHover { isHovering = $0 } } }
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
        case .status(let symbol, _):
            StatusMark(symbol, size: looks.statusSymbolSize * scale)
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

/// A person's initials in the pale circle, the one look a person has wherever the app shows one. A name with no
/// letters has no initials and so draws nothing.
struct PersonCircle: View {
    let initials: String?
    var size: ChipSize = .page
    /// On a row the selection colors with the accent, the initials are white on a paler circle.
    var onAccent = false

    @Environment(\.colorScheme) private var scheme
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize

    var body: some View {
        let looks = ChipLooks.current
        let scale = CGFloat(textSize) / 13
        // A name with no letters keeps its circle, so the person still reads as a person and rows stay aligned.
        Text(verbatim: initials ?? "")
            .font(.system(size: looks.personInitialsSize(for: size) * scale, weight: .medium))
            .foregroundStyle(onAccent ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: looks.personCircle(for: size) * scale, height: looks.personCircle(for: size) * scale)
            .background(onAccent ? Color.white.opacity(0.22) : looks.optionFill(for: scheme), in: Circle())
            .overlay { Circle().strokeBorder(onAccent ? Color.clear : looks.edge(for: scheme), lineWidth: looks.statusEdgeWidth) }
            .accessibilityHidden(true)
    }
}

/// A person: initials in the pale circle, then the name, with no chip round it. In a row, the initials alone, with the
/// name for VoiceOver.
struct PagePerson: View {
    let name: String
    let initials: String?
    var size: ChipSize = .page

    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize

    var body: some View {
        let looks = ChipLooks.current
        let scale = CGFloat(textSize) / 13
        HStack(spacing: looks.personGap * scale) {
            PersonCircle(initials: initials, size: size)
            if size == .page {
                Text(verbatim: name)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(.system(size: looks.textSize(for: size) * scale))
        .foregroundStyle(.primary)
        .padding(.trailing, size == .page ? 2 * scale : 0)
        .frame(height: looks.height(for: size) * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }
}
