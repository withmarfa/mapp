import Foundation
import Observation
@testable import MAPP

/// A library held in memory, with no server and no store, so the views' models can be tested through
/// `ItemLibrary` alone. It keeps items and bodies as given and answers the places by their plain meaning.
@Observable
final class FakeItemLibrary: ItemLibrary {
    var items: [Item]
    var bodies: [ItemID: String]
    var isLoaded = true
    let notices = Notices()
    var notesToPurge: Set<ItemID> = []
    var catalogue = FakeItemLibrary.testCatalogue
    var canPurge = false
    var trashDays: Int?
    /// What `relationships(for:)` answers, by item.
    var relationshipsByItem: [ItemID: [ItemRelationship]] = [:]
    /// Whether `setItemRelationship` takes a write, and the writes it was asked for.
    var acceptsRelationships = false
    var relationshipWrites: [(item: ItemID, field: String, targets: [ItemID])] = []
    var syncReport = SyncReport(queueRead: true)
    let now: () -> Date
    /// What `attach` answers, which may wait or throw; nil attaches nothing.
    var attaching: (() async throws -> [Embed])?

    init(items: [Item] = [], bodies: [ItemID: String] = [:], now: Date = .now) {
        self.items = items
        self.bodies = bodies
        self.now = { now }
    }

    /// A note as the fake holds one: an active core note in the library, or in the Inbox where `tier` is the feed,
    /// edited at `modified`.
    static func note(
        _ title: String, modified: Date, tier: Tier = .library, isFavorite: Bool = false, state: ItemState = .active,
        id: ItemID = .mint()
    ) -> Item {
        Item(
            id: id, type: TypeID("core.note"), title: title, titleRule: .firstLine, state: state, tier: tier,
            tags: isFavorite ? [ItemTag.favorite] : [], version: ItemVersion(1), created: modified, modified: modified)
    }

    /// A core note holding `body`, titled by its first line as one is, added to the library.
    @discardableResult
    func add(_ body: String, id: ItemID = .mint(), state: ItemState = .active) -> Item {
        let firstLine = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let item = Self.note(
            firstLine.trimmingCharacters(in: CharacterSet(charactersIn: "# ")), modified: now(), state: state, id: id)
        items.append(item)
        bodies[id] = body
        return item
    }

    /// Notes, tasks with a status, projects that hold them, and files, as a server's catalogue might have them.
    static let testCatalogue: Catalogue = {
        let task = TypeID("core.task")
        let project = TypeID("test.project")
        let taskFields = [
            ItemTypeInfo.Field(key: "status", label: "Status", kind: .choice(["todo", "in_progress", "done"]), declaredBy: task),
            ItemTypeInfo.Field(key: "priority", label: "Priority", kind: .choice(["high", "medium", "low"]), declaredBy: task),
            ItemTypeInfo.Field(key: "assignee", label: "Assignee", kind: .text, declaredBy: task),
        ]
        let types = [
            ItemTypeInfo(id: TypeID("core.note"), label: "Note", fields: [], titleField: "title", bodyField: "body", parent: nil),
            ItemTypeInfo(id: task, label: "Task", fields: taskFields, titleField: "title", bodyField: "body", parent: nil),
            ItemTypeInfo(
                id: project, label: "Project",
                fields: [ItemTypeInfo.Field(key: "description", label: "Description", kind: .text, declaredBy: project)],
                titleField: "title", bodyField: "body", parent: nil),
            ItemTypeInfo(id: .file, label: "File", fields: [], titleField: nil, bodyField: nil, parent: nil),
            ItemTypeInfo(id: TypeID("core.file.image"), label: "Image", fields: [], titleField: nil, bodyField: nil, parent: .file),
        ]
        // A child names its parent, so `parent-of` is written at its target, under its reverse name.
        let parent = EdgeTypeInfo(
            id: "parent-of", label: "Children", reverseLabel: "Parent", reverseName: "child-of", cardinality: .one, writtenAt: .target,
            sourceTypes: [], targetTypes: [])
        return Catalogue(itemTypes: types, edgeTypes: [parent])
    }()

    // MARK: Reading

    func item(_ id: ItemID) -> Item? { items.first { $0.id == id } }

    private func isBelow(_ item: Item, _ ancestor: ItemID) -> Bool {
        var visited: Set<ItemID> = [item.id]
        var current = item
        while let parent = current.parentID, visited.insert(parent).inserted {
            if parent == ancestor { return true }
            guard let next = self.item(parent) else { return false }
            current = next
        }
        return false
    }

    func items(in place: SidebarItem) -> [Item] {
        if place == .recents { return Self.recent(items) }
        return items.filter { item in
            switch place {
            case .inbox: item.state == .active && item.tier == .feed
            case .allNotes: item.state == .active
            case .sources, .collections: false
            case .source(let name): item.state == .active && item.source == name
            case .recents: false
            case .favorites: item.state == .active && item.isFavorite
            case .favoriteItem(let id): item.id == id && item.state == .active && item.isFavorite
            case .itemType(let type): item.state == .active && item.type == TypeID(type)
            case .collection(let id): item.state == .active && isBelow(item, id)
            case .files: item.state == .active && item.isFile
            case .recentlyDeleted: item.state == .trashed
            }
        }
    }

    func items(matching query: String) -> [Item] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return items.filter {
            $0.state == .active && ($0.title.localizedCaseInsensitiveContains(query)
                || bodies[$0.id]?.localizedCaseInsensitiveContains(query) == true)
        }
    }

    func count(in place: SidebarItem) -> Int { items(in: place).count }
    func name(of place: SidebarItem) -> String {
        switch place {
        case .favoriteItem(let id), .collection(let id): item(id)?.title ?? ""
        case .itemType(let type): catalogue.itemTypes[TypeID(type)]?.label ?? type
        default: "\(place)"
        }
    }
    func isGone(_ id: ItemID?) -> Bool { isLoaded && id.flatMap(item) == nil }
    func idsForWindows(_ ids: some Collection<ItemID>) -> [ItemID] { ids.filter { item($0) != nil } }
    func body(of id: ItemID) -> ItemBody? {
        guard let item = item(id), !item.isFile else { return nil }
        return ItemBody(id: id, text: bodies[id] ?? "", version: item.version)
    }
    func resolveLink(_ link: NoteLink, in source: ItemID) -> NoteReferenceResolution {
        let name = link.lookupName
        let named = items.filter {
            $0.state == .active && !$0.isFile
                && ($0.id.rawValue == name || NoteLinks.nameKey($0.title) == NoteLinks.nameKey(name))
        }
        switch named.count {
        case 0: return .missing
        case 1: return .resolved(named[0].id)
        default: return .ambiguous(named.map(\.id))
        }
    }
    func relationships(for id: ItemID) -> [ItemRelationship] { relationshipsByItem[id] ?? [] }
    func relationshipCandidates(for id: ItemID, field: String) -> [Item] { [] }
    func bodyMentions(for id: ItemID) -> [ItemRelationshipTarget] { [] }
    /// The items each type may be made under, by type.
    var parentCandidates: [String: [ItemID]] = [:]
    func creationParentCandidates(typeID: String) -> [Item] { (parentCandidates[typeID] ?? []).compactMap { item($0) } }

    // MARK: Files

    /// The file each file item fetches as.
    var files: [ItemID: URL] = [:]
    var fetchFails = false
    /// How many times a file was asked for.
    @ObservationIgnored var fetches = 0
    /// How long fetching each file takes, as a server's can.
    var fetchDelay: [ItemID: Duration] = [:]

    func fileURL(of id: ItemID) async throws -> URL? {
        fetches += 1
        if fetchFails { throw SourceFailure(kind: .failed, message: "The server can’t be reached.") }
        if let delay = fetchDelay[id] { try await Task.sleep(for: delay) }
        return files[id]
    }

    // MARK: Writing

    func createItem(
        typeID: String, title: String, body: String, parentID: ItemID?, in place: SidebarItem, undoManager: UndoManager?
    ) -> ItemID? {
        guard !title.isEmpty else { return nil }
        let id = ItemID.mint()
        let parent = parentID.map { Edge(id: EdgeID("child-of-\(id.rawValue)"), type: "child-of", source: id, target: .item($0), origin: .property("child-of")) }
        let item = Item(
            id: id, type: TypeID(typeID), title: title, titleRule: .property("title"),
            version: ItemVersion(1), created: now(), modified: now(), edgesOut: parent.map { [$0] } ?? [])
        bodies[item.id] = body
        created.append(item)
        if !holdsCreations { deliverCreated() }
        return item.id
    }

    /// Made, and not yet held, as a created item is until a server's source says so.
    private(set) var created: [Item] = []
    /// While set, a created item reaches the library only when `deliverCreated` is called.
    var holdsCreations = false

    func deliverCreated() {
        items += created
        created = []
    }

    /// Every text written, with the version it was typed on.
    private(set) var bodyWrites: [(id: ItemID, text: String, readAt: ItemVersion)] = []

    func updateBody(of id: ItemID, to body: String, readAt: ItemVersion) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        bodyWrites.append((id, body, readAt))
        bodies[id] = body
        items[index].version = ItemVersion(items[index].version.rawValue + 1)
        items[index].modified = now()
    }

    func resolve(_ problem: SyncProblemEntry.ID, by action: SyncAction) async throws -> Bool { false }
    /// Creates refused after `createItem` answered, as a server's source refuses one it cannot queue.
    var refusedCreations: Set<ItemID> = []
    func finish() {}
    func wasRefused(creating id: ItemID) -> Bool { refusedCreations.contains(id) }
    /// What `wasTouched` answers yes for, as a library does for an item another item points at.
    var touched: Set<ItemID> = []
    func wasTouched(_ id: ItemID) -> Bool { touched.contains(id) }
    func setItemProperty(_ id: ItemID, key: String, value: PropertyValue?, undoManager: UndoManager?) -> Bool { false }
    func setItemRelationship(_ id: ItemID, field: String, targetIDs: [ItemID], undoManager: UndoManager?) -> Bool {
        relationshipWrites.append((id, field, targetIDs))
        return acceptsRelationships
    }

    func setFavorite(_ ids: Set<ItemID>, _ isFavorite: Bool, undoManager: UndoManager?) {
        change(ids) { item in
            if isFavorite { item.tags.insert(ItemTag.favorite) } else { item.tags.remove(ItemTag.favorite) }
        }
    }

    func delete(_ ids: Set<ItemID>, undoManager: UndoManager?) {
        change(ids) { item in
            item.state = .trashed
            item.trashed = now()
        }
    }

    func recover(_ ids: Set<ItemID>, undoManager: UndoManager?) {
        change(ids) { item in
            item.state = .active
            item.trashed = nil
        }
    }

    func deletePermanently(_ ids: Set<ItemID>) {
        items.removeAll { ids.contains($0.id) && $0.state == .trashed }
        notesToPurge.subtract(ids)
    }

    func attach(_ files: [(name: String, data: Data)], to id: ItemID) async throws -> [Embed] {
        try await attaching?() ?? []
    }

    private func change(_ ids: Set<ItemID>, _ body: (inout Item) -> Void) {
        for index in items.indices where ids.contains(items[index].id) {
            body(&items[index])
            items[index].version = ItemVersion(items[index].version.rawValue + 1)
        }
    }
}
