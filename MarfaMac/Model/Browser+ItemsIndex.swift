import Foundation

/// The Items index: the table of every item under its tabs, whose chosen row is the window's selection.
extension Browser {
    /// The rows the Items index draws: the tab's rows, or, while searching, what the search found under that tab. One
    /// answer for the page and for the modal's arrows, so they never disagree.
    func itemIndexRows(in library: any ItemLibrary) -> [ItemIndexRow] {
        let tab = IndexPreferences.tab(for: .items, in: defaults)
        return itemIndexTabs(in: library)?.rows(for: tab) ?? []
    }

    /// The items an item's full page opened from Items follows, as they change: the tab's rows in the table's order, then
    /// the rest, so an item that moves to the other tier is still the one shown.
    func itemIndexIDs(in library: any ItemLibrary) -> [ItemID] {
        let tab = IndexPreferences.tab(for: .items, in: defaults)
        let tabs = itemIndexTabs(in: library) ?? .empty
        let shown = tabs.rows(for: tab).map(\.id)
        guard tab != .all else { return shown }
        let isShown = Set(shown)
        return shown + tabs.all.map(\.id).filter { !isShown.contains($0) }
    }

    /// What the search finds, under each tab: in the library's relevance order, until the person orders by a column
    /// (`ordersByRelevance`), then in the page's sort. A search lists at most `SearchResults.limit` items, so these are
    /// worked out on the spot.
    func searchedItemTabs(in library: any ItemLibrary) -> ItemIndexTabs {
        guard let found = searchResults(in: library)?.items, !found.isEmpty else { return .empty }
        let rows = ItemIndexRows.rows(of: found, catalogue: library.catalogue, directory: library.sources)
        guard !ordersByRelevance else { return ItemIndexRows.split(rows) }
        return ItemIndexRows.arranged(rows, by: IndexPreferences.sort(for: .items, in: defaults))
    }

    /// Shows an item's row on Items: under All where the tab chosen lists only the other tier, and scrolled into view
    /// once the page has it (`itemToScrollTo`).
    func revealOnItems(_ item: Item) {
        if !IndexPreferences.tab(for: .items, in: defaults).includes(tier: item.tier) {
            IndexPreferences.set(.all, for: .items, in: defaults)
        }
        itemToScrollTo = item.id
    }

    /// Keeps the chosen item to one the library still holds and has not deleted, so the right sidebar never points at an
    /// item that is gone, deleted here or by another app. An item that moved to the other tier stays chosen, as the tab or
    /// the search leaving an item out does. Where the library has not loaded, nothing is known to be gone.
    func keepItemChoice(in library: any ItemLibrary) {
        guard showsItemsIndex, library.isLoaded else { return }
        let kept = selection.filter { id in library.item(id).map { $0.state != .trashed } ?? false }
        if kept != selection { selectAutomatically(kept) }
    }
}
