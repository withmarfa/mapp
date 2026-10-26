import SwiftUI

/// The actions for a set of notes, shared by the list's context menu and the menu bar: whether it is a favorite, then
/// what removes it. The More menu places the same two parts apart, with other commands between them.
struct NoteActions: View {
    @CurrentLibrary private var library
    let ids: Set<ItemID>
    /// Passed in, since the menu bar has no window of its own to read one from.
    let undoManager: UndoManager?
    /// The menu bar names what its items act on, since nothing has been clicked to say so.
    var inMenuBar = false

    var body: some View {
        NoteOrganizeActions(ids: ids, undoManager: undoManager, inMenuBar: inMenuBar)
        if inMenuBar || !NoteActionContext(library: library, ids: ids, keepsPlace: false).notes.isEmpty { Divider() }
        NoteRemoveActions(ids: ids, undoManager: undoManager, inMenuBar: inMenuBar)
    }
}

/// How the actions on notes read in the menu that shows them.
private struct NoteActionContext {
    let library: any ItemLibrary
    let ids: Set<ItemID>
    let keepsPlace: Bool

    /// Deleting and favoring act on notes, so a file selected takes none of these.
    var notes: [Item] { ids.compactMap { library.item($0) }.filter { !$0.isFile } }
    var allDeleted: Bool { !notes.isEmpty && notes.allSatisfy { $0.state == .trashed } }
    /// Nothing to act on and nowhere to keep the items in place, as the context menu has none.
    var isEmpty: Bool { notes.isEmpty && !keepsPlace }
}

/// Favorites and Change Type for notes, or Recover for deleted ones.
struct NoteOrganizeActions: View {
    @CurrentLibrary private var library
    /// The window's, for the Change Type sheet; the menu bar passes the front window's in.
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    let ids: Set<ItemID>
    let undoManager: UndoManager?
    /// The menu bar names what its items act on, since nothing has been clicked to say so.
    var inMenuBar = false
    /// Keeps the items in the menu, dimmed, when nothing is selected, as the menu bar and the More menu do.
    var keepsPlace = false

    var body: some View {
        let context = NoteActionContext(library: library, ids: ids, keepsPlace: inMenuBar || keepsPlace)
        let notes = context.notes
        if context.isEmpty {
            EmptyView()
        } else if context.allDeleted {
            Button("Recover", systemImage: "arrow.uturn.backward") { library.recover(ids, undoManager: undoManager) }
        } else {
            let allFavorites = !notes.isEmpty && notes.allSatisfy(\.isFavorite)
            Button(allFavorites ? "Remove from Favorites" : "Add to Favorites", systemImage: allFavorites ? "star.slash" : "star") {
                library.setFavorite(ids, !allFavorites, undoManager: undoManager)
            }
            .disabled(notes.isEmpty)
            TypeChangeButton(ids: ids, details: details, undoManager: undoManager)
        }
    }
}

/// Delete for notes, or Delete Immediately for notes already deleted.
struct NoteRemoveActions: View {
    @CurrentLibrary private var library
    let ids: Set<ItemID>
    let undoManager: UndoManager?
    var inMenuBar = false
    var keepsPlace = false

    var body: some View {
        let context = NoteActionContext(library: library, ids: ids, keepsPlace: inMenuBar || keepsPlace)
        if context.isEmpty {
            EmptyView()
        } else if context.allDeleted {
            Button(inMenuBar ? "Delete Note Immediately…" : "Delete Immediately…", systemImage: "trash", role: .destructive) {
                library.notesToPurge = ids
            }
            .disabled(!library.canPurge)
        } else {
            Button(inMenuBar ? "Delete Note" : "Delete", systemImage: "trash", role: .destructive) {
                library.deleteAfterSaving(ids, undoManager: undoManager)
            }
            .disabled(context.notes.isEmpty)
        }
    }
}

extension ItemLibrary {
    /// Moves notes to Recently Deleted once every open page has handed over what was just typed, since a deleted
    /// note takes no edit. Every way of deleting a note comes through here.
    func deleteAfterSaving(_ ids: Set<ItemID>, undoManager: UndoManager?) {
        EditorController.flushAll(leaving: false) { [self] kept in if kept { delete(ids, undoManager: undoManager) } }
    }
}
