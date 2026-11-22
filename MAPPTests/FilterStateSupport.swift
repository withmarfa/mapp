import Foundation
@testable import MAPP

extension FilterState {
    /// One "is" clause for each field, in field order, for a test that only needs some filter.
    init(is filters: [String: Set<String>]) {
        self.init(clauses: filters.keys.sorted().map { FilterClause(field: $0, op: .is, values: Array(filters[$0]!)) })
    }

    /// The values each field's clauses hold, whatever their operator.
    var valuesByField: [String: Set<String>] {
        clauses.reduce(into: [:]) { $0[$1.field, default: []].formUnion($1.values) }
    }
}

extension Browser {
    /// Gives a field the one filter of "is" or "is not" these values, or none where there are none, as a chip of the first
    /// kind the row had.
    func setFilter(_ field: String, values: Set<String>, negated: Bool? = nil) {
        var options = tableOptions[item] ?? ItemTableOptions()
        let held = options.filter.clauses.first { $0.field == field }
        options.filter.clauses.removeAll { $0.field == field }
        if !values.isEmpty {
            let isNot = negated ?? (held?.op == .isNot)
            options.filter.clauses.append(FilterClause(field: field, op: isNot ? .isNot : .is, values: Array(values)))
        }
        tableOptions[item] = options
    }
}
