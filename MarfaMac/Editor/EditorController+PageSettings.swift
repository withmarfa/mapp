import AppKit
import WebKit

/// What the page is told when it loads: how it is set out, the accent, its own words and its keys.
extension EditorController {
    /// How the page is set out: its width, its text size, whether spelling is checked and how links look.
    func setStyle(_ style: PageStyle) {
        self.style = style
        if isReady { applyStyle() }
    }

    func applyStyle() {
        call("setFullWidth", String(style.fullWidth))
        call("setTextSize", String(style.textSize))
        call("setReadingWidth", String(style.readingEms))
        call("setOptions", json(EditorOptions(style)))
        call("setLineSpacing", String(style.lineSpacing.multiple))
        call("setParagraphSpacing", String(style.paragraphSpacing.multiple))
        call("setLinkStyle", json(style.linkLook.cssVariables()))
        applyAccent()
        applyFonts()
    }

    /// An item opened newly takes the mode Settings > Editor names, whatever the last item was switched to. A reload of the
    /// item already shown keeps the person's own switch.
    func applyEditingMode() {
        setSourceMode(style.editingMode == .source)
    }

    // MARK: Matching the system

    @objc func systemColorsDidChange() {
        applyAccent()
    }

    /// The page's accent is the one chosen in Settings, or the system's, or the app's own when the system leaves it to
    /// apps. It is sent again when the appearance changes, since a system color resolves differently in light and dark.
    func applyAccent() {
        guard isReady else { return }
        var hex: String?
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            hex = AccentChoice.hex(of: style.accent.nsColor ?? .controlAccentColor)
        }
        guard let hex else { return }
        setProperty("--inkkit-accent-color", hex)
        applyHighlight()
    }

    /// The color behind highlighted text, with the accent's own when the person chose that.
    private func applyHighlight() {
        var color: String?
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            color = style.highlight.css(accent: style.accent.nsColor ?? .controlAccentColor)
        }
        setProperty("--item-highlight", color)
    }

    /// The families of the item's text and its code. One no longer installed is left out, so the page keeps its own.
    func applyFonts() {
        let text = FontChoice.resolved(style.textFont, among: FontChoice.installedFamilies())
        let code = FontChoice.resolved(style.codeFont, among: FontChoice.installedMonospacedFamilies())
        setProperty("--inkkit-font-family", text.map { FontChoice.css(family: $0, generic: "-apple-system, system-ui, sans-serif") }, onBody: true)
        setProperty("--inkkit-monospace-font", code.map { FontChoice.css(family: $0, generic: "ui-monospace, monospace") }, onBody: true)
    }

    /// Sets a custom property on the page's root, or on its body where the page sets the same property there, and takes
    /// it off again for nil.
    private func setProperty(_ name: String, _ value: String?, onBody: Bool = false) {
        let target = onBody ? "document.body" : "document.documentElement"
        let script = value.map { "\(target).style.setProperty(\(json(name)), \(json($0)))" } ?? "\(target).style.removeProperty(\(json(name)))"
        webView.evaluateJavaScript(script)
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
            "loadAction": String(localized: "Load"),
            "loadingNamed": String(localized: "Loading %@…"),
            "picture": String(localized: "Picture"),
            "picturesOff": String(localized: "Remote Pictures Are Off"),
            "loadOnePicture": String(localized: "Load Picture"),
            "loadPictures": String(localized: "Load Pictures"),
            "closePictures": String(localized: "Close"),
            "pictureNotLoaded": String(localized: "1 picture from another website isn’t loaded."),
            // The page puts the count in place of the placeholder.
            "picturesNotLoaded": String(localized: "%lld pictures from other websites aren’t loaded."),
            "fileLoading": String(localized: "Loading file…"),
            "fileError": String(localized: "File could not be loaded"),
            "filePreviewUnavailable": String(localized: "Preview unavailable"),
            "filePDFPreview": String(localized: "Open to view this PDF"),
            "imageResize": String(localized: "Resize Image"),
            "taskCheckbox": String(localized: "Task"),
            "wikiMissing": String(localized: "Link unavailable"),
            // The hint under a link the pointer rests on, since a plain click places the caret.
            "linkOpenHint": String(localized: "⌘-click to open"),
            "formattedEditor": String(localized: "Text"),
            "sourceEditor": String(localized: "Markdown Source"),
            "copyCode": String(localized: "Copy"),
            "codeWrap": String(localized: "Wrap Code"),
            "foldHeading": String(localized: "Fold Section"),
            "unfoldHeading": String(localized: "Unfold Section"),
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
            // The page puts the file's name in place of the placeholder.
            "quickLookNamed": String(localized: "Quick Look %@"),
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
            "linkToItem": String(localized: "Link to Item"),
            "untitled": String(localized: "Untitled"),
            "title": String(localized: "Title"),
            "status": String(localized: "Status"),
            "empty": String(localized: "Empty"),
            "discardChanges": String(localized: "Discard Changes"),
            "showLess": String(localized: "Show Less"),
            "properties": String(localized: "Properties"),
            "reorder": String(localized: "Drag to Reorder"),
            "changeType": String(localized: "Change Type"),
        ]
    }

    /// The keys the person gave the Format commands, which the page answers as the menu does.
    func setFormatShortcuts(_ shortcuts: [Format: Shortcut?]) {
        formatShortcuts = shortcuts
        if isReady { applyKeymap() }
    }

    func applyKeymap() {
        // Open Link takes Command-Shift-O: Command-O is Open in New Window, which the page would otherwise answer first.
        // Inkkit reads a capital letter as Shift, so the Shift is named and the letter is lowercase.
        var keymap: [String: [String]] = ["Shift-Mod-o": ["openLink"]]
        for format in Format.allCases {
            guard let key = format.pageKey(for: formatShortcuts[format] ?? ShortcutCommand.format(format).defaultShortcut) else { continue }
            let (name, argument) = format.command
            keymap[key] = [name] + (argument.map { [$0] } ?? [])
        }
        call("setKeymap", json(keymap))
    }
}
