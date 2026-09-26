import SwiftUI

struct MainView: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    @State private var browser = Browser()
    @State private var editor = EditorController()
    @StoredOrder private var order
    @SceneStorage("browser") private var storedBrowser: Data?
    @FocusState private var pane: Browser.Pane?
    @FocusState private var isSearchFocused: Bool
    @State private var noteName = ""
    @State private var takenNoteName: String?

    var body: some View {
        NavigationSplitView {
            Sidebar(browser: browser, order: order)
                // In SwiftUI's focus system, so the sidebar's own keys (Return, Delete) reach it.
                .focused($pane, equals: .sidebar)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } content: {
            NoteList(browser: browser, order: order, pane: $pane)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
        } detail: {
            NoteDetail(browser: browser, editor: editor)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        NoteToolbar(browser: browser)
                    }
                }
        }
        .searchable(text: $browser.searchText, placement: .toolbar)
        .searchFocused($isSearchFocused)
        .focusedSceneValue(\.browser, browser)
        .focusedSceneValue(\.editor, editor)
        .focusedSceneValue(\.focusedNotes, FocusedNotes(ids: browser.selection, undoManager: undoManager))
        .onChange(of: library.folders) {
            browser.folderRemoved(in: library, order: order)
        }
        // The page grants its own requests, since it may not exist until the request's selection shows.
        .onChange(of: browser.focusRequest) {
            switch browser.focusRequest {
            case .search: isSearchFocused = true
            case .sidebar, .list: pane = browser.focusRequest
            case .page, nil: return
            }
            browser.focusRequest = nil
        }
        .onChange(of: browser.snapshot(in: library)) { _, snapshot in
            storedBrowser = try? JSONEncoder().encode(snapshot)
        }
        .onDisappear { editor.flush() }
        .onAppear {
            editor.onChange = { [library] id, markdown in library.updateBody(of: id, to: markdown) }
            editor.onLeave = { [library] id in library.leave(id) }
            editor.onEscape = { [browser] in browser.focusRequest = .list }
        }
        // A window restores what it showed once the folder has been read, since before then nothing is there.
        .onChange(of: library.isLoaded, initial: true) {
            if library.isLoaded { restore() }
        }
        .confirmationDialog(
            library.notesToPurge.count == 1
                ? "Delete this note immediately?"
                : "Delete \(library.notesToPurge.count) notes immediately?",
            isPresented: Binding { !library.notesToPurge.isEmpty } set: { if !$0 { library.notesToPurge = [] } }
        ) {
            Button("Delete", role: .destructive) { library.deletePermanently(library.notesToPurge) }
        } message: {
            Text("You can’t undo this action.")
        }
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
        .alert(
            "Couldn’t Save “\(library.failure.map { ($0.path as NSString).lastPathComponent } ?? "")”",
            isPresented: Binding { library.failure != nil } set: { if !$0 { library.failure = nil } }
        ) {
        } message: {
            Text(library.failure?.message ?? "")
        }
        .alert("Name Taken", isPresented: Binding { takenNoteName != nil } set: { if !$0 { takenNoteName = nil } }) {
        } message: {
            Text("A note named “\(takenNoteName ?? "")” is already in this folder. Please choose a different name.")
        }
    }

    /// A name another note in the folder has is refused with an alert, as the Finder does.
    private func renameNote() {
        guard let id = browser.renamingNote else { return }
        let name = NoteLibrary.fileSafe(noteName)
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

/// Delete, Share and New Note, acting on the window's selection.
private struct NoteToolbar: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    let browser: Browser

    var body: some View {
        let notes = browser.selectedNotes(in: library)
        DeleteNotesButton(notes: notes)
        NoteShareLink(note: notes.count == 1 ? notes.first : nil)
        Button("New Note", systemImage: "square.and.pencil") {
            browser.newNote(in: library, undoManager: undoManager)
        }
        .disabled(!library.isLoaded)
    }
}

/// Deletes to Recently Deleted, or for good when the notes are already there, and says which.
struct DeleteNotesButton: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    let notes: [Note]

    var body: some View {
        let immediately = !notes.isEmpty && notes.allSatisfy(\.isDeleted)
        Button(immediately ? "Delete Immediately" : "Delete", systemImage: "trash") {
            Browser.delete(Set(notes.map(\.id)), in: library, undoManager: undoManager)
        }
        .disabled(notes.isEmpty)
    }
}

/// Shares a note's markdown as text, the form every destination can take.
struct NoteShareLink: View {
    let note: Note?

    var body: some View {
        if let note {
            ShareLink(item: note.body, subject: Text(note.title), preview: SharePreview(note.title))
        } else {
            ShareLink(item: "")
                .disabled(true)
        }
    }
}
