import Foundation
import Marfa

/// Sorts rows by one column. Empty cells go last whichever way the column runs, and rows that tie keep the order
/// of their titles, so the table never shuffles rows that compare equal.
nonisolated struct ItemTableComparator: SortComparator, Hashable, Sendable {
    var column: ItemTableColumn
    var order: SortOrder = .forward

    func compare(_ lhs: ItemTableRow, _ rhs: ItemTableRow) -> ComparisonResult {
        compareValues(column.sortValue(of: lhs), column.sortValue(of: rhs))
    }

    /// The comparison of two cells' values, which a sort of many rows reads once for each row rather than for
    /// each comparison (`ItemTableLayout.sorted`).
    func compareValues(_ lhs: ItemTableValue.Sort?, _ rhs: ItemTableValue.Sort?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        case let (left?, right?):
            let result = left.compare(right)
            guard order == .reverse else { return result }
            switch result {
            case .orderedAscending: return .orderedDescending
            case .orderedDescending: return .orderedAscending
            case .orderedSame: return .orderedSame
            }
        }
    }
}

// MARK: The table's shape

/// What the person chose for one place's table: how it is grouped, sorted and filtered, and which groups are
/// folded. Nil means the place's default, worked out from what it holds.
nonisolated struct ItemTableOptions: Hashable, Sendable {
    enum Grouping: Hashable, Sendable {
        case automatic, none
        /// By a column, as `mode` says: each value, or a date's day, week, month or year.
        case column(String, by: GroupMode = .value)

        /// The column it names, where it names one.
        var columnID: String? {
            if case .column(let id, _) = self { id } else { nil }
        }

        var mode: GroupMode {
            if case .column(_, let mode) = self { mode } else { .value }
        }
    }

    var grouping = Grouping.automatic
    /// The groups that come first, in this order, by key (`GroupKey`); the rest follow in the grouping's own order.
    /// A saved view's `group.order`, or a place's own. Nil or empty orders nothing.
    var groupOrder: [String]?
    /// The groups left out, whose items still count in the place. A saved view's `group.hidden`, or a place's own.
    var hiddenGroups: Set<String>?
    var sort: [ItemTableComparator]?
    /// The filter row's clauses and whether any one of them will do (`FilterClause`).
    var filter = FilterState()
    var collapsed: Set<String>?
    /// How many rows show at first and each time Load More is chosen. Kept with the place's other choices, not in
    /// a saved view, which has no field for it.
    var pageSize = TablePageSize.standard
    /// The tiers the place lists (From), where the person or a saved view chose; nil is the place's own
    /// (`Browser.listing`).
    var scope: ListScope?
    /// Whether archived items are listed, where the person or a saved view chose; nil hides them.
    var archived: ArchivedItems?
    /// Whether a type lists its kinds, where the person chose; nil lists them.
    var includesKinds: Bool?

    /// The options as far as the rows and their groups depend on them: a page size never changes the rows, nor does a
    /// clause that says too little to filter by.
    var settled: ItemTableOptions {
        var options = self
        options.pageSize = .standard
        options.filter = filter.complete
        if options.groupOrder?.isEmpty == true { options.groupOrder = nil }
        if options.hiddenGroups?.isEmpty == true { options.hiddenGroups = nil }
        return options
    }

    /// Groups by `grouping`, which orders and hides no group until the person does.
    mutating func group(by grouping: Grouping) {
        guard grouping != self.grouping else { return }
        self.grouping = grouping
        groupOrder = nil
        hiddenGroups = nil
        collapsed = nil
    }

    /// Whether any clause filters.
    var isFiltering: Bool { !filter.complete.isEmpty }

    /// Removes every filter.
    mutating func clearFilters() {
        filter = FilterState()
    }
}

nonisolated struct ItemTableGroup: Identifiable, Hashable, Sendable {
    /// The category, or the empty string for the rows with none.
    let id: String
    let title: String
    let rows: [ItemTableRow]
    var value: String? { id.isEmpty ? nil : id }
}

nonisolated enum ItemTableLayout {
    /// The links the table reads for its rows: the parent always, one lookup a row, so its filter and grouping are
    /// always offered; then children and collections where the types' looks show them, the person shows their
    /// column, or a group, filter or sort names them. Those none of them asks for cost nothing.
    static func relations(
        of types: Set<TypeID>, looks: [TypeID: TypeLook], options: ItemTableOptions, shown: Set<Relation>
    ) -> Set<Relation> {
        var wanted = shown.union([.parent])
        for type in types { wanted.formUnion((looks[type] ?? .empty).relations) }
        // A column the options group, filter or sort by is read too, shown or not.
        var named = Set(options.filter.clauses.map(\.field))
        if let id = options.grouping.columnID { named.insert(id) }
        for comparator in options.sort ?? [] { named.insert(comparator.column.id) }
        for id in named { if let relation = Relation(rawValue: id) { wanted.insert(relation) } }
        return wanted
    }

    /// The table's columns for these rows: the name, then the type where the rows mix types, then what the types' looks
    /// show (`TypeLook`): the status of each type that has one, then the facts in the order the looks give them, then
    /// their dates. The columns of several types are the union of their looks. The fields of `listed` types no row holds
    /// come too, hidden, so a grouping or a sort can name a field no item has yet. Every other column starts hidden and the
    /// person can show any of them. A look's column that no row fills starts hidden too, as an empty column says nothing.
    /// The Archive and the Library's own list show items by what they are and where they came from, so each starts with the
    /// name, type, source and edit date and hides the looks' columns.
    static func columns(
        for rows: [ItemTableRow], types listed: Set<TypeID> = [], catalogue: Catalogue, hidden: Set<String>, looks: [TypeID: TypeLook],
        listsByOrigin: Bool = false
    ) -> [ItemTableColumn] {
        let held = Set(rows.map(\.item.type))
        let types = held.union(listed).sorted { $0.rawValue < $1.rawValue }
        var columns: [ItemTableColumn] = [.title]
        if held.count > 1 { columns.append(.type) }

        var fields: [String: ItemTypeInfo.Field] = [:]
        var styles: [String: ItemTableColumn.Style] = [:]
        var order: [String] = []
        for type in types {
            let info = catalogue.itemTypes[type]
            let page: Set<String> = [info?.titleKey, info?.bodyKey].compactMap { $0 }.reduce(into: []) { $0.insert($1) }
            for field in info?.fields ?? [] {
                if hidden.contains(field.key) || page.contains(field.key) || ["title", "body"].contains(field.key) { continue }
                if field.kind.isOutsideForms { continue }
                let fieldStyle = style(of: field, in: type, catalogue: catalogue)
                if let known = fields[field.key] {
                    if fieldStyle.specificity > styles[field.key]!.specificity {
                        // A status or priority in one type outranks the plain field another type calls the same.
                        fields[field.key] = field
                        styles[field.key] = fieldStyle
                    } else {
                        // Types that share a status field may each add words of their own.
                        fields[field.key] = known.addingStatusWords(of: field)
                    }
                    continue
                }
                fields[field.key] = field
                styles[field.key] = fieldStyle
                order.append(field.key)
            }
        }

        var used: Set<String> = []
        func add(_ column: ItemTableColumn, shown: Bool) {
            var column = column
            column.isShownByDefault = shown
            columns.append(column)
            if shown { used.insert(column.id) }
        }
        func fieldColumn(_ key: String) -> ItemTableColumn? {
            fields[key].map { ItemTableColumn(id: "field." + key, label: $0.label, content: .field($0), style: styles[key]!) }
        }
        func isFilled(_ key: String) -> Bool { rows.contains { InspectorFields.hasValue($0.item.value(of: key)) } }

        // The status of each type that has one comes first.
        for type in types {
            guard let key = catalogue.itemTypes[type]?.statusField?.key, !used.contains("field." + key),
                  isFilled(key), let column = fieldColumn(key) else { continue }
            add(column, shown: true)
        }
        // Then the facts and the dates of the looks, in order, each once.
        for entry in shown(by: looks, of: types) {
            switch entry {
            case .field(let key):
                guard !used.contains("field." + key), isFilled(key), let column = fieldColumn(key) else { continue }
                add(column, shown: true)
            case .tags:
                guard rows.contains(where: { !$0.item.tags.subtracting([ItemTag.favorite]).isEmpty }) else { continue }
                add(.tags, shown: true)
            case .relation(let relation):
                guard rows.contains(where: { !$0.items(of: relation).isEmpty }) else { continue }
                add(.relation(relation, in: catalogue), shown: true)
            case .count(let fact):
                guard !used.contains(ItemTableColumn.count(fact, hasStatus: false).id) else { continue }
                let hasStatus = types.contains { catalogue.itemTypes[$0]?.statusField != nil && (looks[$0] ?? .empty).counts.contains(fact) }
                // Until Marfa has answered a count for some row, the column has nothing to say and starts hidden.
                let column = ItemTableColumn.count(fact, hasStatus: hasStatus)
                add(column, shown: rows.contains { CountWording.text(of: fact, answer: $0.counts[fact], hasStatus: hasStatus) != nil })
            case .created: add(.created, shown: true)
            case .edited: add(.edited, shown: true)
            case .occurred: add(.occurred, shown: true)
            }
        }

        // What the looks do not show waits behind View Options. Where each item is filed is one of those.
        for relation in Relation.allCases where !used.contains(ItemTableColumn.relation(relation, in: catalogue).id) {
            add(.relation(relation, in: catalogue), shown: false)
        }
        for key in order where !used.contains("field." + key) {
            if let column = fieldColumn(key) { add(column, shown: false) }
            if key == MarfaMapping.startField, fields[MarfaMapping.endField] != nil {
                add(ItemTableColumn(
                    id: "duration", label: String(localized: "Duration"),
                    content: .duration(start: MarfaMapping.startField, end: MarfaMapping.endField), style: .duration), shown: false)
            }
        }
        for column in [ItemTableColumn.edited, .created, .occurred, .tags, .source] where !used.contains(column.id) {
            add(column, shown: false)
        }
        return listsByOrigin ? originColumns(columns) : columns
    }

    /// The columns of a place that lists items by what they are and where they came from, first and shown, then every other column hidden.
    private static func originColumns(_ columns: [ItemTableColumn]) -> [ItemTableColumn] {
        let own = [ItemTableColumn.title, .type, .source, .edited]
        let ids = Set(own.map(\.id))
        return (own + columns.filter { !ids.contains($0.id) }).map { column in
            var column = column
            column.isShownByDefault = ids.contains(column.id)
            return column
        }
    }

    /// The columns a sort can name for a view that shows `types`: the fields those types declare, and the columns every
    /// item has (title, type, parent, edited, created, tags). Title and type lead, then the status and the other
    /// fields in the order the looks give them, then the parent and the dates.
    static func sortChoices(from columns: [ItemTableColumn], types: Set<TypeID>, catalogue: Catalogue) -> [ItemTableColumn] {
        let declared = Set(types.flatMap { catalogue.itemTypes[$0]?.fields.map(\.key) ?? [] })
        func rank(_ column: ItemTableColumn) -> Int {
            switch column.content {
            case .title: 0
            case .type: 1
            case .field: column.style == .status ? 2 : 3
            case .parent: 4
            case .children, .collections, .count: 4
            case .duration, .occurred, .source: 5
            case .edited: 6
            case .created: 7
            case .tags: 8
            }
        }
        let available = columns.filter { column in
            guard column.isSortable else { return false }
            return switch column.content {
            case .field(let field): declared.contains(field.key)
            case .duration(let start, let end): declared.contains(start) && declared.contains(end)
            case .type: types.count > 1
            default: true
            }
        }
        return available.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    /// What a look shows of a column that is not a field's, or a field it shows: a fact or a date.
    private enum Shown: Hashable {
        case field(String)
        case tags, created, edited, occurred
        case relation(Relation)
        case count(CountFact)
    }

    /// The facts of the types' looks in order, type by type, then their dates, each once.
    private static func shown(by looks: [TypeID: TypeLook], of types: [TypeID]) -> [Shown] {
        var facts: [Shown] = []
        var dates: [Shown] = []
        for type in types {
            let look = looks[type] ?? .empty
            for fact in look.facts {
                let entry: Shown = switch fact {
                case .field(let key): .field(key)
                case .tags: .tags
                case .relation(let relation): .relation(relation)
                case .count(let count): .count(count)
                }
                if !facts.contains(entry) { facts.append(entry) }
            }
            let date: Shown? = switch look.date {
            case .field(let key): .field(key)
            case .created: .created
            case .edited: .edited
            case .occurred: .occurred
            case .off: nil
            }
            if let date, !dates.contains(date) { dates.append(date) }
        }
        return facts + dates.filter { !facts.contains($0) }
    }

    /// How a column of `field`, as `type` declares it, reads. A status is the field's kind, whatever its name; a
    /// priority belongs to a task, and is not guessed from the name on any other type. A column that types share
    /// keeps the most specific style any of them gives it (`Style.specificity`).
    static func style(of field: ItemTypeInfo.Field, in type: TypeID, catalogue: Catalogue) -> ItemTableColumn.Style {
        switch field.kind {
        case .boolean: return .boolean
        case .number: return .number
        case .date: return .date
        case .status: return .status
        case .choice: return catalogue.isPriority(field, of: type) ? .priority : .choice
        case .text, .other, .words, .list: return .text
        }
    }

    /// The grouping a place starts with: by status where its items have one, else none.
    static func grouping(_ options: ItemTableOptions, columns: [ItemTableColumn]) -> ItemTableColumn? {
        switch options.grouping {
        case .none: return nil
        case .column(let id, let mode): return columns.first { $0.id == id && $0.groups(by: mode) }
        // Only where items fill their status: a place of events, whose type has one nobody sets, is not grouped.
        case .automatic: return columns.first { $0.style == .status && $0.isShownByDefault }
        }
    }

    /// The order a place starts with: the most pressing first where items have a priority, else the latest edit, which
    /// is all the Archive and the Library use. A place that keeps its own order, as a collection does, starts unsorted, so its rows stay
    /// in the order given.
    static func sort(
        _ options: ItemTableOptions, columns: [ItemTableColumn], keepsGivenOrder: Bool = false, listsByOrigin: Bool = false
    ) -> [ItemTableComparator] {
        if let sort = options.sort {
            // Resolve stored sort keys against the columns the place offers now.
            let fresh = sort.compactMap { comparator in
                columns.first { $0.id == comparator.column.id && $0.isSortable }.map { ItemTableComparator(column: $0, order: comparator.order) }
            }
            if !fresh.isEmpty { return fresh }
        }
        if keepsGivenOrder { return [] }
        var sort: [ItemTableComparator] = []
        if !listsByOrigin, let priority = columns.first(where: { $0.style == .priority }) {
            sort.append(ItemTableComparator(column: priority, order: .reverse))
        }
        sort.append(ItemTableComparator(column: .edited, order: .reverse))
        return sort
    }

    static func sorted(_ rows: [ItemTableRow], by sort: [ItemTableComparator]) -> [ItemTableRow] {
        guard !sort.isEmpty else { return rows }
        // Each row's values are read once, not at each of the roughly n log n comparisons: reading one parses a
        // date or works out a status's group. The row's place is the last tie-break, which keeps rows that compare
        // equal in the order given, as a stable sort does.
        let values = sort.map { comparator in rows.map { comparator.column.sortValue(of: $0) } }
        let titles = rows.map(\.item.displayTitle)
        let order = rows.indices.sorted { a, b in
            for (position, comparator) in sort.enumerated() {
                switch comparator.compareValues(values[position][a], values[position][b]) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: continue
                }
            }
            switch titles[a].localizedStandardCompare(titles[b]) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return a < b
            }
        }
        return order.map { rows[$0] }
    }

    /// The rows in groups by `column` as `mode` says, in the grouping's own order, with the rows that hold no value
    /// last and, where a type does not declare the field, Not Applicable after them (`GroupKey`):
    /// - each value: a choice's options and a status's words as declared, Yes before No, any other value A to Z;
    /// - a date's span: keyed as Marfa keys it (`DateGroups.key`), earliest first;
    /// - Set or Not Set: Not Set, then Set;
    /// - status groups: Marfa's four in their order, then No Status, each row by its own type's status field.
    /// `catalogue` tells which types declare the field and their status words; without it every row is applicable.
    /// With `declared`, a grouping whose groups are known before the rows are (a choice, a status, yes or no, Set or
    /// Not Set, status groups) lists the empty ones too, for Hide Empty Groups to leave out.
    static func groups(
        of rows: [ItemTableRow], by column: ItemTableColumn, mode: GroupMode, catalogue: Catalogue? = nil, declared: Bool = false,
        calendar: Calendar = .current, now: Date = .now
    ) -> [ItemTableGroup] {
        var applicable = rows
        var notApplicable: [ItemTableRow] = []
        if let catalogue, mode != .statusGroups, let key = column.field?.key {
            applicable = []
            for row in rows {
                if catalogue.itemTypes[row.item.type]?.fields.contains(where: { $0.key == key }) == false {
                    notApplicable.append(row)
                } else {
                    applicable.append(row)
                }
            }
        }
        var groups: [ItemTableGroup]
        switch mode {
        case .bucket(let bucket): groups = dated(applicable, by: column, bucket: bucket, calendar: calendar, now: now)
        case .presence: groups = presence(applicable, by: column, declared: declared)
        case .statusGroups: groups = statusGroups(applicable, by: column, catalogue: catalogue, declared: declared)
        case .value: groups = categories(of: applicable, by: column, including: declared ? column.declaredValues : [], byLabel: true)
        }
        if !notApplicable.isEmpty {
            groups.append(ItemTableGroup(id: GroupKey.notApplicable, title: String(localized: "Not Applicable"), rows: notApplicable))
        }
        return groups
    }

    /// The groups in the order a view or a place gives (`group.order`): those it names first, in its order, then the
    /// rest as they came, Not Applicable last.
    static func ordered(_ groups: [ItemTableGroup], by order: [String]?) -> [ItemTableGroup] {
        guard let order, !order.isEmpty else { return groups }
        let byKey = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let named = order.compactMap { key -> ItemTableGroup? in
            guard key != GroupKey.notApplicable, seen.insert(key).inserted else { return nil }
            return byKey[key]
        }
        let rest = groups.filter { !seen.contains($0.id) }
        return named + rest.filter { $0.id != GroupKey.notApplicable } + rest.filter { $0.id == GroupKey.notApplicable }
    }

    /// The rows in groups by the day, week, month or year of `column`'s date, keyed as Marfa keys them
    /// (`DateGroups.key`), in ascending order, then the rows with no date.
    private static func dated(
        _ rows: [ItemTableRow], by column: ItemTableColumn, bucket: LibraryViewGroup.Bucket, calendar: Calendar, now: Date
    ) -> [ItemTableGroup] {
        var buckets: [String: [ItemTableRow]] = [:]
        for row in rows {
            let key = column.date(of: row, calendar: calendar).map { DateGroups.key(of: $0, bucket: bucket, calendar: calendar) } ?? ""
            buckets[key, default: []].append(row)
        }
        var groups = buckets.keys.filter { !$0.isEmpty }.sorted().map { key in
            ItemTableGroup(id: key, title: DateGroups.title(ofKey: key, bucket: bucket, now: now, calendar: calendar), rows: buckets[key]!)
        }
        if let empty = buckets[""] { groups.append(ItemTableGroup(id: "", title: String(localized: "No \(column.label)"), rows: empty)) }
        return groups
    }

    /// Not Set, then Set.
    private static func presence(_ rows: [ItemTableRow], by column: ItemTableColumn, declared: Bool) -> [ItemTableGroup] {
        let set = rows.filter(column.isSet(in:))
        let unset = rows.filter { !column.isSet(in: $0) }
        return [
            ItemTableGroup(id: GroupKey.notSet, title: String(localized: "Not Set"), rows: unset),
            ItemTableGroup(id: GroupKey.set, title: String(localized: "Set"), rows: set),
        ].filter { declared || !$0.rows.isEmpty }
    }

    /// Marfa's four status groups in their order, then the words no group claims, then No Status. Each row goes by its
    /// own type's status field where the catalogue is given, so types that keep their status under different names
    /// share the groups; a type with no status field, or a row with no word, is No Status.
    private static func statusGroups(
        _ rows: [ItemTableRow], by column: ItemTableColumn, catalogue: Catalogue?, declared: Bool
    ) -> [ItemTableGroup] {
        var buckets: [StatusBucket: [ItemTableRow]] = [:]
        var empty: [ItemTableRow] = []
        for row in rows {
            let field = catalogue.map { $0.itemTypes[row.item.type]?.statusField } ?? column.field
            guard let field, let word = ItemTableValue.string(row, key: field.key) else {
                empty.append(row)
                continue
            }
            buckets[field.statusBucket(of: word), default: []].append(row)
        }
        if declared { for group in StatusGroup.allCases where buckets[.group(group)] == nil { buckets[.group(group)] = [] } }
        var groups = buckets.keys.sorted { $0.rank < $1.rank }.map { ItemTableGroup(id: $0.id, title: $0.title, rows: buckets[$0]!) }
        if !empty.isEmpty || declared { groups.append(ItemTableGroup(id: "", title: String(localized: "No Status"), rows: empty)) }
        return groups
    }

    /// The rows in groups by each value of `column`: a picked value's in the order its values are given, any other
    /// column's largest first (A to Z `byLabel`), and the rows with no value last. A filter offers these, so a status column's are its
    /// words, ordered by their groups.
    static func categories(
        of rows: [ItemTableRow], by column: ItemTableColumn, including extra: Set<String> = [], byLabel: Bool = false
    ) -> [ItemTableGroup] {
        var buckets: [String: [ItemTableRow]] = [:]
        for row in rows { buckets[column.category(of: row) ?? "", default: []].append(row) }
        for value in extra where buckets[value] == nil { buckets[value] = [] }
        let keys = buckets.keys.filter { !$0.isEmpty }.sorted { a, b in
            switch column.style {
            case .status, .priority, .choice:
                let (x, y) = (column.rank(of: a), column.rank(of: b))
                return x == y ? a < b : x < y
            case .boolean:
                return a == "true"
            default:
                if byLabel { return column.label(ofCategory: a, in: rows).localizedStandardCompare(column.label(ofCategory: b, in: rows)) == .orderedAscending }
                let (x, y) = (buckets[a]!.count, buckets[b]!.count)
                return x == y ? column.label(ofCategory: a, in: rows).localizedStandardCompare(column.label(ofCategory: b, in: rows)) == .orderedAscending : x > y
            }
        }
        var groups = keys.map { ItemTableGroup(id: $0, title: column.label(ofCategory: $0, in: rows), rows: buckets[$0]!) }
        if let empty = buckets[""] {
            groups.append(ItemTableGroup(id: "", title: String(localized: "No \(column.label)"), rows: empty))
        }
        return groups
    }

    /// The groups folded when the person has not chosen: finished work, so what is still to do leads.
    static func collapsed(
        _ options: ItemTableOptions, groups: [ItemTableGroup], by column: ItemTableColumn, mode: GroupMode = .statusGroups
    ) -> Set<String> {
        if let collapsed = options.collapsed { return collapsed }
        guard column.style == .status else { return [] }
        switch mode {
        case .statusGroups: return Set(groups.compactMap { $0.value.flatMap { StatusBucket(id: $0)?.isFinished == true ? $0 : nil } })
        case .value: return Set(groups.compactMap { $0.value.flatMap { column.statusBucket(of: $0).isFinished ? $0 : nil } })
        case .bucket, .presence: return []
        }
    }
}
