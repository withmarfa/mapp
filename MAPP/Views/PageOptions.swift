import SwiftUI

/// Where the page's settings are kept, shared by every view that reads or sets them.
enum PageKey {
    static let fullWidth = "fullWidthPages"
    static let textSize = "noteTextSize"
    static let checksSpelling = "checksSpelling"
    static let readingWidth = "readingWidth"
    static let titleLines = "titleLines"
    static let linkLook = LinkLook.key
    /// Whether a Location's latitude and longitude show as rows of their own. Off, they are drawn by the Location row alone.
    static let showsCoordinates = "showsCoordinates"
    static let all = [fullWidth, textSize, checksSpelling, readingWidth, titleLines, linkLook, showsCoordinates]
}

/// Reads the Show Coordinates setting where the page's rows are made, which are not views.
enum ShowsCoordinates {
    static func stored(in defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: PageKey.showsCoordinates) }
}

/// How many lines an item page's title shows before an ellipsis cuts it, while the title is not being edited.
enum TitleLines {
    static let choices = [2, 3, 4, 5]
    static let standard = 2

    /// A stored value as the number of lines shown: the standard where nothing usable is stored, and the nearest
    /// choice where the value lies outside them.
    static func resolved(_ stored: Int?) -> Int {
        guard let stored else { return standard }
        return min(choices.last!, max(choices.first!, stored))
    }

    static func stored(in defaults: UserDefaults = .standard) -> Int {
        resolved(defaults.object(forKey: PageKey.titleLines) as? Int)
    }
}

/// How an item's page is set out. The defaults here are the only ones; stored settings fall back to them.
nonisolated struct PageStyle: Equatable {
    var fullWidth = false
    /// The body text's size in points; headings, spacing and the reading width scale with it.
    var textSize = 13
    var checksSpelling = true
    /// How wide the text runs when not full width, in ems of the item's text, so it holds about as many words
    /// whatever the text size.
    var readingWidth = 54
    /// How a link to another item reads in the text.
    var linkLook = LinkLook.standard
    /// The page's accent, its highlight color and the families of its text and its code, as Settings > Appearance
    /// chooses. A family that is empty, or no longer installed, is the page's own.
    var accent = AccentChoice.standard
    var highlight = HighlightChoice.standard
    var textFont = ""
    var codeFont = ""

    /// Matches the editor's three-rem minimum margins and chosen reading width.
    func horizontalInset(for width: CGFloat) -> CGFloat {
        max(CGFloat(textSize * 3), fullWidth ? 0 : (width - CGFloat(readingWidth * textSize)) / 2)
    }

    static let textSizes = [11, 12, 13, 14, 16, 18, 20, 24]
    static let readingWidths = 36...80
}

/// Reads the stored page settings, for the views that show an item.
@propertyWrapper
struct StoredPageStyle: DynamicProperty {
    @AppStorage(PageKey.fullWidth) private var fullWidth = PageStyle().fullWidth
    @AppStorage(PageKey.textSize) private var textSize = PageStyle().textSize
    @AppStorage(PageKey.checksSpelling) private var checksSpelling = PageStyle().checksSpelling
    @AppStorage(PageKey.readingWidth) private var readingWidth = PageStyle().readingWidth
    @AppStorage(PageKey.linkLook) private var linkLook = PageStyle().linkLook
    @AppStorage(AppearanceKey.accent) private var accent = AccentChoice.standard
    @AppStorage(AppearanceKey.highlights) private var highlight = HighlightChoice.standard
    @AppStorage(AppearanceKey.textFont) private var textFont = ""
    @AppStorage(AppearanceKey.codeFont) private var codeFont = ""

    init() {}

    var wrappedValue: PageStyle {
        PageStyle(
            fullWidth: fullWidth, textSize: textSize, checksSpelling: checksSpelling, readingWidth: readingWidth,
            linkLook: linkLook, accent: accent, highlight: highlight, textFont: textFont, codeFont: codeFont)
    }
}

/// How wide an item's text runs: a comfortable measure for reading, or the window's whole width. Offered alike
/// by the View menu and Settings.
struct PageWidthOptions: View {
    @AppStorage(PageKey.fullWidth) private var fullWidth = PageStyle().fullWidth

    var body: some View {
        Picker("Page Width", systemImage: "arrow.left.and.right", selection: $fullWidth) {
            Text("Standard").tag(false)
            Text("Full Width").tag(true)
        }
        .accessibilityLabel("Page Width")
        .accessibilityIdentifier("PageWidth")
    }
}
