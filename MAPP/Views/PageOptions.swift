import SwiftUI

/// Where the page's settings are kept, shared by every view that reads or sets them.
enum PageKey {
    static let fullWidth = "fullWidthPages"
    static let textSize = "noteTextSize"
    static let checksSpelling = "checksSpelling"
    static let readingWidth = "readingWidth"
    static let all = [fullWidth, textSize, checksSpelling, readingWidth]
}

/// How a note's page is set out. The defaults here are the only ones; stored settings fall back to them.
nonisolated struct PageStyle: Equatable {
    var fullWidth = false
    /// The body text's size in points; headings, spacing and the reading width scale with it.
    var textSize = 13
    var checksSpelling = true
    /// How wide the text runs when not full width, in ems of the note's text, so it holds about as many words
    /// whatever the text size.
    var readingWidth = 54

    /// Matches the editor's three-rem minimum margins and chosen reading width.
    func horizontalInset(for width: CGFloat) -> CGFloat {
        max(CGFloat(textSize * 3), fullWidth ? 0 : (width - CGFloat(readingWidth * textSize)) / 2)
    }

    static let textSizes = [11, 12, 13, 14, 16, 18, 20, 24]
    static let readingWidths = 36...80
}

/// Reads the stored page settings, for the views that show a note.
@propertyWrapper
struct StoredPageStyle: DynamicProperty {
    @AppStorage(PageKey.fullWidth) private var fullWidth = PageStyle().fullWidth
    @AppStorage(PageKey.textSize) private var textSize = PageStyle().textSize
    @AppStorage(PageKey.checksSpelling) private var checksSpelling = PageStyle().checksSpelling
    @AppStorage(PageKey.readingWidth) private var readingWidth = PageStyle().readingWidth

    init() {}

    var wrappedValue: PageStyle {
        PageStyle(fullWidth: fullWidth, textSize: textSize, checksSpelling: checksSpelling, readingWidth: readingWidth)
    }
}

/// How wide a note's text runs: a comfortable measure for reading, or the window's whole width. Offered alike
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

/// How wide Standard pages run, set in Settings; Full Width leaves it aside.
struct ReadingWidthOptions: View {
    @AppStorage(PageKey.fullWidth) private var fullWidth = PageStyle().fullWidth
    @AppStorage(PageKey.readingWidth) private var readingWidth = PageStyle().readingWidth

    var body: some View {
        let range = PageStyle.readingWidths
        Slider(
            value: Binding { Double(readingWidth) } set: { readingWidth = Int($0.rounded()) },
            in: Double(range.lowerBound)...Double(range.upperBound),
            step: 2
        ) {
            Text("Standard Width")
        } minimumValueLabel: {
            Text("Narrow")
        } maximumValueLabel: {
            Text("Wide")
        }
        .accessibilityLabel("Standard Width")
        .accessibilityIdentifier("ReadingWidth")
        .disabled(fullWidth)
    }
}

/// The size of a note's text, and whether its spelling is checked as it is typed.
struct TextOptions: View {
    @AppStorage(PageKey.textSize) private var textSize = PageStyle().textSize
    @AppStorage(PageKey.checksSpelling) private var checksSpelling = PageStyle().checksSpelling

    var body: some View {
        Picker("Text Size", systemImage: "textformat.size", selection: $textSize) {
            ForEach(PageStyle.textSizes, id: \.self) { size in
                Text("\(size) pt").tag(size)
            }
        }
        .accessibilityLabel("Text Size")
        .accessibilityIdentifier("TextSize")
        Toggle("Check Spelling While Typing", systemImage: "textformat.abc.dottedunderline", isOn: $checksSpelling)
            .accessibilityLabel("Check Spelling While Typing")
            .accessibilityIdentifier("CheckSpelling")
    }
}
