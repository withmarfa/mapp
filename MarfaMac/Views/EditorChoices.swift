import Foundation

/// How tightly the lines of an item's text sit: Inkkit's `--inkkit-line-height`, a multiple of the text size.
nonisolated enum LineSpacing: String, CaseIterable, Identifiable, Sendable {
    case tight, standard, relaxed

    static let key = "lineSpacing"
    var id: Self { self }

    var title: String {
        switch self {
        case .tight: String(localized: "Tight")
        case .standard: String(localized: "Standard")
        case .relaxed: String(localized: "Relaxed")
        }
    }

    var multiple: Double {
        switch self {
        case .tight: 1.4
        case .standard: 1.55
        case .relaxed: 1.8
        }
    }
}

/// How far apart paragraphs sit: Inkkit's `--inkkit-paragraph-spacing`, a multiple of the text size.
nonisolated enum ParagraphSpacing: String, CaseIterable, Identifiable, Sendable {
    case tight, standard, relaxed

    static let key = "paragraphSpacing"
    var id: Self { self }

    var title: String {
        switch self {
        case .tight: String(localized: "Tight")
        case .standard: String(localized: "Standard")
        case .relaxed: String(localized: "Relaxed")
        }
    }

    var multiple: Double {
        switch self {
        case .tight: 0.333
        case .standard: 0.667
        case .relaxed: 1
        }
    }
}

/// What Tab inserts in Markdown source: a tab, or a number of spaces. Inkkit takes a kind and a width, which are always
/// sent together, since Tab indents in the source only once the kind is set.
nonisolated enum IndentWith: String, CaseIterable, Identifiable, Sendable {
    case tab, twoSpaces, fourSpaces, eightSpaces

    static let key = "indentWith"
    var id: Self { self }

    var usesTab: Bool { self == .tab }

    var title: String {
        switch self {
        case .tab: String(localized: "Tabs")
        case .twoSpaces: String(localized: "2 Spaces")
        case .fourSpaces: String(localized: "4 Spaces")
        case .eightSpaces: String(localized: "8 Spaces")
        }
    }

    /// The width of one indent made of spaces. A tab sends Inkkit's own default, which it ignores.
    var width: Int {
        switch self {
        case .tab, .fourSpaces: 4
        case .twoSpaces: 2
        case .eightSpaces: 8
        }
    }
}

/// How ⌘V reads what it pastes: with its formatting, or as the plain text, which keeps every character as it is.
nonisolated enum PasteAs: String, CaseIterable, Identifiable, Sendable {
    case formatted, plainText

    static let key = "pasteAs"
    var id: Self { self }
}

/// What an item's text opens as: formatted, or as Markdown source. A page can switch on its own from the Format menu.
nonisolated enum EditingMode: String, CaseIterable, Identifiable, Sendable {
    case formatted, source

    static let key = "editingMode"
    var id: Self { self }
}

/// The text input and display options Inkkit takes, as the page's one call carries them (`window.editor.setOptions`):
/// each of Inkkit's two calls replaces its whole set, so every option goes in this one value and none on a path of its own.
nonisolated struct EditorOptions: Encodable, Equatable, Sendable {
    struct TextInput: Encodable, Equatable, Sendable {
        var spellcheck: Bool
        var smartPunctuation: Bool
        var pairBrackets: Bool
        var continueLists: Bool
        /// `tab` or `spaces`.
        var indent: String
        var indentWidth: Int
        /// `formatted` or `plainText`.
        var paste: String
    }

    struct Display: Encodable, Equatable, Sendable {
        var foldHeadings: Bool
        var codeLineNumbers: Bool
    }

    var textInput: TextInput
    var display: Display

    init(_ style: PageStyle) {
        textInput = TextInput(
            spellcheck: style.checksSpelling, smartPunctuation: style.smartPunctuation, pairBrackets: style.pairsBrackets,
            continueLists: style.continuesLists, indent: style.indentWith.usesTab ? "tab" : "spaces",
            indentWidth: style.indentWith.width, paste: style.pasteAs.rawValue)
        display = Display(foldHeadings: style.foldsHeadings, codeLineNumbers: style.showsCodeLineNumbers)
    }
}
