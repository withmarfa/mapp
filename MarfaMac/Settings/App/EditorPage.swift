import SwiftUI

/// The Editor page: how an item's page is laid out, its text, how it is edited, typed into and pasted into. The options
/// that are Inkkit's reach every page that is open at once (`EditorController.applyStyle`).
struct EditorPage: View {
    @AppStorage(AppearanceKey.textFont) private var textFont = ""
    @AppStorage(AppearanceKey.codeFont) private var codeFont = ""
    @AppStorage(PDFBackground.key) private var pdfBackground = PDFBackground.gray
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

    @State private var families: [String] = []
    @State private var monospacedFamilies: [String] = []
    @State private var hasListedFonts = false

    var body: some View {
        SettingsPageColumn {
            text
            page
            pageControls
            editing
            typing
        }
        .accessibilityIdentifier("EditorPage")
        .task {
            guard !hasListedFonts else { return }
            families = FontChoice.installedFamilies()
            monospacedFamilies = FontChoice.installedMonospacedFamilies()
            hasListedFonts = true
        }
    }

    private var text: some View {
        SettingsSection("Text") {
            SettingsRow("Font") {
                fontPopUp("Font", selection: $textFont, defaultName: String(localized: "System"), installed: families)
                    .accessibilityIdentifier("TextFont")
            }
            SettingsRow("Code font") {
                fontPopUp("Code font", selection: $codeFont, defaultName: "SF Mono", installed: monospacedFamilies)
                    .accessibilityIdentifier("CodeFont")
            }
            SettingsRow("Text size") {
                SettingsPopUp(title: "Text size", selection: Binding(get: { PageStyle.nearestTextSize(textSize) }, set: { textSize = $0 })) {
                    ForEach(PageStyle.textSizes, id: \.self) { Text("\($0) pt").tag($0) }
                }
                .accessibilityIdentifier("TextSize")
            }
            SettingsRow("Line spacing") {
                SettingsPopUp(title: "Line spacing", selection: $lineSpacing) {
                    ForEach(LineSpacing.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("LineSpacing")
            }
            SettingsRow("Paragraph spacing") {
                SettingsPopUp(title: "Paragraph spacing", selection: $paragraphSpacing) {
                    ForEach(ParagraphSpacing.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("ParagraphSpacing")
            }
            SettingsRow("Links to items") {
                SettingsPopUp(title: "Links to items", selection: $linkLook) {
                    ForEach(LinkLook.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("LinkLook")
            }
        }
    }

    /// A pop-up of the installed families after the default. A family chosen once and not installed now is listed and said
    /// to be missing, while the page and the editor use the default.
    private func fontPopUp(_ title: LocalizedStringKey, selection: Binding<String>, defaultName: String, installed: [String]) -> some View {
        SettingsPopUp(title: title, selection: selection) {
            Text(verbatim: defaultName).tag("")
            Divider()
            ForEach(installed, id: \.self) { Text(verbatim: $0).tag($0) }
            if !selection.wrappedValue.isEmpty, !installed.contains(selection.wrappedValue) {
                Divider()
                // Until the installed fonts are listed, the chosen one cannot be said to be missing.
                Text(verbatim: hasListedFonts ? MissingChoice.label(selection.wrappedValue) : selection.wrappedValue)
                    .tag(selection.wrappedValue)
            }
        }
    }

    private var page: some View {
        SettingsSection("Page") {
            SettingsRow("Page width") {
                SettingsPopUp(title: "Page width", selection: $fullWidth) {
                    Text("Standard").tag(false)
                    Text("Full Width").tag(true)
                }
                .accessibilityIdentifier("PageWidth")
            }
            SettingsRow("Standard width", look: fullWidth ? .off : .normal) {
                let range = PageStyle.readingWidths
                SettingsSizeSlider(
                    title: "Standard width",
                    value: Binding { Double(readingWidth) } set: { readingWidth = Int($0.rounded()) },
                    range: Double(range.lowerBound)...Double(range.upperBound)
                )
                .accessibilityLabel("Standard width")
                .accessibilityIdentifier("ReadingWidth")
            }
            SettingsRow("Title length") {
                SettingsPopUp(title: "Title length", selection: Binding { TitleLines.resolved(titleLines) } set: { titleLines = $0 }) {
                    ForEach(TitleLines.choices, id: \.self) { Text("Up to \($0) Lines").tag($0) }
                }
                .accessibilityIdentifier("TitleLines")
            }
            SettingsRow("Fold headings with a triangle") {
                SettingsToggle(title: "Fold headings with a triangle", isOn: $foldsHeadings).accessibilityIdentifier("FoldHeadings")
            }
            SettingsRow("Line numbers in code") {
                SettingsToggle(title: "Line numbers in code", isOn: $showsCodeLineNumbers).accessibilityIdentifier("CodeLineNumbers")
            }
            SettingsRow("Pinned properties", line: "Properties can be pinned under the title from a row’s menu.") {
                SettingsToggle(title: "Pinned properties", isOn: $pinsProperties).accessibilityIdentifier("PinsProperties")
            }
            SettingsRow("PDF background") {
                SettingsPopUp(title: "PDF background", selection: Binding { pdfBackground } set: { $0.store() }) {
                    ForEach(PDFBackground.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("PDFBackground")
            }
        }
    }

    private var pageControls: some View {
        SettingsSection("Page Controls", footer: "A control turned off is in the page’s More menu.") {
            SettingsRow("Formats", line: "Aa, which opens the formats bar.") {
                SettingsToggle(title: "Formats", isOn: $cornerShowsFormats).accessibilityIdentifier("CornerFormats")
            }
            SettingsRow("Text size and width") {
                SettingsToggle(title: "Text size and width", isOn: $cornerShowsTextSize).accessibilityIdentifier("CornerTextSize")
            }
            SettingsRow("Focus", line: "Hides the title and properties.") {
                SettingsToggle(title: "Focus", isOn: $cornerShowsFocus).accessibilityIdentifier("CornerFocus")
            }
        }
    }

    private var editing: some View {
        SettingsSection("Editing", footer: "A page or an article can switch on its own from the View menu.") {
            SettingsRow("Edit pages as") {
                SettingsPopUp(title: "Edit pages as", selection: $editingMode) {
                    Text("Formatted").tag(EditingMode.formatted)
                    Text("Markdown Source").tag(EditingMode.source)
                }
                .accessibilityIdentifier("EditingMode")
            }
            SettingsRow("Articles open in") {
                SettingsPopUp(title: "Articles open in", selection: $articlesOpenIn) {
                    Text("Reader").tag(SourceViewMode.reader)
                    Text("Original").tag(SourceViewMode.original)
                }
                .accessibilityIdentifier("ArticlesOpenIn")
            }
            SettingsRow("Paste formatted text as") {
                SettingsPopUp(title: "Paste formatted text as", selection: $pasteAs) {
                    Text("Markdown").tag(PasteAs.formatted)
                    Text("Plain Text").tag(PasteAs.plainText)
                }
                .accessibilityIdentifier("PasteAs")
            }
        }
    }

    private var typing: some View {
        SettingsSection("Typing") {
            SettingsRow("Check spelling") {
                SettingsToggle(title: "Check spelling", isOn: $checksSpelling).accessibilityIdentifier("CheckSpelling")
            }
            SettingsRow("Smart quotes and dashes in formatted text") {
                SettingsToggle(title: "Smart quotes and dashes in formatted text", isOn: $smartPunctuation).accessibilityIdentifier("SmartPunctuation")
            }
            SettingsRow("Pair brackets and quotes") {
                SettingsToggle(title: "Pair brackets and quotes", isOn: $pairsBrackets).accessibilityIdentifier("PairBrackets")
            }
            SettingsRow("Continue lists on Return", line: "In Markdown Source too.") {
                SettingsToggle(title: "Continue lists on Return", isOn: $continuesLists).accessibilityIdentifier("ContinueLists")
            }
            SettingsRow("Indent Markdown Source with") {
                SettingsPopUp(title: "Indent Markdown Source with", selection: $indentWith) {
                    ForEach(IndentWith.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("IndentWith")
            }
        }
    }
}
