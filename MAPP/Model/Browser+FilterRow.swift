import Foundation

/// The row of filters above the list: whether the window shows it, and the request to add a filter, which the row
/// answers by opening its Add Filter panel. Whether the row shows is the window's, and is never saved with a view.
extension Browser {
    /// Whether the row shows. A saved view opens with it hidden, since the count on the View Options button says filters
    /// apply, and any other place shows it whenever it holds a filter, until the person hides it.
    var showsFilterRow: Bool {
        if let choice = filterRowChoice[item] { return choice }
        if case .view = item { return false }
        if item == .collections { return !collectionSourceFilter.isEmpty }
        return tableOptions[item]?.isFiltering == true
    }

    /// What the command that shows or hides the row is called now.
    var toggleFiltersTitle: LocalizedStringResource {
        showsFilterRow ? "Hide Filters" : "Show Filters"
    }

    /// How many filters the open place holds.
    var filterCount: Int {
        tableOptions[item]?.filter.complete.clauses.count ?? 0
    }

    /// View Options' and the View menu's Show Filters and Hide Filters.
    func toggleFilterRow() {
        filterRowChoice[item] = !showsFilterRow
    }

    /// Add Filter…: shows the row and asks it to open its panel.
    func requestAddFilter() {
        filterRowChoice[item] = true
        isAddFilterRequested = true
    }

    /// Adds a filter on a field with the operator the field starts with, and returns its place in the row. It says too little
    /// to filter by until the person gives it a value, so it hides nothing and is dropped if they leave it so
    /// (`dropUnfinishedFilters`).
    @discardableResult
    func addFilter(on target: FilterTarget) -> Int {
        filterRowChoice[item] = true
        var options = tableOptions[item] ?? ItemTableOptions()
        options.filter.clauses.append(FilterClause(field: target.id, op: target.kind.startingOperator))
        tableOptions[item] = options
        return options.filter.clauses.count - 1
    }

    /// Changes one clause of the row, keeping the row in view.
    func changeFilter(at index: Int, _ change: (inout FilterClause) -> Void) {
        guard var options = tableOptions[item], options.filter.clauses.indices.contains(index) else { return }
        filterRowChoice[item] = true
        change(&options.filter.clauses[index])
        tableOptions[item] = options
    }

    /// Gives a clause another operator. The values stay where the new operator asks for the same kind of value (is and is
    /// not, before and after) and start again where it does not.
    func setFilterOperator(at index: Int, to op: FilterOp, kind: FilterKind) {
        // A text's is and is not take one text, as its other operators do.
        func shape(_ op: FilterOp) -> FilterOp.ValueShape { kind == .text && op.valueShape == .set ? .single : op.valueShape }
        changeFilter(at: index) { clause in
            let kept = shape(clause.op) == shape(op)
            clause.op = op
            if !kept {
                clause.values = op.valueShape == .range ? [clause.values.first ?? ""].filter { !$0.isEmpty } : []
                if op.valueShape == .count { clause.values = ["7"] }
            }
        }
    }

    /// Removes one filter.
    func removeFilter(at index: Int) {
        guard var options = tableOptions[item], options.filter.clauses.indices.contains(index) else { return }
        options.filter.clauses.remove(at: index)
        if options.filter.clauses.count < 2 { options.filter.matchesAny = false }
        tableOptions[item] = options
    }

    /// Drops the filters that still ask for a value, once their panel is closed.
    func dropUnfinishedFilters() {
        guard var options = tableOptions[item], options.filter.clauses.contains(where: { !$0.isComplete }) else { return }
        options.filter.clauses.removeAll { !$0.isComplete }
        if options.filter.clauses.count < 2 { options.filter.matchesAny = false }
        tableOptions[item] = options
    }

    /// Whether an item needs to meet every filter or any one of them.
    func setFiltersMatchAny(_ any: Bool) {
        guard var options = tableOptions[item], options.filter.matchesAny != any else { return }
        options.filter.matchesAny = any
        tableOptions[item] = options
    }

    /// Removes every filter.
    func clearFilters() {
        tableOptions[item, default: .init()].clearFilters()
    }
}
