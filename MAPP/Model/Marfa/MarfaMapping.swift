import Foundation
import Marfa
import struct MarfaCore.Item
import struct MarfaCore.Edge
import enum MarfaCore.ItemState
import enum MarfaCore.Tier
import enum MarfaCore.JsonValue
import UniformTypeIdentifiers

/// Reads the package's values into the item layer's. Pure, so the rules are tested on values made by hand.
nonisolated enum MarfaMapping {
    static let fileType = TypeID.file
    /// The core.file fields naming the bytes, their kind and their length, which the server sets.
    static let blobField = "blob_ref"
    static let mimeTypeField = "mime_type"
    static let sizeField = "size_bytes"
    /// The keys a file item keeps its bytes' facts under, shown as the file's kind and size instead.
    static let fileFacts: Set<String> = [blobField, mimeTypeField, sizeField]
    /// Marfa's folder device writes a body link as this edge, so it reads as the body's, not a property's.
    static let bodyLinkEdge = "references"
    /// Marfa writes an embed of a file as this edge, from the file's item to the item whose body embeds it.
    static let attachmentEdge = "attached-to"
    static let parentEdge = "parent-of"
    /// Marfa places an item in a synced folder with this edge, from the item to the folder; its `path` is the file
    /// the item is written to, whose name a link or an embed may name the item by.
    static let placementEdge = "in-folder"
    /// Marfa files an item in a collection with this edge, from the member to the collection.
    static let collectionEdge = "in-collection"
    /// The role a type plays to be a collection, which `in-collection` names at its target.
    static let containerRole = "container"
    /// The `in-collection` property that orders a collection's members.
    static let positionProperty = "position"

    /// Marfa keeps what apps share, such as saved views, as `system.*` rows, which are no items of the library. The
    /// copy holds `system.view` so the sidebar can list the views (`MarfaSync.slice`), and only that prefix is tested.
    static func isLibraryItem(_ row: Marfa.Item) -> Bool { !row.type.hasPrefix("system.") }

    /// A view still in use, as the sidebar lists it.
    static func view(_ view: SavedView) -> LibraryView? {
        guard view.state != .revoked else { return nil }
        let settings = view.settings
        let query = settings.query
        return LibraryView(
            id: ItemID(view.id), title: settings.title, version: view.version,
            query: LibraryViewQuery(
                types: query.types.map { TypeID($0) },
                tier: query.tier.flatMap(viewTier),
                states: query.states.map { Set($0.map(state)) },
                filter: query.filter, beneath: query.beneath.map { ItemID($0) }),
            sort: settings.sort.map { LibraryViewSort(field: $0.by, ascending: $0.direction == .ascending) },
            group: settings.group.map { LibraryViewGroup(field: $0.by, bucket: $0.bucket.map(bucket)) })
    }

    /// Nil where a view lists both tiers.
    private static func viewTier(_ tier: SliceTier) -> Tier? {
        switch tier {
        case .library: .library
        case .feed: .feed
        case .all: nil
        }
    }

    private static func bucket(_ bucket: ViewGrouping.Bucket) -> LibraryViewGroup.Bucket {
        switch bucket {
        case .day: .day
        case .week: .week
        case .month: .month
        case .year: .year
        }
    }

    private static func marfaBucket(_ bucket: LibraryViewGroup.Bucket) -> ViewGrouping.Bucket {
        switch bucket {
        case .day: .day
        case .week: .week
        case .month: .month
        case .year: .year
        }
    }

    static func viewSettings(_ settings: LibraryViewSettings) -> ViewSettings {
        ViewSettings(
            title: settings.title, query: viewQuery(settings.query), sort: settings.sort.map(viewSort),
            group: settings.group.map(viewGrouping))
    }

    static func viewChange(_ change: LibraryViewChange) -> ViewSettingsChange {
        ViewSettingsChange(
            title: change.title, query: change.query.map(viewQuery), sort: change.sort.map { $0.map(viewSort) },
            group: change.group.map { grouping in
                switch grouping {
                case .set(let group): .set(viewGrouping(group))
                case .clear: .clear
                }
            })
    }

    private static func viewQuery(_ query: LibraryViewQuery) -> ViewQuery {
        ViewQuery(
            types: query.types.map(\.rawValue),
            tier: query.tier.map { $0 == .feed ? SliceTier.feed : .library },
            // Ordered, so one query is always sent alike.
            states: query.states.map { states in [ItemState.active, .archived, .trashed].filter(states.contains).map(marfaState) },
            filter: query.filter, beneath: query.beneath?.rawValue)
    }

    private static func viewSort(_ sort: LibraryViewSort) -> ViewSort {
        ViewSort(by: sort.field, direction: sort.ascending ? .ascending : .descending)
    }

    private static func viewGrouping(_ group: LibraryViewGroup) -> ViewGrouping {
        ViewGrouping(by: group.field, bucket: group.bucket.map(marfaBucket))
    }

    /// The server's refusal of a view write, in words for the person. A view is written at once, so a server that
    /// cannot be reached saved nothing.
    static func viewFailure(_ error: any Error) -> ViewWriteFailure {
        guard let error = error as? MarfaError else {
            return ViewWriteFailure(kind: .refused, message: error.localizedDescription)
        }
        switch error {
        case .noServer, .network:
            return ViewWriteFailure(kind: .offline, message: String(localized: "MAPP can’t reach your Marfa server, so nothing was saved. Try again when it’s back."))
        case .server(409, "version_conflict", _):
            return ViewWriteFailure(kind: .conflict, message: String(localized: "This view was changed elsewhere since this window read it, so nothing was saved. The window now shows the view as it is; make your changes again."))
        case .notFound:
            return ViewWriteFailure(kind: .gone, message: String(localized: "Your Marfa server no longer has this view."))
        case .forbidden:
            return ViewWriteFailure(kind: .notPermitted, message: String(localized: "The key MAPP uses can’t change views on your Marfa server."))
        default:
            return ViewWriteFailure(kind: .refused, message: error.message)
        }
    }

    // MARK: Catalogue

    static func catalogue(itemTypes: [Marfa.ItemType], edgeTypes: [Marfa.EdgeType]) -> Catalogue {
        Catalogue(itemTypes: itemTypes.map(itemType), edgeTypes: edgeTypes.map(edgeType))
    }

    static func itemType(_ type: Marfa.ItemType) -> ItemTypeInfo {
        ItemTypeInfo(
            id: TypeID(type.id), label: type.label ?? type.id,
            fields: type.fields.map(field),
            titleField: type.titleField, bodyField: type.bodyField, parent: type.parent.map { TypeID($0) }, icon: type.icon,
            description: type.description, version: type.version, roles: type.roles,
            compatibleWith: type.compatibleWith.map { TypeID($0) }, linkField: type.linkField)
    }

    private static func field(_ field: Marfa.TypeField) -> ItemTypeInfo.Field {
        ItemTypeInfo.Field(
            key: field.name, label: label(forField: field.name), kind: kind(of: field),
            declaredBy: TypeID(field.declaredBy), required: field.required, description: field.description,
            format: format(of: field), isInteger: field.type == "integer")
    }

    /// A field is a web or mail address when its kind says so or, as a text field's `format` refines it, when its
    /// definition does: the server stores such a field as that kind, but a catalogue can still carry it as `string`.
    static func format(of field: Marfa.TypeField) -> ItemTypeInfo.Field.TextFormat? {
        let name = field.type == "string" ? field.definition["format"]?.string : field.type
        switch name {
        case "url": return .url
        case "email": return .email
        default: return nil
        }
    }

    static func edgeType(_ type: Marfa.EdgeType) -> EdgeTypeInfo {
        // Cardinality is given from source to target; the end that writes the edge holds as many as the other
        // side of it allows.
        let ends = type.cardinality.split(separator: "-to-").map(String.init)
        let held = type.writtenAt == .target ? ends.first : ends.last
        let other = type.writtenAt == .target ? ends.last : ends.first
        return EdgeTypeInfo(
            id: type.id, label: type.label, reverseLabel: type.reverseLabel, reverseName: type.reverseName,
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
        case "date": .date(includesTime: false)
        case "datetime": .date(includesTime: true)
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
            title = NoteName.firstLine(of: body)
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
        // A row the copy could not read shows no properties and no text. Saying why, rather than showing an empty
        // item, keeps it from being taken for one the person emptied; the problem also keeps it from being edited.
        let damaged = row.unreadableProperties != nil
        let bound = (bodyLinks?.links ?? []).map { name in
            BoundLink(link: NoteLink(reading: Self.inside(brackets: name.text)), resolution: resolution(of: name.target))
        }
        let embeds = (bodyLinks?.embeds ?? []).map { BoundEmbed(text: $0.text, resolution: resolution(of: $0.target)) }
        let content = content(of: row, catalogue: catalogue)
        let preview: String
        if case .file(let fileType, let byteCount) = content {
            preview = ItemPreview.file(fileType, byteCount: byteCount)
        } else {
            preview = ItemPreview.text(of: body, title: title, fallback: row.properties["description"]?.string)
        }
        return Item(
            id: ItemID(row.id), type: type, title: title, titleRule: titleRule, properties: properties,
            preview: damaged ? MarfaProblems.unreadableMessage : preview, content: content, state: state,
            tier: row.tier.map(tier) ?? .library, tags: Set(row.tags), version: ItemVersion(row.version),
            created: created, modified: modified, trashed: state == .trashed ? modified : nil, edgesOut: edgesOut,
            sync: sync, problem: damaged ? ItemProblem(message: MarfaProblems.unreadableMessage, withholdsText: true) : nil, boundLinks: bound,
            boundEmbeds: embeds, source: row.source.isEmpty ? nil : row.source)
    }

    /// The text between the brackets of a link as the package renders it, `[[text]]`.
    static func inside(brackets text: String) -> String {
        guard text.hasPrefix("[["), text.hasSuffix("]]"), text.count >= 4 else { return text }
        return String(text.dropFirst(2).dropLast(2))
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
            let atTarget = info?.writtenAt == .target
            guard (atTarget ? edge.targetId : edge.sourceId) == id else { return nil }
            let other = atTarget ? edge.sourceId : edge.targetId
            guard isHeld(other) else { return nil }
            let name = atTarget ? info?.reverseName ?? edge.edgeType : edge.edgeType
            return Edge(
                id: EdgeID(edge.id), type: name, source: ItemID(id), target: .item(ItemID(other)),
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

    static func date(_ text: String) -> Date {
        ItemDate.parse(text)?.date ?? .distantPast
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
        case .failingAlone: .failingAlone
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

    /// How much a state needs the person: a conflict outranks writes that merely wait, and a refusal or a block
    /// outranks a conflict.
    static func rank(_ state: SyncState?) -> Int {
        switch state {
        case nil, .settled: 0
        case .waiting: 1
        case .conflicted: 2
        case .refused: 3
        case .blocked: 4
        }
    }
}

extension BodyTarget {
    /// Whether the link or embed names an item, which the copy then holds an edge for.
    nonisolated var isItem: Bool {
        if case .item = self { true } else { false }
    }
}
