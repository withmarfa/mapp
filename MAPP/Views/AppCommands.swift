import SwiftUI

/// The menu bar. File makes and opens notes and acts on the selected ones; View chooses how the list shows and
/// orders items and moves back and forward through the items the window has shown.
struct AppCommands: Commands {
    /// Nil while no library is open: before a server is set, or while a server's copy opens.
    let library: (any ItemLibrary)?
    @FocusedValue(\.browser) private var browser
    @FocusedValue(\.focusedNotes) private var notes
    @FocusedValue(\.editor) private var editor
    @FocusedValue(\.detailsPresentation) private var details
    @Environment(\.openWindow) private var openWindow
    @StoredOrder private var order
    @AppStorage(QuickAdd.lastTypeKey) private var lastType = ""

    var body: some Commands {
        SidebarCommands()

        CommandGroup(replacing: .newItem) {
            Button("New Item", systemImage: "plus") {
                if let library { browser?.openQuickAdd(remembered: lastType, in: library) }
            }
                .keyboardShortcut("n")
                .disabled(browser == nil || library?.isLoaded != true)
            Button("New Window", systemImage: "macwindow.badge.plus") {
                openWindow(id: "main")
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
        }

        // The note commands sit with the File menu's making and opening, above Close, as Notes has them.
        CommandGroup(after: .newItem) {
            let ids: Set<ItemID> = notes?.ids ?? []
            // The note commands act on notes; a file selected has only its share and its window.
            let shown = ids.compactMap { library?.item($0) }.filter { !$0.isFile }
            let one = ids.count == 1 ? shown.first : nil
            Button("Open in New Window", systemImage: "macwindow") {
                for id in library?.idsForWindows(ids) ?? [] { openWindow(value: id) }
            }
            .keyboardShortcut("o")
            .disabled(browser == nil || ids.isEmpty)
            Divider()
            NoteShareLink(share: library.map { library in
                NoteShare(note: one, fileURL: ids.count == 1 ? ids.first.flatMap { browser?.fileURL(of: $0) } : nil, in: library)
            } ?? NoteShare())
            if let library {
                NoteActions(ids: ids, undoManager: notes?.undoManager, inMenuBar: true)
                    .environment(\.library, library)
            }
        }

        // Print has ⌘P, as everywhere; the print panel sets the paper.
        CommandGroup(replacing: .printItem) {
            Button("Export as PDF…", systemImage: "doc.richtext") { editor?.exportPDF() }
                .disabled(browser?.showsCollection == true || editor?.hasNote != true)
            Button("Print…", systemImage: "printer") { editor?.printNote() }
                .keyboardShortcut("p")
                .disabled(browser?.showsCollection == true || editor?.hasNote != true)
        }

        CommandGroup(after: .textEditing) {
            palette("Search Notes…", systemImage: "magnifyingglass", .search)
                .keyboardShortcut("p", modifiers: [.command, .shift])
            palette("Command Palette", systemImage: "command", .commands)
                .keyboardShortcut("k")
        }

        CommandGroup(before: .sidebar) {
            Button("Recently Deleted", systemImage: "trash") {
                if let library { browser?.show(.recentlyDeleted, in: library, order: order) }
            }
            .disabled(browser == nil || library == nil)
            Divider()
            Button(editor?.caret.sourceMode == true ? "Show Formatted Text" : "Show Markdown Source") {
                if let editor { editor.setSourceMode(!editor.caret.sourceMode) }
            }
            .disabled(editor?.hasNote != true)
            Divider()
            ItemViewOptions(browser: browser, modes: browser.flatMap { browser in library.map { browser.availableViewModes(in: $0) } } ?? ItemViewMode.allCases)
            Divider()
            Button(details?.isPresented == true ? "Hide Details" : "Show Details", systemImage: "sidebar.right") {
                details?.isPresented.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(details == nil || notes?.ids.count != 1)
            Divider()
            OrderOptions()
            Divider()
            PageWidthOptions()
            Divider()
            // ⌘[ and ⌘], as in Safari and the Finder.
            // The page uses the same keys to outdent and indent a list item and to move between table cells, so
            // while it has the keyboard the menu items give the keys up (the items still work from the menu).
            Button(String(localized: browser?.viewMode.backTitle ?? "Back"), systemImage: "chevron.backward") {
                if browser?.usesCollection == true { browser?.returnToCollection() }
                else if let browser, let library { browser.go(.back, in: library) }
            }
                .keyboardShortcut(pageKeepsHistoryKeys ? nil : KeyboardShortcut("[", modifiers: .command))
                .disabled(!canGoBack)
            Button("Forward", systemImage: "chevron.forward") {
                if let browser, let library { browser.go(.forward, in: library) }
            }
                .keyboardShortcut(pageKeepsHistoryKeys ? nil : KeyboardShortcut("]", modifiers: .command))
                .disabled(!canGoForward)
            Divider()
        }

        // There is no help book yet, and a Help item that only says so is not worth showing.
        CommandGroup(replacing: .help) {}
    }
}

extension AppCommands {
    private var pageKeepsHistoryKeys: Bool { editor?.isFocused == true }

    private var canGoBack: Bool {
        guard let browser else { return false }
        if browser.usesCollection { return browser.showsCollection == false }
        return library.map { browser.canGoBack(in: $0) } ?? false
    }

    private var canGoForward: Bool {
        guard let browser, !browser.usesCollection else { return false }
        return library.map { browser.canGoForward(in: $0) } ?? false
    }

    /// Opens a palette over the window in front, or puts it away if that palette is already out.
    private func palette(_ title: LocalizedStringKey, systemImage: String, _ palette: Browser.Palette) -> some View {
        Button(title, systemImage: systemImage) {
            browser?.palette = browser?.palette == palette ? nil : palette
        }
        .disabled(browser == nil)
    }
}

/// The list's own search, beside View Options, from ⌥⌘F under Find, as Notes has it.
struct SearchListButton: View {
    @FocusedValue(\.browser) private var browser

    var body: some View {
        Button("Search List", systemImage: "magnifyingglass") {
            browser?.focusRequest = .search
        }
        .disabled(browser?.canSearchList != true)
    }
}
