import Foundation

/// The pages of the table a window has loaded (`TablePaging`).
extension Browser {
    private var pagingKey: TablePagingKey {
        TablePagingKey(place: item, search: searchText, byRelevance: ordersByRelevance, options: tableOptions[item] ?? ItemTableOptions())
    }

    /// The pages loaded for what the table shows now: one again whenever the place, the search, the order, the
    /// filters, the grouping or the page size has changed since they were asked for.
    var tablePaging: TablePaging {
        guard let held = pagingState, held.key == pagingKey else { return TablePaging() }
        return held.paging
    }

    var tablePageSize: TablePageSize { tableOptions[item]?.pageSize ?? .standard }

    /// Adds a page to the whole table, or to one group of it.
    func loadMoreTableRows(group: String? = nil) {
        var paging = tablePaging
        paging.loadMore(group: group)
        pagingState = (pagingKey, paging)
    }

    /// How many rows the table holds that are not loaded yet, counting the groups the person has not folded away.
    func tableRowsNotLoaded(in content: ItemTableContent) -> Int {
        let (paging, size) = (tablePaging, tablePageSize)
        guard content.grouping != nil else { return paging.slice(content.rows, size: size).remaining }
        return content.groups.filter { !content.collapsed.contains($0.id) }
            .reduce(0) { $0 + paging.slice($1.rows, size: size, group: $1.id).remaining }
    }

    /// Loads the next page of the whole table, or of every group that has rows left.
    func loadMoreTableRows(in content: ItemTableContent) {
        guard content.grouping != nil else { return loadMoreTableRows() }
        var paging = tablePaging
        for group in content.groups where !content.collapsed.contains(group.id)
            && paging.slice(group.rows, size: tablePageSize, group: group.id).remaining > 0 {
            paging.loadMore(group: group.id)
        }
        pagingState = (pagingKey, paging)
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
