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

    var body: some View { renamingWindow }

    private var splitView: some View {
        // Every place keeps the same three columns, Marfa Types among them: AppKit crashed laying out the toolbar
        // as the columns changed with the sidebar hidden or resized.
        NavigationSplitView {
            Sidebar(browser: browser, order: order)
                // In SwiftUI's focus system, so the sidebar's own keys (Return, Delete) reach it.
                .focused($pane, equals: .sidebar)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } content: {
            Group {
                if browser.showsTypes {
                    TypesListView(browser: browser.types, pane: $pane)
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { typesListWidth = $0 }
                        .navigationTitle(settings.isPresented ? "" : library.name(of: .marfaTypes))
                        .toolbar(removing: !settings.isPresented && browser.isSearchExpanded ? .title : nil)
                        .toolbar {
                            if !settings.isPresented {
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
                        }
                } else {
                    NoteList(browser: browser, order: order, pane: $pane, settingsPresented: settings.isPresented)
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
        } detail: {
            Group {
                if browser.isCreatingItem, let draft = browser.itemDraft {
                    NewItemPage(browser: browser, draft: draft)
                        .onAppear { editor.close() }
                } else if browser.showsTypes {
                    TypeDetailView(browser: browser.types)
                        // The note that was on the page is out of sight, so it is left.
                        .onAppear { editor.close() }
                } else {
                    NoteDetail(browser: browser, editor: editor, details: details)
                }
            }
            .toolbar(id: "main") {
                if !settings.isPresented {
                    NoteToolbar(browser: browser, items: browser.selectedItems(in: library), editor: editor, details: details)
                }
            }
        }
        .toolbar(removing: settings.isPresented ? .sidebarToggle : nil)
    }

    private var presentedWindow: some View {
        splitView
        .inspector(isPresented: Binding { details.isPresented && !settings.isPresented && !browser.showsTypes && !browser.isCreatingItem } set: { if !settings.isPresented { details.isPresented = $0 } }) {
            ItemInspectorHost(browser: browser, details: details)
                .inspectorColumnWidth(min: 260, ideal: 310, max: 440)
        }
        .focusedSceneValue(\.detailsPresentation, settings.isPresented ? nil : details)
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
        .focusedSceneValue(\.browser, settings.isPresented ? nil : browser)
        .focusedSceneValue(\.editor, settings.isPresented ? nil : editor)
        .focusedSceneValue(\.focusedNotes, settings.isPresented ? nil : FocusedNotes(ids: browser.isCreatingItem ? [] : browser.selection, undoManager: undoManager))
    }

    private var lifecycleWindow: some View {
        presentedWindow
        .onChange(of: settings.isPresented) {
            if settings.isPresented {
                editor.flush()
                browser.palette = nil
                pane = nil
            }
        }
        .onChange(of: library.folders) {
            browser.folderRemoved(in: library, order: order)
        }
        .onChange(of: library.items(in: .allNotes).map(\.id)) { browser.folderRemoved(in: library, order: order) }
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
        // A window restores what it showed once the folder has been read, since before then nothing is there.
        .onChange(of: library.isLoaded, initial: true) {
            if library.isLoaded && restoresWindow { browser.restore(from: storedBrowser, in: library, order: order) }
        }
    }

    private var importingWindow: some View {
        lifecycleWindow
        .onChange(of: browser.sidebarItem) { browser.isCreatingItem = false }
        .onChange(of: browser.selection) { browser.isCreatingItem = false }
        .fileImporter(isPresented: $browser.isImportingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                let requestID = UUID()
                importRequestID = requestID
                library.importFiles(urls, folderID: browser.selectedFolder, requestID: requestID)
            }
        }
        .onChange(of: library.items(in: .allNotes).map(\.id), revealImportedItem)
        .onChange(of: completedImportID, revealImportedItem)
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

    private var completedImportID: ItemID? {
        importRequestID.flatMap { library.completedImports[$0] }
    }

    private func revealImportedItem() {
        guard let requestID = importRequestID, let id = completedImportID,
              library.item(id) != nil else { return }
        browser.sidebarItem = .allNotes
        browser.searchText = ""
        browser.selection = [id]
        library.consumeImportCompletion(requestID)
        importRequestID = nil
    }

    /// The list's search comes out as a field, which takes the keyboard. Search List over Marfa Types searches
    /// All Notes, since Find there searches the types.
    private func grantFocusRequest() {
        switch browser.focusRequest {
        case .search:
            if browser.showsTypes { browser.show(.allNotes, in: library, order: order) }
            browser.isSearchExpanded = true
            browser.searchFocusRequests += 1
        case .typesSearch:
            browser.isSearchExpanded = true
            browser.searchFocusRequests += 1
        case .sidebar, .list:
            // Asked for as the place changes, the list that takes the keyboard is not yet in the window.
            let request = browser.focusRequest
            Task { pane = request }
        case .page, nil: return
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
