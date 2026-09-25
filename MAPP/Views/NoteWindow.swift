import SwiftUI

/// One note in a window of its own, opened by double-clicking it in the list.
struct NoteWindow: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss
    @State private var editor = EditorController()
    let id: Note.ID?

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
        // A window whose note has gone, deleted for good or not there when the window is restored, closes.
        .onAppear {
            editor.onChange = { [library] id, markdown in library.updateBody(of: id, to: markdown) }
            if note == nil { dismiss() }
        }
        .onChange(of: note == nil) { if note == nil { dismiss() } }
    }
}
