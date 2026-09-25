import SwiftUI

/// The Format menu: text styles, lists and tables, acting on the note whose page has the keyboard, with a
/// checkmark on the style the caret sits in.
struct FormatCommands: Commands {
    @FocusedValue(\.editor) private var editor

    var body: some Commands {
        CommandMenu("Format") {
            section([.title, .heading, .subheading, .body])
            Divider()
            section([.bold, .italic, .strikethrough, .code])
            Divider()
            section([.codeBlock, .quote, .bulletList, .orderedList, .checklist])
            Divider()
            Menu("Table") {
                item(.table, title: "Insert Table")
                Divider()
                section([.addRowAbove, .addRowBelow, .addColumnBefore, .addColumnAfter])
                Divider()
                section([.deleteRow, .deleteColumn])
                Divider()
                section([.alignLeft, .alignCenter, .alignRight])
            }
        }
    }

    private func section(_ formats: [Format]) -> some View {
        ForEach(formats, id: \.self) { format in
            item(format)
        }
    }

    @ViewBuilder
    private func item(_ format: Format, title: LocalizedStringResource? = nil) -> some View {
        let caret = editor?.caret ?? CaretState()
        let enabled = editor?.isFocused == true && (format.needsTable ? caret.inTable : format != .table || !caret.inTable)
        Toggle(isOn: Binding { format.isActive(in: caret) } set: { _ in editor?.format(format) }) {
            Text(title ?? format.title)
        }
        .keyboardShortcut(format.shortcut.map { KeyboardShortcut(KeyEquivalent($0.key), modifiers: $0.modifiers) })
        .disabled(!enabled)
    }
}

extension Format {
    /// The commands that work on a table the caret is in.
    var needsTable: Bool {
        switch self {
        case .addRowAbove, .addRowBelow, .addColumnBefore, .addColumnAfter, .deleteRow, .deleteColumn,
             .alignLeft, .alignCenter, .alignRight: true
        default: false
        }
    }
}
