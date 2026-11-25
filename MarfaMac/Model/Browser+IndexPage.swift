import Foundation

/// What the index pages (Items, Collections and Sources) share beyond their tables: the tabs' toolbar items that come in
/// once the title scrolls away, the filter the page holds and the rows it leaves out.
extension Browser {
    /// Whether the tabs and their buttons are in the window's toolbar: the page's title and tabs have scrolled away.
    var showsIndexTools: Bool { showsSidebarIndex && isIndexHeaderAway }

    /// Whether the page offers Search, Filter and New: Collections and Items do, Sources lists only its tabs.
    var indexPlaceHasTools: Bool { indexPlace != .sources }

    /// Whether a filter is set on the page.
    var indexIsFiltered: Bool {
        switch indexPlace {
        case .items: tableOptions[.library]?.isFiltering == true
        case .collections: !collectionSourceFilter.isEmpty
        default: false
        }
    }

    /// Whether the New row's tiles show: Items has them, and while its filter row shows the row takes their place.
    var showsNewRow: Bool { indexPlace == .items && !showsFilterRow }

    /// Filter on the page's button: shows or hides the row. Turning it off drops the filters, so the table never keeps
    /// narrowing without a row to say so.
    func toggleIndexFilter() {
        toggleFilterRow()
        if !showsFilterRow { clearIndexFilters() }
    }

    /// Removes every filter the page holds.
    func clearIndexFilters() {
        collectionSourceFilter = []
        if tableOptions[.library]?.isFiltering == true { tableOptions[.library, default: .init()].clearFilters() }
    }

    /// The tabs of the Items page: the library's, or what the search found, less what the filters hide.
    func itemIndexTabs(in library: any ItemLibrary) -> ItemIndexTabs? {
        guard let tabs = isSearching ? searchedItemTabs(in: library) : itemIndex.tabs else { return nil }
        guard showsItemsIndex, tableOptions[shown]?.isFiltering == true else { return tabs }
        let kept = Set(tableContent(in: library).kept.map(\.item.id))
        return tabs.keeping { kept.contains($0.id) }
    }

    /// Adds or removes one source from the Collections filter, by name.
    func toggleCollectionSource(_ name: String) {
        filterRowChoice[.collections] = true
        if collectionSourceFilter.contains(name) { collectionSourceFilter.remove(name) } else { collectionSourceFilter.insert(name) }
    }
}

extension Browser {
    /// The page's New: a new item on Items, starting from the type last made; a new collection on Collections.
    func openQuickAddFromIndex(remembered: String, in library: any ItemLibrary) {
        openQuickAdd(remembered: indexPlace == .items ? remembered : nil, in: library)
    }
}
