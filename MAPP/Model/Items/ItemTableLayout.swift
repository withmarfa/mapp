import Foundation

/// One row of the table: an item, with what its cells show that the item alone does not say.
nonisolated struct ItemTableRow: Identifiable, Hashable, Sendable {
    struct Link: Hashable, Sendable {
        let id: ItemID
        let title: String
        let symbol: String
    }

    let item: Item
    let typeLabel: String
    let typeSymbol: String
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
                typeLabel: TypeSymbol.label(for: item.type, in: catalogue),
                typeSymbol: TypeSymbol.name(for: item.type, in: catalogue),
                parent: parent.map { Link(id: $0.id, title: $0.title, symbol: TypeSymbol.name(for: $0.type, in: catalogue)) })
        }
    }
}

/// How a status reads, whatever word a type uses for it, so every type's statuses sort, group and colour alike.
nonisolated enum StatusTone: Int, Hashable, Sendable, CaseIterable, Comparable {
    case active, waiting, planned, later, done, canceled, other

    init(_ value: String) {
        let word = value.lowercased().replacingOccurrences(of: "-", with: "_")
        switch word {
        case "in_progress", "doing", "active", "started", "ongoing", "running", "current": self = .active
        case "blocked", "waiting", "review", "in_review", "on_hold", "paused": self = .waiting
        case "pending", "todo", "to_do", "open", "planned", "next", "ready", "new", "not_started": self = .planned
        case "someday", "later", "backlog", "idea", "maybe", "deferred": self = .later
        case "completed", "done", "closed", "resolved", "finished", "shipped", "accepted": self = .done
        case "canceled", "cancelled", "wontfix", "won't_fix", "dropped", "abandoned", "rejected", "superseded": self = .canceled
        default: self = .other
        }
    }

    /// Whether the work is over, so its group starts folded away.
    var isFinished: Bool { self == .done || self == .canceled }

    static func < (lhs: StatusTone, rhs: StatusTone) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A column of the table: which part of an item it shows, and how.
nonisolated struct ItemTableColumn: Identifiable, Hashable, Sendable {
    enum Content: Hashable, Sendable {
        case title, type, parent, created, edited
        /// The time between two date fields, as a session's start and end.
        case duration(start: String, end: String)
        case field(ItemTypeInfo.Field)
    }

    enum Style: Hashable, Sendable {
        case title, status, priority, person, choice, date, number, boolean, link, text, longText, duration
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
        case .status, .priority, .person, .choice, .boolean, .link: true
        case .title, .date, .number, .text, .longText, .duration: content == .type
        }
    }

    static let title = ItemTableColumn(id: "title", label: String(localized: "Name"), content: .title, style: .title)
    static let type = ItemTableColumn(id: "type", label: String(localized: "Type"), content: .type, style: .text)
    static let parent = ItemTableColumn(id: "parent", label: "", content: .parent, style: .link)
    static let edited = ItemTableColumn(id: "edited", label: String(localized: "Edited"), content: .edited, style: .date)
    static let created = ItemTableColumn(
        id: "created", label: String(localized: "Created"), content: .created, style: .date, isShownByDefault: false)
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
    /// The values a categorical column offers, in the order its groups and its sort take them.
    func rank(of value: String) -> Int {
        switch style {
        case .status: return StatusTone(value).rawValue * 100 + (field?.options.firstIndex(of: value) ?? 99)
        case .priority, .choice: return field?.options.firstIndex(of: value) ?? Int.max
        default: return 0
        }
    }

    /// What the cell holds for grouping and filtering: a value from the item, or nil for an empty cell.
    func category(of row: ItemTableRow) -> String? {
        switch content {
        case .type: return row.item.type.rawValue
        case .parent: return row.parent?.id.rawValue
        case .field(let field): return ItemTableValue.string(row, key: field.key)
        case .title, .created, .edited, .duration: return nil
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
        case .title, .created, .edited, .duration: return value
        }
    }

    func sortValue(of row: ItemTableRow) -> ItemTableValue.Sort? {
        switch content {
        case .title: return .text(row.item.title)
        case .type: return .text(row.typeLabel)
        case .parent: return row.parent.map { .text($0.title) }
        case .created: return .date(row.item.created)
        case .edited: return .date(row.item.modified)
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
    /// For each column filtered, the categories it keeps; the empty string keeps empty cells.
    var filters: [String: Set<String>] = [:]
    var collapsed: Set<String>?
}

nonisolated struct ItemTableGroup: Identifiable, Hashable, Sendable {
    /// The category, or the empty string for the rows with none.
    let id: String
    let title: String
    let rows: [ItemTableRow]
    var value: String? { id.isEmpty ? nil : id }
}

nonisolated enum ItemTableLayout {
    /// The fields a table leads with, in this order, wherever a type has them.
    private static let leading = ["status", "priority", "assignee", "due_at", "starts_at", "ends_at", "completed_at", "occurred_at"]
    /// Fields that read as a paragraph or as bookkeeping, shown only when the person asks.
    private static let quiet: Set<String> = ["notes", "url", "place", "precision"]

    /// The table's columns for these rows: the name, then the type where the rows mix types, then status, priority
    /// and assignee, then where each item is filed, then the other fields their types have, and when it was edited.
    /// A field few of the rows fill starts hidden, as do the quiet ones; the person can show any of them.
    static func columns(for rows: [ItemTableRow], catalogue: Catalogue, hidden: Set<String>) -> [ItemTableColumn] {
        var columns: [ItemTableColumn] = [.title]
        let types = Set(rows.map(\.item.type))
        if types.count > 1 { columns.append(.type) }

        var fields: [String: ItemTypeInfo.Field] = [:]
        var order: [String] = []
        for type in types.sorted(by: { $0.rawValue < $1.rawValue }) {
            let info = catalogue.itemTypes[type]
            let page: Set<String> = [info?.titleKey, info?.bodyKey].compactMap { $0 }.reduce(into: []) { $0.insert($1) }
            for field in info?.fields ?? [] where fields[field.key] == nil {
                if hidden.contains(field.key) || page.contains(field.key) || ["title", "body"].contains(field.key) { continue }
                if case .other = field.kind { continue }
                fields[field.key] = field
                order.append(field.key)
            }
        }
        let filled = Dictionary(uniqueKeysWithValues: order.map { key in
            (key, rows.count(where: { InspectorFields.hasValue($0.item.value(of: key)) }))
        })
        // Fields that only some types have, or few items fill, would make a mixed table wide and mostly empty.
        let threshold = max(1, rows.count / 10)
        let sorted = order.sorted { a, b in
            let (x, y) = (leading.firstIndex(of: a) ?? Int.max, leading.firstIndex(of: b) ?? Int.max)
            if x != y { return x < y }
            if (a == "description") != (b == "description") { return b == "description" }
            return order.firstIndex(of: a)! < order.firstIndex(of: b)!
        }
        // Who and what state come first, then where the item is filed, then its dates and its prose.
        let (people, rest) = (sorted.filter(Self.firstFields.contains), sorted.filter { !Self.firstFields.contains($0) })
        for key in people { columns.append(column(for: fields[key]!, filled: filled[key, default: 0], threshold: threshold)) }

        // The parent is worth showing where enough rows have one, such as a ticket's epic.
        var parent = ItemTableColumn.parent
        // The column is headed with Marfa's name for the child end of the parent link.
        if let name = catalogue.edgeTypes[MarfaMapping.parentEdge]?.reverseLabel { parent.label = name }
        parent.isShownByDefault = rows.count(where: { $0.parent != nil }) >= threshold
        columns.append(parent)

        for key in rest {
            columns.append(column(for: fields[key]!, filled: filled[key, default: 0], threshold: threshold))
            if key == "starts_at", fields["ends_at"] != nil {
                columns.append(ItemTableColumn(
                    id: "duration", label: String(localized: "Duration"),
                    content: .duration(start: "starts_at", end: "ends_at"), style: .duration,
                    isShownByDefault: filled["ends_at", default: 0] >= threshold))
            }
        }
        columns.append(.edited)
        columns.append(.created)
        return columns
    }

    private static let firstFields: Set<String> = ["status", "priority", "assignee"]

    private static func column(for field: ItemTypeInfo.Field, filled: Int, threshold: Int) -> ItemTableColumn {
        var column = ItemTableColumn(id: "field." + field.key, label: field.displayLabel, content: .field(field), style: style(of: field))
        column.isShownByDefault = !quiet.contains(field.key) && filled >= threshold
        return column
    }

    static func style(of field: ItemTypeInfo.Field) -> ItemTableColumn.Style {
        switch field.kind {
        case .boolean: return .boolean
        case .number: return .number
        case .date: return .date
        case .choice:
            return field.key == "status" ? .status : field.key == "priority" ? .priority : .choice
        case .text:
            if field.key == "status" { return .status }
            if field.key == "priority" { return .priority }
            if ["assignee", "owner", "person", "author"].contains(field.key) { return .person }
            if field.isPicked { return .choice }
            return field.key == "description" || field.key == "notes" ? .longText : .text
        case .other: return .text
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

    /// The rows the filters keep.
    static func filter(_ rows: [ItemTableRow], by filters: [String: Set<String>], columns: [ItemTableColumn]) -> [ItemTableRow] {
        let active = filters.compactMap { id, kept in columns.first { $0.id == id }.map { ($0, kept) } }
        guard !active.isEmpty else { return rows }
        return rows.filter { row in active.allSatisfy { column, kept in kept.contains(column.category(of: row) ?? "") } }
    }

    static func sorted(_ rows: [ItemTableRow], by sort: [ItemTableComparator]) -> [ItemTableRow] {
        guard !sort.isEmpty else { return rows }
        // Each row's values are read once, not at each of the roughly n log n comparisons: reading one parses a
        // date or works out a status's tone. The row's place is the last tie-break, which keeps rows that compare
        // equal in the order given, as a stable sort does.
        let values = sort.map { comparator in rows.map { comparator.column.sortValue(of: $0) } }
        let titles = rows.map(\.item.title)
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

    /// The rows in groups by `column`: a picked value's groups in the order its values are given, any other
    /// column's largest first, and the rows with no value last.
    static func groups(of rows: [ItemTableRow], by column: ItemTableColumn) -> [ItemTableGroup] {
        var buckets: [String: [ItemTableRow]] = [:]
        for row in rows { buckets[column.category(of: row) ?? "", default: []].append(row) }
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

    /// The groups folded when the person has not chosen: finished work, so what is still to do leads.
    static func collapsed(_ options: ItemTableOptions, groups: [ItemTableGroup], by column: ItemTableColumn) -> Set<String> {
        if let collapsed = options.collapsed { return collapsed }
        guard column.style == .status else { return [] }
        return Set(groups.compactMap { $0.value.flatMap { StatusTone($0).isFinished ? $0 : nil } })
    }
}
