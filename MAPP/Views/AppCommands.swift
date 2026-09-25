import SwiftUI

/// The menu bar. File makes and opens notes and acts on the selected ones; View orders the list.
struct AppCommands: Commands {
    let library: NoteLibrary
    @FocusedValue(\.browser) private var browser
    @FocusedValue(\.focusedNotes) private var notes
    @Environment(\.openWindow) private var openWindow
    @StoredOrder private var order

    var body: some Commands {
        SidebarCommands()

        CommandGroup(replacing: .newItem) {
            Button("New Note", systemImage: "square.and.pencil") {
                browser?.newNote(in: library, undoManager: notes?.undoManager)
            }
            .keyboardShortcut("n")
            .disabled(browser == nil)
            Button("New Folder", systemImage: "folder.badge.plus") {
                browser?.newFolder(in: library, order: order, undoManager: notes?.undoManager)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(browser == nil)
            Button("New Window", systemImage: "macwindow.badge.plus") {
                openWindow(id: "main")
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
        }

        // The note and folder commands sit with the File menu's making and opening, above Close, as Notes has them.
        CommandGroup(after: .newItem) {
            let ids = notes?.ids ?? []
            let shown = ids.compactMap { library.note($0) }
            Button("Open in New Window", systemImage: "macwindow") {
                for id in ids { openWindow(value: id) }
            }
            .keyboardShortcut("o")
            .disabled(browser == nil || shown.isEmpty)
            Divider()
            NoteShareLink(note: shown.count == 1 ? shown.first : nil)
            NoteActions(ids: ids, undoManager: notes?.undoManager, inMenuBar: true)
                .environment(library)
            Divider()
            Button("Rename Folder", systemImage: "pencil") {
                browser?.renamingFolder = browser?.selectedFolder
            }
            .disabled(browser?.selectedFolder == nil)
            Button("Delete Folder…", systemImage: "folder.badge.minus") {
                browser?.folderToDelete = browser?.selectedFolder
            }
            .disabled(browser?.selectedFolder == nil)
        }

        CommandGroup(after: .textEditing) {
            Button("Search Notes", systemImage: "magnifyingglass") {
                browser?.focusRequest = .search
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
            .disabled(browser == nil)
        }

        CommandGroup(before: .sidebar) {
            OrderOptions()
            Divider()
        }

        // There is no help book yet, and a Help item that only says so is not worth showing.
        CommandGroup(replacing: .help) {}
    }
}
