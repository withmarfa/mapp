import SwiftUI

/// The actions for a set of notes, shared by the list's context menu and the menu bar.
struct NoteActions: View {
    @Environment(NoteLibrary.self) private var library
    let ids: Set<Note.ID>
    /// Passed in, since the menu bar has no window of its own to read one from.
    let undoManager: UndoManager?
    /// The menu bar names what its items act on, since nothing has been clicked to say so.
    var inMenuBar = false

    private var notes: [Note] { ids.compactMap { library.note($0) } }

    var body: some View {
        let notes = notes
        if notes.isEmpty && !inMenuBar {
            EmptyView()
        } else if !notes.isEmpty && notes.allSatisfy(\.isDeleted) {
            Button("Recover", systemImage: "arrow.uturn.backward") { library.recover(ids, undoManager: undoManager) }
            moveMenu(notes)
            Divider()
            Button(inMenuBar ? "Delete Note Immediately…" : "Delete Immediately…", systemImage: "trash", role: .destructive) {
                library.notesToPurge = ids
            }
        } else {
            let allPinned = !notes.isEmpty && notes.allSatisfy(\.isPinned)
            // The menu bar keeps these in place, dimmed, when nothing is selected.
            Group {
                Button(pinTitle(allPinned), systemImage: allPinned ? "pin.slash" : "pin") {
                    library.setPinned(ids, !allPinned, undoManager: undoManager)
                }
                moveMenu(notes)
                Divider()
                // Archiving is Marfa's to supply; until then the command keeps its place, dimmed.
                Button(inMenuBar ? "Archive Note" : "Archive", systemImage: "archivebox") {}
                    .disabled(true)
                Button(inMenuBar ? "Delete Note" : "Delete", systemImage: "trash", role: .destructive) {
                    // What was just typed reaches the note before it goes, since a deleted note takes no edit.
                    EditorController.flushAll(leaving: false) { [ids, undoManager] in library.delete(ids, undoManager: undoManager) }
                }
            }
            .disabled(notes.isEmpty)
        }
    }

    private func pinTitle(_ allPinned: Bool) -> LocalizedStringKey {
        switch (allPinned, inMenuBar) {
        case (true, true): "Unpin Note"
        case (true, false): "Unpin"
        case (false, true): "Pin Note"
        case (false, false): "Pin"
        }
    }

    private func moveMenu(_ notes: [Note]) -> some View {
        Menu("Move To", systemImage: "folder") {
            Button("Inbox", systemImage: "tray") { library.move(ids, to: nil, undoManager: undoManager) }
                .disabled(notes.allSatisfy { $0.folderID == nil && !$0.isDeleted })
            Divider()
            ForEach(library.folders) { folder in
                Button(folder.name, systemImage: "folder") { library.move(ids, to: folder.id, undoManager: undoManager) }
                    .disabled(notes.allSatisfy { $0.folderID == folder.id && !$0.isDeleted })
            }
        }
    }
}
