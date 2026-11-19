import CoreGraphics

/// A button in the corner of an item's page, in the order the corner draws them: Focus is always the last.
nonisolated enum PageCornerButton: Hashable, Sendable {
    /// Aa, which opens the formats card.
    case formats
    /// Reader or Original, one segmented control.
    case look
    case focus
}

/// Which buttons the corner of an item's page holds. Pure, so the rule is tested without a window.
nonisolated enum PageCorner {
    /// The buttons for a page of `layout`. `hasReader` is whether a web page has a Reader view to switch to; a page
    /// without one has no switch. Aa is only where the page is the editor, since a page that is not text has no
    /// formats, and every page has Focus.
    static func buttons(layout: ItemPageLayout, hasReader: Bool) -> [PageCornerButton] {
        switch layout {
        case .text: [.formats, .focus]
        case .webPage: hasReader ? [.look, .focus] : [.focus]
        case .file: [.focus]
        }
    }

    /// The most room the formats card takes, and the least before it would be too narrow to use, in points.
    static let cardWidth: CGFloat = 340
    static let narrowestCard: CGFloat = 220

    /// The card's width for content `width` points wide, with the corner's inset on both sides kept clear.
    static func cardWidth(forContentWidth width: CGFloat, inset: CGFloat) -> CGFloat {
        min(cardWidth, max(narrowestCard, width - inset * 2))
    }
}
