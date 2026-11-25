import SwiftUI

/// The Editor page: how an item's page is laid out, its text, how it is edited, typed into and pasted into. The options
/// that are Inkkit's reach every page that is open at once (`EditorController.applyStyle`).
struct EditorPage: View {
    @AppStorage(PageKey.fullWidth) private var fullWidth = PageStyle().fullWidth
    @AppStorage(PageKey.readingWidth) private var readingWidth = PageStyle().readingWidth
    @AppStorage(PageKey.titleLines) private var titleLines = TitleLines.standard
    @AppStorage(PageKey.pinsProperties) private var pinsProperties = false
    @AppStorage(PageKey.textSize) private var textSize = PageStyle().textSize
    @AppStorage(LineSpacing.key) private var lineSpacing = PageStyle().lineSpacing
    @AppStorage(ParagraphSpacing.key) private var paragraphSpacing = PageStyle().paragraphSpacing
    @AppStorage(PageKey.linkLook) private var linkLook = PageStyle().linkLook
    @AppStorage(EditingMode.key) private var editingMode = PageStyle().editingMode
    @AppStorage(SourceViewMode.key) private var articlesOpenIn = SourceViewMode.standard
    @AppStorage(PageKey.checksSpelling) private var checksSpelling = PageStyle().checksSpelling
    @AppStorage(PageKey.smartPunctuation) private var smartPunctuation = PageStyle().smartPunctuation
    @AppStorage(PageKey.pairsBrackets) private var pairsBrackets = PageStyle().pairsBrackets
    @AppStorage(PageKey.continuesLists) private var continuesLists = PageStyle().continuesLists
    @AppStorage(IndentWith.key) private var indentWith = PageStyle().indentWith
    @AppStorage(PasteAs.key) private var pasteAs = PageStyle().pasteAs
    @AppStorage(PageKey.foldsHeadings) private var foldsHeadings = PageStyle().foldsHeadings
    @AppStorage(PageKey.showsCodeLineNumbers) private var showsCodeLineNumbers = PageStyle().showsCodeLineNumbers
    @AppStorage(PageKey.cornerShowsFormats) private var cornerShowsFormats = true
    @AppStorage(PageKey.cornerShowsTextSize) private var cornerShowsTextSize = true
    @AppStorage(PageKey.cornerShowsFocus) private var cornerShowsFocus = true

    var body: some View {
        SettingsPageColumn {
            text
            page
            corner
            editing
            typing
            pasting
            display
        }
        .accessibilityIdentifier("EditorPage")
    }

    private var text: some View {
        SettingsSection("Text") {
            SettingsRow("Text Size", line: "An item’s own text.") {
                SettingsPopUp(title: "Text Size", selection: $textSize) {
                    ForEach(PageStyle.textSizes, id: \.self) { Text("\($0) pt").tag($0) }
                }
                .accessibilityIdentifier("TextSize")
            }
            SettingsRow("Line Spacing") {
                SettingsPopUp(title: "Line Spacing", selection: $lineSpacing) {
                    ForEach(LineSpacing.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("LineSpacing")
            }
            SettingsRow("Paragraph Spacing") {
                SettingsPopUp(title: "Paragraph Spacing", selection: $paragraphSpacing) {
                    ForEach(ParagraphSpacing.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("ParagraphSpacing")
            }
            SettingsRow("Links to Items") {
                SettingsPopUp(title: "Links to Items", selection: $linkLook) {
                    ForEach(LinkLook.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("LinkLook")
            }
        }
    }

    private var page: some View {
        SettingsSection("Page") {
            SettingsRow("Page Width") {
                SettingsPopUp(title: "Page Width", selection: $fullWidth) {
                    Text("Standard").tag(false)
                    Text("Full Width").tag(true)
                }
                .accessibilityIdentifier("PageWidth")
            }
            SettingsRow("Standard Width", line: "How wide a line of text grows.", look: fullWidth ? .off : .normal) {
                let range = PageStyle.readingWidths
                SettingsSizeSlider(
                    title: "Standard Width",
                    value: Binding { Double(readingWidth) } set: { readingWidth = Int($0.rounded()) },
                    range: Double(range.lowerBound)...Double(range.upperBound)
                )
                .accessibilityLabel("Standard Width")
                .accessibilityIdentifier("ReadingWidth")
            }
            SettingsRow("Title Length", line: "Longer titles are cut short.") {
                SettingsPopUp(title: "Title Length", selection: Binding { TitleLines.resolved(titleLines) } set: { titleLines = $0 }) {
                    ForEach(TitleLines.choices, id: \.self) { Text("Up to \($0) Lines").tag($0) }
                }
                .accessibilityIdentifier("TitleLines")
            }
            SettingsRow("Pinned Properties", line: "Properties can be pinned under the title from a row’s menu.") {
                SettingsToggle(title: "Pinned Properties", isOn: $pinsProperties).accessibilityIdentifier("PinsProperties")
            }
        }
    }

    private var corner: some View {
        SettingsSection("Page Corner", footer: "A control turned off is in the page’s More menu, and the View menu keeps every command.") {
            SettingsRow("Formats", line: "Aa, which opens the formats bar.") {
                SettingsToggle(title: "Formats", isOn: $cornerShowsFormats).accessibilityIdentifier("CornerFormats")
            }
            SettingsRow("Text Size", line: "The page’s text size and width.") {
                SettingsToggle(title: "Text Size", isOn: $cornerShowsTextSize).accessibilityIdentifier("CornerTextSize")
            }
            SettingsRow("Focus", line: "Hides the title and properties.") {
                SettingsToggle(title: "Focus", isOn: $cornerShowsFocus).accessibilityIdentifier("CornerFocus")
            }
        }
    }

    private var editing: some View {
        SettingsSection("Editing") {
            SettingsRow("Edit Pages As", line: "A page can switch on its own.") {
                SettingsPopUp(title: "Edit Pages As", selection: $editingMode) {
                    Text("Formatted").tag(EditingMode.formatted)
                    Text("Markdown Source").tag(EditingMode.source)
                }
                .accessibilityIdentifier("EditingMode")
            }
            SettingsRow("Articles Open In", line: "View > Show Original switches it.") {
                SettingsPopUp(title: "Articles Open In", selection: $articlesOpenIn) {
                    Text("Reader").tag(SourceViewMode.reader)
                    Text("Original").tag(SourceViewMode.original)
                }
                .accessibilityIdentifier("ArticlesOpenIn")
            }
        }
    }

    private var typing: some View {
        SettingsSection("Typing") {
            SettingsRow("Check Spelling While Typing") {
                SettingsToggle(title: "Check Spelling While Typing", isOn: $checksSpelling).accessibilityIdentifier("CheckSpelling")
            }
            SettingsRow("Smart Quotes and Dashes", line: "In formatted text.") {
                SettingsToggle(title: "Smart Quotes and Dashes", isOn: $smartPunctuation).accessibilityIdentifier("SmartPunctuation")
            }
            SettingsRow("Pair Brackets and Quotes") {
                SettingsToggle(title: "Pair Brackets and Quotes", isOn: $pairsBrackets).accessibilityIdentifier("PairBrackets")
            }
            SettingsRow("Continue Lists on Return", line: "In Markdown Source too.") {
                SettingsToggle(title: "Continue Lists on Return", isOn: $continuesLists).accessibilityIdentifier("ContinueLists")
            }
            SettingsRow("Indent With", line: "In Markdown Source.") {
                SettingsPopUp(title: "Indent With", selection: $indentWith) {
                    ForEach(IndentWith.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("IndentWith")
            }
        }
    }

    private var pasting: some View {
        SettingsSection("Pasting") {
            SettingsRow("Paste Formatted Text As", line: "From a web page or another app.") {
                SettingsPopUp(title: "Paste Formatted Text As", selection: $pasteAs) {
                    Text("Markdown").tag(PasteAs.formatted)
                    Text("Plain Text").tag(PasteAs.plainText)
                }
                .accessibilityIdentifier("PasteAs")
            }
        }
    }

    private var display: some View {
        SettingsSection("Display") {
            SettingsRow("Fold Headings", line: "A triangle beside each heading hides what follows.") {
                SettingsToggle(title: "Fold Headings", isOn: $foldsHeadings).accessibilityIdentifier("FoldHeadings")
            }
            SettingsRow("Line Numbers in Code") {
                SettingsToggle(title: "Line Numbers in Code", isOn: $showsCodeLineNumbers).accessibilityIdentifier("CodeLineNumbers")
            }
        }
    }
}
