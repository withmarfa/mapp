import SwiftUI

/// The actions for a set of items, shared by the list's context menu and the menu bar: whether it is a favorite, then
/// the moves and what removes it. The More menu places them apart, with other commands between.
struct ItemActions: View {
    @CurrentLibrary private var library
    /// The window's, for the Add to Collection panel; the menu bar passes the front window's in.
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    let ids: Set<ItemID>
    /// Passed in, since the menu bar has no window of its own to read one from.
    let undoManager: UndoManager?
    /// The menu bar names what its items act on, since nothing has been clicked to say so.
    var inMenuBar = false
    /// The keys the menu bar binds; a context menu has none.
    var shortcuts: ShortcutBindings?

    var body: some View {
        ItemOrganizeActions(ids: ids, undoManager: undoManager, inMenuBar: inMenuBar, shortcuts: shortcuts)
        CollectionActions(selection: ids, details: details, undoManager: undoManager)
        if inMenuBar || ids.contains(where: { library.item($0) != nil }) { Divider() }
        ItemMoveActions(ids: ids, undoManager: undoManager, keepsPlace: inMenuBar, shortcuts: shortcuts)
        ItemRemoveActions(ids: ids, undoManager: undoManager, inMenuBar: inMenuBar, shortcuts: shortcuts)
    }
}

/// How the actions on items read in the menu that shows them.
private struct ItemActionContext {
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

/// Favorites, Add Tag, Change Type, Customize Layout and Version History for the selection, or Recover for deleted items. The
/// collection actions sit beside these (`CollectionActions`).
struct ItemOrganizeActions: View {
    @CurrentLibrary private var library
    /// The window's, for the Change Type panel; the menu bar passes the front window's in.
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    let ids: Set<ItemID>
    let undoManager: UndoManager?
    /// The menu bar names what its items act on, since nothing has been clicked to say so.
    var inMenuBar = false
    /// Keeps the items in the menu, dimmed, when nothing is selected, as the menu bar and the More menu do.
    var keepsPlace = false
    var shortcuts: ShortcutBindings?

    var body: some View {
        let context = ItemActionContext(library: library, ids: ids, keepsPlace: inMenuBar || keepsPlace)
        if context.isEmpty {
            EmptyView()
        } else if context.allDeleted {
            Button("Recover", systemImage: "arrow.uturn.backward") { library.recover(ids, undoManager: undoManager) }
            VersionHistoryButton(ids: ids, details: details, shortcuts: shortcuts)
        } else {
            FavoriteButton(ids: ids, undoManager: undoManager, shortcuts: shortcuts)
            AddTagButton(ids: ids, details: details, undoManager: undoManager, shortcuts: shortcuts)
            TypeChangeButton(ids: ids, details: details, undoManager: undoManager, shortcuts: shortcuts)
            // A right click on a card with no page open has nothing to arrange; the menus keep the item in place.
            if details?.showsPage != false || inMenuBar || keepsPlace {
                CustomizeLayoutButton(ids: ids, details: details, shortcuts: shortcuts)
            }
            VersionHistoryButton(ids: ids, details: details, shortcuts: shortcuts)
        }
    }
}

/// Adds the selection to Favorites, or removes it once every item is there.
struct FavoriteButton: View {
    @CurrentLibrary private var library
    let ids: Set<ItemID>
    let undoManager: UndoManager?
    var shortcuts: ShortcutBindings?

    var body: some View {
        // An item in the bin keeps its tags, so it neither decides the toggle nor takes the change.
        let active = ItemActionContext(library: library, ids: ids, keepsPlace: true).items.filter { $0.state == .active }
        let allFavorites = !active.isEmpty && active.allSatisfy(\.isFavorite)
        Button(allFavorites ? "Remove from Favorites" : "Add to Favorites", systemImage: allFavorites ? "star.slash" : "star") {
            library.setFavorite(ids, !allFavorites, undoManager: undoManager)
        }
        .shortcut(.favorite, shortcuts)
        .disabled(active.isEmpty)
    }
}

/// Delete for items, or Delete Immediately for items already deleted.
struct ItemRemoveActions: View {
    @CurrentLibrary private var library
    /// The window's, to ask before moving several items; the menu bar passes the front window's in.
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    let ids: Set<ItemID>
    let undoManager: UndoManager?
    var inMenuBar = false
    var keepsPlace = false
    var shortcuts: ShortcutBindings?

    var body: some View {
        let context = ItemActionContext(library: library, ids: ids, keepsPlace: inMenuBar || keepsPlace)
        if context.isEmpty {
            EmptyView()
        } else if context.allDeleted {
            Button("Delete Immediately…", systemImage: "trash", role: .destructive) {
                library.itemsToPurge = ids
            }
            .disabled(!library.reachesServer)
        } else {
            Button("Delete", systemImage: "trash") {
                library.deleteAfterSaving(ids, undoManager: undoManager, asking: details)
            }
            .shortcut(.delete, shortcuts)
            .disabled(context.items.isEmpty)
        }
    }
}

extension ItemLibrary {
    /// Moves items to Recently Deleted once every open page has handed over what was just typed, since a deleted
    /// item takes no edit. Every way of deleting comes through here. More than one item asks the person first, in
    /// the window whose presentation it is given.
    func deleteAfterSaving(_ ids: Set<ItemID>, undoManager: UndoManager?, asking details: DetailsPresentation?, naming title: String? = nil) {
        EditorController.flushAll(leaving: false) { [self] kept in
            guard kept else { return }
            Browser.delete(ids, in: self, undoManager: undoManager, toasts: details?.toasts, naming: title, asking: details.map { details in
                { moving in
                    // `ids` is the whole selection, which decides whether the server is asked at all.
                    Task { await details.askToMove(moving, of: ids, in: self, undoManager: undoManager) }
                }
            })
        }
    }
}
