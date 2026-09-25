import SwiftUI

struct MainView: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    @State private var browser = Browser()
    @AppStorage("noteSort") private var sort: NoteSort = .dateEdited

    var body: some View {
        NavigationSplitView {
            Sidebar(browser: browser, sort: sort)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } content: {
            NoteList(browser: browser, sort: sort)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
        } detail: {
            NoteDetail(selection: browser.selection)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New Note", systemImage: "square.and.pencil") {
                            browser.newNote(in: library, undoManager: undoManager)
                        }
                    }
                }
        }
        .searchable(text: $browser.searchText, placement: .toolbar)
        .onChange(of: library.folders) {
            browser.folderRemoved(in: library, sort: sort)
        }
        .onAppear {
            browser.selectFirstNote(in: library, sort: sort)
        }
    }
}
