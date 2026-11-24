import Foundation

extension Browser {
    /// Shows a sidebar item as a person picks it in the sidebar, the menus or the palette: any search is cleared and the
    /// list's first item is selected, where the place is not an index, which chooses nothing until the person does.
    func show(_ item: SidebarItem, in library: any ItemLibrary, order: ItemOrder) {
        let interval = Telemetry.begin(.navigation, "place.choose")
        defer { interval.end() }
        isCollectionItemPresented = false
        modalItem = nil
        searchText = ""
        isSearchExpanded = false
        sidebarItem = item
        fallBackToListIfUnavailable(in: library)
        selectFirstItem(in: library, order: order)
    }

    func selectFirstItem(in library: any ItemLibrary, order: ItemOrder) {
        // An index chooses nothing until the person does, and ordering every item for a first one would hold the window.
        guard !showsSidebarIndex else { return selectAutomatically([]) }
        let first = sections(in: library, order: order, now: library.now()).first?.items.first
        selectAutomatically(first.map { [$0.id] } ?? [])
    }

    /// Moves the selection as the app does, not as the person chose, so Back does not stop there.
    func selectAutomatically(_ ids: Set<ItemID>) {
        isSelectingAutomatically = true
        defer { isSelectingAutomatically = false }
        selection = ids
    }

    /// Whether the selection follows the items the window's layout holds as they change: a layout that spans the window
    /// has no list to do it, and nor has a full page opened from the list, which takes the list's place.
    var followsCollection: Bool { usesCollection || isCollectionItemPresented }

    /// Keeps the selection true as the items the window holds change (`collectionItemIDs`), while it follows them.
    func collectionItemsChanged(from old: [ItemID], to new: [ItemID]) {
        guard followsCollection else { return }
        keepSelection(from: old, to: new)
    }

    /// The items the layout that spans the window holds, which its selection follows as they change (`keepSelection`):
    /// the table's in the order it shows them, then those its filters hide, and the gallery's, the board's and the
    /// timeline's in the list's order, which is also the order of a full page opened from the list. The table's come from
    /// its own content, so a move between its places sorts no list. Items' are its table's (`itemIndexIDs`).
    func collectionItemIDs(in library: any ItemLibrary, order: ItemOrder) -> [ItemID] {
        guard followsCollection else { return [] }
        // Items has no layout: a full page opened from it follows the rows of its table.
        if item == .allItems { return itemIndexIDs(in: library) }
        guard !showsSidebarIndex else { return [] }
        guard viewMode == .table else {
            let shown = sections(in: library, order: order, now: library.now()).flatMap { $0.items.map(\.id) }
            // The items the filters and the hidden groups leave out stay in the selection's reach, as the table's do.
            let rest: [ItemID]
            if listShape?.arranged == true, !ordersByRelevance {
                rest = tableContent(in: library).allRows.map(\.id)
            } else if tableOptions[item]?.isFiltering == true {
                rest = items(in: library).map(\.id)
            } else {
                return shown
            }
            let isShown = Set(shown)
            return shown + rest.filter { !isShown.contains($0) }
        }
        let content = tableContent(in: library)
        // A grouped table shows its rows group by group, not in the sort's order across groups.
        let shown = (content.grouping == nil ? content.rows : content.groups.flatMap(\.rows)).map(\.id)
        let isShown = Set(shown)
        return shown + content.allRows.map(\.id).filter { !isShown.contains($0) }
    }

    /// Keeps the selection in the list after items leave it or the search changes it (see `selection(_:keptFrom:in:)`).
    ///
    /// A search not yet answered shows nothing, which says nothing about the selection: it is held, and the answer is
    /// compared with the list as it stood before the search.
    func keepSelection(from old: [ItemID], to new: [ItemID], isPending: Bool = false) {
        if isPending {
            listBeforePendingSearch = listBeforePendingSearch ?? old
            return
        }
        let before = listBeforePendingSearch ?? old
        listBeforePendingSearch = nil
        let kept = Self.selection(selection, keptFrom: before, in: new)
        if kept != selection { selectAutomatically(kept) }
    }

    /// Compares the answer of a search with the list before it, when the answer arrives without changing the list,
    /// as one that finds nothing does after a list that showed nothing while it waited.
    func keepHeldSelection(in list: [ItemID]) {
        guard listBeforePendingSearch != nil else { return }
        keepSelection(from: list, to: list)
    }

    /// A place that is gone can no longer be shown, so the window moves to where `placeFallback(in:)` says.
    func placeRemoved(in library: any ItemLibrary, order: ItemOrder) {
        if let place = placeFallback(in: library) { show(place, in: library, order: order) }
    }

    /// Where the window should go instead, when the place it shows has gone; nil while the place stands. Reading it
    /// observes what a place's existence depends on (membership and the saved views), so a view that only asks this
    /// is told when the answer may have changed, and reads no list of the library's items to find out.
    func placeFallback(in library: any ItemLibrary) -> SidebarItem? {
        guard library.isLoaded else { return nil }
        switch sidebarItem {
        case .collection(let id):
            // A collection's state is part of membership, which `item(_:)` follows only once the item is missing.
            _ = library.membershipRevision
            return library.item(id)?.state != .active ? .allItems : nil
        // A type is in the sidebar while it holds an item, so one whose last item went has no row to stay on.
        case .itemType(let type):
            return library.count(in: .itemType(type)) == 0 ? .allItems : nil
        case .view(let id):
            return library.views.contains { $0.id == id } ? nil : .allItems
        case .favoriteItem(let id):
            _ = library.membershipRevision
            return library.item(id).map({ $0.state == .active && $0.isFavorite }) == true ? nil : .favorites
        default:
            return nil
        }
    }

    // MARK: Keeping the selection in the list

    /// When selected items leave the list (deleted, moved elsewhere, filtered out by a search), the selection
    /// keeps whichever are still there. If none are, it moves to the item that followed them, or failing that
    /// the one before, as Notes and Mail do.
    static func selection(_ selection: Set<ItemID>, keptFrom old: [ItemID], in new: [ItemID]) -> Set<ItemID> {
        let visible = Set(new)
        let kept = selection.intersection(visible)
        guard kept.isEmpty, let first = old.firstIndex(where: selection.contains) else { return kept }
        let candidates = old[first...].dropFirst() + old[..<first].reversed()
        return candidates.first { visible.contains($0) && !selection.contains($0) }.map { [$0] } ?? []
    }
}
