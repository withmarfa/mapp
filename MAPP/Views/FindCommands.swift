import AppKit
import SwiftUI

/// Edit > Find, as TextEdit and Notes lay it out, acting on the note whose page the window shows through the
/// system find bar. Search Notes leads it with ⌥⌘F, as in Notes, so Find and Replace has no shortcut of its own.
struct FindCommands: Commands {
    @FocusedValue(\.editor) private var editor

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Menu("Find", systemImage: "magnifyingglass") {
                SearchNotesButton()
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Divider()
                item("Find…", systemImage: "magnifyingglass", .showFindInterface)
                    .keyboardShortcut("f")
                item("Find and Replace…", systemImage: "arrow.left.arrow.right", .showReplaceInterface)
                    .disabled(editor?.isEditable != true)
                item("Find Next", systemImage: "chevron.down", .nextMatch)
                    .keyboardShortcut("g")
                item("Find Previous", systemImage: "chevron.up", .previousMatch)
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                item("Use Selection for Find", systemImage: "text.cursor", .setSearchString)
                    .keyboardShortcut("e")
            }
        }
    }

    private func item(_ title: LocalizedStringKey, systemImage: String, _ action: NSTextFinder.Action) -> some View {
        Button(title, systemImage: systemImage) { editor?.performFind(action) }
            .disabled(editor?.hasNote != true)
    }
}
