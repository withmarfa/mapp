import SwiftUI

/// The page: the selected note, or a word on why there is none.
struct NoteDetail: View {
    @Environment(NoteLibrary.self) private var library
    let selection: Set<Note.ID>

    var body: some View {
        if selection.count > 1 {
            ContentUnavailableView("^[\(selection.count) note](inflect: true) selected", systemImage: "note.text")
        } else if let id = selection.first, let note = library.note(id) {
            NotePage(note: note)
                .id(note.id)
        } else {
            ContentUnavailableView("No Note Selected", systemImage: "note.text")
        }
    }
}

/// One note as a page. Until the formatted editor arrives, the markdown is edited as plain text.
struct NotePage: View {
    @Environment(NoteLibrary.self) private var library
    let note: Note

    var body: some View {
        TextEditor(text: Binding(
            get: { library.note(note.id)?.body ?? "" },
            set: { library.updateBody(of: note.id, to: $0) }
        ))
        .font(.body)
        .accessibilityIdentifier("NoteEditor")
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .disabled(note.isDeleted)
        .navigationTitle(note.title)
        .safeAreaInset(edge: .top, spacing: 0) {
            if note.isDeleted {
                DeletedNoteBanner(id: note.id)
            }
        }
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
