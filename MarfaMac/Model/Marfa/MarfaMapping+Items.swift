import Foundation
import Marfa
import UniformTypeIdentifiers

nonisolated extension MarfaMapping {
    /// `bodyLinks` are what the item's text names, read by the package: the links and embeds that name no item,
    /// or none yet, are shown as such beside the edges the copy holds for those that do.
    ///
    /// `display` is what the core answers for the row's name and preview. Without it the item has no name and no
    /// preview, as a row the core could not name has none.
    static func item(
        _ row: Marfa.Item, edges: [Marfa.Edge], catalogue: Catalogue, sync: SyncState = .settled,
        bodyLinks: BodyLinks? = nil, display: ItemDisplay? = nil, isHeld: (String) -> Bool
    ) -> Item {
        let type = TypeID(row.type)
        let info = catalogue.itemTypes[type]
        let body = self.body(of: row, catalogue: catalogue) ?? ""
        let title: String
        let titleRule: Item.TitleRule
        if let titleField = titleField(of: info) {
            title = row.properties[titleField]?.string ?? ""
            titleRule = .property(titleField)
        } else {
            title = NameText.firstLine(of: body)
            titleRule = .firstLine
        }
        let bodyField = bodyField(of: info)
        // The server answers the properties in the order it keeps them, which is the order shown.
        let properties = row.properties.filter { $0.key != bodyField }.map { Property(key: $0.key, value: value($0.value)) }
        let created = timestamp(row.createdDate)
        let modified = timestamp(row.updatedDate)
        let state = self.state(row.state)
        var edgesOut = edgesOut(of: row.id, among: edges, catalogue: catalogue, isHeld: isHeld)
        edgesOut += unresolvedLinks(of: row.id, in: bodyLinks)
        // A row the copy could not read shows no properties and no text. Saying why, rather than showing an empty
        // item, keeps it from being taken for one the person emptied; the problem also keeps it from being edited.
        let damaged = row.unreadableProperties != nil
        let embeds = (bodyLinks?.embeds ?? []).map { BoundEmbed(text: $0.text, resolution: resolution(of: $0.target)) }
        let content = content(of: row, catalogue: catalogue)
        let preview: String
        if case .file(let fileType, let byteCount) = content {
            preview = ItemPreview.file(fileType, byteCount: byteCount)
        } else {
            preview = display?.preview ?? ""
        }
        return Item(
            id: ItemID(row.id), type: type, title: title, name: display?.name, titleRule: titleRule, properties: properties,
            preview: damaged ? MarfaProblems.unreadableMessage : preview, content: content, state: state,
            tier: row.tier.map(tier) ?? .library, tags: Set(row.tags), version: ItemVersion(row.version),
            created: created, modified: modified, occurred: row.occurredDate,
            trashed: state == .trashed ? row.trashedDate ?? modified : nil,
            edgesOut: edgesOut,
            sync: sync, problem: damaged ? ItemProblem(message: MarfaProblems.unreadableMessage, withholdsText: true) : nil,
            readOnly: row.readOnly, boundEmbeds: embeds, source: row.source.isEmpty ? nil : row.source)
    }

    /// What a link in an item's text names, as the package reads it from the copy.
    static func resolution(of target: BodyTarget) -> ReferenceResolution {
        switch target {
        case .item(let id): .resolved(ItemID(id))
        case .pending: .pending
        case .missing: .missing
        // The package says only that more than one item answers to the name.
        case .ambiguous: .ambiguous([])
        case .refused(let reason): .refused(reason)
        }
    }

    /// Where an item's title is read and written: the field the type's hints name, else `title`, as Marfa reads
    /// it. Where the type does not declare `title` either, the title is the first line of the body rather than a
    /// property the type lacks. A type the catalogue lacks is read as Marfa reads one with no hints.
    static func titleField(of type: ItemTypeInfo?) -> String? {
        guard let type else { return "title" }
        return type.titleKey
    }

    /// Where an item's text is read and written: the field the type's hints name, else `body` where the type
    /// declares it. Marfa reads `body` even where it is not declared; the app refuses text for such a type rather
    /// than write a property the type lacks.
    static func bodyField(of type: ItemTypeInfo?) -> String? {
        type?.bodyKey
    }

    /// An item of a type with text that holds no text property, as one made from a title alone, has empty text. A row
    /// the copy could not read, or a text property that is not a string, has none that can be shown.
    static func body(of row: Marfa.Item, catalogue: Catalogue) -> String? {
        guard row.unreadableProperties == nil, let field = bodyField(of: catalogue.itemTypes[TypeID(row.type)]) else { return nil }
        guard let value = row.properties[field], value != .null else { return "" }
        return value.string
    }

    /// Each edge sits with the item at the end its type is written at, named as that end writes it: a `parent-of`
    /// is held by the child as `child-of`, which the package cannot name, so the catalogue's reverse name is used.
    /// An edge to an item the copy does not hold, such as a folder's bookkeeping, could be neither shown nor opened.
    static func edgesOut(
        of id: String, among edges: [Marfa.Edge], catalogue: Catalogue, isHeld: (String) -> Bool
    ) -> [Edge] {
        edges.compactMap { edge in
            let info = catalogue.edgeTypes[edge.edgeType]
            let atTo = info?.writtenFrom == .to
            guard (atTo ? edge.toId : edge.fromId) == id else { return nil }
            let other = atTo ? edge.fromId : edge.toId
            guard isHeld(other) else { return nil }
            let name = atTo ? info?.reverseName ?? edge.edgeType : edge.edgeType
            return Edge(
                id: EdgeID(edge.id), type: name, from: ItemID(id), to: .item(ItemID(other)),
                origin: edge.edgeType == bodyLinkEdge ? .body : .property(name),
                position: edge.properties[positionProperty]?.number)
        }
    }

    /// The links and embeds of a body that name no item the copy can show: none yet, none at all, more than one, or
    /// one the server refused. Those that name an item are the copy's own edges, which `edgesOut` reads. Each
    /// is given an identifier of its own, from the item and its place in the body, so a list of them is stable.
    static func unresolvedLinks(of id: String, in bodyLinks: BodyLinks?) -> [Edge] {
        guard let bodyLinks else { return [] }
        var found: [Edge] = []
        for (kind, names) in [(bodyLinkEdge, bodyLinks.links), (attachmentEdge, bodyLinks.embeds)] {
            for (position, name) in names.enumerated() {
                let to: EdgeTo
                switch name.target {
                case .item: continue
                case .pending: to = .pending(spelling: name.name)
                case .missing: to = .unresolved(spelling: name.name, ambiguous: false)
                case .ambiguous: to = .unresolved(spelling: name.name, ambiguous: true)
                case .refused(let reason): to = .refused(spelling: name.name, reason: reason)
                }
                found.append(Edge(
                    id: EdgeID("\(id)#\(kind)#\(position)"), type: kind, from: ItemID(id), to: to,
                    origin: .body))
            }
        }
        return found
    }

    static func state(_ state: Marfa.ItemState) -> ItemState {
        switch state {
        case .active: .active
        case .archived: .archived
        case .trashed: .trashed
        // Only system items are revoked: kept and read, never edited again, as an archived item is.
        case .revoked: .archived
        }
    }

    static func marfaState(_ state: ItemState) -> Marfa.ItemState {
        switch state {
        case .active: .active
        case .archived: .archived
        case .trashed: .trashed
        }
    }

    static func tier(_ tier: Marfa.Tier) -> Tier {
        switch tier {
        case .library: .library
        case .feed: .feed
        }
    }

    static func marfaTier(_ tier: Tier) -> Marfa.Tier {
        switch tier {
        case .library: .library
        case .feed: .feed
        }
    }

    static func value(_ value: JSONValue) -> PropertyValue {
        switch value {
        case .null: .null
        case .bool(let bool): .bool(bool)
        case .integer(let integer): .number(Decimal(integer))
        case .number(let number): self.number(number)
        case .string(let string): .string(string)
        case .array(let values): .array(values.map(self.value))
        case .object(let object): .object(Dictionary(object.map { ($0.key, self.value($0.value)) }, uniquingKeysWith: { first, _ in first }))
        }
    }

    static func json(_ value: PropertyValue) -> JSONValue {
        switch value {
        case .null: .null
        case .bool(let bool): .bool(bool)
        case .number(let number):
            // An integer stays an integer, so one above 2^53 goes back exactly as it came.
            if let integer = integer(number) { .integer(integer) } else { .number(number.nearestDouble) }
        case .double(let number): .number(number)
        case .string(let string): .string(string)
        case .array(let values): .array(values.map(json))
        case .object(let object): .object(JSONObject(object.sorted { $0.key < $1.key }.map { ($0.key, json($0.value)) }))
        }
    }

    /// The number through its shortest text, since Decimal(Double) keeps the binary error: 0.1 would read 0.1000…05.
    /// One that text does not give back exactly is kept as the Double, never as Decimal's NaN or zero.
    private static func number(_ number: Double) -> PropertyValue {
        guard let decimal = Decimal(string: "\(number)"), !decimal.isNaN, Double("\(decimal)") == number else { return .double(number) }
        return .number(decimal)
    }

    /// The number as an Int64 where it is a whole number in Int64's range.
    private static func integer(_ number: Decimal) -> Int64? {
        var rounded = Decimal()
        var source = number
        NSDecimalRound(&rounded, &source, 0, .plain)
        guard rounded == number else { return nil }
        return Int64(NSDecimalNumber(decimal: number).stringValue)
    }

    private static func content(of row: Marfa.Item, catalogue: Catalogue) -> Item.Content {
        let type = TypeID(row.type)
        guard type == fileType || catalogue.isSubtype(type, ofAnyOf: [fileType]) else { return .markdown }
        let mimeType = row.properties[mimeTypeField]?.string
        // `size_bytes` is an integer: the package stamps it when the file is queued and the server when it holds the
        // bytes. Anything else, or none, is no size.
        let size = row.properties[sizeField]?.integer
        return .file(mimeType.flatMap { UTType(mimeType: $0) } ?? .data, byteCount: size ?? 0)
    }

    /// A time the package read from a row, or the oldest moment, reported once a run, where the row's time is not one
    /// the contract allows.
    static func timestamp(_ read: Date?, reporting: Reporting = .shared) -> Date {
        guard let read else {
            Telemetry.timestampUnreadable(reporting: reporting)
            return .distantPast
        }
        return read
    }

    /// A time the package gives as text, such as when a write was queued.
    static func date(_ text: String, reporting: Reporting = .shared) -> Date {
        timestamp(ItemDate.parse(text)?.date, reporting: reporting)
    }
}

extension BodyTarget {
    /// Whether the link or embed names an item, which the copy then holds an edge for.
    nonisolated var isItem: Bool {
        if case .item = self { true } else { false }
    }
}
