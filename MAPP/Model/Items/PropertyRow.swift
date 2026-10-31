import Foundation

/// One row of the property block an item's page draws under its title: the label and a value drawn by the
/// kind of field it came from. The block is for reading at a glance; every value is edited in the inspector, except
/// the status and the parent, which keep the menus they had as pins.
nonisolated struct PropertyRow: Identifiable, Hashable, Sendable {
    /// An item a row links to.
    struct Target: Hashable, Sendable {
        let title: String
        let item: ItemID
        /// The icon of the item's type, an Iconify ID, which the page draws before the title.
        var icon: String?
    }

    enum Value: Hashable, Sendable {
        /// The status pill, drawn by the page from the header's status pin.
        case status
        /// The parent pin, drawn the same way.
        case parent
        case items([Target])
        case tags([String])
        /// A date or datetime as a person reads it.
        case date(String)
        case url(String)
        case email(String)
        /// A number to call.
        case phone(String)
        case boolean(Bool)
        /// Text, a choice's label or a number.
        case text(String)

        /// The SF Symbol that stands for the kind of value beside its label.
        var symbol: String {
            switch self {
            case .status: "circle.dotted"
            case .parent: "square.stack"
            case .items: "link"
            case .tags: "tag"
            case .date: "calendar"
            case .url: "globe"
            case .email: "envelope"
            case .phone: "phone"
            case .boolean: "checkmark.square"
            case .text: "text.alignleft"
            }
        }

        /// Every symbol a row can show, for a page that draws them as images.
        static let symbols = ["circle.dotted", "square.stack", "link", "tag", "calendar", "globe", "envelope", "phone", "checkmark.square", "text.alignleft"]
    }

    let id: String
    let label: String
    let value: Value

    /// How many rows show before "Show N more".
    static let foldAfter = 6

    /// The rows to draw, and how many are left out until the block is expanded.
    static func split(_ rows: [PropertyRow], expanded: Bool) -> (shown: ArraySlice<PropertyRow>, hidden: Int) {
        guard !expanded, rows.count > foldAfter else { return (rows[...], 0) }
        return (rows.prefix(foldAfter), rows.count - foldAfter)
    }

    /// A text value too long to read in a row belongs in the body or the inspector.
    static let longestText = 120

    /// The rows for an item, in the order a person reads them: the type's fields as the catalogue orders them,
    /// then the parent if the item has one, then the item's other relationships, then its tags. A field shows only
    /// with a value, except the status, which always shows where the type has one, since its pill is how a status
    /// is set. The keys in `hidden` are what the page shows elsewhere, such as the title and the text, and
    /// `placement` is the person's choice of which of the rest the page shows (the inspector lists them all). An
    /// item with no parent has no parent row: the parent is set from the inspector, and the pin keeps its menu once
    /// it has a value.
    static func rows(
        of item: Item, type: ItemTypeInfo?, hidden: Set<String>, relationships: [ItemRelationship], parentField: String,
        tags: [String], placement: PagePlacement = .standard, icon: (ItemID) -> String? = { _ in nil }
    ) -> [PropertyRow] {
        var rows: [PropertyRow] = []
        let parent = relationships.contains { $0.field == parentField && !$0.targets.isEmpty }
        let status = type?.statusField
        for field in type?.fields ?? [] where !hidden.contains(field.key) {
            if field.key == status?.key {
                if placement.showsOnPage(field.key) { rows.append(PropertyRow(id: field.key, label: field.displayLabel, value: .status)) }
                if parent, placement.showsOnPage(parentField) { rows.append(parentRow(relationships, parentField)) }
            } else if placement.showsOnPage(field.key), let value = value(of: field, in: item) {
                rows.append(PropertyRow(id: field.key, label: field.displayLabel, value: value))
            }
        }
        if parent, placement.showsOnPage(parentField), !rows.contains(where: { $0.value == .parent }) {
            rows.insert(parentRow(relationships, parentField), at: 0)
        }
        for relationship in relationships
        where !relationship.field.hasPrefix("inverse:") && relationship.field != parentField && placement.showsOnPage(relationship.field) {
            let targets = relationship.targets.compactMap { target -> Target? in
                guard target.isOpenable, !target.isDeleted, let id = target.itemID else { return nil }
                return Target(title: target.title, item: id, icon: icon(id))
            }
            if !targets.isEmpty {
                rows.append(PropertyRow(id: relationship.field, label: ItemTypeInfo.Field.displayLabel(relationship.label), value: .items(targets)))
            }
        }
        if !tags.isEmpty, placement.showsOnPage(PagePlacement.tags) {
            rows.append(PropertyRow(id: PagePlacement.tags, label: String(localized: "Tags"), value: .tags(tags)))
        }
        return rows
    }

    private static func parentRow(_ relationships: [ItemRelationship], _ field: String) -> PropertyRow {
        let label = relationships.first { $0.field == field }?.label ?? String(localized: "Parent")
        return PropertyRow(id: field, label: ItemTypeInfo.Field.displayLabel(label), value: .parent)
    }

    /// The value a field's row draws, or nil where the field has none or holds something a row does not show.
    static func value(of field: ItemTypeInfo.Field, in item: Item) -> Value? {
        guard let stored = item.value(of: field.key), InspectorFields.hasValue(stored) else { return nil }
        switch (field.kind, stored) {
        case (.boolean, .bool(let flag)): return .boolean(flag)
        case (.number, .number(let number)): return .text(number.formatted())
        case (.date, .string(let text)): return .date(ItemDate.parse(text)?.text() ?? text)
        case (.choice, .string(let text)): return .text(ItemTypeInfo.Field.label(ofOption: text))
        case (.text, .string(let text)):
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if field.format == .url { return .url(text) }
            if field.format == .email { return .email(text) }
            guard !text.contains(where: \.isNewline), text.count <= longestText else { return nil }
            return .text(text)
        case (_, .array(let values)):
            let words = values.compactMap(\.string).filter { !$0.isEmpty }
            return words.count == values.count && !words.isEmpty ? .tags(words) : nil
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

    init(item: Item, now: Date, calendar: Calendar = .current, locale: Locale = .current) {
        let source = item.source?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source?.isEmpty == false ? source : nil
        date = NoteDate.listLabel(for: item.created, now: now, calendar: calendar, locale: locale)
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
        pointingTo id: ItemID, in relationships: [ItemRelationship], catalogue: Catalogue, now: Date,
        members: Members = .all, item: (ItemID) -> Item?, calendar: Calendar = .current, locale: Locale = .current
    ) -> [LinkedItem] {
        Cost.measure(.linkedItems) {
            find(pointingTo: id, in: relationships, catalogue: catalogue, now: now, members: members, item: item, calendar: calendar, locale: locale)
        }
    }

    private static func find(
        pointingTo id: ItemID, in relationships: [ItemRelationship], catalogue: Catalogue, now: Date,
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
                    date: NoteDate.listLabel(for: held.modified, now: now, calendar: calendar, locale: locale))
            }
    }
}
