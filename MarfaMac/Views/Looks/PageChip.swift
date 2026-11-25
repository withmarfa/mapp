import MarfaIcons
import SwiftUI

/// One chip, for one kind of value, drawn in SwiftUI from the same looks as the item page's web header: the sizes and
/// fills of `ChipLooks.current`, scaled with the interface's text size (the design's 13 points). A chip is a word from
/// a set: a status, an option or a tag. A type or a linked item is never a chip, it is a mark and a name (`MarkedName`),
/// and only the type being given to an item takes a tint (`TintedChip`). It serves the page, the right sidebar and, at
/// `.row` size, a list row. A chip is as tall as its size says whatever it holds, so chips side by side line up.
struct PageChip: View {
    enum Kind {
        /// A status: its group's symbol, and a chevron where it opens a menu.
        case status(StatusSymbol, chevron: Bool)
        /// A choice or a word of a list: a dot in its own color.
        case option(TypeTone)
        /// One of the item's tags, after a number sign.
        case tag
        /// A word with no mark of its own, on the same wash: a date or a number.
        case plain
    }

    let text: String
    let kind: Kind
    var size: ChipSize = .page

    @Environment(\.colorScheme) private var scheme
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize

    private var isPlain: Bool {
        if case .plain = kind { true } else { false }
    }

    var body: some View {
        let looks = ChipLooks.current
        // The chip's measures follow the interface's text size, and a row's chip is the page chip in proportion.
        let scale = CGFloat(textSize) / 13 * looks.unit(for: size)
        let shape = RoundedRectangle(cornerRadius: looks.cornerRadius * scale)
        HStack(spacing: isPlain ? 0 : looks.gap * scale) {
            leading(looks: looks, scale: scale)
            Text(verbatim: text)
                .lineLimit(1)
                .truncationMode(.tail)
            if case .status(_, true) = kind {
                Image(systemName: "chevron.down")
                    .font(.system(size: looks.textSize(for: size) * CGFloat(textSize) / 13 * 0.6, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(looks.chevronOpacity)
                    .accessibilityHidden(true)
            }
        }
        .font(looks.chipFont(for: size, textSize: CGFloat(textSize)))
        .foregroundStyle(looks.chipText(for: scheme))
        .padding(.leading, start(looks: looks) * scale)
        .padding(.trailing, looks.padding * scale)
        .frame(height: looks.height(for: size) * CGFloat(textSize) / 13)
        .background(looks.chipWash(for: scheme), in: shape)
    }

    private func start(looks: ChipLooks) -> CGFloat {
        switch kind {
        case .status: looks.statusPaddingStart
        case .tag: looks.tagPaddingStart
        case .option, .plain: looks.padding
        }
    }

    @ViewBuilder private func leading(looks: ChipLooks, scale: CGFloat) -> some View {
        switch kind {
        case .status(let symbol, _):
            StatusMark(symbol, scale: scale)
        case .option(let tone):
            Circle()
                .fill(tone.color(for: scheme))
                .frame(width: 7 * scale, height: 7 * scale)
                .accessibilityHidden(true)
        case .tag:
            Image(systemName: "number")
                .font(.system(size: looks.textSize(for: size) * CGFloat(textSize) / 13 * 0.85, weight: .medium))
                .foregroundStyle(.secondary)
                // The number sign sits closer to the word than the chip's other parts.
                .padding(.trailing, -2 * scale)
                .accessibilityHidden(true)
        case .plain:
            EmptyView()
        }
    }
}

/// A type or a linked item as a fact about an item: the type's mark in its tone, then its name, with no chip round it.
/// A linked item underlines its title under the pointer where `underlinesOnHover` says a click opens it.
struct MarkedName: View {
    let text: String
    let icon: String?
    var size: ChipSize = .page
    var underlinesOnHover = false

    @Environment(\.colorScheme) private var scheme
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize
    @State private var isHovering = false

    var body: some View {
        let looks = ChipLooks.current
        let scale = CGFloat(textSize) / 13
        HStack(spacing: looks.gap * scale) {
            TonedGlyph(id: icon, size: looks.chipMarkSize * scale)
            Text(verbatim: text)
                .underline(underlinesOnHover && isHovering)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(looks.factFont(for: size, textSize: CGFloat(textSize)))
        .foregroundStyle(size == .page ? Color.primary : looks.chipText(for: scheme))
        .frame(height: looks.height(for: size) * scale)
        .background { if underlinesOnHover { Color.clear.onHover { isHovering = $0 } } }
    }
}

/// The type being given to an item, the one chip that takes a tint: its mark and name on the type's own pale color, or
/// on the gray wash when Settings > Appearance says Gray (`TypeChipTint`). A chevron says it opens a menu.
struct TintedChip: View {
    let text: String
    let icon: String?
    var chevron = true
    /// The panel's scale, where the chip stands in one that scales itself (`ValueChipView`); otherwise the interface's.
    var scale: CGFloat?
    /// Set by a menu that holds the chip as its label, where the label does not see its menu's keyboard focus.
    var isFocused = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.isFocused) private var isInFocus
    @AppStorage(AppearanceKey.typeChipTint) private var tint = TypeChipTint.standard
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize

    var body: some View {
        let looks = ChipLooks.current
        let tone = TypeTone(icon: icon)
        let tinted = tint != .gray
        let scale = scale ?? CGFloat(textSize) / 13
        HStack(spacing: looks.gap * scale) {
            TonedGlyph(id: icon, size: looks.chipMarkSize * scale)
            Text(verbatim: text).lineLimit(1).truncationMode(.tail)
            if chevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8 * scale, weight: .semibold))
                    .opacity(looks.chevronOpacity)
                    .accessibilityHidden(true)
            }
        }
        .font(looks.chipFont(for: .page, textSize: scale * 13))
        .foregroundStyle(tinted ? tone.nameInk(looks, for: scheme) : looks.chipText(for: scheme))
        .padding(.leading, looks.typePaddingStart * scale)
        .padding(.trailing, looks.padding * scale)
        .frame(height: looks.height * scale)
        .background(
            tinted ? tone.fill(scheme == .dark ? looks.typeTintOpacityDark : looks.typeTintOpacity, for: scheme) : looks.chipWash(for: scheme),
            in: RoundedRectangle(cornerRadius: looks.cornerRadius * scale)
        )
        .overlay {
            if isFocused || isInFocus { AppButtonStyle.focusRing(AnyShape(.rect(cornerRadius: looks.cornerRadius * scale))) }
        }
    }
}

/// Whether the type being given to an item is tinted in its own color or gray, chosen in Settings > Appearance.
nonisolated enum TypeChipTint: String, Sendable {
    case tinted, gray

    static let key = "typeChipTint"
    static let standard = TypeChipTint.tinted
}

/// A person's initials in a pale purple circle with no edge, the one look a person has wherever the app shows one. A name with no
/// letters has no initials and so draws nothing.
struct PersonCircle: View {
    let initials: String?
    var size: ChipSize = .page

    @Environment(\.colorScheme) private var scheme
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize

    var body: some View {
        let looks = ChipLooks.current
        let scale = CGFloat(textSize) / 13
        // A name with no letters keeps its circle, so the person still reads as a person and rows stay aligned.
        Text(verbatim: initials ?? "")
            .font(.system(size: looks.personInitialsSize(for: size) * scale, weight: ChipLooks.weight(looks.initialsWeight)))
            .tracking(0.02 * looks.personInitialsSize(for: size) * scale)
            .foregroundStyle(looks.personInkColor(for: scheme))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: looks.personCircle(for: size) * scale, height: looks.personCircle(for: size) * scale)
            .background(looks.personFillColor(for: scheme), in: Circle())
            .accessibilityHidden(true)
    }
}

/// A person: initials in the pale circle, then the name, with no chip round it. In a row, the initials alone, with the
/// name for VoiceOver, unless the name is asked for (`showsName`).
struct PagePerson: View {
    let name: String
    let initials: String?
    var size: ChipSize = .page
    /// Whether the name is written beside the initials at row size, as a table cell does: a table is not a row, and a
    /// person there is read by name. The page's person always has it.
    var showsName = false

    @Environment(\.colorScheme) private var scheme
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize

    var body: some View {
        let looks = ChipLooks.current
        let scale = CGFloat(textSize) / 13
        let named = size == .page || showsName
        HStack(spacing: looks.personGap * scale) {
            PersonCircle(initials: initials, size: size)
            if named {
                Text(verbatim: name)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(looks.factFont(for: size, textSize: CGFloat(textSize)))
        .foregroundStyle(size == .page ? Color.primary : looks.chipText(for: scheme))
        .padding(.trailing, named ? 2 * scale : 0)
        .frame(height: looks.height(for: size) * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }
}
