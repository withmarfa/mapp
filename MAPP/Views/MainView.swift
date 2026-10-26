import SwiftUI

struct MainView: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @Environment(\.undoManager) private var undoManager
    @State private var browser = Browser()
    @State private var editorSlot = EditorSlot()
    @State private var details = DetailsPresentation()
    @SceneStorage("detailsPresented") private var storedDetailsPresented = false
    @StoredOrder private var order
    @SceneStorage("browser") private var storedBrowser: Data?
    @FocusState private var pane: Browser.Pane?
    @State private var isSidebarVisible = true
    @State private var sidebarWidth: CGFloat = 230
    @State private var listWidth: CGFloat = 350
    @State private var measuredWidths = ColumnWidths()
    private let restoresWindow: Bool

    init(browser: Browser = Browser(), details: DetailsPresentation = DetailsPresentation(), restoresWindow: Bool = true) {
        _browser = State(initialValue: browser)
        _details = State(initialValue: details)
        self.restoresWindow = restoresWindow
    }

    /// The window's editor, holding the window's title drafts.
    private var editor: EditorController {
        editorSlot.editor {
            let editor = EditorController(library: library)
            editor.titleDrafts = details
            return editor
        }
    }

    var body: some View { lifecycleWindow }

    /// The gallery and the table have no list column, so they mount the two-column split view. Settings
    /// shows in the three-column one, in place of the list and the page, whatever the window is set to show.
    private var usesCollectionLayout: Bool { browser.usesCollection && !browser.showsSettings }

    private var workspacePresentation: WorkspacePresentation {
        if browser.showsSettings { return .settings }
        if browser.showsSidebarIndex { return .index }
        return usesCollectionLayout ? .collection : .list
    }

    private var activeWindow: some View {
        // Settings replaces both column toolbar providers even when the split keeps three columns.
        // Release the outgoing providers before mounting that workspace or changing the column count.
        // Browser, editor, drafts, and column preferences remain above this presentation identity.
        dialogsWindow.id(workspacePresentation)
        .onChange(of: workspacePresentation) {
            sidebarWidth = measuredWidths.sidebar
            listWidth = measuredWidths.list
            editor.flush()
        }
        .onChange(of: browser.showsCollection) {
            if browser.showsCollection { editor.releaseFocus(); editor.flush() }
        }
        .onChange(of: browser.showsSettings) {
            if browser.showsSettings {
                editor.flush()
                browser.palette = nil
                pane = nil
            }
        }
    }

    // Both native split shapes read the same sidebar preference before their first layout.
    private var listColumnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding { isSidebarVisible ? .all : .doubleColumn } set: { isSidebarVisible = $0 == .all }
    }

    private var galleryColumnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding { isSidebarVisible ? .all : .detailOnly } set: { isSidebarVisible = $0 == .all }
    }

    private var splitView: some View {
        // The gallery and the table replace this entire split view rather than changing the columns inside it.
        NavigationSplitView(columnVisibility: listColumnVisibility) {
            sidebarColumn
        } content: {
            Group {
                if browser.showsSettings {
                    SettingsPageList(browser: browser)
                } else {
                    NoteList(browser: browser, order: order, pane: $pane)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                if $0.isFinite, $0 >= 280, !browser.showsSettings { measuredWidths.list = $0 }
            }
            // The page list is about as wide as the sidebar; the list's own width is kept for the list.
            .navigationSplitViewColumnWidth(
                min: browser.showsSettings ? 200 : 280, ideal: browser.showsSettings ? 240 : listWidth,
                max: browser.showsSettings ? 340 : 480)
        } detail: {
            if browser.showsSettings {
                SettingsPageView(page: browser.settingsPage, browser: browser)
            } else {
                itemPage
                    .modifier(itemInspector)
                    .toolbar(id: "main") {
                        NoteToolbar(browser: browser, items: browser.selectedItems(in: library), editor: editor, details: details,
                            showsCreation: !isSidebarVisible)
                    }
            }
        }
    }

    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            Sidebar(browser: browser, order: order)
                // In SwiftUI's focus system, so the sidebar's own keys (Return, Delete) reach it.
                .focused($pane, equals: .sidebar)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
            if $0.isFinite, $0 >= 200 { measuredWidths.sidebar = $0 }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: sidebarWidth, max: 340)
        .toolbar {
            if isSidebarVisible {
                ToolbarItem(id: "sidebarNewItem") {
                    NewItemButton(browser: browser)
                }
            }
        }
    }

    private var itemPage: some View {
        NoteDetail(browser: browser, editor: editor, details: details)
    }

    private var workspace: some View {
        Group {
            if browser.showsSidebarIndex {
                NavigationSplitView(columnVisibility: galleryColumnVisibility) {
                    sidebarColumn
                } detail: {
                    SidebarIndex(browser: browser, order: order, showsCreation: !isSidebarVisible)
                }
            } else if usesCollectionLayout {
                NavigationSplitView(columnVisibility: galleryColumnVisibility) {
                    sidebarColumn
                } detail: {
                    Group {
                        if browser.showsCollection {
                            switch browser.viewMode {
                            case .table:
                                ItemTable(browser: browser, order: order, pane: $pane)
                            case .board:
                                ItemBoard(browser: browser, pane: $pane)
                            case .agenda:
                                ItemAgenda(browser: browser, pane: $pane)
                            case .list, .gallery:
                                ItemGallery(browser: browser, order: order, pane: $pane)
                            }
                        } else {
                            itemPage
                                .toolbar {
                                    ToolbarItem(placement: .navigation) {
                                        Button(String(localized: browser.viewMode.backTitle), systemImage: "chevron.backward") { browser.returnToCollection() }
                                            .accessibilityIdentifier("BackToGallery")
                                    }
                                }
                        }
                    }
                    .modifier(itemInspector)
                    .toolbar {
                        GalleryToolbar(
                            browser: browser, items: browser.selectedItems(in: library), editor: editor, details: details,
                            showsCreation: !isSidebarVisible
                        )
                    }
                }
            } else {
                splitView
            }
        }
    }

    private var itemInspector: ItemInspectorColumn {
        ItemInspectorColumn(browser: browser, details: details, editor: editor)
    }

    private var presentedWindow: some View {
        workspace
        .safeAreaBar(edge: .bottom, spacing: 0) {
            if !browser.showsSettings, browser.item == .recentlyDeleted {
                RecentlyDeletedActions(browser: browser)
            }
        }
        .focusedSceneValue(\.detailsPresentation, details)
        .onChange(of: details.isPresented) { if restoresWindow { storedDetailsPresented = details.isPresented } }
        .overlay(alignment: .top) {
            if let palette = browser.palette {
                FloatingPanel {
                    browser.palette = nil
                    browser.focusRequest = .list
                } content: {
                    CommandPalette(browser: browser, editor: editor, mode: palette)
                        // Each palette starts afresh, as ⌘K's Search Notes moves from one to the other.
                        .id(palette)
                }
            } else if browser.quickAdd.isPresented, browser.quickAdd.draft != nil {
                FloatingPanel {
                    browser.putAwayQuickAdd()
                    if browser.focusRequest == nil { browser.focusRequest = .list }
                } content: {
                    QuickAddPanel(browser: browser, quickAdd: browser.quickAdd, editor: editor)
                }
            }
        }
        .focusedSceneValue(\.browser, browser)
        .focusedSceneValue(\.editor, browser.showsCollection || browser.showsSidebarIndex ? nil : editor)
        .focusedSceneValue(\.focusedNotes, FocusedNotes(ids: browser.selection, undoManager: undoManager))
    }

    private var lifecycleWindow: some View {
        activeWindow
        // The gallery or table disappears while an item is open; selection must still follow deletes and moves.
        .onChange(of: galleryItemIDs) { old, new in
            guard browser.usesCollection else { return }
            browser.keepSelection(from: old, to: new)
        }
        .onChange(of: library.items(in: .allNotes).map(\.id)) { browser.placeRemoved(in: library, order: order) }
        // The page grants its own requests, since it may not exist until the request's selection shows.
        .onChange(of: browser.focusRequest, grantFocusRequest)
        .onChange(of: browser.snapshot()) { _, snapshot in
            if restoresWindow { storedBrowser = try? JSONEncoder().encode(snapshot) }
        }
        // The window has gone, by closing or changing library, once its titles were saved or the person chose to
        // go; its drafts take no part in what other windows do. The library is the one this view showed, so a
        // window whose libraries now read another has changed library rather than closed.
        .onDisappear { [library, libraries] in
            editorSlot.made?.flush()
            editorSlot.made?.windowWent()
            let changed = libraries.current.map { ObjectIdentifier($0) != ObjectIdentifier(library) } ?? true
            browser.quickAdd.handOff(to: library.notices, because: changed ? .libraryChanged : .closed)
        }
        .onAppear {
            if restoresWindow { details.isPresented = storedDetailsPresented }
            let editor = editor
            editor.onChange = { [library] id, markdown, read in library.updateBody(of: id, to: markdown, readAt: read) }
            editor.onEscape = { [browser] in browser.focusRequest = .list }
            editor.onOpenNote = { [browser, library, order] id in
                if let item = library.item(id) { browser.open(linked: item, in: library, order: order) }
            }
            editor.onShowRefusedTitle = { [browser, library, order] id in
                if let item = library.item(id) { browser.reveal(item, in: library, order: order) }
            }
        }
        // A window restores what it showed once the library has been read, since before then nothing is there. A
        // window carried to another library starts afresh with it.
        // A layout the place cannot show (Board with no choice fields) is not offered, and a window left on one
        // returns to the list. Changing `viewMode` only moves between layouts the workspace already handles.
        .onChange(of: browser.availableViewModes(in: library), initial: true) { browser.fallBackToListIfUnavailable(in: library) }
        .onChange(of: browser.viewMode) { browser.fallBackToListIfUnavailable(in: library) }
        .onChange(of: library.isLoaded, initial: true) {
            browser.adopt(library, undoManager: undoManager)
            guard library.isLoaded else { return }
            if restoresWindow { browser.restore(from: storedBrowser, in: library, order: order) }
            #if DEBUG
            if SampleLibrary.isRequested, SampleLibrary.withCollections {
                browser.sidebarItem = .itemType("core.task")
                browser.viewMode = .board
            }
            #endif
        }
        // A new item reaches a server's library when its source says so, which the window waits for to open it.
        .onChange(of: newItemIsSettled) {
            if newItemIsSettled { browser.finishNewItem(in: library) }
        }
        #if DEBUG
        // A sample launch can open an item without a click, as `-MAPPSelectItem <id>`, once the library holds it.
        .onChange(of: launchSelection.map { library.item($0) != nil }, initial: true) {
            if let id = launchSelection, library.item(id) != nil { browser.selection = [id] }
        }
        #endif
    }

    private var galleryItemIDs: [ItemID] {
        guard browser.usesCollection else { return [] }
        return browser.sections(in: library, order: order, now: library.now()).flatMap { $0.items.map(\.id) }
    }

    private var dialogsWindow: some View {
        presentedWindow
        .libraryDialogs()
    }

    private var newItemIsSettled: Bool { browser.isNewItemSettled(in: library) }

    #if DEBUG
    private var launchSelection: ItemID? {
        let arguments = ProcessInfo.processInfo.arguments
        guard SampleLibrary.isRequested, let flag = arguments.firstIndex(of: "-MAPPSelectItem"),
              arguments.indices.contains(flag + 1) else { return nil }
        return ItemID(arguments[flag + 1])
    }
    #endif

    /// The list's search comes out as a field, which takes the keyboard.
    private func grantFocusRequest() {
        switch browser.focusRequest {
        case .search:
            if browser.usesCollection { browser.isCollectionItemPresented = false }
            browser.isSearchExpanded = true
            browser.searchFocusRequests += 1
        case .sidebar, .list:
            editor.releaseFocus()
            // Asked for as the place changes, the list that takes the keyboard is not yet in the window.
            let request = browser.focusRequest
            Task { pane = request }
        case .page, .title:
            if browser.showsCollection { browser.isCollectionItemPresented = true }
            return
        case nil: return
        }
        browser.focusRequest = nil
    }
}

private enum WorkspacePresentation: Hashable {
    case list, collection, settings, index
}

// Measuring a drag must not invalidate the view and reapply its preferred column widths.
private final class ColumnWidths {
    var sidebar: CGFloat = 230
    var list: CGFloat = 350
}

/// Applied to a detail column, before its toolbar, never to the split view: an inspector on the split view makes every
/// resize of the window lay out every column again, which made live resizing several times slower, and one applied
/// after the column's toolbar raises an exception during layout when a new window opens.
private struct ItemInspectorColumn: ViewModifier {
    @CurrentLibrary private var library
    let browser: Browser
    let details: DetailsPresentation
    let editor: EditorController

    func body(content: Content) -> some View {
        content.inspector(isPresented: Binding { details.isPresented } set: { details.isPresented = $0 }) {
            ItemInspectorHost(browser: browser, details: details)
                .inspectorColumnWidth(min: 260, ideal: 310, max: 440)
                .toolbar {
                    InspectorToolbar(browser: browser, items: browser.selectedItems(in: library), editor: editor, details: details)
                }
        }
    }
}
