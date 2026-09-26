import SwiftUI

/// One note in a window of its own, opened by double-clicking it in the list. The window remembers where its
/// note is, so it finds the note again at the next launch, and follows the note when it is renamed or moved.
struct NoteWindow: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss
    @State private var editor = EditorController()
    @Binding var path: String?
    @State private var id: Note.ID?

    private var note: Note? { id.flatMap { library.note($0) } }

    var body: some View {
        Group {
            if let note {
                NotePage(note: note, editor: editor)
                    .navigationTitle(note.title)
                    .focusedSceneValue(\.editor, editor)
                    .focusedSceneValue(\.focusedNotes, FocusedNotes(ids: [note.id], undoManager: undoManager))
                    .toolbar {
                        ToolbarItemGroup(placement: .primaryAction) {
                            DeleteNotesButton(notes: [note])
                            NoteShareLink(note: note)
                        }
                    }
            }
        }
        .onAppear {
            editor.onChange = { [library] id, markdown in library.updateBody(of: id, to: markdown) }
            editor.onLeave = { [library] id in library.leave(id) }
        }
        // The note is found once the folder has been read. A window whose note has gone, deleted for good or not
        // there when the window is restored, closes.
        .onChange(of: library.isLoaded, initial: true) {
            guard library.isLoaded, id == nil else { return }
            id = path.flatMap { library.note(at: $0) }?.id
            if id == nil { dismiss() }
        }
        .onChange(of: note?.path) {
            if let moved = note?.path { path = moved }
        }
        .onChange(of: note == nil) { if library.isLoaded, note == nil { dismiss() } }
        .onDisappear { editor.flush() }
    }
}
