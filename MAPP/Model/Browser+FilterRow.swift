import Foundation

/// The row of filters above the list: whether the window shows it, and the request to add a filter, which the row
/// answers by opening its Add Filter panel. Whether the row shows is the window's, and is never saved with a view.
extension Browser {
    /// Whether the row shows. A saved view opens with it hidden, since the count on the filter button says filters
    /// apply, and any other place shows it whenever it holds a filter, until the person hides it.
    var showsFilterRow: Bool {
        if let choice = filterRowChoice[item] { return choice }
        if case .view = item { return false }
        return tableOptions[item]?.isFiltering == true
    }

    /// How many filters the open place holds.
    var filterCount: Int {
        tableOptions[item]?.filterChoices.count ?? 0
    }

    /// The filter button and the View menu's Show Filters and Hide Filters.
    func toggleFilterRow() {
        filterRowChoice[item] = !showsFilterRow
    }

    /// Add Filter…: shows the row and asks it to open its panel.
    func requestAddFilter() {
        filterRowChoice[item] = true
        isAddFilterRequested = true
    }

    /// Adds or changes a filter, and keeps the row in view, so a row that held only this filter does not vanish
    /// when it is removed.
    func setFilter(_ column: String, values: Set<String>, negated: Bool? = nil) {
        filterRowChoice[item] = true
        tableOptions[item, default: .init()].setFilter(column, values: values, negated: negated)
    }

    /// Removes one filter.
    func removeFilter(_ column: String) {
        tableOptions[item, default: .init()].clearFilter(column)
    }

    /// Removes every filter.
    func clearFilters() {
        tableOptions[item, default: .init()].clearFilters()
    }
}
