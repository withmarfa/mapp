import SwiftUI

/// Where the page's settings are kept, shared by every view that reads or sets them.
enum PageKey {
    static let fullWidth = "fullWidthPages"
    static let textSize = "noteTextSize"
    static let checksSpelling = "checksSpelling"
}

/// How a note's page is set out. The defaults here are the only ones; stored settings fall back to them.
nonisolated struct PageStyle: Equatable {
    var fullWidth = false
    /// The body text's size in points; headings, spacing and the reading width scale with it.
    var textSize = 13
    var checksSpelling = true

    static let textSizes = [11, 12, 13, 14, 16, 18, 20, 24]
}

/// Reads the stored page settings, for the views that show a note.
@propertyWrapper
struct StoredPageStyle: DynamicProperty {
    @AppStorage(PageKey.fullWidth) private var fullWidth = PageStyle().fullWidth
    @AppStorage(PageKey.textSize) private var textSize = PageStyle().textSize
    @AppStorage(PageKey.checksSpelling) private var checksSpelling = PageStyle().checksSpelling

    init() {}

    var wrappedValue: PageStyle { PageStyle(fullWidth: fullWidth, textSize: textSize, checksSpelling: checksSpelling) }
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
        Toggle("Check Spelling While Typing", systemImage: "textformat.abc.dottedunderline", isOn: $checksSpelling)
    }
}
