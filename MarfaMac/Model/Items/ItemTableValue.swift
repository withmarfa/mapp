import Foundation
import Marfa

/// One row of the table: an item, with what its cells show that the item alone does not say.
nonisolated struct ItemTableRow: Identifiable, Hashable, Sendable {
    let item: Item
    let typeLabel: String
    let typeIcon: String?
    /// The item the row's item is filed under (`child-of`), if it is to be shown (`ItemRelations`).
    let parent: RelatedItem?
    /// The items filed under the row's item and the collections it is in, which the columns for them show. A row holds
    /// only the links the table asked for (`rows(of:in:wanting:)`); the others are empty.
    var children: [RelatedItem] = []
    var collections: [RelatedItem] = []
    /// What Marfa answered for the counts the table's looks ask for (`rows(of:in:wanting:looks:)`).
    var counts: [CountFact: ItemCountAnswer] = [:]
    var id: ItemID { item.id }

    func items(of relation: Relation) -> [RelatedItem] {
        switch relation {
        case .parent: parent.map { [$0] } ?? []
        case .children: children
        case .collections: collections
        }
    }
}

extension ItemTableRow {
    @MainActor
    static func rows(
        of items: [Item], in library: any ItemLibrary, wanting wanted: Set<Relation> = [], looks: [TypeID: TypeLook] = [:]
    ) -> [ItemTableRow] {
        let catalogue = library.catalogue
        return items.map { item in
            let relations = library.relations(of: item, wanting: wanted, counts: (looks[item.type] ?? .empty).counts)
            return ItemTableRow(
                item: item,
                typeLabel: catalogue.label(for: item.type),
                typeIcon: catalogue.icon(for: item.type),
                parent: relations.parent, children: relations.children, collections: relations.collections, counts: relations.counts)
        }
    }
}

/// A column of the table: which part of an item it shows, and how.
nonisolated struct ItemTableColumn: Identifiable, Hashable, Sendable {
    enum Content: Hashable, Sendable {
        case title, type, parent, children, collections, created, edited
        /// A count worked out when read (`CountFact`), which a look shows as its fact.
        case count(CountFact)
        /// When the item happened (Marfa's `occurred_at`), which a record's look shows as its date.
        case occurred
        /// The item's tags, which an item's look shows as its fact.
        case tags
        /// The time between two date fields, as a session's start and end.
        case duration(start: String, end: String)
        case field(ItemTypeInfo.Field)
    }

    enum Style: Hashable, Sendable {
        case title, status, priority, choice, date, number, boolean, link, text, duration
        case count
        /// Several linked items, shown as their chips. Not a value to group or filter by.
        case links

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

    /// The link this column shows, if it is the column of one.
    var relation: Relation? {
        switch content {
        case .parent: .parent
        case .children: .children
        case .collections: .collections
        default: nil
        }
    }

    /// Whether the cells hold a few values a person picks from, which the table can group and filter by.
    var isCategorical: Bool {
        switch style {
        case .status, .priority, .choice, .boolean, .link: true
        case .title, .date, .number, .text, .duration, .links, .count: content == .type
        }
    }

    static let title = ItemTableColumn(id: "title", label: String(localized: "Name"), content: .title, style: .title)
    static let type = ItemTableColumn(id: "type", label: String(localized: "Type"), content: .type, style: .text)
    static let parent = ItemTableColumn(id: "parent", label: "", content: .parent, style: .link)
    static let children = ItemTableColumn(
        id: "children", label: "", content: .children, style: .links, isShownByDefault: false)
    static let collections = ItemTableColumn(
        id: "collections", label: "", content: .collections, style: .links, isShownByDefault: false)
    static let edited = ItemTableColumn(id: "edited", label: String(localized: "Edited"), content: .edited, style: .date)
    static let created = ItemTableColumn(
        id: "created", label: String(localized: "Created"), content: .created, style: .date, isShownByDefault: false)
    static let occurred = ItemTableColumn(
        id: "occurred", label: String(localized: "Happened"), content: .occurred, style: .date, isShownByDefault: false)
    static let tags = ItemTableColumn(
        id: "tags", label: String(localized: "Tags"), content: .tags, style: .text, isShownByDefault: false)

    /// The column of a count, headed as the count is named. A type with a status calls its children subtasks.
    static func count(_ fact: CountFact, hasStatus: Bool) -> ItemTableColumn {
        ItemTableColumn(
            id: "count." + fact.word.dropFirst("count:".count).replacingOccurrences(of: ":", with: "."),
            label: CountWording.heading(of: fact, hasStatus: hasStatus), content: .count(fact), style: .count)
    }

    /// The column of a link, headed with Marfa's name for it (`Relation.label`).
    static func relation(_ relation: Relation, in catalogue: Catalogue) -> ItemTableColumn {
        var column: ItemTableColumn = switch relation {
        case .parent: .parent
        case .children: .children
        case .collections: .collections
        }
        column.label = relation.label(in: catalogue)
        return column
    }
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

    /// The panel an empty cell of this column opens to take a first value, or nil where it offers none: the column is no
    /// field, the row's type does not declare it, the item cannot be edited, the cell holds a value, or its value is
    /// picked from a menu or switched (a status, priority, choice or yes or no), which the cell edits in place.
    func addKind(for row: ItemTableRow, catalogue: Catalogue) -> ValueEditKind? {
        guard let field = field(for: row, catalogue: catalogue), row.item.isEditable, !picksFrom(field),
              let kind = ValueEditKind(field: field) else { return nil }
        guard !InspectorFields.hasValue(row.item.value(of: field.key)) else { return nil }
        return kind
    }

    /// Whether the row's own field is picked from a menu or switched in place, whatever the merged column's style is.
    func picksFrom(_ field: ItemTypeInfo.Field) -> Bool {
        switch style(for: field) {
        case .status, .priority, .choice, .boolean: true
        default: false
        }
    }

    /// The column's style as this row's field has it: a merged column takes the style of one type's field, and another
    /// type's field of the same key may be a different kind.
    func style(for field: ItemTypeInfo.Field) -> Style {
        switch field.kind {
        case .boolean: return .boolean
        case .status where field.isPicked: return .status
        case .choice where field.isPicked: return style == .priority ? .priority : .choice
        default:
            switch style {
            case .status, .priority, .choice, .boolean: return .text
            default: return style
            }
        }
    }

    /// What the cell holds for grouping and filtering: a value from the item, or nil for an empty cell.
    func category(of row: ItemTableRow) -> String? {
        switch content {
        case .type: return row.item.type.rawValue
        case .parent: return row.parent?.id.rawValue
        case .field(let field): return ItemTableValue.string(row, key: field.key)
        case .title, .children, .collections, .count, .created, .edited, .occurred, .tags, .duration: return nil
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
        case .title, .children, .collections, .count, .created, .edited, .occurred, .tags, .duration: return value
        }
    }

    /// Sorting by count would need answers for rows the table has yet to display.
    var isSortable: Bool {
        if case .count = content { false } else { true }
    }

    func sortValue(of row: ItemTableRow) -> ItemTableValue.Sort? {
        switch content {
        case .title: return .text(row.item.displayTitle)
        case .type: return .text(row.typeLabel)
        case .parent: return row.parent.map { .text($0.title) }
        case .children: return row.children.first.map { .text($0.title) }
        case .collections: return row.collections.first.map { .text($0.title) }
        case .count: return nil
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
