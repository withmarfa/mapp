import SwiftUI

/// One note in a window of its own, opened by double-clicking it in the list.
struct NoteWindow: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    let id: Note.ID?

    var body: some View {
        if let id, let note = library.note(id) {
            NotePage(note: note)
                .navigationTitle(note.title)
                .focusedSceneValue(\.focusedNotes, FocusedNotes(ids: [id], undoManager: undoManager))
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Delete", systemImage: "trash") {
                            library.delete([id], undoManager: undoManager)
                        }
                        .disabled(note.isDeleted)
                        NoteShareLink(note: note)
                    }
                }
        } else {
            // A note deleted for good while its window was open, or one a restored window no longer finds.
            ContentUnavailableView("No Note", systemImage: "note.text", description: Text("This note has been deleted."))
        }
    }
}
