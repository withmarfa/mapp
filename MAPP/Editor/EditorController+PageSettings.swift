import AppKit
import WebKit

/// What the page is told when it loads: how it is set out, the accent, its own words and its keys.
extension EditorController {
    /// How the page is set out: its width, its text size and whether spelling is checked.
    func setStyle(_ style: PageStyle) {
        self.style = style
        if isReady { applyStyle() }
    }

    func applyStyle() {
        call("setFullWidth", String(style.fullWidth))
        call("setTextSize", String(style.textSize))
        call("setReadingWidth", String(style.readingWidth))
        call("setSpellcheck", String(style.checksSpelling))
    }

    // MARK: Matching the system

    @objc func systemColorsDidChange() {
        applyAccent()
    }

    /// The page's accent follows the system's, or the app's own when the system leaves it to apps.
    func applyAccent() {
        guard isReady else { return }
        var hex: String?
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            hex = NSColor.controlAccentColor.usingColorSpace(.sRGB).map {
                String(format: "#%02X%02X%02X", Int(($0.redComponent * 255).rounded()),
                       Int(($0.greenComponent * 255).rounded()), Int(($0.blueComponent * 255).rounded()))
            }
        }
        guard let hex else { return }
        webView.evaluateJavaScript("document.documentElement.style.setProperty('--inkkit-accent-color', \(json(hex)))")
    }

    /// The page's own words, from the String Catalog.
    static var editorLabels: [String: String] {
        [
            "plainTextEditor": String(localized: "Plain Text"),
            "placeholder": String(localized: "Start typing…"),
            "expandCallout": String(localized: "Expand"),
            "collapseCallout": String(localized: "Collapse"),
            "diagramRendering": String(localized: "Rendering diagram…"),
            "diagramUnavailable": String(localized: "Diagram unavailable:"),
            "footnote": String(localized: "Footnote"),
            "loadPicture": String(localized: "Load Picture"),
            "loadingPicture": String(localized: "Loading Picture…"),
            "picturesOff": String(localized: "Remote Pictures Are Off"),
            "loadOnePicture": String(localized: "Load 1 Picture"),
            // The page puts the count in place of the placeholder, so the word is sent as the catalog holds it.
            "loadPictures": String(localized: "Load %lld Pictures"),
            "fileLoading": String(localized: "Loading file…"),
            "fileError": String(localized: "File could not be loaded"),
            "filePreviewUnavailable": String(localized: "Preview unavailable"),
            "filePDFPreview": String(localized: "Open to view this PDF"),
            "wikiMissing": String(localized: "Link unavailable"),
            "formattedEditor": String(localized: "Note"),
            "sourceEditor": String(localized: "Markdown Source"),
            "copyCode": String(localized: "Copy"),
            "codeLanguage": String(localized: "Code Language"),
            "codeLanguageSearch": String(localized: "Search Languages"),
            "codeAuto": String(localized: "Automatic"),
            "codePlainText": String(localized: "Plain Text"),
            "tableAddRow": String(localized: "Add Row"),
            "tableAddColumn": String(localized: "Add Column"),
            "tableDeleteRow": String(localized: "Delete Row"),
            "tableDeleteColumn": String(localized: "Delete Column"),
            "tableAlignLeft": String(localized: "Align Left"),
            "tableAlignCenter": String(localized: "Align Center"),
            "tableAlignRight": String(localized: "Align Right"),
            "tableMoveRow": String(localized: "Row"),
            "tableMoveColumn": String(localized: "Column"),
            "fileOpen": String(localized: "Open"),
            "fileMissing": String(localized: "File Not Found"),
            "fileRetry": String(localized: "Try Again"),
            "comment": String(localized: "Author Comment"),
            "preservedMarkdown": String(localized: "Preserved Markdown"),
            "suggestions": String(localized: "Suggestions"),
            "suggestionsLoading": String(localized: "Loading…"),
            "suggestionsEmpty": String(localized: "No Results"),
            "slashHeading1": String(localized: "Heading 1"),
            "slashHeading2": String(localized: "Heading 2"),
            "slashHeading3": String(localized: "Heading 3"),
            "slashBulletList": String(localized: "Bulleted List"),
            "slashOrderedList": String(localized: "Numbered List"),
            "slashTaskList": String(localized: "Checklist"),
            "slashQuote": String(localized: "Quote"),
            "slashCodeBlock": String(localized: "Code Block"),
            "slashTable": String(localized: "Table"),
            "slashCallout": String(localized: "Callout"),
            "slashDivider": String(localized: "Divider"),
            "slashDiagram": String(localized: "Diagram"),
            "slashNote": String(localized: "Note"),
            "slashTip": String(localized: "Tip"),
            "slashImportant": String(localized: "Important"),
            "slashWarning": String(localized: "Warning"),
            "slashCaution": String(localized: "Caution"),
            "linkToNote": String(localized: "Link to Note"),
            "untitled": String(localized: "Untitled"),
            "title": String(localized: "Title"),
            "itemType": String(localized: "Item Type"),
            "status": String(localized: "Status"),
            "discardChanges": String(localized: "Discard Changes"),
            "propertyRejected": String(localized: "The value could not be saved. Please try again."),
            "parentRejected": String(localized: "The connection could not be removed."),
            "linkedFrom": String(localized: "Linked From"),
            "contents": String(localized: "Contents"),
            "showLess": String(localized: "Show Less"),
            "timeline": String(localized: "Timeline"),
            "properties": String(localized: "Properties"),
        ]
    }

    func applyKeymap() {
        var keymap: [String: [String]] = [:]
        for format in Format.allCases {
            guard let key = format.pageKey else { continue }
            let (name, argument) = format.command
            keymap[key] = [name] + (argument.map { [$0] } ?? [])
        }
        call("setKeymap", json(keymap))
    }
}
