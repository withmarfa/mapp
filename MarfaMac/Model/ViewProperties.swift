import Foundation

/// The Properties list of one view or place: what shows after the title, in what order, in every layout. A table draws
/// the shown ones as columns; a list row, a board card, a gallery card and a timeline row say the first few as chips.
///
/// An empty list is "As in Layouts": nothing is chosen, so each item shows its own type's look. The first change makes it
/// the person's, "This Mac", and Use Layouts (`reset`) puts the fallback back. It is one of the app's settings, which sync: in
/// a saved view's (`ViewMacSettings`) and a place's default view (`PlaceDefault`), never in the view Marfa holds.
nonisolated struct ViewProperties: Codable, Hashable, Sendable {
    /// The identifiers in the order the person gave. Empty follows the place's own order. A property not named
    /// follows those named.
    private(set) var order: [String] = []
    /// A property's choice where it differs from whether it shows by default, so the same arrangement is the
    /// same value however it was reached.
    private(set) var shown: [String: Bool] = [:]

    init(order: [String] = [], shown: [String: Bool] = [:]) {
        self.order = order
        self.shown = shown
    }

    /// Whether the person changed the list, so it is theirs and no longer the looks'.
    var isChanged: Bool { !order.isEmpty || !shown.isEmpty }

    func isShown(_ column: ItemTableColumn) -> Bool {
        column.content == .title || (shown[column.id] ?? column.isShownByDefault)
    }

    /// Every property in the person's order, the name first. A stored identifier the place no longer offers is
    /// ignored, and a property the order does not name follows in the place's own order.
    func arranged(_ columns: [ItemTableColumn]) -> [ItemTableColumn] {
        let name = columns.filter { $0.content == .title }
        let others = columns.filter { $0.content != .title }
        let byID = Dictionary(others.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var named: [ItemTableColumn] = []
        var seen = Set<String>()
        for id in order {
            if let column = byID[id], seen.insert(id).inserted { named.append(column) }
        }
        return name + named + others.filter { !seen.contains($0.id) }
    }

    /// The properties shown, in order: the columns of a table.
    func shownColumns(_ columns: [ItemTableColumn]) -> [ItemTableColumn] {
        arranged(columns).filter(isShown)
    }

    mutating func setShown(_ column: ItemTableColumn, _ isShown: Bool) {
        guard column.content != .title else { return }
        shown[column.id] = isShown == column.isShownByDefault ? nil : isShown
    }

    /// Moves a property to sit before another, or last. The name stays first. The saved place of a property the place
    /// lacks is kept, since another place may have it again, so the move is spliced into the order.
    mutating func move(_ id: String, before other: String?, in columns: [ItemTableColumn]) {
        let own = columns.filter { $0.content != .title }.map(\.id)
        guard id != other, own.contains(id) else { return }
        var seen = Set<String>()
        var spliced = order.filter { seen.insert($0).inserted }
        spliced += own.filter { seen.insert($0).inserted }
        spliced.removeAll { $0 == id }
        spliced.insert(id, at: other.flatMap { spliced.firstIndex(of: $0) } ?? spliced.count)
        order = spliced == own ? [] : spliced
    }

    /// The order a table header drag wrote. The header lists only the shown columns, so a hidden one and a stored
    /// identifier the place lacks keep their places, and the name stays first. A drag that is not those shown columns
    /// rearranged is ignored, and an order that matches the place's own is stored as none.
    mutating func adoptHeaderOrder(_ header: [String], in columns: [ItemTableColumn]) {
        let own = columns.filter { $0.content != .title }.map(\.id)
        let title = columns.first { $0.content == .title }?.id
        let shown = Set(shownColumns(columns).map(\.id))
        var seen = Set<String>()
        let dragged = header.filter { id in id != title && shown.contains(id) && seen.insert(id).inserted }
        guard !dragged.isEmpty else { return }
        var seenAll = Set<String>()
        var full = order.filter { seenAll.insert($0).inserted }
        full += own.filter { seenAll.insert($0).inserted }
        let shownNow = full.filter { shown.contains($0) }
        guard Set(dragged) == Set(shownNow) else { return }
        var index = dragged.startIndex
        var next: [String] = []
        for id in full {
            if shown.contains(id) {
                next.append(dragged[index])
                index = dragged.index(after: index)
            } else {
                next.append(id)
            }
        }
        order = next == own ? [] : next
    }

    /// Use Layouts: the list as each type's look gives it.
    mutating func reset() {
        self = ViewProperties()
    }
}

// MARK: What a layout can say

nonisolated extension ItemTableColumn {
    /// Whether a row or a card can say it as a chip: the status and the type, a field, the tags, a link or a count. The
    /// item's own dates have their place on the row (the look's date), so only a table shows them as properties.
    var isChip: Bool {
        switch content {
        case .title, .created, .edited, .occurred, .duration, .source: false
        case .type, .parent, .children, .collections, .count, .tags, .field: true
        }
    }

    /// Whether the column is a status, which a row says first, as a chip of its own.
    var isStatus: Bool { style == .status && field != nil }

    /// The symbol that stands for what the property holds, beside its name in the View panel's Properties.
    var symbol: String {
        switch content {
        case .title: "textformat"
        case .type: "square.grid.2x2"
        case .parent: "square.stack"
        case .children: "link"
        case .collections: "square.stack"
        case .created, .edited, .occurred: "calendar"
        case .count: "number"
        case .tags: "tag"
        case .source: "antenna.radiowaves.left.and.right"
        case .duration: "clock"
        case .field(let field): PageLayout.symbol(of: field)
        }
    }
}

nonisolated extension ViewProperties {
    /// The properties a layout lists: all of them in a table, which draws every column, and in any other layout those
    /// a chip can say, less what the layout already says another way (`leaving`, the identifiers of the property a
    /// board's lanes or a timeline's days are made of). Every field the place's `types` declare is offered. One that
    /// every type declaring it already says as its date or on its Secondary line shows by default, and stays in that
    /// place on the row; its switch only hides it.
    static func offered(
        _ columns: [ItemTableColumn], in layout: ItemViewMode, leaving: Set<String> = [], looks: [TypeID: TypeLook] = [:],
        types: [TypeID] = [], catalogue: Catalogue? = nil
    ) -> [ItemTableColumn] {
        guard layout != .table else { return columns }
        return columns.compactMap { column in
            guard column.isChip, !leaving.contains(column.id) else { return nil }
            guard let key = column.field?.key, let catalogue else { return column }
            let declaring = types.filter { catalogue.itemTypes[$0]?.fields.contains { $0.key == key } == true }
            guard !declaring.isEmpty, declaring.allSatisfy({ (looks[$0] ?? .empty).says(key) }) else { return column }
            var said = column
            said.isShownByDefault = true
            return said
        }
    }

    /// The looks of every type with this list drawn into them, which a layout of chips reads in place of the types' own.
    /// Until the list is changed they are the types' looks, untouched. Once it is, each type's facts are the shown
    /// properties in the list's order, less those the type does not declare, which are skipped for its items, and the
    /// status and the type show or hide as their properties do. The date and the Secondary line stay the type's, less a
    /// field in them the person hid.
    func looks(_ base: [TypeID: TypeLook], columns: [ItemTableColumn], catalogue: Catalogue) -> [TypeID: TypeLook] {
        guard isChanged else { return base }
        let listed = arranged(columns).filter { $0.content != .title }
        let typeColumn = listed.first { $0.content == .type }
        var looks = base
        for (type, look) in base {
            var own = look
            let info = catalogue.itemTypes[type]
            own.facts = listed.filter(isShown).compactMap { $0.fact(of: type, info: info, look: look) }
            if let key = info?.statusField?.key, let status = listed.first(where: { $0.id == Browser.fieldColumnPrefix + key }) {
                own.showsStatus = isShown(status)
            }
            if let typeColumn { own.showsType = isShown(typeColumn) }
            own.hide { shown[Browser.fieldColumnPrefix + $0] == false }
            looks[type] = own
        }
        return looks
    }
}

nonisolated extension TypeLook {
    /// Whether the look already says the field: as its date, or in its Secondary line.
    func says(_ key: String) -> Bool {
        if date == .field(key) { return true }
        return secondary.contains { $0 == .field(key) || $0 == .time(key) }
    }

    /// Takes out of the date and the Secondary line each field `hidden` names.
    mutating func hide(_ hidden: (String) -> Bool) {
        if case .field(let key) = date, hidden(key) { date = .off }
        secondary.removeAll { part in
            switch part {
            case .field(let key), .time(let key): hidden(key)
            default: false
            }
        }
    }
}

nonisolated extension ItemTableColumn {
    /// The fact this property is on an item of `type`, or nil where the type has none of it: a field it does not declare,
    /// a count its look does not ask for, or a part a row says another way. A field the look already says as its date or
    /// on its Secondary line is left out, since those stay the type's.
    fileprivate func fact(of type: TypeID, info: ItemTypeInfo?, look: TypeLook) -> LookFact? {
        switch content {
        case .field(let field):
            // The status is the row's first chip and no fact, so a status field is never one.
            guard let own = info?.fields.first(where: { $0.key == field.key }), !own.isStatus, !look.says(field.key) else { return nil }
            return .field(field.key)
        case .tags: return .tags
        case .parent: return .relation(.parent)
        case .children: return .relation(.children)
        case .collections: return .relation(.collections)
        case .count(let fact): return look.counts.contains(fact) ? .count(fact) : nil
        case .title, .type, .created, .edited, .occurred, .duration, .source: return nil
        }
    }
}
