import SwiftUI

/// The actions for a set of notes, shared by the list's context menu and the menu bar.
struct NoteActions: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    let ids: Set<Note.ID>

    private var notes: [Note] { ids.compactMap { library.note($0) } }

    var body: some View {
        let notes = notes
        if notes.isEmpty {
            EmptyView()
        } else if notes.allSatisfy(\.isDeleted) {
            Button("Recover") { library.recover(ids, undoManager: undoManager) }
            moveMenu(notes)
            Divider()
            Button("Delete Immediately", role: .destructive) {
                library.deletePermanently(ids, undoManager: undoManager)
            }
        } else {
            let allPinned = notes.allSatisfy(\.isPinned)
            Button(allPinned ? "Unpin" : "Pin") {
                library.setPinned(ids, !allPinned, undoManager: undoManager)
            }
            moveMenu(notes)
            Divider()
            Button("Delete", role: .destructive) { library.delete(ids, undoManager: undoManager) }
        }
    }

    private func moveMenu(_ notes: [Note]) -> some View {
        Menu("Move To") {
            Button("Inbox") { library.move(ids, to: nil, undoManager: undoManager) }
                .disabled(notes.allSatisfy { $0.folderID == nil && !$0.isDeleted })
            Divider()
            ForEach(library.folders) { folder in
                Button(folder.name) { library.move(ids, to: folder.id, undoManager: undoManager) }
                    .disabled(notes.allSatisfy { $0.folderID == folder.id && !$0.isDeleted })
            }
        }
    }
}
