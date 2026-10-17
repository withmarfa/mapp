import Foundation
import Marfa
import UniformTypeIdentifiers

/// Reads the package's values into the item layer's. Pure, so the rules are tested on values made by hand.
nonisolated enum MarfaMapping {
    static let fileType = TypeID("core.file")
    static let projectType = TypeID("aic.project")
    /// The core.file fields naming the bytes, their kind and their length, which the server sets.
    static let blobField = "blob_ref"
    static let mimeTypeField = "mime_type"
    static let sizeField = "size_bytes"
    /// Marfa's folder device writes a body link as this edge, so it reads as the body's, not a property's.
    static let bodyLinkEdge = "references"
    /// Marfa writes an embed of a file as this edge, from the file's item to the item whose body embeds it.
    static let attachmentEdge = "attached-to"
    static let parentEdge = "parent-of"

    // MARK: Catalogue

    static func catalogue(itemTypes: [Marfa.ItemType], edgeTypes: [Marfa.EdgeType]) -> Catalogue {
        Catalogue(itemTypes: itemTypes.map(itemType), edgeTypes: edgeTypes.map(edgeType))
    }

    static func itemType(_ type: Marfa.ItemType) -> ItemTypeInfo {
        ItemTypeInfo(
            id: TypeID(type.id), label: type.label ?? type.id,
            fields: type.fields.map(field),
            titleField: type.titleField, bodyField: type.bodyField, parent: type.parent.map { TypeID($0) },
            description: type.description, version: type.version, roles: type.roles,
            compatibleWith: type.compatibleWith.map { TypeID($0) })
    }

    private static func field(_ field: Marfa.TypeField) -> ItemTypeInfo.Field {
        ItemTypeInfo.Field(
            key: field.name, label: label(forField: field.name), kind: kind(of: field),
            declaredBy: TypeID(field.declaredBy), required: field.required, description: field.description)
    }

    static func edgeType(_ type: Marfa.EdgeType) -> EdgeTypeInfo {
        // Cardinality is given from source to target; the end that writes the edge holds as many as the other
        // side of it allows.
        let ends = type.cardinality.split(separator: "-to-").map(String.init)
        let held = type.writtenAt == .target ? ends.first : ends.last
        let other = type.writtenAt == .target ? ends.last : ends.first
        return EdgeTypeInfo(
            id: type.id, label: type.label ?? type.id, reverseName: type.reverseName,
            cardinality: held == "one" ? .one : .many, writtenAt: type.writtenAt == .target ? .target : .source,
            sourceTypes: constraints(type.sourceTypeConstraints).types,
            targetTypes: constraints(type.targetTypeConstraints).types,
            sourceRoles: constraints(type.sourceTypeConstraints).roles,
            targetRoles: constraints(type.targetTypeConstraints).roles,
            description: type.description, reverseCardinality: other == "one" ? .one : .many,
            cascadeOnDelete: cascade(type.cascadeOnDelete), properties: type.properties.map(field))
    }

    private static func cascade(_ name: String) -> EdgeTypeInfo.CascadeOnDelete {
        switch name {
        case "cascade": .cascade
        case "block": .block
        default: .orphan
        }
    }

    /// A constraint names a type, which matches its subtypes, or `role:<name>`, which matches the types that play
    /// the role. `*` allows any.
    private static func constraints(_ names: [String]) -> (types: Set<TypeID>, roles: Set<String>) {
        guard !names.contains("*") else { return ([], []) }
        let prefix = "role:"
        let roles = names.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        return (Set(names.filter { !$0.hasPrefix(prefix) }.map { TypeID($0) }), Set(roles))
    }

    private static func kind(of field: Marfa.TypeField) -> ItemTypeInfo.Field.Kind {
        switch field.type {
        case "string", "url", "email": .text
        case "number", "integer": .number
        case "boolean": .boolean
        case "date", "datetime": .date
        case "enum":
            if case .array(let values) = field.definition["enum_values"] {
                .choice(values.compactMap(\.string))
            } else {
                .other
            }
        default: .other
        }
    }

    /// The catalogue names fields only by key, such as `due_at`, which reads as "Due at".
    static func label(forField key: String) -> String {
        let words = key.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// One wildcard for each namespace the catalogue holds, so the slice is every type the key reads, each with
    /// its subtypes. Marfa refuses `*`, and `system` holds the server's own bookkeeping, not the person's items.
    static func namespaces(of catalogue: Catalogue) -> [String] {
        let roots = catalogue.itemTypes.keys.compactMap { $0.rawValue.split(separator: ".").first.map(String.init) }
        return Set(roots).subtracting(["system"]).sorted().map { "\($0).*" }
    }

    // MARK: Items

    /// `bodyLinks` are what the item's text names, read by the package: the links and embeds that name no item,
    /// or none yet, are shown as such beside the edges the copy holds for those that do.
    static func item(
        _ row: Marfa.Item, edges: [Marfa.Edge], catalogue: Catalogue, sync: SyncState = .settled,
        bodyLinks: BodyLinks? = nil, isHeld: (String) -> Bool
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
            title = firstLine(of: body)
            titleRule = .firstLine
        }
        let bodyField = bodyField(of: info)
        // The server answers the properties in the order it keeps them, which is the order shown.
        let properties = row.properties.filter { $0.key != bodyField }.map { Property(key: $0.key, value: value($0.value)) }
        let created = date(row.createdAt)
        let modified = date(row.updatedAt)
        let state = self.state(row.state)
        var edgesOut = edgesOut(of: row.id, among: edges, catalogue: catalogue, isHeld: isHeld)
        edgesOut += unresolvedLinks(of: row.id, in: bodyLinks)
        var bound: [String: NoteReferenceResolution] = [:]
        for name in bodyLinks?.links ?? [] {
            let key = NoteLinks.nameKey(NoteName.trimmed(name.name))
            let resolution = resolution(of: name.target)
            switch bound[key] {
            case .resolved:
                // The first note a name was bound to keeps it.
                continue
            case nil:
                bound[key] = resolution
            default:
                // A name that no note answers to yields to a link that did name one.
                if case .resolved = resolution { bound[key] = resolution }
            }
        }
        return Item(
            id: ItemID(row.id), type: type, title: title, titleRule: titleRule, properties: properties,
            preview: preview(of: body), content: content(of: row, catalogue: catalogue), state: state,
            tier: row.tier.map(tier) ?? .library, container: nil, tags: Set(row.tags), version: ItemVersion(row.version),
            created: created, modified: modified, trashed: state == .trashed ? modified : nil, edgesOut: edgesOut,
            sync: sync, linkTargets: bound)
    }

    /// What a link in an item's text names, as the package reads it from the copy.
    static func resolution(of target: BodyTarget) -> NoteReferenceResolution {
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
        return type.titleField ?? (type.declares("title") ? "title" : nil)
    }

    /// Where an item's text is read and written: the field the type's hints name, else `body` where the type
    /// declares it. Marfa reads `body` even where it is not declared; the app refuses text for such a type rather
    /// than write a property the type lacks.
    static func bodyField(of type: ItemTypeInfo?) -> String? {
        type.flatMap { $0.bodyField ?? ($0.declares("body") ? "body" : nil) }
    }

    static func body(of row: Marfa.Item, catalogue: Catalogue) -> String? {
        bodyField(of: catalogue.itemTypes[TypeID(row.type)]).flatMap { row.properties[$0]?.string }
    }

    /// Each edge sits with the item at the end its type is written at, named as that end writes it: a `parent-of`
    /// is held by the child as `child-of`, which the package cannot name, so the catalogue's reverse name is used.
    /// An edge to an item the copy does not hold, such as a folder's bookkeeping, could be neither shown nor opened.
    static func edgesOut(
        of id: String, among edges: [Marfa.Edge], catalogue: Catalogue, isHeld: (String) -> Bool
    ) -> [Edge] {
        edges.compactMap { edge in
            let info = catalogue.edgeTypes[edge.edgeType]
            let atTarget = info?.writtenAt == .target
            guard (atTarget ? edge.targetId : edge.sourceId) == id else { return nil }
            let other = atTarget ? edge.sourceId : edge.targetId
            guard isHeld(other) else { return nil }
            let name = atTarget ? info?.reverseName ?? edge.edgeType : edge.edgeType
            return Edge(
                id: EdgeID(edge.id), type: name, source: ItemID(id), target: .item(ItemID(other)),
                origin: edge.edgeType == bodyLinkEdge ? .body : .property(name))
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
                let target: EdgeTarget
                switch name.target {
                case .item: continue
                case .pending: target = .pending(spelling: name.name)
                case .missing: target = .unresolved(spelling: name.name, ambiguous: false)
                case .ambiguous: target = .unresolved(spelling: name.name, ambiguous: true)
                case .refused(let reason): target = .refused(spelling: name.name, reason: reason)
                }
                found.append(Edge(
                    id: EdgeID("\(id)#\(kind)#\(position)"), type: kind, source: ItemID(id), target: target,
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
        // Through its shortest text, since Decimal(Double) keeps the binary error: 0.1 would read 0.1000…05.
        case .number(let number): .number(Decimal(string: "\(number)") ?? Decimal(number))
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
            if let integer = Int64(exactly: NSDecimalNumber(decimal: number).doubleValue), Decimal(integer) == number {
                .integer(integer)
            } else {
                .number(NSDecimalNumber(decimal: number).doubleValue)
            }
        case .string(let string): .string(string)
        case .array(let values): .array(values.map(json))
        case .object(let object): .object(JSONObject(object.sorted { $0.key < $1.key }.map { ($0.key, json($0.value)) }))
        }
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

    private static func firstLine(of body: String) -> String {
        body.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    private static func preview(of body: String) -> String {
        String(body.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(240))
    }

    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let whole = Date.ISO8601FormatStyle()

    static func date(_ text: String) -> Date {
        (try? fractional.parse(text)) ?? (try? whole.parse(text)) ?? .distantPast
    }

    // MARK: Verdicts and sync

    static func outcome(_ verdict: Marfa.Verdict) -> WriteOutcome {
        switch verdict {
        case .accepted: .accepted
        case .merged(let fields): .merged(fields: fields)
        case .conflicted(let sibling, let fields): .conflicted(sibling: ItemID(sibling), fields: fields)
        case .refused(let refusal): .refused(problem(refusal))
        case .blocked(let reason, let refusal): .blocked(blockedReason(reason), refusal.map(problem))
        case .dead: .dead
        }
    }

    static func problem(_ refusal: Marfa.Refusal) -> SyncProblem {
        SyncProblem(
            code: refusal.code ?? refusal.reason, message: refusal.message,
            fields: Dictionary(refusal.fields.map { ($0.field, $0.message) }, uniquingKeysWith: { first, _ in first }),
            isTrashed: refusal.trashed, grant: refusal.grant.map(grant))
    }

    private static func grant(_ grant: MissingGrant) -> SyncProblem.Grant {
        let kind: SyncProblem.Grant.Kind =
            switch grant.kind {
            case .type: .type
            case .edgeType: .edgeType
            case .extension: .extension
            }
        return SyncProblem.Grant(kind: kind, name: grant.name, level: grant.level == .read ? .read : .write)
    }

    static func blockedReason(_ reason: Marfa.BlockedReason) -> BlockedReason {
        switch reason {
        case .credentialRefused: .credentialRefused
        case .keySpent: .keySpent
        case .ancestorUnavailable: .ancestorUnavailable
        case .conflictUnresolved: .conflictUnresolved
        }
    }

    /// Each item the queue holds a write for, or that a drain answered `refused` or `conflicted` (which the queue
    /// forgets unless the write carried content), with what most needs the person: a stopped write, then a refused
    /// one, then a conflict, then the count still waiting. An item missing from the answer is settled.
    static func syncStates(queue: [Marfa.QueuedWrite], remembered: [ItemID: SyncState] = [:]) -> [ItemID: SyncState] {
        var waiting: [ItemID: Int] = [:]
        var answered: [ItemID: SyncState] = remembered
        for write in queue {
            guard let itemID = write.itemId else { continue }
            let id = ItemID(itemID)
            guard let verdict = write.verdict else {
                waiting[id, default: 0] += 1
                continue
            }
            let state = outcome(verdict).syncState
            if state != .settled, rank(state) > rank(answered[id]) { answered[id] = state }
        }
        for (id, count) in waiting where answered[id] == nil {
            answered[id] = .waiting(writes: count)
        }
        return answered
    }

    private static func rank(_ state: SyncState?) -> Int {
        switch state {
        case nil, .settled: 0
        case .waiting: 1
        case .conflicted: 2
        case .refused: 3
        case .blocked: 4
        }
    }

    // MARK: Places

    static func places(items: some Collection<Item>, catalogue: Catalogue) -> [Place] {
        var places: [Place] = [
            Place(
                id: .inbox, title: String(localized: "Inbox"), symbol: "tray", section: .library,
                query: ItemQuery(tier: .feed)),
            Place(
                id: .all, title: String(localized: "All Items"), symbol: "note.text", section: .library,
                query: ItemQuery()),
            Place(
                id: .favorites, title: String(localized: "Favorites"), symbol: "star", section: .library,
                query: ItemQuery(tags: [ItemTag.favorite]), drop: .tag(ItemTag.favorite)),
            Place(
                id: .archive, title: String(localized: "Archive"), symbol: "archivebox", section: .library,
                query: ItemQuery(states: [.archived]), drop: .transition(.archived))
        ]
        let active = items.filter { $0.state == .active }
        if catalogue.itemTypes[projectType] != nil {
            places.append(
                Place(
                    id: .type(projectType), title: String(localized: "Projects"), symbol: "square.stack",
                    section: .projects, query: ItemQuery(types: [projectType])))
            let projects = active.filter { $0.type == projectType }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            places += projects.map { project in
                Place(
                    id: .beneath(project.id), title: project.title, symbol: "square.stack", section: .projects,
                    query: ItemQuery(beneath: project.id))
            }
        }
        let held = Set(active.map(\.type)).subtracting([projectType])
        places += held.compactMap { catalogue.itemTypes[$0] }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
            .map { type in
                Place(
                    id: .type(type.id), title: type.label, symbol: type.id == fileType ? "doc" : "doc.text",
                    section: .types, query: ItemQuery(types: [type.id]))
            }
        places += [
            Place(
                id: .recentlyDeleted, title: String(localized: "Recently Deleted"), symbol: "trash", section: .footer,
                query: ItemQuery(states: [.trashed]), drop: .transition(.trashed)),
            Place(id: .marfaTypes, title: String(localized: "Marfa Types"), symbol: "cube", section: .footer, query: nil)
        ]
        return places
    }
}

extension BodyTarget {
    /// Whether the link or embed names an item, which the copy then holds an edge for.
    nonisolated var isItem: Bool {
        if case .item = self { true } else { false }
    }
}
