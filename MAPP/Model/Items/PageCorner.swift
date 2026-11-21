/// A button in the corner of an item's page, in the order the corner draws them: Focus is always the last.
nonisolated enum PageCornerButton: Hashable, Sendable {
    /// Aa, which opens the formats bar. Only on a page that can be written.
    case formats
    /// The text size of a page of text: its size with a menu of sizes and of the page's width.
    case textSize
    /// Reader or Original, one segmented control.
    case look
    /// A PDF's page as "2 of 4", with arrows.
    case pages
    /// An image's or a PDF's size, with its menu.
    case zoom
    case focus
}

/// Which buttons the corner of an item's page holds. Pure, so the rule is tested without a window.
nonisolated enum PageCorner {
    /// The buttons for a page of `layout`. `hasReader` is whether a web page has a Reader view to switch to; a page
    /// without one has no switch and no text of the app's to size. `canWrite` is whether the page can be written: Aa
    /// is only there then, since a page that cannot be written has no formats to apply. Every page of text has its
    /// size, written or not. `file` is the kind of file the page has ready to view: an image has its size, a PDF its
    /// page and its size, and a file that is still arriving, failed to load or is neither has neither. Every page has
    /// Focus.
    static func buttons(layout: ItemPageLayout, hasReader: Bool, canWrite: Bool = true, file: FileViewKind? = nil) -> [PageCornerButton] {
        switch layout {
        case .text: canWrite ? [.formats, .textSize, .focus] : [.textSize, .focus]
        case .webPage: hasReader ? [.look, .textSize, .focus] : [.focus]
        case .file:
            switch file {
            case .image: [.zoom, .focus]
            case .pdf: [.pages, .zoom, .focus]
            case nil: [.focus]
            }
        }
    }

    /// Whether the text size applies to what the page shows. A web page's size is only the Reader view's, since the
    /// original page is as it was written.
    static func sizesText(layout: ItemPageLayout, look: SourceViewMode?) -> Bool {
        if case .webPage = layout { return look == .reader }
        return true
    }
}
