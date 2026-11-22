import Foundation

/// What a field's values are, for the filter that asks about them: which operators it takes and which control picks its value.
nonisolated enum FilterKind: Hashable, Sendable {
    /// A status field: words, and Marfa's four groups of them.
    case status
    /// A choice or priority: one of the options the type declares.
    case choice
    case boolean
    /// A date field of a type, or a day or an instant.
    case date
    case number
    /// Text, a link or an email address.
    case text
    /// A list of entries, found by one member's value, such as a person's name.
    case people
    case tags
    case parent
    case collection
    case type
    case source
    /// Created, Edited and Happened: instants every item has, so none is ever empty.
    case moment

    /// Whether the field's values are a closed set the type declares, so a chip of several "is" values can be saved as
    /// "is not" the others.
    var isClosed: Bool {
        switch self {
        case .status, .choice, .boolean: true
        default: false
        }
    }

    /// The operator a new filter on the field starts with.
    var startingOperator: FilterOp {
        switch self {
        case .status, .choice, .boolean, .parent, .collection, .type, .source: .is
        case .date, .moment: .before
        case .number: .equal
        case .text: .contains
        case .people, .tags: .includes
        }
    }

    /// Whether the kind compares instants.
    var isDated: Bool { self == .date || self == .moment }
}

/// What a filter says of its field.
nonisolated enum FilterOp: String, Codable, Hashable, Sendable, CaseIterable {
    case `is`, isNot
    /// A person or tag among those the item holds; one or more, any of which will do.
    case includes
    case isSet, isEmpty
    case on, before, after, between
    case beforeToday, afterToday, inLast, inNext
    case equal, notEqual, less, lessOrEqual, greater, greaterOrEqual
    case contains, startsWith

    /// A date relative to the day it is worked out on, which only this Mac keeps (`FilterClause.isRelative`).
    var isRelative: Bool {
        switch self {
        case .beforeToday, .afterToday, .inLast, .inNext: true
        default: false
        }
    }

    /// Whether the operator asks for a value of its own.
    var takesValue: Bool {
        switch self {
        case .isSet, .isEmpty, .beforeToday, .afterToday: false
        default: true
        }
    }

    /// What kind of value the operator asks for, so a change of operator keeps the value where the shape is the same.
    enum ValueShape { case none, set, day, range, count, single }

    var valueShape: ValueShape {
        switch self {
        case .isSet, .isEmpty, .beforeToday, .afterToday: .none
        case .includes: .set
        case .is, .isNot: .set
        case .on, .before, .after: .day
        case .between: .range
        case .inLast, .inNext: .count
        case .equal, .notEqual, .less, .lessOrEqual, .greater, .greaterOrEqual, .contains, .startsWith: .single
        }
    }

    /// Whether values are a set the person picks from, which a chip joins by OR (by AND where they are left out).
    var isSetOfValues: Bool { self == .is || self == .isNot || self == .includes }

    /// The operators a kind takes, in the order its pop-up lists them; a divider comes where `startsSection` is set.
    static func offered(for kind: FilterKind) -> [(op: FilterOp, startsSection: Bool)] {
        func list(_ ops: FilterOp...) -> [(FilterOp, Bool)] { ops.map { ($0, false) } }
        switch kind {
        case .status, .choice, .boolean, .parent, .collection, .type, .source:
            let presence: [FilterOp] = kind == .type || kind == .source ? [] : [.isSet, .isEmpty]
            return list(.is, .isNot) + presence.enumerated().map { ($1, $0 == 0) }
        case .date, .moment:
            var ops: [(FilterOp, Bool)] = list(.on, .before, .after, .between)
            if kind == .date { ops += [(.isSet, true), (.isEmpty, false)] }
            return ops + [(.beforeToday, true), (.afterToday, false), (.inLast, false), (.inNext, false)]
        case .number:
            return list(.equal, .notEqual, .less, .lessOrEqual, .greater, .greaterOrEqual) + [(.isSet, true), (.isEmpty, false)]
        case .text:
            return list(.contains, .startsWith, .is, .isNot) + [(.isSet, true), (.isEmpty, false)]
        case .people, .tags:
            return list(.includes) + [(.isSet, true), (.isEmpty, false)]
        }
    }

    /// What a chip says between the field and the values: "is before", "include".
    func word(for kind: FilterKind) -> String {
        switch self {
        case .is: String(localized: "is")
        case .isNot: String(localized: "is not")
        case .includes: String(localized: "include")
        case .isSet:
            switch kind {
            case .tags: String(localized: "has any")
            case .parent: String(localized: "has one")
            case .collection: String(localized: "is in any")
            default: String(localized: "is set")
            }
        case .isEmpty:
            switch kind {
            case .tags: String(localized: "has none")
            case .parent: String(localized: "has none")
            case .collection: String(localized: "is in none")
            default: String(localized: "is empty")
            }
        case .on: String(localized: "is on")
        case .before: String(localized: "is before")
        case .after: String(localized: "is after")
        case .between: String(localized: "is between")
        case .beforeToday: String(localized: "is before today")
        case .afterToday: String(localized: "is after today")
        case .inLast: String(localized: "is in the last")
        case .inNext: String(localized: "is in the next")
        case .equal: "="
        case .notEqual: "≠"
        case .less: "<"
        case .lessOrEqual: "≤"
        case .greater: ">"
        case .greaterOrEqual: "≥"
        case .contains: String(localized: "contains")
        case .startsWith: String(localized: "starts with")
        }
    }

    /// The operator's name in the pop-up, where it reads fuller than the chip: "is in the last…".
    func menuTitle(for kind: FilterKind) -> String {
        switch self {
        case .inLast: String(localized: "is in the last…")
        case .inNext: String(localized: "is in the next…")
        case .equal: String(localized: "is equal to")
        case .notEqual: String(localized: "is not equal to")
        case .less: String(localized: "is less than")
        case .lessOrEqual: String(localized: "is at most")
        case .greater: String(localized: "is greater than")
        case .greaterOrEqual: String(localized: "is at least")
        default: word(for: kind)
        }
    }
}

/// One condition of the filter row, as a chip shows it: a field, an operator and its values. Several may name one field.
nonisolated struct FilterClause: Hashable, Sendable, Codable {
    /// The field's identifier: a column's (`field.due_at`, `type`, `parent`, `tags`, `collections`, `created`, `edited`,
    /// `occurred`), or `source`.
    var field: String
    var op: FilterOp
    /// What the operator asks for, as text:
    /// - a set of values: each word or id, in order; the empty string is "no value", and a status group is written
    ///   `group:<name>` (`groupValue`);
    /// - a date: a day, `YYYY-MM-DD`, or two for between; a day's count for the last or the next;
    /// - a number or a text: the one value.
    var values: [String] = []

    static let groupPrefix = "group:"

    static func groupValue(_ group: StatusGroup) -> String { groupPrefix + group.rawValue }

    /// The group a value names, where it names one.
    static func group(of value: String) -> StatusGroup? {
        value.hasPrefix(groupPrefix) ? StatusGroup(rawValue: String(value.dropFirst(groupPrefix.count))) : nil
    }

    init(field: String, op: FilterOp, values: [String] = []) {
        self.field = field
        self.op = op
        self.values = op.isSetOfValues ? Self.normalized(values) : values
    }

    /// The values of a set in one order, so two clauses that hold the same values are equal.
    private static func normalized(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }

    /// Whether the clause says enough to filter by: an operator that asks for a value has one.
    var isComplete: Bool {
        guard op.takesValue else { return true }
        switch op {
        case .is, .isNot, .includes: return !values.isEmpty
        case .between: return values.count == 2 && !values.contains { $0.isEmpty }
        case .inLast, .inNext: return values.first.flatMap { Int($0) }.map { $0 > 0 } ?? false
        case .contains, .startsWith: return values.first?.isEmpty == false
        case .equal, .notEqual, .less, .lessOrEqual, .greater, .greaterOrEqual: return values.first.flatMap(Self.number) != nil
        default: return values.first?.isEmpty == false
        }
    }

    /// Whether it is relative to the day, which a saved view cannot hold.
    var isRelative: Bool { op.isRelative }

    /// The number a value holds, written with a point or the person's own separator.
    static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let value = Double(trimmed), value.isFinite { return value }
        if let value = try? Double(trimmed, format: .number), value.isFinite { return value }
        return nil
    }

    func adding(_ value: String) -> FilterClause {
        var clause = self
        clause.values = op.isSetOfValues ? Self.normalized(values + [value]) : values + [value]
        return clause
    }

    func removing(_ value: String) -> FilterClause {
        var clause = self
        clause.values.removeAll { $0 == value }
        return clause
    }
}

/// The filters a place holds: its clauses and whether any one of them or all of them must hold.
nonisolated struct FilterState: Hashable, Sendable {
    var clauses: [FilterClause] = []
    /// Whether an item needs to match only one clause, which a saved view holds as a filter joined by OR.
    var matchesAny = false

    var isEmpty: Bool { clauses.isEmpty }

    /// The clauses that say enough to filter by.
    var complete: FilterState {
        FilterState(clauses: clauses.filter(\.isComplete), matchesAny: matchesAny && clauses.filter(\.isComplete).count > 1)
    }

    /// What a saved view can keep: the clauses that are not relative to the day.
    var savable: FilterState {
        let kept = complete.clauses.filter { !$0.isRelative }
        return FilterState(clauses: kept, matchesAny: matchesAny && kept.count > 1)
    }

    /// The relative clauses, which only this Mac keeps.
    var relative: [FilterClause] { complete.clauses.filter(\.isRelative) }
}
