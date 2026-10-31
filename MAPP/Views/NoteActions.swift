import SwiftUI

/// The actions for a set of notes, shared by the list's context menu and the menu bar: whether it is a favorite, then
/// what removes it. The More menu places the same two parts apart, with other commands between them.
struct NoteActions: View {
    @CurrentLibrary private var library
    /// The window's, for the Add to Collection sheet; the menu bar passes the front window's in.
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    let ids: Set<ItemID>
    /// Passed in, since the menu bar has no window of its own to read one from.
    let undoManager: UndoManager?
    /// The menu bar names what its items act on, since nothing has been clicked to say so.
    var inMenuBar = false

    var body: some View {
        NoteOrganizeActions(ids: ids, undoManager: undoManager, inMenuBar: inMenuBar)
        CollectionActions(selection: ids, details: details, undoManager: undoManager)
        if inMenuBar || ids.contains(where: { library.item($0) != nil }) { Divider() }
        NoteRemoveActions(ids: ids, undoManager: undoManager, inMenuBar: inMenuBar)
    }
}

/// How the actions on notes read in the menu that shows them.
private struct NoteActionContext {
    /// Every selected item, files too: a command that suits only some of them leaves the rest alone and says so.
    /// Looked up once, since a selection can hold every item in the library.
    let items: [Item]
    let keepsPlace: Bool

    init(library: any ItemLibrary, ids: Set<ItemID>, keepsPlace: Bool) {
        items = ids.compactMap { library.item($0) }
        self.keepsPlace = keepsPlace
    }

    var allDeleted: Bool { !items.isEmpty && items.allSatisfy { $0.state == .trashed } }
    /// Nothing to act on and nowhere to keep the items in place, as the context menu has none.
    var isEmpty: Bool { items.isEmpty && !keepsPlace }
}

/// Favorites, Add Tag, Change Type, Customize Page and Version History for the selection, or Recover for deleted items. The
/// collection actions sit beside these (`CollectionActions`).
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
        if context.isEmpty {
            EmptyView()
        } else if context.allDeleted {
            Button("Recover", systemImage: "arrow.uturn.backward") { library.recover(ids, undoManager: undoManager) }
            VersionHistoryButton(ids: ids, details: details, undoManager: undoManager)
        } else {
            // An item in the bin keeps its tags, so it neither decides the toggle nor takes the change.
            let active = context.items.filter { $0.state == .active }
            let allFavorites = !active.isEmpty && active.allSatisfy(\.isFavorite)
            Button(allFavorites ? "Remove from Favorites" : "Add to Favorites", systemImage: allFavorites ? "star.slash" : "star") {
                library.setFavorite(ids, !allFavorites, undoManager: undoManager)
            }
            .disabled(active.isEmpty)
            AddTagButton(ids: ids, details: details, undoManager: undoManager)
            TypeChangeButton(ids: ids, details: details, undoManager: undoManager)
            CustomizePageButton(ids: ids, details: details)
            VersionHistoryButton(ids: ids, details: details, undoManager: undoManager)
        }
    }
}

/// Delete for items, or Delete Immediately for items already deleted.
struct NoteRemoveActions: View {
    @CurrentLibrary private var library
    /// The window's, to ask before moving several items; the menu bar passes the front window's in.
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    let ids: Set<ItemID>
    let undoManager: UndoManager?
    var inMenuBar = false
    var keepsPlace = false

    var body: some View {
        let context = NoteActionContext(library: library, ids: ids, keepsPlace: inMenuBar || keepsPlace)
        if context.isEmpty {
            EmptyView()
        } else if context.allDeleted {
            Button("Delete Immediately…", systemImage: "trash", role: .destructive) {
                library.notesToPurge = ids
            }
            .disabled(!library.canPurge)
        } else {
            Button("Delete", systemImage: "trash", role: .destructive) {
                library.deleteAfterSaving(ids, undoManager: undoManager, asking: details)
            }
            .disabled(context.items.isEmpty)
        }
    }
}

extension ItemLibrary {
    /// Moves items to Recently Deleted once every open page has handed over what was just typed, since a deleted
    /// note takes no edit. Every way of deleting comes through here. More than one item asks the person first, in
    /// the window whose presentation it is given.
    func deleteAfterSaving(_ ids: Set<ItemID>, undoManager: UndoManager?, asking details: DetailsPresentation?) {
        EditorController.flushAll(leaving: false) { [self] kept in
            guard kept else { return }
            Browser.delete(ids, in: self, undoManager: undoManager, asking: details.map { details in
                { details.deletion = DeleteRequest(ids: $0, undoManager: undoManager) }
            })
        }
    }
}
