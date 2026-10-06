import SwiftUI

/// The menu bar. File makes and opens notes and acts on the selected ones; View orders the list and moves back
/// and forward through the types Marfa Types has shown.
struct AppCommands: Commands {
    /// Nil while no library is open: before a folder is chosen, or while a server's copy opens.
    let library: (any ItemLibrary)?
    @FocusedValue(\.browser) private var browser
    @FocusedValue(\.focusedNotes) private var notes
    @FocusedValue(\.editor) private var editor
    @FocusedValue(\.detailsPresentation) private var details
    @Environment(\.openWindow) private var openWindow
    @StoredOrder private var order

    var body: some Commands {
        SidebarCommands()

        CommandGroup(replacing: .newItem) {
            Button("New Item", systemImage: "plus") { browser?.startItemDraft() }
                .keyboardShortcut("n")
                .disabled(browser == nil || library?.isLoaded != true)
            Button("Import Files…") { browser?.isImportingFiles = true }
                .disabled(browser == nil || library?.isLoaded != true || library?.capabilities.contains(.importFiles) != true)
            Button("New Folder", systemImage: "folder.badge.plus") {
                if let library { browser?.newFolder(in: library, order: order, undoManager: notes?.undoManager) }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            // A folder made before the notes folder is read would be lost in the reading.
            .disabled(browser == nil || library?.isLoaded != true || !editsFolders)
            Button("New Window", systemImage: "macwindow.badge.plus") {
                openWindow(id: "main")
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
        }

        // The note and folder commands sit with the File menu's making and opening, above Close, as Notes has them.
        CommandGroup(after: .newItem) {
            let ids: Set<ItemID> = browser?.isCreatingItem == true ? [] : (notes?.ids ?? [])
            // The note commands act on notes; a file selected has only its share and its window.
            let shown = ids.compactMap { library?.item($0) }.filter { !$0.isFile }
            let one = ids.count == 1 ? shown.first : nil
            Button("Open in New Window", systemImage: "macwindow") {
                for id in library?.idsForWindows(ids) ?? [] { openWindow(value: id) }
            }
            .keyboardShortcut("o")
            .disabled(browser == nil || ids.isEmpty)
            Divider()
            NoteShareLink(
                title: one?.title ?? "", text: one.flatMap { library?.body(of: $0.id)?.text },
                fileURL: ids.count == 1 ? ids.first.flatMap { id in library.flatMap { browser?.fileURL(of: id, in: $0) ?? $0.fileURL(for: id) } } : nil)
            Button("Rename Note…", systemImage: "pencil") {
                browser?.renamingNote = ids.count == 1 ? shown.first?.id : nil
            }
            .disabled(browser == nil || ids.count != 1 || shown.count != 1 || library?.canRenameFile(of: shown.first) != true)
            if let library {
                NoteActions(ids: ids, undoManager: notes?.undoManager, inMenuBar: true)
                    .environment(\.library, library)
            }
            Divider()
            Button("Rename Folder", systemImage: "pencil") {
                browser?.renamingFolder = browser?.selectedFolder
            }
            .disabled(browser?.selectedFolder == nil || !editsFolders)
            Button("Delete Folder…", systemImage: "folder.badge.minus") {
                browser?.folderToDelete = browser?.selectedFolder
            }
            .disabled(browser?.selectedFolder == nil || !editsFolders)
        }

        // ⌘P is Search Notes, so Print takes ⇧⌘P, which Page Setup would have had; the print panel sets the paper.
        CommandGroup(replacing: .printItem) {
            Button("Export as PDF…", systemImage: "doc.richtext") { editor?.exportPDF() }
                .disabled(browser?.isCreatingItem == true || editor?.hasNote != true)
            Button("Print…", systemImage: "printer") { editor?.printNote() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(browser?.isCreatingItem == true || editor?.hasNote != true)
        }

        CommandGroup(after: .textEditing) {
            palette("Search Notes…", systemImage: "magnifyingglass", .search)
                .keyboardShortcut("p")
            palette("Command Palette", systemImage: "command", .commands)
                .keyboardShortcut("k")
        }

        CommandGroup(before: .sidebar) {
            Button(details?.isPresented == true ? "Hide Details" : "Show Details", systemImage: "info.circle") {
                details?.isPresented.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(browser?.isCreatingItem == true || details == nil || notes?.ids.count != 1 || browser?.showsTypes == true)
            Divider()
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

extension AppCommands {
    private var editsFolders: Bool { library?.capabilities.contains(.folders) == true }

    /// Marfa Types, while the window in front shows it, for Back and Forward.
    private var marfaTypes: TypesBrowser? { browser?.showsTypes == true ? browser?.types : nil }

    /// Opens a palette over the window in front, or puts it away if that palette is already out.
    private func palette(_ title: LocalizedStringKey, systemImage: String, _ palette: Browser.Palette) -> some View {
        Button(title, systemImage: systemImage) {
            browser?.palette = browser?.palette == palette ? nil : palette
        }
        .disabled(browser == nil)
    }
}

/// The list's own search, beside Sort, from ⌥⌘F under Find, as Notes has it.
struct SearchListButton: View {
    @FocusedValue(\.browser) private var browser

    var body: some View {
        Button("Search List", systemImage: "magnifyingglass") {
            browser?.focusRequest = .search
        }
        .disabled(browser == nil)
    }
}
