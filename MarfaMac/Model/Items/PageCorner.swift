/// A button in the corner of an item's page, in the order the corner draws them: Open leads where the page has
/// somewhere outside the app to go, and Focus is always the last.
nonisolated enum PageCornerButton: Hashable, Sendable {
    /// Open, which takes the page to the app that shows it best: the browser, the app that opens a file, or Maps.
    case open
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

/// Which of the corner's controls a person keeps there: Aa, the text size and Focus, each on or off. A control turned
/// off is reached from the page's More menu instead, and its command stays in the View menu either way. The other
/// controls (Open, Reader or Original, a PDF's page, a file's size) belong to the page they are for and are never a choice.
nonisolated struct PageCornerChoice: Equatable, Sendable {
    var formats = true
    var textSize = true
    var focus = true

    static let all = PageCornerChoice()

    func shows(_ button: PageCornerButton) -> Bool {
        switch button {
        case .formats: formats
        case .textSize: textSize
        case .focus: focus
        case .open, .look, .pages, .zoom: true
        }
    }
}

/// What a page's corner is made from: the page, and what the page has to give it. Pure, so the rule is tested without a
/// window.
nonisolated struct PageCornerKind: Equatable, Sendable {
    var layout: ItemPageLayout
    /// Whether a web page has a Reader view to switch to; a page without one has no switch and no text of the app's to size.
    var hasReader = false
    /// Whether the page can be written: Aa is only there then, since a page that cannot be written has no formats.
    var canWrite = true
    /// Whether the item's type keeps text. A person or a place has none, so it has its size and Focus and no Aa.
    var keepsText = true
    /// The kind of file the page has ready to view: an image has its size, a PDF its page and its size, and a file still
    /// arriving, failed to load or neither has neither.
    var file: FileViewKind?
    /// How many pages a PDF has, once read. One page has nothing to page through.
    var pageCount: Int?
    /// Whether the page has somewhere outside the app to be opened (`PageOpenTarget`).
    var opens = false
}

/// Which buttons the corner of an item's page holds. Pure, so the rule is tested without a window.
nonisolated enum PageCorner {
    /// The buttons for `kind`, less those `shows` turns off. Every page has Focus, and it is the last.
    static func buttons(_ kind: PageCornerKind, shows: PageCornerChoice = .all) -> [PageCornerButton] {
        available(kind).filter(shows.shows)
    }

    /// The buttons `shows` turns off that the page would otherwise have, which its More menu offers in their place.
    static func inMore(_ kind: PageCornerKind, shows: PageCornerChoice) -> [PageCornerButton] {
        available(kind).filter { !shows.shows($0) }
    }

    private static func available(_ kind: PageCornerKind) -> [PageCornerButton] {
        let open: [PageCornerButton] = kind.opens ? [.open] : []
        switch kind.layout {
        case .text: return open + (kind.canWrite && kind.keepsText ? [.formats, .textSize, .focus] : [.textSize, .focus])
        case .webPage: return open + (kind.hasReader ? [.look, .textSize, .focus] : [.focus])
        case .file:
            switch kind.file {
            case .image: return open + [.zoom, .focus]
            case .pdf: return open + ((kind.pageCount ?? 2) > 1 ? [.pages, .zoom, .focus] : [.zoom, .focus])
            case nil: return open + [.focus]
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
