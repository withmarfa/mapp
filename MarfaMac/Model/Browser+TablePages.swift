import Foundation

/// The pages of the table a window has loaded (`TablePaging`).
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

    /// How many rows the table holds that are not loaded yet, counting the groups the person has not folded away.
    func tableRowsNotLoaded(in content: ItemTableContent) -> Int {
        let (paging, size) = (tablePaging, tablePageSize)
        guard content.grouping != nil else { return paging.slice(content.rows, size: size).remaining }
        return paging.slice(groups: content.groups, collapsed: content.collapsed, size: size).remaining
    }

    /// Loads the next page of the place.
    func loadMoreTableRows(in content: ItemTableContent) {
        guard tableRowsNotLoaded(in: content) > 0 else { return }
        loadMoreTableRows()
    }

    /// Loads enough pages to show the selected items the table holds, such as one reached by Back, a link or a new
    /// item. Nothing changes when they are all shown already.
    func revealSelectionInTable(_ content: ItemTableContent) {
        var paging = tablePaging
        paging.reveal(
            selection, rows: content.rows, groups: content.grouping == nil ? nil : content.groups,
            collapsed: content.collapsed, size: tablePageSize)
        if paging != tablePaging { pagingState = (pagingKey, paging) }
    }
}
