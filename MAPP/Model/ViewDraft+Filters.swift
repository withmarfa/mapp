import Foundation
import Marfa

/// How the filter row's clauses become the conditions of a saved view's `query.filter`, and a view's conditions the
/// row's clauses. The core writes and reads the grammar (`FilterExpression`), so nothing here quotes or escapes a value.
///
/// A clause becomes a piece: the conditions it takes and how they join among themselves (a chip of several "is" values is
/// OR, one of several "is not" values is AND, a date's bounds are AND). The pieces join by AND, or all by OR where the row
/// says Any. Marfa's grammar has no parenthesis, so a combination that needs both joins is not held (`Unkept.mixedFilters`),
/// except where the chip can be said the other way: "is" several words of a closed field is saved as "is not" its other
/// words, which joins by AND.
nonisolated extension ViewDraft {
    /// The field the row stores the Type filter under, which a view also holds as its listed types.
    static let typeFieldID = ItemTableColumn.type.id

    // MARK: Pieces

    /// What one clause says in the grammar, and how those conditions join.
    struct Piece: Hashable {
        var conditions: [FilterCondition]
        var join: FilterJoin = .all
    }

    /// The field a target is filtered by.
    private static func filterField(of target: FilterTarget) -> FilterField? {
        switch target.kind {
        case .type: .system(.type)
        case .source: .system(.source)
        case .parent: .edge(type: MarfaMapping.parentEdge, direction: .backref)
        case .collection: .edge(type: MarfaMapping.collectionEdge, direction: .outbound)
        case .tags: .tags
        case .moment:
            switch target.id {
            case ItemTableColumn.created.id: .system(.createdAt)
            case ItemTableColumn.edited.id: .system(.updatedAt)
            default: .system(.occurredAt)
            }
        default: target.key.flatMap { isPropertyName($0) ? .property($0) : nil }
        }
    }

    /// The clause as conditions, or nil where the grammar cannot say it: a value it cannot write, a field no filter can be
    /// made on, or a date relative to the day.
    static func piece(of clause: FilterClause, target: FilterTarget, calendar person: Calendar) -> Piece? {
        let calendar = FilterDays.calendar(for: target, person: person)
        guard let field = filterField(of: target), !clause.isRelative else { return nil }
        func one(_ op: FilterOperator, _ value: FilterValue? = nil) -> Piece {
            Piece(conditions: [FilterCondition(field: field, operator: op, value: value)])
        }
        let hasPresence = ![FilterKind.moment, .type, .source].contains(target.kind)
        switch clause.op {
        case .isSet: return hasPresence ? one(.exists) : nil
        case .isEmpty: return hasPresence ? one(.notExists) : nil
        case .is, .isNot:
            let negated = clause.op == .isNot
            if target.kind == .text { return clause.values.first.map { one(negated ? .neq : .eq, .text($0)) } }
            let conditions = clause.values.map { setCondition($0, target: target, field: field, negated: negated) }
            guard !conditions.isEmpty, !conditions.contains(nil) else { return nil }
            return Piece(conditions: conditions.compactMap { $0 }, join: negated ? .all : .any)
        case .includes:
            let conditions: [FilterCondition] = clause.values.compactMap { value in
                switch target.kind {
                case .tags: FilterCondition(field: .tags, operator: .contains, value: .text(value))
                case .people:
                    if let key = target.key, let member = target.member, isPropertyName(key), isPropertyName(member) {
                        FilterCondition(field: .member(field: key, member: member), operator: .eq, value: .text(value))
                    } else { nil }
                default: nil
                }
            }
            guard !conditions.isEmpty, conditions.count == clause.values.count else { return nil }
            return Piece(conditions: conditions, join: .any)
        case .on, .before, .after, .between:
            return dateBounds(of: clause, field: field, calendar: calendar)
        case .equal, .notEqual, .less, .lessOrEqual, .greater, .greaterOrEqual:
            guard let number = clause.values.first.flatMap(FilterClause.number) else { return nil }
            let op: FilterOperator = switch clause.op {
            case .equal: .eq
            case .notEqual: .neq
            case .less: .lt
            case .lessOrEqual: .lte
            case .greater: .gt
            default: .gte
            }
            return one(op, .number(number))
        case .contains, .startsWith:
            guard let text = clause.values.first, !text.isEmpty else { return nil }
            return one(clause.op == .contains ? .contains : .startsWith, .text(text))
        case .beforeToday, .afterToday, .inLast, .inNext: return nil
        }
    }

    /// One value of a set as a condition: `eq`, or `neq` where it is left out. "No value" is the absence of the property,
    /// `not_exists`, or `exists` where it is left out. A status group is the group term.
    private static func setCondition(_ value: String, target: FilterTarget, field: FilterField, negated: Bool) -> FilterCondition? {
        if value.isEmpty {
            guard ![FilterKind.type, .source].contains(target.kind) else { return nil }
            return FilterCondition(field: field, operator: negated ? .exists : .notExists)
        }
        let comparison: FilterOperator = negated ? .neq : .eq
        if let group = FilterClause.group(of: value) {
            return target.kind == .status ? FilterCondition(field: .statusGroup, operator: comparison, value: .text(group.rawValue)) : nil
        }
        if target.kind == .boolean {
            return value == "true" || value == "false" ? FilterCondition(field: field, operator: comparison, value: .bool(value == "true")) : nil
        }
        return FilterCondition(field: field, operator: comparison, value: .text(value))
    }

    /// A day, or a run of days, as bounds of the clock `calendar` names: from the first moment of a day to the first moment of
    /// the day after the last, each written with the clock's offset (`filter-property-instant`). That clock is the person's, or
    /// UTC for a date-only field (`FilterDays.calendar(for:person:)`).
    private static func dateBounds(of clause: FilterClause, field: FilterField, calendar: Calendar) -> Piece? {
        func instant(_ date: Date?) -> FilterValue? { date.map { .text(FilterDays.instantText($0, calendar: calendar)) } }
        func condition(_ op: FilterOperator, _ date: Date?) -> FilterCondition? {
            instant(date).map { FilterCondition(field: field, operator: op, value: $0) }
        }
        guard let first = clause.values.first else { return nil }
        let conditions: [FilterCondition?]
        switch clause.op {
        case .on: conditions = [condition(.gte, FilterDays.start(of: first, calendar: calendar)), condition(.lt, FilterDays.startOfNext(first, calendar: calendar))]
        case .before: conditions = [condition(.lt, FilterDays.start(of: first, calendar: calendar))]
        case .after: conditions = [condition(.gte, FilterDays.startOfNext(first, calendar: calendar))]
        case .between:
            guard clause.values.count == 2 else { return nil }
            let (from, to) = clause.values[0] <= clause.values[1] ? (clause.values[0], clause.values[1]) : (clause.values[1], clause.values[0])
            conditions = [condition(.gte, FilterDays.start(of: from, calendar: calendar)), condition(.lt, FilterDays.startOfNext(to, calendar: calendar))]
        default: return nil
        }
        guard !conditions.contains(nil) else { return nil }
        return Piece(conditions: conditions.compactMap { $0 })
    }

    /// The same chip said as "is not" the other values, where it is a closed field's "is" of several words, or several groups:
    /// Marfa joins "is not" by AND, so the chip then sits beside others in one filter. The two select the same items,
    /// except one holding a word its type does not declare: "is not" of the other words keeps it, and of the other groups does not.
    static func complement(of clause: FilterClause, target: FilterTarget, catalogue: Catalogue) -> FilterClause? {
        guard clause.op == .is, target.kind.isClosed, clause.values.count > 1 else { return nil }
        let chosen = Set(clause.values)
        var universe: [String]
        if clause.values.allSatisfy({ FilterClause.group(of: $0) != nil }) {
            guard target.kind == .status else { return nil }
            universe = StatusGroup.allCases.map { FilterClause.groupValue($0) }
        } else if clause.values.contains(where: { $0.isEmpty || FilterClause.group(of: $0) != nil }) {
            return nil
        } else if target.kind == .boolean {
            universe = ["true", "false"]
        } else if let key = target.key {
            // The words of every type that declares the field, in the order the types give them.
            universe = []
            for type in catalogue.itemTypes.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                for word in catalogue.itemTypes[type]?.fields.first(where: { $0.key == key })?.options ?? [] where !word.isEmpty && !universe.contains(word) {
                    universe.append(word)
                }
            }
        } else {
            return nil
        }
        let rest = universe.filter { !chosen.contains($0) }
        guard !rest.isEmpty else { return nil }
        return FilterClause(field: clause.field, op: .isNot, values: rest)
    }

    /// What a clause's field is called where its field is no longer offered: the property's key.
    private static func fieldName(of id: String) -> String {
        id.hasPrefix(Browser.fieldColumnPrefix) ? String(id.dropFirst(Browser.fieldColumnPrefix.count)) : id
    }

    // MARK: Combining

    /// What the clauses become beside a view's own conditions: the filter text, what could not be held, and how many
    /// conditions they take (a chip's every value and a date's every bound count).
    struct Combination {
        var filter: String?
        var unkept: [Unkept]
        var count: Int
    }

    /// The conditions of `base` (the place's or the view's own) with the clauses added. Where nothing is added, `unchanged` is
    /// the filter. A clause that cannot be held is named and left out, never saved wrong; a combination that cannot be
    /// held leaves the filter as it was.
    static func combine(
        base: Parsed, adding state: FilterState, targets: [String: FilterTarget], catalogue: Catalogue, calendar: Calendar = .current,
        keeping unchanged: String?
    ) -> Combination {
        var unkept: [Unkept] = []
        var entries: [(clause: FilterClause, target: FilterTarget, piece: Piece)] = []
        let clauses = state.savable.clauses
        for clause in clauses {
            guard let target = targets[clause.field] else {
                unkept.append(.filter(column: fieldName(of: clause.field)))
                continue
            }
            guard let piece = piece(of: clause, target: target, calendar: calendar) else {
                unkept.append(.filter(column: target.label))
                continue
            }
            entries.append((clause, target, piece))
        }
        let held = base.terms
        let raw = held.count + entries.reduce(0) { $0 + $1.piece.conditions.count }
        guard !entries.isEmpty else { return Combination(filter: unchanged, unkept: unkept, count: held.count) }
        func refused(_ reason: Unkept) -> Combination { Combination(filter: unchanged, unkept: unkept + [reason], count: raw) }

        var pieces = entries.map(\.piece)
        var join = FilterJoin.all
        if state.savable.matchesAny && entries.count > 1 {
            // Every condition by OR: nothing of the view's own can stand beside them, and no chip may need AND inside.
            guard held.isEmpty, pieces.allSatisfy({ $0.conditions.count == 1 || $0.join == .any }) else { return refused(.mixedFilters) }
            join = .any
        } else {
            if held.count > 1, base.join == .any { return refused(.mixedFilters) }
            if held.isEmpty, entries.count == 1, pieces[0].join == .any, pieces[0].conditions.count > 1 {
                join = .any
            } else {
                for index in pieces.indices where pieces[index].join == .any && pieces[index].conditions.count > 1 {
                    guard let other = complement(of: entries[index].clause, target: entries[index].target, catalogue: catalogue),
                          let rewritten = piece(of: other, target: entries[index].target, calendar: calendar) else {
                        return refused(.mixedFilters)
                    }
                    pieces[index] = rewritten
                }
            }
        }
        let conditions = held + pieces.flatMap(\.conditions)
        guard conditions.count <= maxConditions else { return Combination(filter: unchanged, unkept: unkept + [.tooManyFilters], count: conditions.count) }
        do {
            let text = try FilterExpression(join: join, conditions: conditions).encoded()
            return Combination(filter: text, unkept: unkept, count: conditions.count)
        } catch {
            return Combination(filter: unchanged, unkept: unkept + [.refused(message(of: error))], count: conditions.count)
        }
    }

    /// What a row of clauses could not be saved as, named at once: the clauses that need both joins, or more conditions than a
    /// view takes, and those the grammar cannot say.
    static func holdability(
        of state: FilterState, targets: [String: FilterTarget], catalogue: Catalogue, calendar: Calendar = .current
    ) -> Combination {
        combine(base: Parsed(terms: [], join: .all), adding: state, targets: targets, catalogue: catalogue, calendar: calendar, keeping: nil)
    }

    /// Whether this leaves the whole filter unwritable, rather than only one clause's part of it.
    static func refusesFilter(_ unkept: Unkept) -> Bool {
        switch unkept {
        case .mixedFilters, .tooManyFilters, .refused: true
        default: false
        }
    }

    // MARK: Reading

    /// A filter's conditions, in order, and what joins them.
    struct Parsed: Hashable {
        var terms: [FilterCondition]
        var join: FilterJoin
    }

    /// A filter's conditions as the core reads them; throws what it refuses.
    static func terms(of filter: String?) throws -> Parsed {
        guard let filter, !filter.allSatisfy(\.isWhitespace) else { return Parsed(terms: [], join: .all) }
        let expression = try FilterExpression(decoding: filter)
        return Parsed(terms: expression.conditions, join: expression.join)
    }

    /// The text of one condition on its own, or nil where the core refuses it.
    static func text(of condition: FilterCondition) -> String? {
        try? FilterExpression(conditions: [condition]).encoded()
    }

    /// A clause a view's condition stands for, with the conditions that made it.
    struct ReadClause: Hashable {
        var clause: FilterClause
        var conditions: [FilterCondition]
    }

    /// What the window shows of a view's filter: its clauses, and whether any one of them will do.
    struct Reading: Hashable {
        var items: [ReadClause] = []
        var matchesAny = false

        var state: FilterState {
            FilterState(clauses: items.map(\.clause), matchesAny: matchesAny && items.count > 1)
        }

        var shown: [FilterCondition] { items.flatMap(\.conditions) }
    }

    /// The types a view lists and their subtypes, which its filter's fields are looked for in; none where it lists every type.
    static func scope(of query: LibraryViewQuery, catalogue: Catalogue) -> Set<TypeID> {
        Set(query.types).union(query.types.flatMap { catalogue.descendants(of: $0) })
    }

    /// The status field a status group is read as: the first the types give.
    private static func statusTarget(among types: Set<TypeID>, catalogue: Catalogue) -> FilterTarget? {
        let scope = types.isEmpty ? Array(catalogue.itemTypes.keys) : Array(types)
        for type in scope.sorted(by: { $0.rawValue < $1.rawValue }) {
            if let key = catalogue.itemTypes[type]?.statusField?.key, let target = FilterTarget.target(ofProperty: key, among: types, catalogue: catalogue) {
                return target
            }
        }
        return nil
    }

    /// The target a condition's field names, where the window has a filter for it.
    private static func target(of field: FilterField, among types: Set<TypeID>, catalogue: Catalogue) -> FilterTarget? {
        switch field {
        case .system(.type): .type
        case .system(.source): .source
        case .system(.createdAt): .created
        case .system(.updatedAt): .edited
        case .system(.occurredAt): .occurred
        case .tags: .tags
        case .statusGroup: statusTarget(among: types, catalogue: catalogue)
        case .edge(MarfaMapping.parentEdge, .backref): .parent
        case .edge(MarfaMapping.collectionEdge, .outbound): .collection
        case .property(let key): isPropertyName(key) ? FilterTarget.target(ofProperty: key, among: types, catalogue: catalogue) : nil
        case .member(let key, let member):
            FilterTarget.target(ofProperty: key, among: types, catalogue: catalogue).flatMap { $0.kind == .people && $0.member == member ? $0 : nil }
        default: nil
        }
    }

    /// One condition as the clause that says it alone, or nil where the window has no way to show it.
    private static func clause(of condition: FilterCondition, among types: Set<TypeID>, catalogue: Catalogue, calendar person: Calendar) -> (target: FilterTarget, clause: FilterClause)? {
        guard let target = target(of: condition.field, among: types, catalogue: catalogue) else { return nil }
        let calendar = FilterDays.calendar(for: target, person: person)
        func make(_ op: FilterOp, _ values: [String] = []) -> (FilterTarget, FilterClause) { (target, FilterClause(field: target.id, op: op, values: values)) }
        let kind = target.kind
        switch (condition.operator, condition.value) {
        case (.exists, nil):
            return [FilterKind.moment, .type, .source].contains(kind) || condition.field == .statusGroup ? nil : make(.isSet)
        case (.notExists, nil):
            return [FilterKind.moment, .type, .source].contains(kind) || condition.field == .statusGroup ? nil : make(.isEmpty)
        default: break
        }
        switch kind {
        case .status, .choice, .boolean, .type, .parent, .collection, .source:
            let isEqual = condition.operator == .eq
            guard isEqual || condition.operator == .neq else { return nil }
            var word: String?
            switch condition.value {
            case .text(let text)?:
                if condition.field == .statusGroup {
                    word = StatusGroup(rawValue: text).map { FilterClause.groupValue($0) }
                } else if kind != .boolean, !text.isEmpty {
                    word = text
                }
            case .bool(let flag)? where kind == .boolean: word = flag ? "true" : "false"
            default: break
            }
            return word.map { make(isEqual ? .is : .isNot, [$0]) }
        case .text:
            guard case .text(let text)? = condition.value else { return nil }
            switch condition.operator {
            case .contains: return make(.contains, [text])
            case .startsWith: return make(.startsWith, [text])
            case .eq: return make(.is, [text])
            case .neq: return make(.isNot, [text])
            default: return nil
            }
        case .people, .tags:
            guard case .text(let text)? = condition.value, condition.operator == (kind == .tags ? .contains : .eq) else { return nil }
            return make(.includes, [text])
        case .number:
            guard case .number(let number)? = condition.value else { return nil }
            let op: FilterOp? = switch condition.operator {
            case .eq: .equal
            case .neq: .notEqual
            case .lt: .less
            case .lte: .lessOrEqual
            case .gt: .greater
            case .gte: .greaterOrEqual
            default: nil
            }
            let text = number == number.rounded() && abs(number) < 1e15 ? String(Int64(number)) : String(number)
            return op.map { make($0, [text]) }
        case .date, .moment:
            // A bound at the start of the day on the field's clock: "before D" is `lt` it, "after the day before D" is `gte` it.
            guard case .text(let text)? = condition.value, let date = FilterDays.instant(text),
                  calendar.startOfDay(for: date) == date else { return nil }
            let day = FilterDays.text(of: date, calendar: calendar)
            switch condition.operator {
            case .lt: return make(.before, [day])
            case .gte:
                guard let previous = FilterDays.day(day)?.adding(days: -1) else { return nil }
                return make(.after, [previous.text])
            default: return nil
            }
        }
    }

    /// A view's filter as the window's clauses. Conditions joined by AND show where the window has a filter for each: a
    /// closed field's "is not" values are one chip, a day's two bounds one chip. Conditions joined by OR show only where
    /// every one of them does, as one row that matches any: values of one field are one chip. A condition the window cannot
    /// show is not in the reading, which the view keeps as it is.
    static func read(_ parsed: Parsed, among types: Set<TypeID>, catalogue: Catalogue, calendar: Calendar = .current) -> Reading {
        let atoms = parsed.terms.map { condition in clause(of: condition, among: types, catalogue: catalogue, calendar: calendar).map { (condition, $0.target, $0.clause) } }
        var reading = Reading()
        if parsed.join == .any, parsed.terms.count > 1 {
            guard !atoms.contains(where: { $0 == nil }) else { return Reading() }
            reading.matchesAny = true
            for case let (condition, target, clause)? in atoms {
                let merges = clause.op == .is || clause.op == .includes
                if merges, let index = reading.items.firstIndex(where: { $0.clause.field == clause.field && $0.clause.op == clause.op }) {
                    reading.items[index].clause = reading.items[index].clause.adding(clause.values[0])
                    reading.items[index].conditions.append(condition)
                } else if clause.op == .isEmpty, target.kind.isClosed || target.kind == .parent || target.kind == .collection,
                          let index = reading.items.firstIndex(where: { $0.clause.field == clause.field && $0.clause.op == .is }) {
                    reading.items[index].clause = reading.items[index].clause.adding("")
                    reading.items[index].conditions.append(condition)
                } else {
                    reading.items.append(ReadClause(clause: clause, conditions: [condition]))
                }
            }
            return reading
        }
        for case let (condition, target, clause)? in atoms {
            let closed = target.kind.isClosed || [.parent, .collection, .type, .source].contains(target.kind)
            if clause.op == .isNot, closed,
               let index = reading.items.firstIndex(where: { $0.clause.field == clause.field && $0.clause.op == .isNot }) {
                reading.items[index].clause = reading.items[index].clause.adding(clause.values[0])
                reading.items[index].conditions.append(condition)
            } else {
                reading.items.append(ReadClause(clause: clause, conditions: [condition]))
            }
        }
        pairDays(&reading.items)
        return reading
    }

    /// A day's two bounds, `after` the day before and `before` the day after, are one chip: on the day, or between two.
    private static func pairDays(_ items: inout [ReadClause]) {
        var index = 0
        while index < items.count {
            let after = items[index]
            guard after.clause.op == .after, let from = after.clause.values.first.flatMap(FilterDays.day)?.adding(days: 1),
                  let beforeIndex = items.firstIndex(where: { $0.clause.field == after.clause.field && $0.clause.op == .before }),
                  let to = items[beforeIndex].clause.values.first.flatMap(FilterDays.day)?.adding(days: -1), from <= to else {
                index += 1
                continue
            }
            let merged = from == to
                ? FilterClause(field: after.clause.field, op: .on, values: [from.text])
                : FilterClause(field: after.clause.field, op: .between, values: [from.text, to.text])
            items[index] = ReadClause(clause: merged, conditions: after.conditions + items[beforeIndex].conditions)
            items.remove(at: beforeIndex)
            index += 1
        }
    }

    /// The conditions of a view's filter the window has no filter for, as Marfa writes them. Saving a change of filters
    /// leaves them as they are, and the panel lists them so they are not a surprise.
    static func unshownConditions(of query: LibraryViewQuery, catalogue: Catalogue, calendar: Calendar = .current) -> [String] {
        guard let parsed = try? terms(of: query.filter) else { return [] }
        let shown = read(parsed, among: scope(of: query, catalogue: catalogue), catalogue: catalogue, calendar: calendar).shown
        return parsed.terms.filter { !shown.contains($0) }.compactMap(text(of:))
    }

    /// The clauses a view opens with: its filter's, and its listed types as a Type clause where it lists several
    /// (`seededTypes`).
    static func filterState(of view: LibraryView, catalogue: Catalogue, calendar: Calendar = .current) -> FilterState {
        let types = seededTypes(of: view.query, catalogue: catalogue)
        // A saved filter the core refuses shows no clauses; the refusal is told where the view is saved or changed.
        guard let parsed = try? terms(of: view.query.filter) else {
            return FilterState(clauses: types.map { [FilterClause(field: typeFieldID, op: .is, values: $0)] } ?? [])
        }
        let reading = read(parsed, among: scope(of: view.query, catalogue: catalogue), catalogue: catalogue, calendar: calendar)
        var clauses = reading.state.clauses
        if let types { clauses.insert(FilterClause(field: typeFieldID, op: .is, values: types), at: 0) }
        return FilterState(clauses: clauses, matchesAny: reading.matchesAny && clauses.count > 1)
    }

    // MARK: A view's filter as the window's

    /// The query to read a view's items with while the window's filters differ from the view's: the view's own with
    /// the conditions the window shows as filters taken out, and the types it shows as a Type filter. The window's
    /// filters then narrow what is read, so a value unchecked in one brings its items back. The conditions the window
    /// cannot show (those on a field no type declares), the tier and the states stay.
    /// Nil where the view's filter is one the core refuses, since nothing can be taken out of it.
    static func previewQuery(of query: LibraryViewQuery, seededTypes: [String]?, catalogue: Catalogue, calendar: Calendar = .current) -> LibraryViewQuery? {
        let parsed: Parsed
        do { parsed = try terms(of: query.filter) } catch { return nil }
        let shown = read(parsed, among: scope(of: query, catalogue: catalogue), catalogue: catalogue, calendar: calendar).shown
        let kept = parsed.terms.filter { !shown.contains($0) }
        var result = query
        if seededTypes != nil { result.types = [] }
        do {
            result.filter = kept.isEmpty ? nil : try FilterExpression(join: parsed.join, conditions: kept).encoded()
        } catch {
            return nil
        }
        return result
    }

    private static func exactTypes(in parsed: Parsed) -> (conditions: [FilterCondition], values: Set<String>) {
        let own = parsed.terms.filter { condition in
            if case .system(.type) = condition.field, condition.operator == .eq, case .text(let text)? = condition.value { return !text.isEmpty }
            return false
        }
        let values = own.compactMap { condition -> String? in
            if case .text(let text)? = condition.value { text } else { nil }
        }
        return (own, Set(values))
    }

    private static func normalized(_ clauses: [FilterClause], matchesAny: Bool) -> FilterState {
        FilterState(clauses: clauses, matchesAny: matchesAny && clauses.count > 1)
    }

    /// The query with the window's filters added to a place's own (a new view). A Type filter makes the saved query's types the
    /// window's chosen types, replacing the place's own type terms and types. Marfa takes a type with its subtypes,
    /// so a chosen type that has any stays a filter, as the exact-type condition the window applied.
    static func adding(
        _ state: FilterState, to query: LibraryViewQuery, targets: [String: FilterTarget], catalogue: Catalogue, calendar: Calendar = .current
    ) -> (query: LibraryViewQuery, unkept: [Unkept]) {
        var query = query
        var clauses = state.savable.clauses
        let matchesAny = state.savable.matchesAny
        if let index = clauses.firstIndex(where: { $0.field == typeFieldID && $0.op == .is }), targets[typeFieldID] != nil {
            let chosen = Set(clauses[index].values).subtracting([""])
            if chosen.isEmpty {
                clauses.remove(at: index)
            } else if let parsed = try? terms(of: query.filter) {
                // A place's own exact-type terms, such as a type's own items without its subtypes.
                let own = exactTypes(in: parsed)
                if parsed.join != .all && parsed.terms.count > 1 || own.values.isEmpty {
                    let narrowed = narrowing(chosen, listed: query.types, catalogue: catalogue)
                    if let types = narrowed.types { query.types = types }
                    if !narrowed.asFilter { clauses.remove(at: index) }
                } else if chosen == own.values {
                    clauses.remove(at: index)
                } else if chosen.isSubset(of: own.values) {
                    // Fewer than the place's own, which stay and are narrowed by the filter.
                } else {
                    let rest = parsed.terms.filter { !own.conditions.contains($0) }
                    query.filter = rest.isEmpty ? nil : try? FilterExpression(join: parsed.join, conditions: rest).encoded()
                    let narrowed = narrowing(chosen, listed: query.types, catalogue: catalogue)
                    if let types = narrowed.types { query.types = types }
                    if !narrowed.asFilter { clauses.remove(at: index) }
                }
            }
        }
        let base = query.filter.flatMap { $0.allSatisfy(\.isWhitespace) ? nil : $0 }
        let parsed: Parsed
        do { parsed = try terms(of: base) } catch { return (query, [.refused(message(of: error))]) }
        let result = combine(
            base: parsed, adding: normalized(clauses, matchesAny: matchesAny), targets: targets, catalogue: catalogue, calendar: calendar, keeping: base)
        query.filter = result.filter
        return (query, result.unkept)
    }

    /// The view's query with the window's filters in place of the conditions the window showed: the conditions
    /// it could not show stay as they are, in order. A Type filter within the view's listed types leaves them as
    /// they are and is saved as an exact-type condition (`keepsListedTypes`); one outside them replaces them. A window filter the view
    /// cannot hold leaves the query whole, so a filter is never dropped for one the window could not save.
    static func replacing(
        _ query: LibraryViewQuery, with state: FilterState, targets: [String: FilterTarget], seededTypes: [String]?, catalogue: Catalogue,
        calendar: Calendar = .current
    ) -> (query: LibraryViewQuery, unkept: [Unkept]) {
        let parsed: Parsed
        do { parsed = try terms(of: query.filter) } catch { return (query, [.refused(message(of: error))]) }
        let reading = read(parsed, among: scope(of: query, catalogue: catalogue), catalogue: catalogue, calendar: calendar)
        // A field the window lacks, or a clause where the view's types stand for the Type filter, is not the window's to show.
        let owned = reading.items.filter { targets[$0.clause.field] != nil && !(seededTypes != nil && $0.clause.field == typeFieldID) }
        var seededClauses = owned.map(\.clause)
        if let seededTypes, targets[typeFieldID] != nil {
            seededClauses.insert(FilterClause(field: typeFieldID, op: .is, values: seededTypes), at: 0)
        }
        let seeded = normalized(seededClauses, matchesAny: reading.matchesAny)
        var window = normalized(state.savable.clauses.filter { targets[$0.field] != nil }, matchesAny: state.savable.matchesAny)
        guard !window.isSame(as: seeded) else { return (query, []) }

        var result = query
        if targets[typeFieldID] != nil, let index = window.clauses.firstIndex(where: { $0.field == typeFieldID && $0.op == .is }) {
            let chosen = Set(window.clauses[index].values).subtracting([""])
            if chosen.isEmpty {
                window.clauses.remove(at: index)
            } else if keepsListedTypes(chosen, listed: query.types, catalogue: catalogue) {
                // The view's own types stay, and the filter is saved as an exact-type condition, a chip the view still shows
                // when reopened.
            } else {
                // The types are replaced only where a chosen type lies outside them, since the two together would list nothing.
                let narrowed = narrowing(chosen, listed: query.types, catalogue: catalogue)
                if let types = narrowed.types { result.types = types }
                if !narrowed.asFilter { window.clauses.remove(at: index) }
            }
        } else if targets[typeFieldID] != nil, seededTypes != nil {
            result.types = []
        }
        window = normalized(window.clauses, matchesAny: window.matchesAny)
        let ownedConditions = Set(owned.flatMap(\.conditions))
        let kept = parsed.terms.filter { !ownedConditions.contains($0) }
        let combination = combine(
            base: Parsed(terms: kept, join: parsed.join), adding: window, targets: targets, catalogue: catalogue, calendar: calendar,
            keeping: nil)
        if combination.unkept.contains(where: refusesFilter) { return (query, combination.unkept) }
        result.filter = combination.filter ?? (kept.isEmpty ? nil : try? FilterExpression(join: parsed.join, conditions: kept).encoded())
        return (result, combination.unkept)
    }
}

nonisolated extension FilterState {
    /// Whether two states ask the same of the items: the same clauses in any order, joined the same way.
    func isSame(as other: FilterState) -> Bool {
        let (mine, theirs) = (complete, other.complete)
        return Set(mine.clauses) == Set(theirs.clauses) && mine.clauses.count == theirs.clauses.count && mine.matchesAny == theirs.matchesAny
    }
}
