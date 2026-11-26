import Foundation

/// The pages of the table a window has loaded (`TablePaging`), and how much of a long list or timeline it draws.
extension Browser {
    private var pagingKey: TablePagingKey {
        TablePagingKey(place: shown, search: searchText, byRelevance: ordersByRelevance, options: tableOptions[shown] ?? ItemTableOptions())
    }

    /// The pages loaded for what the table shows now: one again whenever the place, the search, the order, the
    /// filters, the grouping or the page size has changed since they were asked for.
    var tablePaging: TablePaging {
        guard let held = pagingState, held.key == pagingKey else { return TablePaging() }
        return held.paging
    }

    var tablePageSize: TablePageSize { tableOptions[shown]?.pageSize ?? .standard }

    /// Adds a page to the place, grouped or not.
    func loadMoreTableRows() {
        var paging = tablePaging
        paging.loadMore()
        pagingState = (pagingKey, paging)
    }

    /// How many rows the table holds that are not loaded yet, counting the groups the person has not folded away and the
    /// sub-items of the parents open.
    func tableRowsNotLoaded(in content: ItemTableContent) -> Int {
        let (paging, size) = (tablePaging, tablePageSize)
        guard content.grouping != nil else {
            return paging.slice(content.rows, nesting: content.nesting, expanded: expandedHere, size: size).remaining
        }
        return paging.slice(
            groups: content.groups, nestings: content.groupNestings, collapsed: content.collapsed, expanded: expandedHere, size: size
        ).remaining
    }

    /// The parents whose sub-items the place shows (`expandedRows`).
    var expandedHere: Set<ItemID> { expandedRows[shown] ?? [] }

    /// Shows or hides the sub-items of `id` in the place, as the table or the list nests them (`subItemNestings`). A chosen
    /// item the closing hides leaves the choice, which moves to `id` where nothing else stays chosen, so no command acts on
    /// an item out of sight.
    func toggleSubItems(of id: ItemID, in library: any ItemLibrary, order: ItemOrder) {
        var open = expandedHere
        if open.remove(id) == nil {
            open.insert(id)
        } else {
            let nestings = subItemNestings(in: library, order: order)
            let hidden = selection.filter { chosen in nestings.contains { $0.ancestors(of: chosen).contains(id) } }
            if !hidden.isEmpty {
                let kept = selection.subtracting(hidden)
                selectAutomatically(kept.isEmpty ? [id] : kept)
            }
        }
        expandedRows[shown] = open
    }

    /// The nestings the place's layout draws its items by: the table's, or the list's sections'.
    func subItemNestings(in library: any ItemLibrary, order: ItemOrder) -> [ItemNesting] {
        viewMode == .table ? tableContent(in: library).nestings : arrangement(in: library, order: order, now: library.now()).nestings
    }

    /// Opens every parent above the chosen items in `nestings`, so a sub-item reached by Back, a link or a new item is
    /// drawn, in the table and the list alike.
    func openParents(of ids: Set<ItemID>, in nestings: [ItemNesting]) {
        guard !ids.isEmpty, nestings.contains(where: { !$0.isFlat }) else { return }
        var open = expandedHere
        for id in ids {
            for nesting in nestings where !nesting.isFlat { open.formUnion(nesting.ancestors(of: id)) }
        }
        if open != expandedHere { expandedRows[shown] = open }
    }

    /// Loads the next page of the place.
    func loadMoreTableRows(in content: ItemTableContent) {
        guard tableRowsNotLoaded(in: content) > 0 else { return }
        loadMoreTableRows()
    }

    /// Loads enough pages to show the selected items the table holds, such as one reached by Back, a link or a new
    /// item. Nothing changes when they are all shown already.
    func revealSelectionInTable(_ content: ItemTableContent) {
        openParents(of: selection, in: content.nestings)
        var paging = tablePaging
        paging.reveal(
            selection, rows: content.rows, nesting: content.nesting, groups: content.grouping == nil ? nil : content.groups,
            nestings: content.groupNestings, collapsed: content.collapsed, expanded: expandedHere, size: tablePageSize)
        if paging != tablePaging { pagingState = (pagingKey, paging) }
    }

    /// How many items a paged layout adds as its end comes into view. SwiftUI goes through every
    /// row it is given at each change, so a place of tens of thousands of items is drawn a page at a time.
    nonisolated static let listPage = 250

    /// Which items the list, the gallery or the timeline draws: a page again whenever the place, the search, the order, the
    /// filters or the grouping has changed since more were drawn.
    var listDrawn: ListDrawn {
        guard let held = listPagingState, held.key == pagingKey else {
            // Native lists visit every row they are first given, even below the window.
            let count: Int
            switch viewMode {
            case .list: count = sectionsWork.held?.value.ids.count ?? 0
            case .timeline: count = timelineWork.held?.value.positions.count ?? 0
            default: count = 0
            }
            return ListDrawn(head: count > Self.arrangesAlongsideAbove ? 40 : Self.listPage)
        }
        return held.drawn
    }

    /// Draws another page after the run of items whose end came into view (`ListDrawn.Part.run`).
    func drawMoreOfList(after run: Int = 0) {
        var drawn = listDrawn
        drawn.drawMore(after: run)
        listPagingState = (pagingKey, drawn)
    }

    /// Draws the item at `position`, such as one reached by Back, a link or a new item, or one a change moved: the pages up
    /// to it where it stands just past them, else a page around it.
    func drawList(showing position: Int) {
        var drawn = listDrawn
        drawn.show(position)
        if drawn != listDrawn { listPagingState = (pagingKey, drawn) }
    }
}
