import SwiftUI

struct NoteDetail: View {
    @Environment(NoteLibrary.self) private var library
    let browser: Browser
    let editor: EditorController

    var body: some View {
        let notes = browser.selection.compactMap { library.note($0) }
        if notes.count > 1 {
            ContentUnavailableView("^[\(notes.count) note](inflect: true) selected", systemImage: "note.text")
        } else if let note = notes.first {
            NotePage(note: note, editor: editor)
                .onAppear(perform: grantFocusRequest)
                .onChange(of: browser.focusRequest, grantFocusRequest)
        } else {
            ContentUnavailableView("No Note Selected", systemImage: "note.text")
        }
    }

    /// The page takes the keyboard when asked, once it shows; the editor holds the request until its page is ready.
    private func grantFocusRequest() {
        guard browser.focusRequest == .page else { return }
        browser.focusRequest = nil
        editor.focus()
    }
}

/// One note as a formatted page. The same editor shows each note in turn, so moving between notes loads
/// text into a page that is already running.
struct NotePage: View {
    let note: Note
    let editor: EditorController

    var body: some View {
        GeometryReader { proxy in
            NoteEditor(controller: editor, topInset: proxy.safeAreaInsets.top)
                .ignoresSafeArea(.container, edges: .top)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if note.isDeleted {
                DeletedNoteBanner(id: note.id)
            }
        }
        .onChange(of: note.id, initial: true) { editor.load(note) }
        .onChange(of: note.body) { editor.noteChanged(note) }
        .onChange(of: note.isDeleted) { editor.noteChanged(note) }
    }
}

/// Deleted notes cannot be edited; this says so and offers the way back, as Notes does.
private struct DeletedNoteBanner: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    let id: Note.ID

    var body: some View {
        HStack {
            Text("Recently deleted notes can’t be edited.")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Recover") { library.recover([id], undoManager: undoManager) }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
