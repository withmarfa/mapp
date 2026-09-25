import SwiftUI

/// One main window: the sidebar picks what the list shows, and the list picks what the page shows.
struct MainView: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    @State private var sidebarSelection: SidebarItem? = .allNotes
    @State private var noteSelection: Set<Note.ID> = []
    @State private var searchText = ""
    @AppStorage("noteSort") private var sort: NoteSort = .dateEdited

    private var item: SidebarItem { sidebarSelection ?? .allNotes }

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } content: {
            NoteList(item: item, searchText: searchText, sort: sort, selection: $noteSelection)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
        } detail: {
            NoteDetail(selection: noteSelection)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New Note", systemImage: "square.and.pencil", action: newNote)
                            .disabled(!searchText.isEmpty)
                    }
                }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: Text("Search"))
        .onChange(of: sidebarSelection) {
            searchText = ""
            selectFirstNote()
        }
        .onAppear(perform: selectFirstNote)
    }

    private func selectFirstNote() {
        let notes = sort.sorted(library.notes(in: item))
        let first = notes.first(where: \.isPinned) ?? notes.first
        noteSelection = first.map { [$0.id] } ?? []
    }

    private func newNote() {
        if item == .recentlyDeleted { sidebarSelection = .inbox }
        let note = library.newNote(in: item, undoManager: undoManager)
        noteSelection = [note.id]
    }
}
