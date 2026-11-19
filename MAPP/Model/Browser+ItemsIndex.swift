import Foundation

/// The Items index: the table of every item under its tabs, whose chosen row is the window's selection.
extension Browser {
    /// The rows the Items index draws: the tab's rows, or, while searching, what the search found under that tab, in the
    /// order of the page's sort. One answer for the page and for the modal's arrows, so they never disagree.
    func itemIndexRows(in library: any ItemLibrary) -> [ItemIndexRow] {
        let tab = IndexPreferences.tab(for: .items, in: defaults)
        guard isSearching else { return itemIndex.tabs?.rows(for: tab) ?? [] }
        return searchedItemTabs(in: library).rows(for: tab)
    }

    /// What the search finds, under each tab. A search lists at most `SearchResults.limit` items, so these are worked
    /// out on the spot.
    func searchedItemTabs(in library: any ItemLibrary) -> ItemIndexTabs {
        guard let found = searchResults(in: library)?.items, !found.isEmpty else { return .empty }
        let rows = ItemIndexRows.rows(of: found, catalogue: library.catalogue, directory: library.sources)
        return ItemIndexRows.arranged(rows, by: IndexPreferences.sort(for: .items, in: defaults))
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
