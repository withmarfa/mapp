import SwiftUI

/// The actions for a set of notes, shared by the list's context menu and the menu bar.
struct NoteActions: View {
    @CurrentLibrary private var library
    let ids: Set<ItemID>
    /// Passed in, since the menu bar has no window of its own to read one from.
    let undoManager: UndoManager?
    /// The menu bar names what its items act on, since nothing has been clicked to say so.
    var inMenuBar = false

    /// Files mode moves, deletes and favors notes only, so a file selected takes none of these.
    private var notes: [Item] { ids.compactMap { library.item($0) }.filter { !$0.isFile } }

    var body: some View {
        let notes = notes
        if notes.isEmpty && !inMenuBar {
            EmptyView()
        } else if !notes.isEmpty && notes.allSatisfy({ $0.state == .trashed }) {
            Button("Recover", systemImage: "arrow.uturn.backward") { library.recover(ids, undoManager: undoManager) }
            moveMenu(notes)
            Divider()
            Button(inMenuBar ? "Delete Note Immediately…" : "Delete Immediately…", systemImage: "trash", role: .destructive) {
                library.notesToPurge = ids
            }
            .disabled(!library.capabilities.contains(.purge))
        } else {
            let allFavorites = !notes.isEmpty && notes.allSatisfy(\.isFavorite)
            // The menu bar keeps these in place, dimmed, when nothing is selected.
            Group {
                Button(allFavorites ? "Remove from Favorites" : "Add to Favorites", systemImage: allFavorites ? "star.slash" : "star") {
                    library.setFavorite(ids, !allFavorites, undoManager: undoManager)
                }
                moveMenu(notes)
                Divider()
                // Archiving is Marfa's to supply; until then the command keeps its place, dimmed.
                Button(inMenuBar ? "Archive Note" : "Archive", systemImage: "archivebox") {}
                    .disabled(true)
                Button(inMenuBar ? "Delete Note" : "Delete", systemImage: "trash", role: .destructive) {
                    library.deleteAfterSaving(ids, undoManager: undoManager)
                }
            }
            .disabled(notes.isEmpty)
        }
    }

    private func moveMenu(_ notes: [Item]) -> some View {
        Menu("Move To", systemImage: "folder") {
            Button("Inbox", systemImage: "tray") { library.move(ids, to: nil, undoManager: undoManager) }
                .disabled(notes.allSatisfy { $0.container == nil && $0.state == .active })
            Divider()
            ForEach(library.folders) { folder in
                Button(folder.name, systemImage: "folder") { library.move(ids, to: folder.id, undoManager: undoManager) }
                    .disabled(notes.allSatisfy { $0.container == ContainerID(folder.id) && $0.state == .active })
            }
        }
        .disabled(!library.capabilities.contains(.move))
    }
}

extension ItemLibrary {
    /// Moves notes to Recently Deleted once every open page has handed over what was just typed, since a deleted
    /// note takes no edit. Every way of deleting a note comes through here.
    func deleteAfterSaving(_ ids: Set<ItemID>, undoManager: UndoManager?) {
        EditorController.flushAll(leaving: false) { [self] in delete(ids, undoManager: undoManager) }
    }
}
