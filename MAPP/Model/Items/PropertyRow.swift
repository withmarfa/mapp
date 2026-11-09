import Foundation
import Marfa

/// One row of the property block an item's page draws under its title, or one pin above it: the label and a value
/// drawn by the kind of field it came from. A row the item can take an edit for (`editable`) opens its editor under
/// the value, as the status and the parent keep their menus; every other value is edited in the inspector.
nonisolated struct PropertyRow: Identifiable, Hashable, Sendable {
    /// An item a row links to.
    struct Target: Hashable, Sendable {
        let title: String
        let item: ItemID
        /// The icon of the item's type, an Iconify ID, which the page draws before the title.
        var icon: String?
        var kind: Kind = .link

        /// How the page draws the item: as its type does (a type mark and tint), or as a person (initials, then the name).
        enum Kind: String, Hashable, Sendable { case link, person }
    }

    enum Value: Hashable, Sendable {
        /// The status pill, drawn by the page from the header's status menu.
        case status
        /// The parent's pill, drawn the same way. A pinned parent is `items`, a link that only opens it.
        case parent
        /// The name of the item's type, drawn as the type's chip: its mark and tint come from its icon.
        case type(String, icon: String?)
        /// What the item came from, by the name the library gives its source.
        case source(String)
        case items([Target])
        /// The entries of a list of people, each by the name it goes by (`ListShape.personName`), drawn as the person chip.
        case people([String])
        /// A choice, or a list of words a field holds, such as labels: each drawn with a dot of its own color.
        case options([String])
        /// The item's own tags, each drawn after a `#`.
        case tags([String])
        /// A date or datetime as a person reads it.
        case date(String)
        /// An event's first pin: when it happens, with its zone and how far off it is in the help.
        case when(String, help: String)
        case url(String)
        case email(String)
        /// A number to call.
        case phone(String)
        case boolean(Bool)
        /// Text, a choice's label or a number.
        case text(String)
        /// A value the item does not have yet, drawn as the word Empty. It only opens the editor, so it is always
        /// `editable`. The symbol is the one a value of the field's kind has.
        case empty(symbol: String)

        /// The SF Symbol that stands for the kind of value beside its label.
        var symbol: String {
            switch self {
            case .status: "circle.dotted"
            case .parent: "square.stack"
            case .type: "square.grid.2x2"
            case .source: "dot.radiowaves.left.and.right"
            case .items: "link"
            case .people: "person.2"
            case .options: "list.bullet"
            case .tags: "tag"
            case .date: "calendar"
            case .when: "clock"
            case .url: "globe"
            case .email: "envelope"
            case .phone: "phone"
            case .boolean: "checkmark.square"
            case .text: "text.alignleft"
            case .empty(let symbol): symbol
            }
        }

        /// Every symbol a row can show, for a page that draws them as images.
        static let symbols = ["circle.dotted", "square.stack", "link", "tag", "calendar", "globe", "envelope", "phone", "checkmark.square", "text.alignleft", "list.bullet", "person.2", "square.grid.2x2", "dot.radiowaves.left.and.right", "clock"]
    }

    let id: String
    let label: String
    let value: Value
    /// The number to call the main entry of a list holds, where its list can hold one (`ListShape.numberToCall`).
    var numberToCall: String?
    /// How many values of a list a pin left out, for the "+N" after the first two. Always 0 in the property block.
    var more = 0
    /// Whether the value opens an editor under it, or for a yes or no flips: any value that can be edited, on an item
    /// that can take the edit. The app says so; the page never decides it.
    var editable = false

    /// Whether the row is a value the item does not have yet.
    var isEmpty: Bool {
        if case .empty = value { true } else { false }
    }

    /// How many rows show before "Show N more".
    static let foldAfter = 6

    /// The rows to draw, and how many are left out until the block is expanded.
    static func split(_ rows: [PropertyRow], expanded: Bool) -> (shown: ArraySlice<PropertyRow>, hidden: Int) {
        guard !expanded, rows.count > foldAfter else { return (rows[...], 0) }
        return (rows.prefix(foldAfter), rows.count - foldAfter)
    }

    /// A text value too long to read in a row belongs in the body or the inspector.
    static let longestText = 120

    /// The rows of the property block, in the order the person chose, else the order a person reads them: of the item's
    /// `candidates`, those the person's `placement` shows, except `excluding`, which the page shows another way
    /// (`PagePins.leftOutOfBlock`).
    static func block(_ candidates: [PropertyRow], placement: PagePlacement, excluding: Set<String> = []) -> [PropertyRow] {
        placement.ordered(candidates.filter { placement.showsOnPage($0.id) && !excluding.contains($0.id) }, id: \.id)
    }

    /// Every row the item could show, whatever the person chose, in the order a person reads them: its type, source
    /// and last edit, the type's fields as the catalogue orders them, then the parent if the item has one, then the
    /// item's other relationships, then its tags. A field shows only with a value, except the status, which always
    /// shows where the type has one, since its pill is how a status is set from the page. The keys in `hidden` are what
    /// the page shows elsewhere, such as the title and the text. With `offersEmpty`, an editable value the item does not
    /// have yet is a row too, read as Empty, that opens its editor: that is the page's way to give a value to the
    /// field, the parent and the tags. Empty rows come after the others in each group, so the fold hides them first. The
    /// block and the pins are both chosen from these.
    static func candidates(
        of item: Item, type: ItemTypeInfo?, hidden: Set<String>, relationships: [ItemRelationship], parentField: String, format: DateFormat,
        tags: [String], typeLabel: String?, typeIcon: String?, sourceName: String?, now: Date, calendar: Calendar, locale: Locale,
        offersEmpty: Bool = false, changesType: Bool? = nil, icon: (ItemID) -> String?, isPerson: (ItemID) -> Bool
    ) -> [PropertyRow] {
        var rows: [PropertyRow] = []
        if let typeLabel {
            rows.append(PropertyRow(id: PagePlacement.type, label: String(localized: "Type"), value: .type(typeLabel, icon: typeIcon), editable: changesType ?? item.isEditable))
        }
        if let source = (sourceName ?? item.source)?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty {
            rows.append(PropertyRow(id: PagePlacement.source, label: String(localized: "Source"), value: .source(source)))
        }
        rows.append(PropertyRow(
            id: PagePlacement.updated, label: String(localized: "Updated"),
            value: .date(DateDisplay.text(of: item.modified, place: .list, format: format, now: now, calendar: calendar, locale: locale))))
        var fields: [PropertyRow] = []
        var empty: [PropertyRow] = []
        let parent = relationships.contains { $0.field == parentField && !$0.targets.isEmpty }
        let status = type?.statusField
        for field in type?.fields ?? [] where !hidden.contains(field.key) {
            if field.key == status?.key {
                fields.append(PropertyRow(id: field.key, label: field.label, value: .status))
                if parent { fields.append(parentRow(relationships, parentField)) }
            } else if let value = value(of: field, in: item, format: format) {
                fields.append(PropertyRow(
                    id: field.key, label: field.label, value: value, numberToCall: numberToCall(of: field, in: item),
                    editable: item.isEditable && isEdited(field)))
            } else if offersEmpty, item.isEditable, isEdited(field), !InspectorFields.hasValue(item.value(of: field.key)) {
                empty.append(PropertyRow(id: field.key, label: field.label, value: .empty(symbol: symbol(of: field)), editable: true))
            }
        }
        if parent, !fields.contains(where: { $0.value == .parent }) { fields.insert(parentRow(relationships, parentField), at: 0) }
        if offersEmpty, !parent, item.isEditable, let none = relationships.first(where: { $0.field == parentField && $0.isEditable }) {
            empty.append(PropertyRow(id: parentField, label: none.label, value: .empty(symbol: "square.stack"), editable: true))
        }
        rows += fields + empty
        for relationship in relationships where !relationship.field.hasPrefix("inverse:") && relationship.field != parentField {
            if let row = linkRow(relationship, icon: icon, isPerson: isPerson) { rows.append(row) }
        }
        if !tags.isEmpty {
            rows.append(PropertyRow(id: PagePlacement.tags, label: String(localized: "Tags"), value: .tags(tags), editable: item.canEditTags))
        } else if offersEmpty, item.canEditTags {
            rows.append(PropertyRow(id: PagePlacement.tags, label: String(localized: "Tags"), value: .empty(symbol: "tag"), editable: true))
        }
        return rows
    }

    /// Whether the page edits the field's value: in a panel, or for a yes or no with a click.
    private static func isEdited(_ field: ItemTypeInfo.Field) -> Bool {
        field.kind == .boolean || ValueEditKind(field: field) != nil
    }

    /// The symbol a value of the field's kind has beside its name, as `Value.symbol` gives it to the value itself.
    private static func symbol(of field: ItemTypeInfo.Field) -> String {
        switch field.kind {
        case .date: Value.date("").symbol
        case .boolean: Value.boolean(false).symbol
        case .list(let shape) where shape.holdsPeople: Value.people([]).symbol
        case .status: Value.status.symbol
        case .choice, .words, .list: Value.options([]).symbol
        case .text where field.format == .url: Value.url("").symbol
        case .text where field.format == .email: Value.email("").symbol
        default: Value.text("").symbol
        }
    }

    /// The row of the items a relationship links to, or nil where it links to none the page can open.
    static func linkRow(_ relationship: ItemRelationship, icon: (ItemID) -> String?, isPerson: (ItemID) -> Bool) -> PropertyRow? {
        let targets = relationship.targets.compactMap { target -> Target? in
            guard target.isOpenable, !target.isDeleted, let id = target.itemID else { return nil }
            return Target(title: target.title, item: id, icon: icon(id), kind: isPerson(id) ? .person : .link)
        }
        return targets.isEmpty ? nil : PropertyRow(id: relationship.field, label: relationship.label, value: .items(targets))
    }

    private static func parentRow(_ relationships: [ItemRelationship], _ field: String) -> PropertyRow {
        let label = relationships.first { $0.field == field }?.label ?? String(localized: "Parent")
        return PropertyRow(id: field, label: label, value: .parent)
    }

    /// The number to call a list field's main entry holds, or nil.
    static func numberToCall(of field: ItemTypeInfo.Field, in item: Item) -> String? {
        guard case .list(let shape) = field.kind, let main = ListEntries.main(of: item.value(of: field.key)) else { return nil }
        return shape.numberToCall(in: main)
    }

    /// The value a field's row draws, or nil where the field has none or holds something a row does not show.
    static func value(of field: ItemTypeInfo.Field, in item: Item, format: DateFormat) -> Value? {
        guard let stored = item.value(of: field.key), InspectorFields.hasValue(stored) else { return nil }
        switch (field.kind, stored) {
        case (.list(let shape), .array(let entries)):
            if shape.holdsPeople {
                let names = entries.compactMap { ListEntries.object($0).flatMap(shape.personName(of:)) }
                return names.isEmpty ? nil : .people(names)
            }
            // Only the main entry shows on the page; the inspector lists them all.
            guard let main = entries.first.flatMap(ListEntries.object) else { return nil }
            return shape.rowValue(of: main)
        case (.boolean, .bool(let flag)): return .boolean(flag)
        case (.number, .number(let number)): return .text(number.formatted())
        case (.date, .string(let text)): return .date(ItemDate.parse(text)?.text(format: format) ?? text)
        case (.choice, .string(let text)): return .options([ItemTypeInfo.Field.label(ofOption: text)])
        case (.text, .string(let text)):
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if field.format == .url { return .url(text) }
            if field.format == .email { return .email(text) }
            guard !text.contains(where: \.isNewline), text.count <= longestText else { return nil }
            return .text(text)
        case (_, .array(let values)):
            let words = values.compactMap(\.string).filter { !$0.isEmpty }
            return words.count == values.count && !words.isEmpty ? .options(words) : nil
        default: return nil
        }
    }
}

/// Who made the item and when, under its title: the source the library names, and the day in the list's own
/// words.
nonisolated struct PageByline: Hashable, Sendable, Encodable {
    var source: String?
    var date: String
    /// A last part some pages add, such as how long a page takes to read.
    var detail: String?

    init(source: String?, date: String, detail: String? = nil) {
        self.source = source
        self.date = date
        self.detail = detail
    }

    /// `sourceName` is what the server names the item's source (`SourceDirectory.name`), given for an item that has one.
    init(item: Item, sourceName: String? = nil, now: Date, format: DateFormat, calendar: Calendar = .current, locale: Locale = .current) {
        let source = (sourceName ?? item.source)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source?.isEmpty == false ? source : nil
        date = DateDisplay.text(of: item.created, place: .list, format: format, now: now, calendar: calendar, locale: locale)
    }
}

/// An item that links to the one on the page, listed at its foot.
nonisolated struct LinkedItem: Hashable, Sendable, Encodable {
    let item: ItemID
    let title: String
    /// The icon of the item's type, an Iconify ID.
    let icon: String?
    let type: String
    let date: String

    /// Most items listed before "Show N more".
    static let foldAfter = LinkLimit.limit

    private enum CodingKeys: String, CodingKey { case item, title, symbol, type, date }

    /// The editor page draws the icon from the images the app sends (`PageHeaderIcons`), which it finds by this key.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(item, forKey: .item)
        try container.encode(title, forKey: .title)
        try container.encode(TypeIconKey.value(for: icon), forKey: .symbol)
        try container.encode(type, forKey: .type)
        try container.encode(date, forKey: .date)
    }

    /// Which of the items that point at a collection a list holds: a collection's members are its contents, and
    /// every other link to it is a plain link to it.
    enum Members {
        case all, only, excluding

        fileprivate func admits(_ field: String) -> Bool {
            let isMembership = field == "inverse:" + MarfaMapping.collectionEdge
            switch self {
            case .all: return true
            case .only: return isMembership
            case .excluding: return !isMembership
            }
        }
    }

    /// The active items that hold a link to `id` in any relationship the library reads (the inverse ones), once
    /// each, the most recently edited first.
    static func list(
        pointingTo id: ItemID, in relationships: [ItemRelationship], catalogue: Catalogue, now: Date, format: DateFormat,
        members: Members = .all, item: (ItemID) -> Item?, calendar: Calendar = .current, locale: Locale = .current
    ) -> [LinkedItem] {
        Cost.measure(.linkedItems) {
            find(pointingTo: id, in: relationships, catalogue: catalogue, now: now, format: format, members: members, item: item, calendar: calendar, locale: locale)
        }
    }

    private static func find(
        pointingTo id: ItemID, in relationships: [ItemRelationship], catalogue: Catalogue, now: Date, format: DateFormat,
        members: Members, item: (ItemID) -> Item?, calendar: Calendar, locale: Locale
    ) -> [LinkedItem] {
        var seen: Set<ItemID> = [id]
        var found: [Item] = []
        for relationship in relationships where relationship.field.hasPrefix("inverse:") && members.admits(relationship.field) {
            for target in relationship.targets {
                guard let other = target.itemID, !target.isDeleted, let held = item(other), held.state == .active,
                      seen.insert(other).inserted else { continue }
                found.append(held)
            }
        }
        return found
            .sorted { $0.modified != $1.modified ? $0.modified > $1.modified : $0.title < $1.title }
            .map { held in
                LinkedItem(
                    item: held.id, title: held.title, icon: catalogue.icon(for: held.type),
                    type: catalogue.label(for: held.type),
                    date: DateDisplay.text(of: held.modified, place: .list, format: format, now: now, calendar: calendar, locale: locale))
            }
    }
}
