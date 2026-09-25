import SwiftUI

struct MainView: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    @State private var browser = Browser()
    @StoredOrder private var order
    @SceneStorage("browser") private var storedBrowser: Data?
    @FocusState private var pane: Browser.Pane?

    var body: some View {
        NavigationSplitView {
            Sidebar(browser: browser, order: order)
                .focused($pane, equals: .sidebar)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } content: {
            NoteList(browser: browser, order: order, pane: $pane)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
        } detail: {
            NoteDetail(browser: browser, pane: $pane)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        NoteToolbar(browser: browser)
                    }
                }
        }
        .searchable(text: $browser.searchText, placement: .toolbar)
        .focusedSceneValue(\.browser, browser)
        .focusedSceneValue(\.focusedNotes, FocusedNotes(ids: browser.selection, undoManager: undoManager))
        .onChange(of: library.folders) {
            browser.folderRemoved(in: library, order: order)
        }
        // The page grants its own requests, since it may not exist until the request's selection shows.
        .onChange(of: browser.focusRequest) {
            guard let request = browser.focusRequest, request != .page else { return }
            pane = request
            browser.focusRequest = nil
        }
        .onChange(of: browser.snapshot) {
            storedBrowser = try? JSONEncoder().encode(browser.snapshot)
        }
        .onAppear(perform: restore)
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
        Button("Delete", systemImage: "trash") {
            browser.delete(browser.selection, in: library, undoManager: undoManager)
        }
        .disabled(notes.isEmpty)
        NoteShareLink(note: notes.count == 1 ? notes.first : nil)
        Button("New Note", systemImage: "square.and.pencil") {
            browser.newNote(in: library, undoManager: undoManager)
        }
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
