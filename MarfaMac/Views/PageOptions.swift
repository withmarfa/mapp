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
    static let showsCoordinates = ShowsCoordinates.key
    static let pinsProperties = PinsProperties.key
    static let smartPunctuation = "smartPunctuation"
    static let pairsBrackets = "pairsBrackets"
    static let continuesLists = "continuesLists"
    static let foldsHeadings = "foldsHeadings"
    static let showsCodeLineNumbers = "showsCodeLineNumbers"
    /// Which of the corner's controls an item's page shows (`PageCornerChoice`).
    static let cornerShowsFormats = "cornerShowsFormats"
    static let cornerShowsTextSize = "cornerShowsTextSize"
    static let cornerShowsFocus = "cornerShowsFocus"
    static let all = [
        fullWidth, textSize, checksSpelling, readingWidth, titleLines, linkLook, showsCoordinates, pinsProperties, LineSpacing.key, ParagraphSpacing.key,
        IndentWith.key, PasteAs.key, EditingMode.key, smartPunctuation, pairsBrackets, continuesLists, foldsHeadings, showsCodeLineNumbers,
        cornerShowsFormats, cornerShowsTextSize, cornerShowsFocus,
    ]
}

/// Reads the Pinned Properties setting where the page's head is made, which is not a view.
nonisolated enum PinsProperties {
    /// Whether an item's page pins properties under its title, which its rows then leave out. Off by default.
    static let key = "pinsProperties"
    static func stored(in defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: key) }
}

/// Reads the Show Coordinates setting where the page's rows are made, which are not views.
nonisolated enum ShowsCoordinates {
    static let key = "showsCoordinates"
    static func stored(in defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: key) }
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
    /// The body text's size in points; headings, spacing and the reading width scale with it. The title is 28 on 34 at
    /// the default.
    var textSize = 15
    var checksSpelling = true
    var lineSpacing = LineSpacing.standard
    var paragraphSpacing = ParagraphSpacing.standard
    /// Curly quotes and dashes as the person types in formatted text. Off until the person turns it on.
    var smartPunctuation = false
    var pairsBrackets = false
    var continuesLists = true
    var indentWith = IndentWith.tab
    var pasteAs = PasteAs.formatted
    /// What an item's text opens as; the Format menu switches one page on its own.
    var editingMode = EditingMode.formatted
    var foldsHeadings = false
    var showsCodeLineNumbers = false
    /// How wide the text runs when not full width, in steps of `readingStep`. The default is the design's column of 680
    /// points at the default text size.
    var readingWidth = 45
    /// How a link to another item reads in the text.
    var linkLook = LinkLook.standard
    /// The page's accent, its highlight color and the families of its text and its code, as Settings > Appearance
    /// chooses. A family that is empty, or no longer installed, is the page's own.
    var accent = AccentChoice.standard
    var highlight = HighlightChoice.standard
    var textFont = ""
    var codeFont = ""

    /// One step of the reading width in ems of the item's text, so a width holds about as many words whatever the text
    /// size.
    static let readingStep = 680.0 / (45 * 15)

    /// The reading width in ems of the item's text, as the editor's page takes it.
    var readingEms: Double { Double(readingWidth) * Self.readingStep }

    /// Matches the editor's three-rem minimum margins and chosen reading width.
    func horizontalInset(for width: CGFloat) -> CGFloat {
        max(CGFloat(textSize * 3), fullWidth ? 0 : (width - CGFloat(readingEms) * CGFloat(textSize)) / 2)
    }

    static let textSizes = [13, 14, 15, 16, 18, 20, 24]

    /// The step nearest `size`, the smaller of two equally near. A size stored before these steps (11 or 12 points) is
    /// kept in the defaults as it is and read as this, wherever the page, its menus and Settings show or use it.
    static func nearestTextSize(_ size: Int) -> Int {
        textSizes.min { abs($0 - size) < abs($1 - size) } ?? size
    }
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
    @AppStorage(LineSpacing.key) private var lineSpacing = PageStyle().lineSpacing
    @AppStorage(ParagraphSpacing.key) private var paragraphSpacing = PageStyle().paragraphSpacing
    @AppStorage(PageKey.smartPunctuation) private var smartPunctuation = PageStyle().smartPunctuation
    @AppStorage(PageKey.pairsBrackets) private var pairsBrackets = PageStyle().pairsBrackets
    @AppStorage(PageKey.continuesLists) private var continuesLists = PageStyle().continuesLists
    @AppStorage(IndentWith.key) private var indentWith = PageStyle().indentWith
    @AppStorage(PasteAs.key) private var pasteAs = PageStyle().pasteAs
    @AppStorage(EditingMode.key) private var editingMode = PageStyle().editingMode
    @AppStorage(PageKey.foldsHeadings) private var foldsHeadings = PageStyle().foldsHeadings
    @AppStorage(PageKey.showsCodeLineNumbers) private var showsCodeLineNumbers = PageStyle().showsCodeLineNumbers
    @AppStorage(AppearanceKey.accent) private var accent = AccentChoice.standard
    @AppStorage(AppearanceKey.highlights) private var highlight = HighlightChoice.standard
    @AppStorage(AppearanceKey.textFont) private var textFont = ""
    @AppStorage(AppearanceKey.codeFont) private var codeFont = ""

    init() {}

    var wrappedValue: PageStyle {
        PageStyle(
            fullWidth: fullWidth, textSize: PageStyle.nearestTextSize(textSize), checksSpelling: checksSpelling, lineSpacing: lineSpacing,
            paragraphSpacing: paragraphSpacing, smartPunctuation: smartPunctuation, pairsBrackets: pairsBrackets,
            continuesLists: continuesLists, indentWith: indentWith, pasteAs: pasteAs, editingMode: editingMode,
            foldsHeadings: foldsHeadings, showsCodeLineNumbers: showsCodeLineNumbers, readingWidth: readingWidth, linkLook: linkLook,
            accent: accent, highlight: highlight, textFont: textFont, codeFont: codeFont)
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
