import Foundation

/// The rows Customize Layout lists for one item, in the three groups the person arranges them in: pinned under the title
/// (at most `PagePlacement.pinLimit`, in order), on the page in the property block (in order), and hidden from it. Pure,
/// with no SwiftUI: the sidebar draws it and `PagePlacements.apply` stores a change, which is a choice for the item's
/// type, so every item of the type follows it.
///
/// Every row the type offers is listed, with a value or without, so a row can be placed before an item has one. A row
/// is moved by `moving(_:to:at:)`, `moved(_:by:)` or, for a drag on the page, `listing(_:moving:)`, which return the
/// new layout, or nil where the move is refused: a fifth pin, or Linked From, which is never pinned.
nonisolated struct PageLayout: Equatable, Sendable {
    enum Group: Sendable { case pinned, page, hidden }

    /// A row the person can place. `symbol` is the SF Symbol of the kind of value it holds.
    struct Row: Identifiable, Equatable, Sendable {
        let id: String
        let label: String
        let symbol: String
    }

    private(set) var pinned: [Row]
    private(set) var page: [Row]
    private(set) var hidden: [Row]
    /// The rows in the order nothing was chosen.
    let defaultOrder: [String]
    /// What the type pins that this item has no row for, which a change keeps behind the pins shown.
    let keptPins: [String]

    /// `rows` in their default order, placed by what the person's `placement` says.
    init(rows: [Row], placement: PagePlacement) {
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        pinned = placement.pins.filter { $0 != PagePlacement.linkedFrom }.compactMap { byID[$0] }
        keptPins = placement.pins.filter { byID[$0] == nil }
        let pinnedIDs = Set(pinned.map(\.id))
        let rest = placement.ordered(rows.filter { !pinnedIDs.contains($0.id) }, id: \.id)
        page = rest.filter { Self.shows($0.id, placement) }
        hidden = rest.filter { !Self.shows($0.id, placement) }
        defaultOrder = rows.map(\.id)
    }

    private static func shows(_ row: String, _ placement: PagePlacement) -> Bool {
        row == PagePlacement.linkedFrom ? placement.linkedFromPlace == .page : placement.showsOnPage(row)
    }

    /// Whether another row can be pinned.
    var canPin: Bool { pinned.count < PagePlacement.pinLimit }

    func group(of id: String) -> Group? {
        if pinned.contains(where: { $0.id == id }) { .pinned }
        else if page.contains(where: { $0.id == id }) { .page }
        else if hidden.contains(where: { $0.id == id }) { .hidden }
        else { nil }
    }

    func rows(in group: Group) -> [Row] {
        switch group {
        case .pinned: pinned
        case .page: page
        case .hidden: hidden
        }
    }

    /// Puts the row in `group`, at `index` among its rows (the end where nil), whichever group it was in. Nil where
    /// that is refused: a row not listed, a fifth pin, or Linked From pinned.
    func moving(_ id: String, to group: Group, at index: Int? = nil) -> PageLayout? {
        guard let current = self.group(of: id), let row = rows(in: current).first(where: { $0.id == id }) else { return nil }
        if group == .pinned, current != .pinned {
            guard canPin, id != PagePlacement.linkedFrom else { return nil }
        }
        var moved = self
        moved.pinned.removeAll { $0.id == id }
        moved.page.removeAll { $0.id == id }
        moved.hidden.removeAll { $0.id == id }
        switch group {
        case .pinned: moved.pinned.insert(row, at: Self.clamp(index, moved.pinned.count))
        case .page: moved.page.insert(row, at: Self.clamp(index, moved.page.count))
        case .hidden: moved.hidden.insert(row, at: Self.clamp(index, moved.hidden.count))
        }
        return moved
    }

    /// Lists the page's rows in `order`, the order the page drew them in once `id` was dragged, which is not always
    /// this layout's own (a pin an event's time pushed out is drawn among them, and the default order can differ from
    /// what was shown). Rows named come first, in that order; page rows it does not name follow as they were; an id
    /// that is not a page row is ignored. Nil where `id` is not a page row, such as a pin.
    func listing(_ order: [String], moving id: String) -> PageLayout? {
        guard group(of: id) == .page else { return nil }
        let byID = Dictionary(page.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let named = order.compactMap { name -> Row? in
            guard let row = byID[name], seen.insert(name).inserted else { return nil }
            return row
        }
        // The named rows take the places named rows held, so a row the page did not draw stays where it was.
        var listed = self
        let slots = page.indices.filter { seen.contains(page[$0].id) }
        for (slot, row) in zip(slots, named) { listed.page[slot] = row }
        return listed
    }

    /// Moves the row up (negative) or down within its group. Nil at either end, or for a row not listed.
    func moved(_ id: String, by offset: Int) -> PageLayout? {
        guard let group = self.group(of: id), let from = rows(in: group).firstIndex(where: { $0.id == id }) else { return nil }
        let to = from + offset
        guard to >= 0, to < rows(in: group).count else { return nil }
        return moving(id, to: group, at: to)
    }

    private static func clamp(_ index: Int?, _ count: Int) -> Int { min(max(index ?? count, 0), count) }

    /// The row ids as the person arranged them, for the order to store: the page's rows, then the hidden. The pins keep
    /// their own order.
    var arrangedOrder: [String] { (page + hidden).map(\.id) }

    /// Whether the page's rows and the hidden rows are each in the order nothing was chosen, which is then not stored.
    var isInDefaultOrder: Bool {
        func same(_ rows: [Row]) -> Bool {
            let ids = Set(rows.map(\.id))
            return defaultOrder.filter(ids.contains) == rows.map(\.id)
        }
        return same(page) && same(hidden)
    }
}

nonisolated extension PagePlacements {
    /// Stores `layout` as the choice for `type`: the pins, what the page shows and the order of its rows. Only what the
    /// layout changes is written, so a row left where its default put it stays a default, and an order equal to the
    /// default order is not kept.
    mutating func apply(_ layout: PageLayout, of type: TypeID, in catalogue: Catalogue) {
        let before = placement(of: type, in: catalogue)
        setPins(layout.pinned.map(\.id) + layout.keptPins, of: type)
        for row in layout.page + layout.pinned + layout.hidden {
            let shown = layout.group(of: row.id) != .hidden
            let wasShown = row.id == PagePlacement.linkedFrom ? before.linkedFromPlace == .page : before.showsOnPage(row.id)
            if shown != wasShown { set(shown, row: row.id, of: type, in: catalogue) }
        }
        setRowOrder(layout.isInDefaultOrder ? nil : layout.arrangedOrder, of: type)
    }
}

nonisolated extension PageLayout {
    /// The rows the page can place for `item`, in their default order: its type, source and last edit, the type's fields
    /// as the catalogue orders them (those `PageCustomization.fields` offers, with the parent after the status, and one Location for the latitude, the longitude and a name for the place), its
    /// other relationships, its tags and Linked From. The type's own rows are there whether or not the item has a
    /// value, and a type with no fields has these built-in rows only.
    static func rows(
        of item: Item, type: ItemTypeInfo?, hidden: Set<String>, relationships: [ItemRelationship], catalogue: Catalogue,
        showsCoordinates: Bool = false
    ) -> [Row] {
        var rows = [Row(id: PagePlacement.type, label: String(localized: "Type"), symbol: "square.grid.2x2")]
        if let source = item.source?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty {
            rows.append(Row(id: PagePlacement.source, label: String(localized: "Source"), symbol: "dot.radiowaves.left.and.right"))
        }
        rows.append(Row(id: PagePlacement.updated, label: String(localized: "Updated"), symbol: "calendar"))
        let offered = relationships.filter { !$0.field.hasPrefix("inverse:") }
        let parent = offered.first { $0.field == PagePlacement.parent }.map {
            Row(id: $0.field, label: $0.label, symbol: "square.stack")
        }
        var fields: [Row] = []
        let status = type?.statusField?.key
        let location = ItemLocation.of(type)
        let owned = location?.ownedKeys(showingCoordinates: showsCoordinates) ?? []
        var locationListed = false
        for field in PageCustomization.fields(of: item, type: type, hidden: hidden, catalogue: catalogue) {
            if let location, location.keys.contains(field.key) {
                // One row stands for the point and its name, where the first of them is.
                if !locationListed {
                    fields.append(Row(id: ItemLocation.rowID, label: String(localized: "Location"), symbol: ItemLocation.symbol))
                    locationListed = true
                }
                if owned.contains(field.key) { continue }
            }
            fields.append(Row(id: field.key, label: field.label, symbol: symbol(of: field)))
            if field.key == status, let parent { fields.append(parent) }
        }
        if let parent, !fields.contains(where: { $0.id == parent.id }) { fields.insert(parent, at: 0) }
        rows += fields
        rows += offered.filter { $0.field != PagePlacement.parent }.map { Row(id: $0.field, label: $0.label, symbol: "link") }
        rows.append(Row(id: PagePlacement.tags, label: String(localized: "Tags"), symbol: "tag"))
        rows.append(Row(id: PagePlacement.linkedFrom, label: String(localized: "Linked From"), symbol: "arrow.down.left"))
        return rows
    }

    /// The symbol of the value a field holds, as the page's rows draw it (`PropertyRow.Value.symbol`).
    static func symbol(of field: ItemTypeInfo.Field) -> String {
        switch field.kind {
        case .status: "circle.dotted"
        case .boolean: "checkmark.square"
        case .date: "calendar"
        case .choice: "list.bullet"
        case .number: "number"
        case .list(let shape): shape.holdsPeople ? "person.2" : "list.bullet"
        case .text: field.format == .url ? "globe" : field.format == .email ? "envelope" : "text.alignleft"
        case .words: "list.bullet"
        case .other: "text.alignleft"
        }
    }
}
