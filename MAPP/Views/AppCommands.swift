import SwiftUI

/// The menu bar. File makes and opens notes and acts on the selected ones; View orders the list and moves back
/// and forward through the types Marfa Types has shown.
struct AppCommands: Commands {
    /// Nil until a folder of notes is chosen.
    let library: NoteLibrary?
    @FocusedValue(\.browser) private var browser
    @FocusedValue(\.focusedNotes) private var notes
    @FocusedValue(\.editor) private var editor
    @FocusedValue(\.marfaTypes) private var marfaTypes
    @Environment(\.openWindow) private var openWindow
    @StoredOrder private var order

    var body: some Commands {
        SidebarCommands()

        CommandGroup(replacing: .newItem) {
            Button("New Note", systemImage: "square.and.pencil") {
                if let library { browser?.newNote(in: library, undoManager: notes?.undoManager) }
            }
            .keyboardShortcut("n")
            .disabled(browser == nil || library?.isLoaded != true)
            Button("New Folder", systemImage: "folder.badge.plus") {
                if let library { browser?.newFolder(in: library, order: order, undoManager: notes?.undoManager) }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            // A folder made before the notes folder is read would be lost in the reading.
            .disabled(browser == nil || library?.isLoaded != true)
            Button("New Window", systemImage: "macwindow.badge.plus") {
                openWindow(id: "main")
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
        }

        // The note and folder commands sit with the File menu's making and opening, above Close, as Notes has them.
        CommandGroup(after: .newItem) {
            let ids = notes?.ids ?? []
            let shown = ids.compactMap { library?.note($0) }
            Button("Open in New Window", systemImage: "macwindow") {
                for path in library?.paths(forWindows: ids) ?? [] { openWindow(value: path) }
            }
            .keyboardShortcut("o")
            .disabled(browser == nil || shown.isEmpty)
            Divider()
            NoteShareLink(note: shown.count == 1 ? shown.first : nil)
            Button("Rename Note…", systemImage: "pencil") {
                browser?.renamingNote = shown.first?.id
            }
            .disabled(browser == nil || shown.count != 1 || shown.first?.isDeleted != false)
            if let library {
                NoteActions(ids: ids, undoManager: notes?.undoManager, inMenuBar: true)
                    .environment(library)
            }
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

        // ⌘P is Search Notes, so Print takes ⇧⌘P, which Page Setup would have had; the print panel sets the paper.
        CommandGroup(replacing: .printItem) {
            Button("Export as PDF…", systemImage: "doc.richtext") { editor?.exportPDF() }
                .disabled(editor?.hasNote != true)
            Button("Print…", systemImage: "printer") { editor?.printNote() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(editor?.hasNote != true)
        }

        CommandGroup(after: .textEditing) {
            SearchNotesButton()
                .keyboardShortcut("p")
            Button("Command Palette", systemImage: "command") {
                browser?.isShowingPalette.toggle()
            }
            .keyboardShortcut("k")
            .disabled(browser == nil)
        }

        CommandGroup(before: .sidebar) {
            OrderOptions()
            Divider()
            PageWidthOptions()
            Divider()
            // ⌘[ and ⌘], as in Safari and the Finder.
            Button("Back", systemImage: "chevron.backward") { marfaTypes?.goBack() }
                .keyboardShortcut("[")
                .disabled(marfaTypes?.canGoBack != true)
            Button("Forward", systemImage: "chevron.forward") { marfaTypes?.goForward() }
                .keyboardShortcut("]")
                .disabled(marfaTypes?.canGoForward != true)
            Divider()
        }

        // There is no help book yet, and a Help item that only says so is not worth showing.
        CommandGroup(replacing: .help) {}
    }
}

/// Search in the window in front: ⌘P from the Edit menu, and ⌥⌘F under Find, as Notes has it.
struct SearchNotesButton: View {
    @FocusedValue(\.browser) private var browser

    var body: some View {
        Button("Search Notes", systemImage: "magnifyingglass") {
            browser?.focusRequest = .search
        }
        .disabled(browser == nil)
    }
}
