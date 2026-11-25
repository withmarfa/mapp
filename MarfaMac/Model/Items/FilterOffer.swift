import Foundation
import Marfa

/// A field a filter can be made on: what it is called, what kind of values it holds, and where those values live.
nonisolated struct FilterTarget: Hashable, Sendable, Identifiable {
    let id: String
    var label: String
    var kind: FilterKind
    /// The type's field, for a field of a type; nil for what every item has.
    var field: ItemTypeInfo.Field?
    /// A list's member a person is found by, such as `name`.
    var member: String?

    /// The property a field of a type is kept in.
    var key: String? { field?.key }

    /// Whether the field is a date that names a day and never a moment. Marfa reads such a value as its midnight in UTC
    /// (`search-and-filters/filter-property-instant`), so a filter on it counts days on the UTC clock, not the Mac's.
    var isDateOnly: Bool {
        if kind == .date, case .date(includesTime: false)? = field?.kind { true } else { false }
    }

    /// The words a status or choice declares, in the order the types give them.
    var declared: [String] { field?.options ?? [] }

    static let type = FilterTarget(id: ItemTableColumn.type.id, label: String(localized: "Type"), kind: .type)
    static let tags = FilterTarget(id: ItemTableColumn.tags.id, label: String(localized: "Tags"), kind: .tags)
    static let collection = FilterTarget(id: ItemTableColumn.collections.id, label: String(localized: "Collection"), kind: .collection)
    static let parent = FilterTarget(id: ItemTableColumn.parent.id, label: String(localized: "Parent"), kind: .parent)
    static let source = FilterTarget(id: "source", label: String(localized: "Source"), kind: .source)
    /// Which tier an item is in, as the From control names it. It is a source-kind target, since it says where an item
    /// came from in the same words and offers the same operators. Only a search offers it (`SearchOffers`); Filter By does not.
    static let tier = FilterTarget(id: "tier", label: String(localized: "From"), kind: .source)

    /// Whether the target is the tier rather than the source code.
    var isTier: Bool { id == Self.tier.id }
    static let created = FilterTarget(id: ItemTableColumn.created.id, label: ItemTableColumn.created.label, kind: .moment)
    static let edited = FilterTarget(id: ItemTableColumn.edited.id, label: ItemTableColumn.edited.label, kind: .moment)
    static let occurred = FilterTarget(id: ItemTableColumn.occurred.id, label: ItemTableColumn.occurred.label, kind: .moment)

    /// What every item has, in the order Filter By lists it.
    static let everyItem: [FilterTarget] = [.type, .tags, .collection, .parent, .source, .created, .edited, .occurred]

    /// The target of a field of a type, or nil where the grammar has no way to ask about it: a list of words, or a shape
    /// the app only shows. `style` is how the place's column reads the field, which the most specific of the types' wins.
    static func target(id: String, label: String, field: ItemTypeInfo.Field, style: ItemTableColumn.Style) -> FilterTarget? {
        let kind: FilterKind
        var member: String?
        switch style {
        case .status: kind = .status
        case .priority, .choice: kind = .choice
        case .boolean: kind = .boolean
        case .date: kind = .date
        case .number: kind = .number
        case .text:
            switch field.kind {
            case .text: kind = .text
            case .list(let shape):
                let texts = shape.members.filter { if case .text = $0.kind { true } else { false } }
                guard let named = texts.first(where: { $0.key == "name" }) ?? texts.first else { return nil }
                kind = .people
                member = named.key
            default: return nil
            }
        default: return nil
        }
        return FilterTarget(id: id, label: label, kind: kind, field: field, member: member)
    }

    static func target(of column: ItemTableColumn) -> FilterTarget? {
        column.field.flatMap { target(id: column.id, label: column.label, field: $0, style: column.style) }
    }

    /// The target a property is filtered as, from the catalogue alone, where no table has built its columns: the field of
    /// the most specific style any of `types` gives it (`ItemTableColumn.Style.specificity`), or of every type where none
    /// is given. Nil where no type declares it.
    static func target(ofProperty key: String, among types: Set<TypeID>, catalogue: Catalogue) -> FilterTarget? {
        var best: (field: ItemTypeInfo.Field, style: ItemTableColumn.Style)?
        let scope = types.isEmpty ? Array(catalogue.itemTypes.keys) : Array(types)
        for type in scope.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let field = catalogue.itemTypes[type]?.fields.first(where: { $0.key == key }) else { continue }
            let style = ItemTableLayout.style(of: field, in: type, catalogue: catalogue)
            if best == nil || style.specificity > best!.style.specificity { best = (field, style) }
        }
        return best.flatMap { target(id: Browser.fieldColumnPrefix + key, label: $0.field.label, field: $0.field, style: $0.style) }
    }

    /// The fields of `types`, or of every type in the catalogue where none are given, found from the catalogue alone: the
    /// status first, then in the order the types declare them, each as `target(ofProperty:among:catalogue:)` reads it.
    static func fields(among types: Set<TypeID>, catalogue: Catalogue) -> [FilterTarget] {
        var keys: [String] = []
        var skipped: Set<String> = ["title", "body"]
        let scope = types.isEmpty ? Set(catalogue.itemTypes.keys) : types
        for type in scope.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let info = catalogue.itemTypes[type] else { continue }
            skipped.formUnion([info.titleKey, info.bodyKey].compactMap { $0 })
            for field in info.fields where !keys.contains(field.key) { keys.append(field.key) }
        }
        var targets = keys.filter { !skipped.contains($0) }.compactMap { target(ofProperty: $0, among: types, catalogue: catalogue) }
        if let status = targets.firstIndex(where: { $0.kind == .status }) { targets.insert(targets.remove(at: status), at: 0) }
        return targets
    }
}

/// What Filter By offers for a place, drawn alike wherever a filter is added: the fields of the types the place lists
/// under their names, then what every item has ([docs/lists.md](../../../docs/lists.md#filters)). The fields
/// come from the types the place lists, as Group by's do (`GroupOffer`), never only from the items on screen, so a field
/// no item fills yet can still be chosen.
nonisolated struct FilterOffer: Hashable, Sendable {
    /// The place's types by name, as the header of their fields reads: "Tasks and Projects".
    var placeTitle: String
    /// The fields of the place's types: the status first, then in the order the looks show them.
    var placeFields: [FilterTarget]
    var everyItem: [FilterTarget]
    /// The types the place lists and holds.
    var typeIDs: Set<TypeID>
    /// Whether the place lists more than one type, which puts a status's groups before its words.
    var hasSeveralTypes: Bool { typeIDs.count > 1 }

    /// Every target by identifier.
    var targets: [String: FilterTarget] {
        Dictionary((placeFields + everyItem).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func make(columns: [ItemTableColumn], types: Set<TypeID>, catalogue: Catalogue) -> FilterOffer {
        var fields: [FilterTarget] = []
        var seen = Set<String>()
        var skipped: Set<String> = ["title", "body"]
        for type in types {
            guard let info = catalogue.itemTypes[type] else { continue }
            skipped.formUnion([info.titleKey, info.bodyKey].compactMap { $0 })
        }
        for column in columns where seen.insert(column.id).inserted {
            guard let target = FilterTarget.target(of: column), let key = target.key, !skipped.contains(key) else { continue }
            fields.append(target)
        }
        // The status leads; the rest keep the order the columns give.
        if let status = fields.firstIndex(where: { $0.kind == .status }) { fields.insert(fields.remove(at: status), at: 0) }
        let labels = types.compactMap { catalogue.itemTypes[$0]?.plural }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let title = labels.count <= 3 ? labels.formatted(.list(type: .and, width: .standard)) : String(localized: "This Place")
        return FilterOffer(placeTitle: title, placeFields: fields, everyItem: FilterTarget.everyItem, typeIDs: types)
    }
}
