import Foundation
import Marfa

/// One row of the table: an item, with what its cells show that the item alone does not say.
nonisolated struct ItemTableRow: Identifiable, Hashable, Sendable {
    struct Link: Hashable, Sendable {
        let id: ItemID
        let title: String
        let icon: String?
    }

    let item: Item
    let typeLabel: String
    let typeIcon: String?
    /// The item the row's item is filed under (`child-of`).
    let parent: Link?
    var id: ItemID { item.id }
}

extension ItemTableRow {
    @MainActor
    static func rows(of items: [Item], in library: any ItemLibrary) -> [ItemTableRow] {
        let catalogue = library.catalogue
        return items.map { item in
            let parent = item.parentID.flatMap { library.item($0) }
            return ItemTableRow(
                item: item,
                typeLabel: catalogue.label(for: item.type),
                typeIcon: catalogue.icon(for: item.type),
                parent: parent.map { Link(id: $0.id, title: $0.displayTitle, icon: catalogue.icon(for: $0.type)) })
        }
    }
}

/// A column of the table: which part of an item it shows, and how.
nonisolated struct ItemTableColumn: Identifiable, Hashable, Sendable {
    enum Content: Hashable, Sendable {
        case title, type, parent, created, edited
        /// When the item happened (Marfa's `occurred_at`), which a record's look shows as its date.
        case occurred
        /// The item's tags, which a note's look shows as its fact.
        case tags
        /// The time between two date fields, as a session's start and end.
        case duration(start: String, end: String)
        case field(ItemTypeInfo.Field)
    }

    enum Style: Hashable, Sendable {
        case title, status, priority, choice, date, number, boolean, link, text, duration

        /// How much a style says about its column, where types give one key different styles: a status, then a
        /// priority, then the rest.
        var specificity: Int {
            switch self {
            case .status: 2
            case .priority: 1
            default: 0
            }
        }
    }

    let id: String
    var label: String
    let content: Content
    let style: Style
    /// Whether the column shows until the person hides it.
    var isShownByDefault = true

    var field: ItemTypeInfo.Field? {
        if case .field(let field) = content { field } else { nil }
    }

    /// Whether the cells hold a few values a person picks from, which the table can group and filter by.
    var isCategorical: Bool {
        switch style {
        case .status, .priority, .choice, .boolean, .link: true
        case .title, .date, .number, .text, .duration: content == .type
        }
    }

    static let title = ItemTableColumn(id: "title", label: String(localized: "Name"), content: .title, style: .title)
    static let type = ItemTableColumn(id: "type", label: String(localized: "Type"), content: .type, style: .text)
    static let parent = ItemTableColumn(id: "parent", label: "", content: .parent, style: .link)
    static let edited = ItemTableColumn(id: "edited", label: String(localized: "Edited"), content: .edited, style: .date)
    static let created = ItemTableColumn(
        id: "created", label: String(localized: "Created"), content: .created, style: .date, isShownByDefault: false)
    static let occurred = ItemTableColumn(
        id: "occurred", label: String(localized: "Happened"), content: .occurred, style: .date, isShownByDefault: false)
    static let tags = ItemTableColumn(
        id: "tags", label: String(localized: "Tags"), content: .tags, style: .text, isShownByDefault: false)
}

// MARK: Values

nonisolated enum ItemTableValue {
    /// What a cell sorts by. Values of one column always share a case.
    enum Sort: Hashable, Sendable {
        case rank(Int, String)
        case text(String)
        case number(Decimal)
        case date(Date)

        func compare(_ other: Sort) -> ComparisonResult {
            switch (self, other) {
            case let (.rank(a, x), .rank(b, y)):
                return a == b ? x.localizedStandardCompare(y) : (a < b ? .orderedAscending : .orderedDescending)
            case let (.text(a), .text(b)): return a.localizedStandardCompare(b)
            case let (.number(a), .number(b)): return a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
            case let (.date(a), .date(b)): return a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
            default: return .orderedSame
            }
        }
    }

    /// The raw text of a field, or nil where it holds nothing.
    static func string(_ row: ItemTableRow, key: String) -> String? {
        guard let value = row.item.value(of: key), InspectorFields.hasValue(value) else { return nil }
        return ItemValueText.string(value)
    }

    static func duration(_ row: ItemTableRow, start: String, end: String) -> TimeInterval? {
        guard let from = string(row, key: start).flatMap({ ItemDate.parse($0)?.date }),
              let to = string(row, key: end).flatMap({ ItemDate.parse($0)?.date }), to >= from else { return nil }
        return to.timeIntervalSince(from)
    }
}

nonisolated extension ItemTableColumn {
    /// Whether Is Not keeps a row with an empty cell. Marfa's `neq` on a property is false for an absent one, and
    /// true for a parent a row lacks.
    var negationKeepsEmpty: Bool { content == .parent }

    /// The values a categorical column offers, in the order its groups and its sort take them.
    func rank(of value: String) -> Int {
        switch style {
        case .status: return statusBucket(of: value).rank * 100 + (field?.options.firstIndex(of: value) ?? 99)
        case .priority, .choice: return field?.options.firstIndex(of: value) ?? Int.max
        default: return 0
        }
    }

    /// Where a status column lists `value`: the group its type declares for the word, else Other.
    func statusBucket(of value: String) -> StatusBucket {
        field?.statusBucket(of: value) ?? .other
    }

    /// The field as the row's own type declares it, which a cell offers its values from: a merged column holds the
    /// words of every type, and a row must not be set to one its type does not declare. Nil where the column is no
    /// field or the type does not declare it.
    func field(for row: ItemTableRow, catalogue: Catalogue) -> ItemTypeInfo.Field? {
        guard let field else { return nil }
        return catalogue.itemTypes[row.item.type]?.fields.first { $0.key == field.key }
    }

    /// What the cell holds for grouping and filtering: a value from the item, or nil for an empty cell.
    func category(of row: ItemTableRow) -> String? {
        switch content {
        case .type: return row.item.type.rawValue
        case .parent: return row.parent?.id.rawValue
        case .field(let field): return ItemTableValue.string(row, key: field.key)
        case .title, .created, .edited, .occurred, .tags, .duration: return nil
        }
    }

    /// A category as people read it.
    func label(ofCategory value: String, in rows: [ItemTableRow]) -> String {
        switch content {
        case .type: return rows.first { $0.item.type.rawValue == value }?.typeLabel ?? value
        case .parent: return rows.lazy.compactMap(\.parent).first { $0.id.rawValue == value }?.title ?? value
        case .field:
            if style == .boolean { return value == "true" ? String(localized: "Yes") : String(localized: "No") }
            return ItemTypeInfo.Field.label(ofOption: value)
        case .title, .created, .edited, .occurred, .tags, .duration: return value
        }
    }

    func sortValue(of row: ItemTableRow) -> ItemTableValue.Sort? {
        switch content {
        case .title: return .text(row.item.displayTitle)
        case .type: return .text(row.typeLabel)
        case .parent: return row.parent.map { .text($0.title) }
        case .created: return .date(row.item.created)
        case .edited: return .date(row.item.modified)
        case .occurred: return .date(row.item.occurred ?? row.item.created)
        case .tags:
            let tags = row.item.tags.subtracting([ItemTag.favorite])
            return tags.isEmpty ? nil : .text(tags.sorted().joined(separator: " "))
        case .duration(let start, let end): return ItemTableValue.duration(row, start: start, end: end).map { .number(Decimal($0)) }
        case .field(let field):
            guard let value = row.item.value(of: field.key), InspectorFields.hasValue(value) else { return nil }
            switch style {
            case .status, .priority, .choice:
                let text = ItemValueText.string(value)
                return .rank(rank(of: text), text)
            case .date:
                return value.string.flatMap { ItemDate.parse($0)?.date }.map { .date($0) } ?? .text(ItemValueText.string(value))
            case .number:
                if case .number(let number) = value { return .number(number) }
                return .text(ItemValueText.string(value))
            case .boolean:
                if case .bool(let flag) = value { return .rank(flag ? 0 : 1, "") }
                return nil
            default:
                if case .list(let shape) = field.kind { return .text(shape.display(of: value)) }
                return .text(ItemValueText.string(value))
            }
        }
    }

    /// Which way a column sorts when its header is first clicked: what matters most comes first.
    var firstOrder: SortOrder {
        switch style {
        case .priority, .date, .number, .duration: .reverse
        default: .forward
        }
    }
}

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
        case column(String)
    }

    var grouping = Grouping.automatic
    var sort: [ItemTableComparator]?
    /// For each column filtered, the categories it keeps; the empty string keeps empty cells. A column in `negated`
    /// keeps the rows outside those categories instead (Is Not).
    var filters: [String: Set<String>] = [:]
    /// The columns whose filter is Is Not. Only a column with a filter counts (`isNegated`).
    var negated: Set<String> = []
    var collapsed: Set<String>?
    /// How many rows show at first and each time Load More is chosen. Kept with the place's other choices, not in
    /// a saved view, which has no field for it.
    var pageSize = TablePageSize.standard

    /// Whether the column's filter is Is Not.
    func isNegated(_ column: String) -> Bool {
        negated.contains(column) && !(filters[column]?.isEmpty ?? true)
    }

    /// The filters that keep or hide something, with their Is and Is Not, which a place that differs only in a
    /// column left in `negated` after its filter went does not change.
    var filterChoices: [String: FilterChoice] {
        filters.reduce(into: [:]) { choices, entry in
            guard !entry.value.isEmpty else { return }
            choices[entry.key] = FilterChoice(values: entry.value, isNegated: negated.contains(entry.key))
        }
    }

    /// The options as far as the rows and their groups depend on them: a page size never changes the rows, a column
    /// left in `negated` after its filter went changes none.
    var settled: ItemTableOptions {
        var options = self
        options.pageSize = .standard
        options.negated = negated.filter(isNegated)
        return options
    }

    /// Whether any column is filtered.
    var isFiltering: Bool { filters.values.contains { !$0.isEmpty } }

    /// Removes every filter.
    mutating func clearFilters() {
        filters = [:]
        negated = []
    }

    /// Removes one column's filter.
    mutating func clearFilter(_ column: String) {
        filters[column] = nil
        negated.remove(column)
    }

    /// Sets a column's filter, dropping it where `values` is empty.
    mutating func setFilter(_ column: String, values: Set<String>, negated isNegated: Bool? = nil) {
        guard !values.isEmpty else { return clearFilter(column) }
        filters[column] = values
        if let isNegated { if isNegated { negated.insert(column) } else { negated.remove(column) } }
    }
}

/// What one column's filter keeps: some categories, or everything outside them.
nonisolated struct FilterChoice: Hashable, Sendable {
    var values: Set<String>
    var isNegated: Bool
}

nonisolated struct ItemTableGroup: Identifiable, Hashable, Sendable {
    /// The category, or the empty string for the rows with none.
    let id: String
    let title: String
    let rows: [ItemTableRow]
    var value: String? { id.isEmpty ? nil : id }
}

nonisolated enum ItemTableLayout {
    /// The table's columns for these rows: the name, then the type where the rows mix types, then what the types' looks
    /// show (`TypeLook`): the status of each type that has one, then the facts in the order the looks give them, then
    /// their dates. The columns of several types are the union of their looks. Every other column starts hidden and the
    /// person can show any of them. A look's column that no row fills starts hidden too, as an empty column says nothing.
    static func columns(
        for rows: [ItemTableRow], catalogue: Catalogue, hidden: Set<String>, looks: [TypeID: TypeLook]
    ) -> [ItemTableColumn] {
        let types = Set(rows.map(\.item.type)).sorted { $0.rawValue < $1.rawValue }
        var columns: [ItemTableColumn] = [.title]
        if types.count > 1 { columns.append(.type) }

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
            case .created: add(.created, shown: true)
            case .edited: add(.edited, shown: true)
            case .occurred: add(.occurred, shown: true)
            }
        }

        // What the looks do not show waits behind View Options. Where each item is filed is one of those.
        var parent = ItemTableColumn.parent
        // The column is headed with Marfa's name for the child end of the parent link.
        if let name = catalogue.edgeTypes[MarfaMapping.parentEdge]?.reverseLabel { parent.label = name }
        add(parent, shown: false)
        for key in order where !used.contains("field." + key) {
            if let column = fieldColumn(key) { add(column, shown: false) }
            if key == MarfaMapping.startField, fields[MarfaMapping.endField] != nil {
                add(ItemTableColumn(
                    id: "duration", label: String(localized: "Duration"),
                    content: .duration(start: MarfaMapping.startField, end: MarfaMapping.endField), style: .duration), shown: false)
            }
        }
        for column in [ItemTableColumn.edited, .created, .occurred, .tags] where !used.contains(column.id) {
            add(column, shown: false)
        }
        return columns
    }

    /// What a look shows of a column that is not a field's, or a field it shows: a fact or a date.
    private enum Shown: Hashable {
        case field(String)
        case tags, created, edited, occurred
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
        case .column(let id): return columns.first { $0.id == id && $0.isCategorical }
        // Only where items fill their status: a place of events, whose type has one nobody sets, is not grouped.
        case .automatic: return columns.first { $0.style == .status && $0.isShownByDefault }
        }
    }

    /// The order a place starts with: the most pressing first where items have a priority, else the latest edit. A
    /// place that keeps its own order, as a collection does, starts unsorted, so its rows stay in the order given.
    static func sort(_ options: ItemTableOptions, columns: [ItemTableColumn], keepsGivenOrder: Bool = false) -> [ItemTableComparator] {
        if let sort = options.sort {
            // A column the place no longer has is dropped; its stored copy may also be out of date.
            let fresh = sort.compactMap { comparator in
                columns.first { $0.id == comparator.column.id }.map { ItemTableComparator(column: $0, order: comparator.order) }
            }
            if !fresh.isEmpty { return fresh }
        }
        if keepsGivenOrder { return [] }
        var sort: [ItemTableComparator] = []
        if let priority = columns.first(where: { $0.style == .priority }) {
            sort.append(ItemTableComparator(column: priority, order: .reverse))
        }
        sort.append(ItemTableComparator(column: .edited, order: .reverse))
        return sort
    }

    /// The rows the filters keep. A column in `negated` keeps the rows whose category is none of its values. A
    /// saved view's Is Not is Marfa's `neq`, which an absent property never satisfies (`exists`), so a column of a
    /// property drops its empty cells, whereas a parent, which Marfa tests by the absence of a link, keeps them.
    static func filter(
        _ rows: [ItemTableRow], by filters: [String: Set<String>], negated: Set<String> = [], columns: [ItemTableColumn]
    ) -> [ItemTableRow] {
        let active = filters.compactMap { id, kept in
            columns.first { $0.id == id }.map { (column: $0, kept: kept, isNegated: negated.contains(id) && !kept.isEmpty) }
        }
        guard !active.isEmpty else { return rows }
        return rows.filter { row in
            active.allSatisfy { column, kept, isNegated in
                let category = column.category(of: row)
                guard isNegated else { return kept.contains(category ?? "") }
                guard let category else { return column.negationKeepsEmpty && !kept.contains("") }
                return !kept.contains(category)
            }
        }
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

    /// The rows in groups by `column`: a status column's by the group each word is in, the four in their order and
    /// then the words no group claims; any other column's as `categories` gives them.
    static func groups(of rows: [ItemTableRow], by column: ItemTableColumn) -> [ItemTableGroup] {
        guard column.style == .status else { return categories(of: rows, by: column) }
        var buckets: [StatusBucket: [ItemTableRow]] = [:]
        var empty: [ItemTableRow] = []
        for row in rows {
            if let word = column.category(of: row) { buckets[column.statusBucket(of: word), default: []].append(row) } else { empty.append(row) }
        }
        var groups = buckets.keys.sorted { $0.rank < $1.rank }.map { ItemTableGroup(id: $0.id, title: $0.title, rows: buckets[$0]!) }
        if !empty.isEmpty { groups.append(ItemTableGroup(id: "", title: String(localized: "No \(column.label)"), rows: empty)) }
        return groups
    }

    /// The rows in groups by each value of `column`: a picked value's in the order its values are given, any other
    /// column's largest first, and the rows with no value last. A filter offers these, so a status column's are its
    /// words, ordered by their groups.
    static func categories(of rows: [ItemTableRow], by column: ItemTableColumn, including extra: Set<String> = []) -> [ItemTableGroup] {
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

    /// The values a column's filter offers: every value the rows hold, and also those the filter keeps and the
    /// catalogue's own for a choice, priority, status or yes/no field, each with the rows that hold it, which may be
    /// none. A view's own filter, or this filter, may already have taken out every row holding a value, and a
    /// person must still see it to take it off.
    static func offered(in rows: [ItemTableRow], by column: ItemTableColumn, keeping kept: Set<String>) -> [ItemTableGroup] {
        var extra = kept
        if let field = column.field {
            switch column.style {
            case .status, .priority, .choice: extra.formUnion(field.options)
            case .boolean: extra.formUnion(["true", "false"])
            default: break
            }
        }
        return categories(of: rows, by: column, including: extra)
    }

    /// The groups folded when the person has not chosen: finished work, so what is still to do leads.
    static func collapsed(_ options: ItemTableOptions, groups: [ItemTableGroup], by column: ItemTableColumn) -> Set<String> {
        if let collapsed = options.collapsed { return collapsed }
        guard column.style == .status else { return [] }
        return Set(groups.compactMap { $0.value.flatMap { StatusBucket(id: $0)?.isFinished == true ? $0 : nil } })
    }
}
