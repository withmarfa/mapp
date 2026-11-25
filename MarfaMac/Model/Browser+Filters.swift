import Foundation

/// The open place's filters, as the View panel's Filter and the search field's tokens change them. Each change goes
/// through the window's choices (`choicesChanged`), so it is one step of Undo and, in a saved view, written as made.
extension Browser {
    /// How many filters the open place holds.
    var filterCount: Int {
        tableOptions[shown]?.filter.complete.clauses.count ?? 0
    }

    /// Adds a filter on a field with the operator the field starts with, and returns its place among the conditions. With
    /// no `values` it says too little to filter by until the person gives it one, so it hides nothing and is dropped if
    /// they leave it so (`dropUnfinishedFilters`).
    @discardableResult
    func addFilter(on target: FilterTarget, values: [String] = []) -> Int {
        var options = tableOptions[shown] ?? ItemTableOptions()
        options.filter.clauses.append(FilterClause(field: target.id, op: target.kind.startingOperator, values: values))
        tableOptions[shown] = options
        return options.filter.clauses.count - 1
    }

    /// Changes one condition.
    func changeFilter(at index: Int, _ change: (inout FilterClause) -> Void) {
        guard var options = tableOptions[shown], options.filter.clauses.indices.contains(index) else { return }
        change(&options.filter.clauses[index])
        tableOptions[shown] = options
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
        guard var options = tableOptions[shown], options.filter.clauses.indices.contains(index) else { return }
        options.filter.clauses.remove(at: index)
        if options.filter.clauses.count < 2 { options.filter.matchesAny = false }
        tableOptions[shown] = options
    }

    /// Drops the filters that still ask for a value, once their panel is closed.
    func dropUnfinishedFilters() {
        guard var options = tableOptions[shown], options.filter.clauses.contains(where: { !$0.isComplete }) else { return }
        options.filter.clauses.removeAll { !$0.isComplete }
        if options.filter.clauses.count < 2 { options.filter.matchesAny = false }
        tableOptions[shown] = options
    }

    /// Whether an item needs to meet every filter or any one of them.
    func setFiltersMatchAny(_ any: Bool) {
        guard var options = tableOptions[shown], options.filter.matchesAny != any else { return }
        options.filter.matchesAny = any
        tableOptions[shown] = options
    }

    /// Removes every filter.
    func clearFilters() {
        tableOptions[shown, default: .init()].clearFilters()
    }
}
