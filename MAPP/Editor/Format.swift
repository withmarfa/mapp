import SwiftUI

/// A formatting command the Format menu offers and the page carries out, with the shortcut Notes gives it
/// where Notes has one.
nonisolated enum Format: CaseIterable, Hashable {
    case title, heading, subheading, body
    case bold, italic, strikethrough, code
    case codeBlock, quote, bulletList, orderedList, checklist
    case table, addRowAbove, addRowBelow, addColumnBefore, addColumnAfter, deleteRow, deleteColumn
    case alignLeft, alignCenter, alignRight

    var title: LocalizedStringResource {
        switch self {
        case .title: "Title"
        case .heading: "Heading"
        case .subheading: "Subheading"
        case .body: "Body"
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .code: "Code"
        case .codeBlock: "Code Block"
        case .quote: "Block Quote"
        case .bulletList: "Bulleted List"
        case .orderedList: "Numbered List"
        case .checklist: "Checklist"
        case .table: "Table"
        case .addRowAbove: "Add Row Above"
        case .addRowBelow: "Add Row Below"
        case .addColumnBefore: "Add Column Before"
        case .addColumnAfter: "Add Column After"
        case .deleteRow: "Delete Row"
        case .deleteColumn: "Delete Column"
        case .alignLeft: "Align Left"
        case .alignCenter: "Align Center"
        case .alignRight: "Align Right"
        }
    }

    /// The page's name for the command, and its argument.
    var command: (name: String, argument: String?) {
        switch self {
        case .title: ("heading", "1")
        case .heading: ("heading", "2")
        case .subheading: ("heading", "3")
        case .body: ("paragraph", nil)
        case .bold: ("bold", nil)
        case .italic: ("italic", nil)
        case .strikethrough: ("strikethrough", nil)
        case .code: ("code", nil)
        case .codeBlock: ("codeBlock", nil)
        case .quote: ("quote", nil)
        case .bulletList: ("bulletList", nil)
        case .orderedList: ("orderedList", nil)
        case .checklist: ("taskList", nil)
        case .table: ("table", nil)
        case .addRowAbove: ("addRowAbove", nil)
        case .addRowBelow: ("addRowBelow", nil)
        case .addColumnBefore: ("addColumnBefore", nil)
        case .addColumnAfter: ("addColumnAfter", nil)
        case .deleteRow: ("deleteRow", nil)
        case .deleteColumn: ("deleteColumn", nil)
        case .alignLeft: ("alignColumn", "left")
        case .alignCenter: ("alignColumn", "center")
        case .alignRight: ("alignColumn", "right")
        }
    }

    var shortcut: (key: Character, modifiers: EventModifiers)? {
        switch self {
        case .title: ("t", [.command, .shift])
        case .heading: ("h", [.command, .shift])
        case .subheading: ("j", [.command, .shift])
        case .body: ("b", [.command, .shift])
        case .bold: ("b", .command)
        case .italic: ("i", .command)
        case .strikethrough: ("x", [.command, .shift])
        case .codeBlock: ("m", [.command, .shift])
        case .quote: ("'", .command)
        case .bulletList: ("7", [.command, .shift])
        case .orderedList: ("9", [.command, .shift])
        case .checklist: ("l", [.command, .shift])
        case .table: ("t", [.command, .option])
        default: nil
        }
    }

    /// The shortcut in ProseMirror's key names, so the page answers it even before the menu sees the key.
    var pageKey: String? {
        guard let (key, modifiers) = shortcut else { return nil }
        var name = ""
        if modifiers.contains(.shift) { name += "Shift-" }
        if modifiers.contains(.option) { name += "Alt-" }
        if modifiers.contains(.command) { name += "Mod-" }
        return name + String(key)
    }

    /// Whether the command's style is what the caret sits in, for the menu's checkmark.
    func isActive(in caret: CaretState) -> Bool {
        switch self {
        case .title: caret.block == .heading(1)
        case .heading: caret.block == .heading(2)
        case .subheading: caret.block == .heading(3)
        case .body: caret.block == .paragraph
        case .bold: caret.marks.contains(.bold)
        case .italic: caret.marks.contains(.italic)
        case .strikethrough: caret.marks.contains(.strikethrough)
        case .code: caret.marks.contains(.code)
        case .codeBlock: caret.block == .codeBlock
        case .quote: caret.quoted
        case .bulletList: caret.block == .bulletList
        case .orderedList: caret.block == .orderedList
        case .checklist: caret.block == .taskList
        default: false
        }
    }
}
