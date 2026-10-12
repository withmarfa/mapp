import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @State private var browser = Browser()
    @State private var editor: EditorController
    @State private var details = DetailsPresentation()
    @SceneStorage("detailsPresented") private var storedDetailsPresented = false
    @StoredOrder private var order
    @SceneStorage("browser") private var storedBrowser: Data?
    @FocusState private var pane: Browser.Pane?
    @State private var isSidebarVisible = true
    @State private var sidebarWidth: CGFloat = 220
    @State private var listWidth: CGFloat = 340
    @State private var measuredWidths = ColumnWidths()
    @State private var typesListWidth: CGFloat = 340
    @State private var noteName = ""
    @State private var takenNoteName: String?
    @State private var importRequestID: UUID?
    private let settings: SettingsPresentation
    private let restoresWindow: Bool

    /// The library is given here as well as in the environment, since the editor is made with it.
    init(library: any ItemLibrary, browser: Browser = Browser(), details: DetailsPresentation = DetailsPresentation(), settings: SettingsPresentation = SettingsPresentation(), restoresWindow: Bool = true) {
        _editor = State(initialValue: EditorController(library: library))
        _browser = State(initialValue: browser)
        _details = State(initialValue: details)
        self.settings = settings
        self.restoresWindow = restoresWindow
    }

    var body: some View { lifecycleWindow }

    private var activeWindow: some View {
        Group {
            if settings.isPresented {
                SettingsView(presentation: settings)
            } else {
                // Release the split view's toolbar provider before changing its native column count.
                // Browser, editor, drafts, and column preferences remain above this presentation identity.
                renamingWindow.id(browser.usesGallery)
            }
        }
        .onChange(of: browser.usesGallery) {
            sidebarWidth = measuredWidths.sidebar
            listWidth = measuredWidths.list
            editor.flush()
        }
        .onChange(of: browser.showsGallery) {
            if browser.showsGallery { editor.releaseFocus(); editor.flush() }
        }
        .onChange(of: settings.isPresented) {
            if settings.isPresented {
                // Changing the ideal during a resize feeds transient layout sizes back into the split view.
                sidebarWidth = measuredWidths.sidebar
                listWidth = measuredWidths.list
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
        // The list workspace keeps three columns even when Marfa Types replaces its content.
        // Gallery replaces this entire split view rather than changing the columns inside it.
        NavigationSplitView(columnVisibility: listColumnVisibility) {
            sidebarColumn
        } content: {
            Group {
                if browser.showsTypes {
                    TypesListView(browser: browser.types, pane: $pane)
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { typesListWidth = $0 }
                        .navigationTitle(library.name(of: .marfaTypes))
                        .toolbar(removing: browser.isSearchExpanded ? .title : nil)
                        .toolbar {
                            ColumnSearch(
                                isExpanded: $browser.isSearchExpanded,
                                text: Bindable(browser.types).searchText,
                                prompt: String(localized: "Search"),
                                columnWidth: typesListWidth,
                                focusRequests: browser.searchFocusRequests,
                                onSubmit: browser.types.selectFirstMatch,
                                onDown: { browser.focusRequest = .list }
                            ) {}
                        }
                } else {
                    NoteList(browser: browser, order: order, pane: $pane)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                if $0.isFinite, $0 >= 280 { measuredWidths.list = $0 }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: listWidth, max: 480)
        } detail: {
            itemPage
                .modifier(itemInspector)
                .toolbar(id: "main") {
                    NoteToolbar(browser: browser, items: browser.selectedItems(in: library), editor: editor, details: details)
                }
        }
    }

    private var sidebarColumn: some View {
        Sidebar(browser: browser, order: order)
            // In SwiftUI's focus system, so the sidebar's own keys (Return, Delete) reach it.
            .focused($pane, equals: .sidebar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SyncStatusBar { settings.show(.marfa) }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                if $0.isFinite, $0 >= 180 { measuredWidths.sidebar = $0 }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: sidebarWidth, max: 320)
            .toolbar {
                ToolbarItem {
                    Button("Settings…", systemImage: "gearshape") { settings.show() }
                        .help("Settings")
                        .accessibilityIdentifier("SettingsToolbar")
                }
            }
    }

    private var itemPage: some View {
        Group {
            if browser.isCreatingItem, let draft = browser.itemDraft {
                NewItemPage(browser: browser, draft: draft)
                    .disabled(browser.isAwaitingCreation)
                    .onAppear { editor.close() }
            } else if browser.showsTypes {
                TypeDetailView(browser: browser.types)
                    // The note that was on the page is out of sight, so it is left.
                    .onAppear { editor.close() }
            } else {
                NoteDetail(browser: browser, editor: editor, details: details)
            }
        }
    }

    private var workspace: some View {
        Group {
            if browser.usesGallery {
                NavigationSplitView(columnVisibility: galleryColumnVisibility) {
                    sidebarColumn
                } detail: {
                    Group {
                        if browser.showsGallery {
                            ItemGallery(browser: browser, order: order, pane: $pane)
                        } else {
                            itemPage
                                .toolbar {
                                    ToolbarItem(placement: .navigation) {
                                        Button("Back to Gallery", systemImage: "chevron.backward") { browser.returnToGallery() }
                                            .accessibilityIdentifier("BackToGallery")
                                    }
                                }
                        }
                    }
                    .modifier(itemInspector)
                    .toolbar {
                        GalleryToolbar(browser: browser, items: browser.selectedItems(in: library), editor: editor, details: details)
                    }
                }
            } else {
                splitView
            }
        }
    }

    private var itemInspector: ItemInspectorColumn {
        ItemInspectorColumn(browser: browser, details: details)
    }

    private var presentedWindow: some View {
        workspace
        .focusedSceneValue(\.detailsPresentation, details)
        .onChange(of: details.isPresented) { if restoresWindow { storedDetailsPresented = details.isPresented } }
        .onChange(of: library.catalogue, initial: true) { browser.types.catalogue = library.catalogue }
        .overlay(alignment: .top) {
            if let palette = browser.palette {
                ZStack(alignment: .top) {
                    // A click anywhere else puts the palette away, as it does a menu.
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture {
                            browser.palette = nil
                            browser.focusRequest = .list
                        }
                    CommandPalette(browser: browser, editor: editor, settings: settings, mode: palette)
                        // Each palette starts afresh, as ⌘K's Search Notes moves from one to the other.
                        .id(palette)
                        .padding(.top, 72)
                }
            }
        }
        .focusedSceneValue(\.browser, browser)
        .focusedSceneValue(\.editor, browser.showsGallery ? nil : editor)
        .focusedSceneValue(\.focusedNotes, FocusedNotes(ids: browser.isCreatingItem ? [] : browser.selection, undoManager: undoManager))
    }

    private var lifecycleWindow: some View {
        activeWindow
        // The gallery disappears while an item is open; selection must still follow deletes and moves.
        .onChange(of: galleryItemIDs) { old, new in
            guard browser.usesGallery, !browser.isCreatingItem else { return }
            browser.selection = Browser.selection(browser.selection, keptFrom: old, in: new)
        }
        .onChange(of: library.folders) {
            browser.folderRemoved(in: library, order: order)
        }
        .onChange(of: library.items(in: .allNotes).map(\.id)) { browser.folderRemoved(in: library, order: order) }
        .onChange(of: library.items(in: .allNotes).map(\.id), revealImportedItem)
        .onChange(of: completedImportID, revealImportedItem)
        // The page grants its own requests, since it may not exist until the request's selection shows.
        .onChange(of: browser.focusRequest, grantFocusRequest)
        .onChange(of: browser.snapshot()) { _, snapshot in
            if restoresWindow { storedBrowser = try? JSONEncoder().encode(snapshot) }
        }
        .onDisappear { editor.flush() }
        .onAppear {
            if restoresWindow { details.isPresented = storedDetailsPresented }
            editor.onChange = { [library] id, markdown, read in library.updateBody(of: id, to: markdown, readAt: read) }
            editor.onLeave = { [library] id in library.leave(id) }
            editor.onEscape = { [browser] in browser.focusRequest = .list }
        }
        // A window restores what it showed once the folder has been read, since before then nothing is there. A
        // window carried to another library starts afresh with it, keeping only a draft the person was writing.
        .onChange(of: library.isLoaded, initial: true) {
            browser.adopt(library, undoManager: undoManager)
            guard library.isLoaded else { return }
            browser.fitDraft(to: library)
            if restoresWindow && !browser.isCreatingItem { browser.restore(from: storedBrowser, in: library, order: order) }
        }
        // A new item reaches a server's library when its source says so, which the draft page waits for.
        .onChange(of: creationIsSettled) {
            if creationIsSettled { browser.finishCreation(in: library) }
        }
    }

    private var galleryItemIDs: [ItemID] {
        guard browser.usesGallery else { return [] }
        return browser.sections(in: library, order: order, now: library.now()).flatMap { $0.items.map(\.id) }
    }

    private var importingWindow: some View {
        presentedWindow
        .onChange(of: browser.sidebarItem) { browser.isCreatingItem = false }
        .onChange(of: browser.selection) { browser.isCreatingItem = false }
        .fileImporter(isPresented: $browser.isImportingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                let requestID = UUID()
                importRequestID = requestID
                library.importFiles(urls, folderID: browser.selectedFolder, requestID: requestID)
            }
        }
        .libraryDialogs()
    }

    private var renamingWindow: some View {
        importingWindow
        .alert("Rename Note", isPresented: Binding { browser.renamingNote != nil } set: { if !$0 { browser.renamingNote = nil } }) {
            TextField("Name", text: $noteName)
            Button("Rename") { renameNote() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The note’s file takes the new name.")
        }
        .onChange(of: browser.renamingNote) {
            noteName = browser.renamingNote.flatMap { library.fileName(of: $0) } ?? ""
        }
        .alert("Name Taken", isPresented: Binding { takenNoteName != nil } set: { if !$0 { takenNoteName = nil } }) {
        } message: {
            Text("A note named “\(takenNoteName ?? "")” is already in this folder. Please choose a different name.")
        }
    }

    private var creationIsSettled: Bool { browser.isCreationSettled(in: library) }

    private var completedImportID: ItemID? {
        importRequestID.flatMap { library.completedImports[$0] }
    }

    private func revealImportedItem() {
        guard let requestID = importRequestID, let id = completedImportID,
              library.item(id) != nil else { return }
        browser.isCreatingItem = false
        browser.sidebarItem = .allNotes
        browser.searchText = ""
        browser.selection = [id]
        browser.openGallerySelection()
        library.consumeImportCompletion(requestID)
        importRequestID = nil
    }

    /// The list's search comes out as a field, which takes the keyboard. Search List over Marfa Types searches
    /// All Notes, since Find there searches the types.
    private func grantFocusRequest() {
        switch browser.focusRequest {
        case .search:
            if browser.showsTypes { browser.show(.allNotes, in: library, order: order) }
            if browser.usesGallery {
                browser.isCreatingItem = false
                browser.isGalleryItemPresented = false
            }
            browser.isSearchExpanded = true
            browser.searchFocusRequests += 1
        case .typesSearch:
            browser.isSearchExpanded = true
            browser.searchFocusRequests += 1
        case .sidebar, .list:
            editor.releaseFocus()
            // Asked for as the place changes, the list that takes the keyboard is not yet in the window.
            let request = browser.focusRequest
            Task { pane = request }
        case .page:
            if browser.showsGallery { browser.isGalleryItemPresented = true }
            return
        case nil: return
        }
        browser.focusRequest = nil
    }

    /// A name another note in the folder has is refused with an alert, as the Finder does.
    private func renameNote() {
        guard let id = browser.renamingNote else { return }
        let name = NoteText.fileSafe(noteName)
        if library.isNoteNameTaken(name, for: id) {
            takenNoteName = name
        } else {
            library.renameNote(id, to: name, undoManager: undoManager)
        }
    }
}

// Measuring a drag must not invalidate the view and reapply its preferred column widths.
private final class ColumnWidths {
    var sidebar: CGFloat = 220
    var list: CGFloat = 340
}

/// Applied to a detail column, before its toolbar, never to the split view: an inspector on the split view makes every
/// resize of the window lay out every column again, which made live resizing several times slower, and one applied
/// after the column's toolbar raises an exception during layout when a new window opens.
private struct ItemInspectorColumn: ViewModifier {
    let browser: Browser
    let details: DetailsPresentation

    func body(content: Content) -> some View {
        content.inspector(isPresented: Binding { details.isPresented && !browser.showsTypes && !browser.isCreatingItem } set: { details.isPresented = $0 }) {
            ItemInspectorHost(browser: browser, details: details)
                .inspectorColumnWidth(min: 260, ideal: 310, max: 440)
        }
    }
}
