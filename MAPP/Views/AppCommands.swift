import SwiftUI

/// The menu bar. File makes and opens items and acts on the selected ones; View chooses how the window shows its
/// items, holds the options of the view in front, and moves back and forward through the items the window has shown.
struct AppCommands: Commands {
    /// Nil while no library is open: before a server is set, or while a server's copy opens.
    let library: (any ItemLibrary)?
    let host: MarfaHost
    @FocusedValue(\.browser) private var browser
    @FocusedValue(\.focusedItems) private var focused
    @FocusedValue(\.editor) private var editor
    @FocusedValue(\.detailsPresentation) private var details
    @FocusedValue(\.indexActions) private var indexActions
    @Environment(\.openWindow) private var openWindow
    @StoredOrder private var order
    @AppStorage(QuickAdd.lastTypeKey) private var lastType = ""

    var body: some Commands {
        SidebarCommands()

        CommandGroup(after: .sidebar) {
            if browser?.customizesSidebar == true {
                Button("Finish Customizing Sidebar", systemImage: "checkmark") { browser?.customizesSidebar = false }
            } else {
                Button("Customize Sidebar…", systemImage: "sidebar.squares.leading") { browser?.customizesSidebar = true }
                    .disabled(browser == nil)
            }
        }

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
            Divider()
            // Pulls what the server has changed and sends what waits; the sidebar's instance menu and the palette have it too.
            Button("Refresh", systemImage: "arrow.clockwise") { host.refresh() }
                .keyboardShortcut("r")
                .disabled(!host.canRefresh)
        }

        // The item commands sit with the File menu's making and opening, above Close, as Notes has them.
        CommandGroup(after: .newItem) {
            let ids: Set<ItemID> = focused?.ids ?? []
            // Sharing an item reads one item; the commands below act on files too.
            let shown = ids.compactMap { library?.item($0) }.filter { !$0.isFile }
            let one = ids.count == 1 ? shown.first : nil
            command(.open)
            command(.openAsModal)
            command(.openAsFullPage)
            command(.openInNewWindow)
            command(.quickLook)
            command(.openOriginal)
            command(.openInBrowser)
            Divider()
            ItemShareLink(share: library.map { library in
                ItemShare(item: one, fileURL: ids.count == 1 ? ids.first.flatMap { browser?.fileURL(of: $0) } : nil, in: library)
            } ?? ItemShare())
            if let library {
                ItemActions(ids: ids, undoManager: focused?.undoManager, inMenuBar: true)
                    .environment(\.library, library)
                    .environment(details)
            }
            VersionHistoryCommands(details: details, library: library, undoManager: focused?.undoManager)
            // The row menu of the index in front: sources are renamed and marked, collections deleted.
            if browser?.showsSidebarIndex == true {
                Divider()
                if browser?.indexPlace == .sources {
                    Button("Rename Source…", systemImage: "pencil") { indexActions?.rename?() }
                        .disabled(indexActions?.rename == nil)
                    Button("Choose Source Mark…", systemImage: "face.smiling") { indexActions?.chooseMark?() }
                        .disabled(indexActions?.chooseMark == nil)
                } else {
                    Button("Delete Collection…", systemImage: "trash") { indexActions?.delete?() }
                        .disabled(indexActions?.delete == nil)
                }
            }
        }

        // Print has ⌘P, as everywhere; the print panel sets the paper.
        // Where Notes keeps Attach File, after the pasteboard's commands.
        CommandGroup(after: .pasteboard) {
            command(.addAttachment)
        }

        CommandGroup(replacing: .printItem) {
            command(.exportPDF)
            command(.print)
        }

        CommandGroup(after: .textEditing) {
            palette("Search Items…", systemImage: "magnifyingglass", .search)
                .keyboardShortcut("p", modifiers: [.command, .shift])
            palette("Command Palette", systemImage: "command", .commands, asksActionsWhenOut: true)
                .keyboardShortcut("k")
        }

        // The dividers here are drawn whether or not the views between them render anything, and the system adds its
        // own around the toolbar and tab groups, so the menu can open with two in a row. `MenuSeparatorTidy` hides
        // the surplus as the menu opens; write a divider wherever one belongs and leave that to it.
        CommandGroup(before: .sidebar) {
            command(.toggleSource)
            command(.toggleReader)
            command(.toggleFormats)
            command(.toggleFocus)
            Divider()
            if let place = browser?.indexPlace {
                IndexViewOptions(place: place, browser: browser)
            } else {
                ItemViewOptions(browser: browser, modes: browser.flatMap { browser in library.map { browser.availableViewModes(in: $0) } } ?? ItemViewMode.allCases, bindsKeys: true)
            }
            Divider()
            SavedViewMenu(browser: browser, library: library)
            // The toolbar's Done for a view's panel.
            Button("Finish Editing View", systemImage: "checkmark") {
                if let browser, let library { Task { await browser.finishViewPanel(in: library, order: order) } }
            }
            .disabled(browser?.showsViewPanel != true)
            Divider()
            Button(details?.isPresented == true ? "Hide Details" : "Show Details", systemImage: "sidebar.right") {
                details?.isPresented.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(details == nil || (browser?.showsSidebarIndex != true && focused?.ids.count != 1))
            Divider()
            // The toolbar's View Options and its filters, for the view in front.
            Group {
                if library != nil, let browser {
                    // A table, board or timeline with an item page open has no view options to offer.
                    if browser.offersViewOptions, !browser.showsSidebarIndex {
                        FilterCommands(browser: browser)
                        CurrentViewOptions(browser: browser, bindsKeys: true)
                    }
                } else {
                    CurrentViewOptions(browser: nil)
                }
            }
            .environment(\.library, library)
            Divider()
            PageWidthOptions()
            Divider()
            if let fileView {
                FileViewCommands(viewing: fileView)
            } else {
                TextZoomCommands(pageFocused: pageKeepsHistoryKeys)
            }
            Divider()
            // ⌘[ and ⌘], as in Safari and the Finder.
            // The page uses the same keys to outdent and indent a list item and to move between table cells, so
            // while it has the keyboard the menu items give the keys up (the items still work from the menu).
            Button(String(localized: browser?.viewMode.backTitle ?? "Back"), systemImage: "chevron.backward") {
                if browser?.isCollectionItemPresented == true { browser?.returnToCollection() }
                else if let browser, let library { browser.go(.back, in: library) }
            }
                .keyboardShortcut(pageKeepsHistoryKeys ? nil : KeyboardShortcut(KeyEquivalent(Character(HistoryKeys.back)), modifiers: .command))
                .disabled(!canGoBack)
            Button("Forward", systemImage: "chevron.forward") {
                if let browser, let library { browser.go(.forward, in: library) }
            }
                .keyboardShortcut(pageKeepsHistoryKeys ? nil : KeyboardShortcut(KeyEquivalent(Character(HistoryKeys.forward)), modifiers: .command))
                .disabled(!canGoForward)
            Divider()
            // The modal's own moves: through the items behind it, and out.
            Button("Previous Item", systemImage: "chevron.up") { step(.previous) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(!canStep(.previous))
            Button("Next Item", systemImage: "chevron.down") { step(.next) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(!canStep(.next))
            Button("Close Modal", systemImage: "xmark") { browser?.closeModal() }
                .disabled(browser?.isModalPresented != true)
            Divider()
        }
    }
}

extension AppCommands {
    /// A command of the page or the selection, which answers as the toolbar's More menu does.
    private func command(_ command: ItemCommand) -> some View {
        ItemCommandButton(
            command: command,
            context: ItemCommandContext(library: library, ids: focused?.ids ?? [], browser: browser, editor: editor, details: details),
            editor: editor, bindsShortcut: true)
    }

    /// The image or PDF the window's page shows and has ready, whose size and page the View menu then commands.
    private var fileView: FileViewing? {
        guard browser?.showsPage != false, let shown = focused?.ids, shown.count == 1 else { return nil }
        return details?.fileViewing(of: shown.first)
    }

    /// The page keeps Command-[ and Command-] while it has the keyboard (outdent and indent a list item, move between table cells), so Back and Forward give those keys up then.
    private var pageKeepsHistoryKeys: Bool { editor?.isFocused == true }

    /// Whether the modal has an item to go to, which it has only while it is open and not at an end of the list behind it.
    private func canStep(_ step: Browser.ModalStep) -> Bool {
        guard let browser, let library, browser.isModalPresented else { return false }
        let neighbors = browser.modalNeighbors(in: library, order: order)
        return (step == .previous ? neighbors.previous : neighbors.next) != nil
    }

    private func step(_ step: Browser.ModalStep) {
        guard let browser, let library else { return }
        browser.moveModal(step, in: library, order: order)
    }

    private var canGoBack: Bool {
        guard let browser else { return false }
        if browser.usesCollection || browser.isCollectionItemPresented { return browser.isCollectionItemPresented }
        return library.map { browser.canGoBack(in: $0) } ?? false
    }

    private var canGoForward: Bool {
        guard let browser, !browser.usesCollection, !browser.isCollectionItemPresented else { return false }
        return library.map { browser.canGoForward(in: $0) } ?? false
    }

    /// Opens a palette over the window in front, or puts it away if that palette is already out. ⌘K, with either palette
    /// out, opens Actions for the chosen row instead.
    private func palette(_ title: LocalizedStringKey, systemImage: String, _ palette: Browser.Palette, asksActionsWhenOut: Bool = false) -> some View {
        Button(title, systemImage: systemImage) {
            guard let browser else { return }
            if asksActionsWhenOut, browser.palette != nil {
                browser.paletteActionsRequests += 1
            } else {
                browser.palette = browser.palette == palette ? nil : palette
            }
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
