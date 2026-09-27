import SwiftUI

struct MainView: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    @State private var browser = Browser()
    @State private var editor = EditorController()
    @State private var types = MarfaTypesPage()
    @StoredOrder private var order
    @SceneStorage("browser") private var storedBrowser: Data?
    @FocusState private var pane: Browser.Pane?
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isTypesSearchFocused: Bool
    @State private var typesQuery = ""
    @State private var noteName = ""
    @State private var takenNoteName: String?

    var body: some View {
        // Marfa Types has no list, so its page takes the list's column and the note's together.
        Group {
            if browser.showsTypes {
                NavigationSplitView {
                    sidebar
                } detail: {
                    MarfaTypesView(page: types)
                        .navigationTitle(library.name(of: .marfaTypes))
                        // The note that was on the page is out of sight, so it is left.
                        .onAppear { editor.close() }
                }
                // The page's own search, in the toolbar where the notes' search is everywhere else.
                .searchable(text: $typesQuery, placement: .toolbar, prompt: Text("Search Types"))
                .searchFocused($isTypesSearchFocused)
                .onSubmit(of: .search) { types.openFirstMatch() }
                .onChange(of: typesQuery) { types.search(typesQuery) }
            } else {
                NavigationSplitView {
                    sidebar
                } content: {
                    NoteList(browser: browser, order: order, pane: $pane)
                        .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
                } detail: {
                    NoteDetail(browser: browser, editor: editor)
                        .toolbar(id: "main") {
                            NoteToolbar(browser: browser, notes: browser.selectedNotes(in: library), editor: editor)
                        }
                }
                // Only the notes are searched here; Marfa Types has a search of its own.
                .searchable(text: $browser.searchText, placement: .toolbar)
                .searchFocused($isSearchFocused)
            }
        }
        .overlay(alignment: .top) {
            if browser.isShowingPalette {
                ZStack(alignment: .top) {
                    // A click anywhere else puts the palette away, as it does a menu.
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture {
                            browser.isShowingPalette = false
                            browser.focusRequest = browser.showsTypes ? .sidebar : .list
                        }
                    CommandPalette(browser: browser, editor: editor)
                        .padding(.top, 72)
                }
            }
        }
        .focusedSceneValue(\.browser, browser)
        .focusedSceneValue(\.editor, editor)
        .focusedSceneValue(\.focusedNotes, FocusedNotes(ids: browser.selection, undoManager: undoManager))
        .onChange(of: library.folders) {
            browser.folderRemoved(in: library, order: order)
        }
        // The page grants its own requests, since it may not exist until the request's selection shows.
        .onChange(of: browser.focusRequest, grantFocusRequest)
        .onChange(of: browser.showsTypes, grantFocusRequest)
        .onChange(of: browser.snapshot(in: library)) { _, snapshot in
            storedBrowser = try? JSONEncoder().encode(snapshot)
        }
        .onDisappear { editor.flush() }
        .onAppear {
            editor.library = library
            editor.onChange = { [library] id, markdown in library.updateBody(of: id, to: markdown) }
            editor.onLeave = { [library] id in library.leave(id) }
            editor.onEscape = { [browser] in browser.focusRequest = .list }
            types.onFind = { [browser] in browser.focusRequest = .typesSearch }
        }
        // A window restores what it showed once the folder has been read, since before then nothing is there.
        .onChange(of: library.isLoaded, initial: true) {
            if library.isLoaded { restore() }
        }
        .libraryDialogs()
        .alert("Rename Note", isPresented: Binding { browser.renamingNote != nil } set: { if !$0 { browser.renamingNote = nil } }) {
            TextField("Name", text: $noteName)
            Button("Rename") { renameNote() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The note’s file takes the new name.")
        }
        .onChange(of: browser.renamingNote) {
            noteName = browser.renamingNote.flatMap { library.note($0) }.map { $0.fileTitle ?? $0.title } ?? ""
        }
        .alert("Name Taken", isPresented: Binding { takenNoteName != nil } set: { if !$0 { takenNoteName = nil } }) {
        } message: {
            Text("A note named “\(takenNoteName ?? "")” is already in this folder. Please choose a different name.")
        }
    }

    /// Search Notes from Marfa Types goes to All Notes first, and its search field takes the keyboard once shown.
    private func grantFocusRequest() {
        switch browser.focusRequest {
        case .search:
            if browser.showsTypes { return browser.show(.allNotes, in: library, order: order) }
            isSearchFocused = true
        case .typesSearch: isTypesSearchFocused = true
        case .sidebar, .list: pane = browser.focusRequest
        case .page, nil: return
        }
        browser.focusRequest = nil
    }

    private var sidebar: some View {
        Sidebar(browser: browser, order: order)
            // In SwiftUI's focus system, so the sidebar's own keys (Return, Delete) reach it.
            .focused($pane, equals: .sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
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

    private func restore() {
        if let storedBrowser, let snapshot = try? JSONDecoder().decode(Browser.Snapshot.self, from: storedBrowser) {
            browser.restore(snapshot, in: library, order: order)
        } else {
            browser.selectFirstNote(in: library, order: order)
        }
    }
}
