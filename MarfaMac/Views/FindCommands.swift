import AppKit
import SwiftUI

/// Edit > Find, as TextEdit and Notes lay it out, acting on the item whose page the window shows through the
/// system find bar. Search List leads it with ⌥⌘F, as Search does in Notes, so Find and Replace has no
/// shortcut of its own.
struct FindCommands: Commands {
    let shortcuts: ShortcutBindings
    @FocusedValue(\.editor) private var editor
    @FocusedValue(\.browser) private var browser

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Menu("Find", systemImage: "magnifyingglass") {
                SearchListButton()
                    .shortcut(.searchList, shortcuts)
                Divider()
                item("Find…", systemImage: "magnifyingglass", .showFindInterface)
                    .shortcut(.find, shortcuts)
                item("Find and Replace…", systemImage: "arrow.left.arrow.right", .showReplaceInterface)
                    .disabled(editor?.isEditable != true)
                item("Find Next", systemImage: "chevron.down", .nextMatch)
                    .shortcut(.findNext, shortcuts)
                item("Find Previous", systemImage: "chevron.up", .previousMatch)
                    .shortcut(.findPrevious, shortcuts)
                item("Use Selection for Find", systemImage: "text.cursor", .setSearchString)
                    .shortcut(.useSelectionForFind, shortcuts)
            }
        }
    }

    private func item(_ title: LocalizedStringKey, systemImage: String, _ action: NSTextFinder.Action) -> some View {
        Button(title, systemImage: systemImage) { editor?.performFind(action) }
            .disabled(editor?.hasItem != true)
    }
}
