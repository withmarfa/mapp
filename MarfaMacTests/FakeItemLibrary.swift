import Foundation
import struct Marfa.LinkParts
import func Marfa.linkParts
import Observation
import UniformTypeIdentifiers
@testable import MarfaMac

/// A library held in memory, with no server and no store, so the views' models can be tested through
/// `ItemLibrary` alone. It keeps items and bodies as given and answers the places by their plain meaning.
@Observable
final class FakeItemLibrary: ItemLibrary {
    var items: [Item] { didSet { contentRevision += 1; membershipRevision += 1 } }
    private(set) var contentRevision = 0
    private(set) var membershipRevision = 0
    var bodies: [ItemID: String]
    var isLoaded = true
    let notices = Notices()
    var itemsToPurge: Set<ItemID> = []
    var catalogue = FakeItemLibrary.testCatalogue { didSet { contentRevision += 1; membershipRevision += 1 } }
    var views: [LibraryView] = []
    /// What each view lists, by view.
    var viewMembers: [ItemID: [ItemID]] = [:]
    /// What a preview of a view lists for each query; a query not named lists what the view lists.
    var previewMembers: [LibraryViewQuery: [ItemID]] = [:]
    /// Every preview asked for, in order.
    @ObservationIgnored private(set) var previewsAsked: [LibraryViewQuery] = []
    var reachesServer = true
    /// What Settings > On This Mac reads, where a test gives it files.
    var downloadedFiles: (any DownloadedFiles)?
    private(set) var downloadedAgain = 0
    func downloadEverythingAgain() { downloadedAgain += 1 }
    /// The instance id the copy answers, which an item link is checked against.
    var heldInstanceID: String?
    /// How long the copy takes to answer its instance id, as when the engine asks again while the key changes.
    var instanceIDDelay: Duration = .zero
    func instanceID() async -> String? {
        if instanceIDDelay > .zero { try? await Task.sleep(for: instanceIDDelay) }
        return heldInstanceID
    }
    /// The counts the library works out from its items the way Marfa does: only active items, the groups of each child's
    /// own type, an item with no status in the total alone.
    @ObservationIgnored lazy var counts: ItemCounts = makeCounts()
    /// What the next icon choice answers: nil keeps it, a failure refuses it.
    var iconFailure: TypeIconFailure?
    /// What the next change to a field answers where it fails, which leaves the catalogue as it was.
    var fieldFailure: TypeSchemaFailure?
    private(set) var editedFields: [FieldEditPlan] = []
    private(set) var chosenIcons: [(type: TypeID, icon: String?)] = []
    /// While set, an icon choice waits for `answerIcon()` before it answers.
    var holdsIconAnswers = false
    private var heldIconAnswer: CheckedContinuation<Void, Never>?
    /// What the server last gave for sources; `serverSources` is what the next refresh reads.
    var sources = SourceDirectory()
    var serverSources: SourceDirectory?
    /// What the next source change answers: nil takes it, a failure refuses it.
    var sourceFailure: SourceEditFailure?
    private(set) var sourceChanges: [(code: String, name: SourceFieldChange?, mark: SourceFieldChange?)] = []
    private(set) var sourceRefreshes = 0
    /// What every view write fails with while set.
    var viewFailure: ViewWriteFailure?
    var trashDays: Int?
    /// What `relationships(for:)` answers, by item.
    var relationshipsByItem: [ItemID: [ItemRelationship]] = [:]
    /// Whether `changeLinks` takes a write, and the writes it was asked for.
    var acceptsRelationships = false
    /// The items whose property writes are still on their way, as a library that queues a write reports them.
    var writingProperties: Set<ItemID> = []
    /// Whether writes carry a mark that is never settled, as a library's queue does while they wait.
    var marksPropertyWrites = false
    var lastPropertyWrite: Int? { marksPropertyWrites ? 1 : nil }
    var relationshipWrites: [(item: ItemID, field: String, adding: [ItemID], removing: [ItemID])] = []
    var syncReport = SyncReport(queueRead: true)
    var now: () -> Date
    var calendar: () -> Calendar = { .current }
    /// What `attach` answers, which may wait; nil attaches nothing.
    var attaching: (() async -> AttachReport)?
    /// Awaited while a view is being made, before it exists, and while one is being deleted, once it is gone, so a
    /// test can act in the window a write leaves open.
    var inViewWrite: (() async -> Void)?
    /// Awaited when a view's change arrives, before it is applied, so a test can act while a write is under way.
    var inViewChange: (() async -> Void)?
    /// Another app's change to a view, taken by the server just before the next view change arrives, which then names
    /// a version the view no longer holds. As `views/change-stale` and `views/change-conflict` say, the server merges
    /// it where it changes only settings the other app left alone, and refuses it otherwise. Stricter than the server in
    /// two cases: naming a setting the other app changed is a conflict even when the value sent equals the new one, and
    /// clearing a group the named version never held is a conflict where the server leaves it (`views/group-clear`).
    var changedElsewhere: ((inout LibraryView) -> Void)?

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
            id: id, type: TypeID("core.note"), title: title, name: title.isEmpty ? nil : title, titleRule: .firstLine, state: state, tier: tier,
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

    /// Notes, tasks with a status, projects that hold them, collections, and files, as a server's catalogue might
    /// have them.
    static let testCatalogue: Catalogue = {
        let task = TypeID("core.task")
        let project = TypeID("test.project")
        let taskFields = [
            ItemTypeInfo.Field(key: "status", label: "Status", kind: .choice(["todo", "in_progress", "done"]), declaredBy: task),
            ItemTypeInfo.Field(key: "priority", label: "Priority", kind: .choice(["low", "medium", "high", "urgent"]), declaredBy: task),
            ItemTypeInfo.Field(key: "assignee", label: "Assignee", kind: .text, declaredBy: task),
        ]
        let types = [
            ItemTypeInfo(id: TypeID("core.note"), label: "Note", fields: [], titleField: "title", bodyField: "body", parent: nil),
            ItemTypeInfo(id: task, label: "Task", fields: taskFields, titleField: "title", bodyField: "body", parent: nil, icon: "lucide:list-checks"),
            ItemTypeInfo(
                id: project, label: "Project",
                fields: [ItemTypeInfo.Field(key: "description", label: "Description", kind: .text, declaredBy: project)],
                titleField: "title", bodyField: "body", parent: nil),
            ItemTypeInfo(
                id: collectionType, label: "Collection", fields: [], titleField: "title", bodyField: "description",
                parent: nil, roles: ["container"]),
            ItemTypeInfo(id: .file, label: "File", fields: [], titleField: nil, bodyField: nil, parent: nil),
            ItemTypeInfo(id: TypeID("core.file.image"), label: "Image", fields: [], titleField: nil, bodyField: nil, parent: .file),
        ]
        // A child names its parent, so `parent-of` is written at its target, under its reverse name.
        let parent = EdgeTypeInfo(
            id: "parent-of", label: "Children", reverseLabel: "Parent", reverseName: "child-of", cardinality: .one, writtenFrom: .to,
            fromTypes: [], toTypes: [])
        let collection = EdgeTypeInfo(
            id: "in-collection", label: "In collection", reverseLabel: "Contents", reverseName: nil, cardinality: .many,
            writtenFrom: .from, fromTypes: [], toTypes: [], toRoles: ["container"], flat: true)
        return Catalogue(itemTypes: types, edgeTypes: [parent, collection])
    }()

    static let collectionType = TypeID("test.collection")

    /// An active collection, of the catalogue's container type.
    static func collection(_ title: String, id: ItemID = .mint(), state: ItemState = .active) -> Item {
        Item(
            id: id, type: collectionType, title: title, name: title.isEmpty ? nil : title, titleRule: .property("title"), state: state,
            version: ItemVersion(1), created: .distantPast, modified: .distantPast)
    }

    // MARK: Reading

    func item(_ id: ItemID) -> Item? { items.first { $0.id == id } }

    /// How often a place's items were listed, for tests of what is kept rather than asked for again.
    @ObservationIgnored private(set) var placeReads = 0

    func items(in place: Place, scope: ListScope, archived: ArchivedItems, includingKinds: Bool) -> [Item] {
        placeReads += 1
        return items.filter { item in
            guard archived.includes(item.state) else { return false }
            switch place {
            case .library: return item.tier == .library
            case .feed: return item.tier == .feed
            case .archive: return true
            case .types, .collections, .sources: return false
            case .type(let type):
                let types = includingKinds ? catalogue.descendants(of: type).union([type]) : [type]
                return scope.includes(item.tier) && types.contains(item.type)
            case .collection(let id): return scope.includes(item.tier) && item.collectionIDs.contains(id)
            case .source(let code): return scope.includes(item.tier) && item.source == code
            }
        }
    }

    func items(inView id: ItemID) -> [Item] {
        placeReads += 1
        return items.filter { $0.state == .active && viewMembers[id]?.contains($0.id) == true }
    }

    func favoriteItems(in scope: ListScope, archived: ArchivedItems) -> [Item] {
        placeReads += 1
        return items.filter { archived.includes($0.state) && scope.includes($0.tier) && $0.isFavorite }
    }

    func previewItems(ofView view: ItemID, query: LibraryViewQuery) -> [Item] {
        previewsAsked.append(query)
        let members = previewMembers[query] ?? viewMembers[view] ?? []
        return items.filter { $0.state == .active && members.contains($0.id) }
    }

    func search(_ query: String, in scope: SearchScope) -> SearchResults {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .none }
        let place: Set<ItemID>? = switch scope {
        case .everywhere: nil
        case .view(let id): Set(items(inView: id).map(\.id))
        case .query(let query): Set(items.filter { item in
            (query.types.isEmpty || query.types.contains(item.type)) && query.tier.map { $0 == item.tier } != false
                && query.states.map { $0.contains(item.state) } != false
        }.map(\.id))
        }
        return SearchResults(items: items.filter {
            $0.state == .active && place?.contains($0.id) != false && ($0.title.localizedCaseInsensitiveContains(query)
                || bodies[$0.id]?.localizedCaseInsensitiveContains(query) == true)
        })
    }

    func search(_ query: String, narrowedBy narrowing: SearchNarrowing) -> SearchResults {
        var results = search(query, in: .everywhere)
        results.items = results.items.filter { item in
            narrowing.admitsType(item.type, in: catalogue) && narrowing.leftOutBy(item, in: catalogue) == nil
        }
        return results
    }

    func searchLeftOut(_ query: String, narrowedBy narrowing: SearchNarrowing) -> SearchResults {
        var results = search(query, in: .everywhere)
        results.items = Array(results.items.filter { item in
            narrowing.admitsType(item.type, in: catalogue) && narrowing.leftOutBy(item, in: catalogue) != nil
        }.prefix(SearchResults.leftOutLimit))
        return results
    }

    var deletedItems: [Item] { items.filter { $0.state == .trashed } }
    var deletedCount: Int { deletedItems.count }
    func count(in place: Place, scope: ListScope) -> Int {
        let scope: ListScope = place == .library ? .library : place == .feed ? .feed : scope
        return items(in: place, scope: scope, archived: .hidden, includingKinds: true).count
    }
    func scopeCounts(in place: Place) -> ScopeCounts {
        ScopeCounts(library: count(in: place, scope: .library), feed: count(in: place, scope: .feed))
    }
    func name(of place: Place) -> String {
        switch place {
        case .collection(let id): item(id)?.title ?? ""
        case .type(let type): catalogue.itemTypes[type]?.label ?? type.rawValue
        default: place.word
        }
    }
    func isGone(_ id: ItemID?) -> Bool { isLoaded && id.flatMap(item) == nil }
    func idsForWindows(_ ids: some Collection<ItemID>) -> [ItemID] { ids.filter { item($0) != nil } }
    func body(of id: ItemID) -> ItemBody? {
        guard let item = item(id), !item.isFile else { return nil }
        return ItemBody(id: id, text: bodies[id] ?? "", version: item.version)
    }
    /// What the core answers for a link target a test sets; any other is read by id or by title ignoring case.
    var linkAnswerOverrides: [String: LinkAnswer] = [:]
    func linkAnswers(of targets: [String], in note: ItemID?) async -> [LinkAnswer]? {
        return targets.map { target in
            if let set = linkAnswerOverrides[target] { return set }
            let name = linkParts(in: "[[\(target)]]").first?.name.text ?? target
            let named = items.filter {
                $0.state == .active && !$0.isFile
                    && ($0.id.rawValue == name || $0.title.lowercased() == name.lowercased())
            }.map(\.id)
            switch named.count {
            case 0: return LinkAnswer(target: target, state: .unresolved, item: nil, candidates: [])
            case 1: return LinkAnswer(target: target, state: .bound, item: named[0], candidates: named)
            default: return LinkAnswer(target: target, state: .ambiguous, item: nil, candidates: named)
            }
        }
    }
    func relationships(for id: ItemID) -> [ItemRelationship] { relationshipsByItem[id] ?? [] }
    /// What `relationFields(of:)` answers, by item.
    var relationFieldsByItem: [ItemID: [RelationField]] = [:] { didSet { membershipRevision += 1 } }
    /// How many times `relationFields(of:)` was asked, which a panel must not do again for each key it reads.
    @ObservationIgnored private(set) var relationFieldReads = 0
    func relationFields(of id: ItemID) -> [RelationField] {
        relationFieldReads += 1
        return relationFieldsByItem[id] ?? []
    }
    func childIDs(of id: ItemID) -> [ItemID] { items.filter { $0.parentID == id }.map(\.id) }
    /// What `relationshipCandidates(for:field:)` answers, by item.
    var candidatesByItem: [ItemID: [Item]] = [:]
    func relationshipCandidates(for id: ItemID, field: String) -> [Item] { candidatesByItem[id] ?? [] }
    /// The refusal for each (item, other) a test sets; any other link is taken.
    var refusals: [ItemID: [ItemID: String]] = [:]
    /// What `changeLinks` answers whatever it is asked, where a test sets one.
    var linkAnswer: EdgeVerdict?
    /// The refusal for a new item filed under each parent a test sets.
    var childRefusals: [ItemID: String] = [:]
    /// Waits before `newChildVerdict` answers, as the core's check does for a moment.
    var checkingParent: (() async -> Void)?
    func newChildVerdict(under parent: ItemID) async -> EdgeVerdict {
        await checkingParent?()
        return childRefusals[parent].map { .refused($0) } ?? .taken
    }
    /// What `linkTakenFrom` answers for each (item chosen, field) a test sets.
    var takenFrom: [ItemID: ItemID] = [:]
    func linkTakenFrom(_ other: ItemID, field: String, for id: ItemID) -> ItemID? { takenFrom[other] }
    func bodyMentions(for id: ItemID) -> [ItemRelationshipTarget] { [] }
    /// The items each type may be made under, by type.
    var parentCandidates: [String: [ItemID]] = [:]
    func creationParentCandidates(typeID: String) -> [Item] { (parentCandidates[typeID] ?? []).compactMap { item($0) } }
    func canHaveParent(typeID: String) -> Bool { !creationParentCandidates(typeID: typeID).isEmpty }

    // MARK: Files

    /// The file each file item fetches as.
    var files: [ItemID: URL] = [:]
    var fetchFails = false
    /// How many times a file was asked for.
    @ObservationIgnored var fetches = 0
    /// How long fetching each file takes, as a server's can.
    var fetchDelay: [ItemID: Duration] = [:]
    /// Files whose fetch waits until a test lets it go, so a test can look at a page that is still loading.
    var fetchGates: [ItemID: FetchGate] = [:]

    /// Notes whose saved text the copy has not read yet.
    var unreadSaves: Set<ItemID> = []

    /// How many times the library asked whether a save is unread, which a test waits on to know a task has begun
    /// waiting for one.
    @ObservationIgnored private(set) var unreadChecks = 0

    func hasUnreadSave(_ id: ItemID) -> Bool {
        unreadChecks += 1
        return unreadSaves.contains(id)
    }

    /// Puts the embed `text` in the text of `note`, unless it is there already, and binds it as Marfa's core does
    /// when the text is saved: to a new file item fetched as `file`, where one is given, or else to `resolution`.
    /// An embed the core does not take for a file, such as one of a note, is not `bound`.
    @discardableResult
    func bindEmbed(
        _ text: String, in note: ItemID, file: URL? = nil, resolution: ReferenceResolution = .missing, bound: Bool = true
    ) -> ItemID? {
        if bodies[note]?.contains(text) != true { bodies[note, default: ""] += text + "\n" }
        var binding = resolution
        var made: ItemID?
        if let file {
            let id = ItemID.mint()
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            items.append(Item(
                id: id, type: TypeID("core.file"), title: file.lastPathComponent, titleRule: .property("title"), content: .file(UTType(filenameExtension: file.pathExtension) ?? .data, byteCount: Int64(size)),
                version: ItemVersion(1), created: now(), modified: now()))
            files[id] = file
            binding = .resolved(id)
            made = id
        }
        guard bound, let index = items.firstIndex(where: { $0.id == note }) else { return made }
        items[index].boundEmbeds.removeAll { $0.text == text }
        items[index].boundEmbeds.append(BoundEmbed(text: text, resolution: binding))
        return made
    }

    func attachments(of id: ItemID) -> [ItemID] {
        items.filter { file in
            file.edgesOut.contains { $0.type == MarfaMapping.attachmentEdge && $0.to == .item(id) }
        }.map(\.id)
    }

    /// Attaches a new image file, fetched as `file`, to `host` as a connector saves a picture, with the web address
    /// it was saved from where one is given.
    @discardableResult
    func attachPicture(
        _ file: URL, to host: ItemID, from address: String? = nil, state: ItemState = .active, created: Date? = nil
    ) -> ItemID {
        let id = ItemID.mint()
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let moment = created ?? now()
        items.append(Item(
            id: id, type: TypeID("core.file.image"), title: file.lastPathComponent, titleRule: .property("title"),
            properties: address.map { [Property(key: SavedPictures.sourceField, value: .string($0))] } ?? [],
            content: .file(UTType(filenameExtension: file.pathExtension) ?? .data, byteCount: Int64(size)), state: state,
            version: ItemVersion(1), created: moment, modified: moment,
            edgesOut: [Edge(id: EdgeID("attached-\(id.rawValue)"), type: MarfaMapping.attachmentEdge, from: id, to: .item(host), origin: .body)]))
        files[id] = file
        return id
    }

    func fileURL(of id: ItemID) async throws -> URL? {
        fetches += 1
        if fetchFails { throw SourceFailure(kind: .failed, message: "The server can’t be reached.") }
        if let delay = fetchDelay[id] { try await Task.sleep(for: delay) }
        await fetchGates[id]?.passed()
        return files[id]
    }

    // MARK: Writing

    /// While set, `createItem` refuses every create and tells the person, as a library does a type it cannot make.
    var refusesCreations = false

    /// The tags each create was sent with, by item.
    private(set) var createdTags: [ItemID: [String]] = [:]
    /// The library a draft names, which a test sets to tell two apart.
    var serverKey = "fake"
    let pictures = WebPictures.kept(for: "Fake")

    func createItem(
        as id: ItemID, typeID: String, title: String, body: String, properties: [String: PropertyValue], tags: [String],
        parentID: ItemID?, tier: Tier, undoManager: UndoManager?
    ) -> ItemID? {
        guard !title.isEmpty || !properties.isEmpty || !body.isEmpty else { return nil }
        guard !refusesCreations else {
            notices.tell("Can’t Create Item", "Refused")
            return nil
        }
        let parent = parentID.map { Edge(id: EdgeID("child-of-\(id.rawValue)"), type: "child-of", from: id, to: .item($0), origin: .property("child-of")) }
        let item = Item(
            id: id, type: TypeID(typeID), title: title, titleRule: .property("title"),
            properties: properties.sorted { $0.key < $1.key }.map { Property(key: $0.key, value: $0.value) },
            tier: tier, tags: Set(tags),
            version: ItemVersion(1), created: now(), modified: now(), edgesOut: parent.map { [$0] } ?? [])
        createdTags[item.id] = tags
        bodies[item.id] = body
        created.append(item)
        if !holdsCreations { deliverCreated() }
        registerNewItemUndo(item.id, undoManager: undoManager)
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
    func setItemProperty(_ id: ItemID, key: String, value: PropertyValue?, undoManager: UndoManager?) -> Bool { false }

    /// Every call of `setItemProperties`, in order, with the changes as asked.
    private(set) var propertiesSet: [(id: ItemID, changes: [String: PropertyValue?], actionName: String)] = []
    /// Whether `setItemProperties` takes an edit; one it takes is made on the item, and its undo step is registered.
    var acceptsProperties = true
    /// While set, an edit `setItemProperties` takes stays on its way, as a library that queues it keeps it: the item does
    /// not show it and `isWritingProperties(of:)` is true, until `landPropertyWrites()`.
    var holdsPropertyWrites = false
    private var heldPropertyWrites: [(id: ItemID, changes: [String: PropertyValue?])] = []

    /// The edits on their way reach the items, in the order they were made.
    func landPropertyWrites() {
        for (id, changes) in heldPropertyWrites {
            if let index = items.firstIndex(where: { $0.id == id }) { apply(changes, to: index) }
        }
        heldPropertyWrites = []
        writingProperties = []
    }

    func setItemProperties(_ id: ItemID, changes: [String: PropertyValue?], actionName: String, undoManager: UndoManager?) -> Bool {
        guard acceptsProperties, let index = items.firstIndex(where: { $0.id == id }),
              changes.keys.allSatisfy({ items[index].obstacle(toField: $0) == nil }) else { return false }
        let old = Dictionary(uniqueKeysWithValues: changes.keys.map { ($0, items[index].value(of: $0)) })
        guard !changes.isEmpty, isWritingProperties(of: id) || changes.contains(where: { old[$0.key] != $0.value }) else { return true }
        write(id, changes, from: old, at: index, actionName: actionName, undoManager: undoManager)
        return true
    }

    /// Sends the edit, and registers an undo that sends the reverse and registers the redo, whatever the item holds by
    /// then, as the library's does. It puts back the values the edit found, as a library whose edits all land does.
    private func write(
        _ id: ItemID, _ changes: [String: PropertyValue?], from old: [String: PropertyValue?], at index: Int, actionName: String,
        undoManager: UndoManager?
    ) {
        propertiesSet.append((id, changes, actionName))
        if holdsPropertyWrites {
            heldPropertyWrites.append((id, changes))
            writingProperties.insert(id)
        } else {
            apply(changes, to: index)
        }
        undoManager?.registerUndo(withTarget: self) { library in
            guard let index = library.items.firstIndex(where: { $0.id == id }) else { return }
            library.write(id, old, from: changes, at: index, actionName: actionName, undoManager: undoManager)
        }
        undoManager?.setActionName(actionName)
    }

    private func apply(_ changes: [String: PropertyValue?], to index: Int) {
        for (key, value) in changes {
            items[index].properties.removeAll { $0.key == key }
            if let value { items[index].properties.append(Property(key: key, value: value)) }
        }
        items[index].version = ItemVersion(items[index].version.rawValue + 1)
        items[index].modified = now()
    }

    func isWritingProperties(of id: ItemID) -> Bool { writingProperties.contains(id) }
    func tookPropertyWrite(_ mark: Int) -> Bool { false }
    func changeLinks(_ id: ItemID, field: String, adding: [ItemID], removing: [ItemID], undoManager: UndoManager?) async -> EdgeVerdict {
        relationshipWrites.append((id, field, adding, removing))
        if let answer = linkAnswer { return answer }
        if let reason = adding.lazy.compactMap({ self.refusals[id]?[$0] }).first { return .refused(reason) }
        return acceptsRelationships ? .taken : .refused("Refused.")
    }

    /// Every change of type asked for.
    private(set) var typeChanges: [(ids: Set<ItemID>, type: TypeID, filling: [String: PropertyValue])] = []

    func changeType(_ ids: Set<ItemID>, to type: TypeID, filling: [String: PropertyValue], undoManager: UndoManager?) -> Bool {
        let plan = typeChangePlan(ids, to: type, filling: filling)
        guard plan.missing.isEmpty else { return false }
        tellSkipped(plan.skips, didChange: !plan.items.isEmpty, failing: "Can’t Change Type")
        guard !plan.items.isEmpty else { return plan.skips.isEmpty }
        let changing = Set(plan.items.map(\.item.id))
        typeChanges.append((changing, type, filling))
        change(changing) { $0.type = type }
        return true
    }

    /// Where `history` reads versions from; nil keeps none, as a library without a server does.
    var history: (any ItemHistorySource)?
    /// The versions restored, in order.
    private(set) var restored: [(snapshot: ItemSnapshot, id: ItemID)] = []

    func restoreVersion(_ snapshot: ItemSnapshot, of id: ItemID, undoManager: UndoManager?) -> Bool {
        switch restoreCheck(of: snapshot, for: id) {
        case .unchanged:
            return true
        case .unavailable(let reason):
            notices.tell("Can’t Restore Version", reason)
            return false
        case .ready(let plan):
            restored.append((snapshot, id))
            if let text = plan.text, let held = body(of: id) { updateBody(of: id, to: text, readAt: held.version) }
            if let title = plan.title { change([id]) { $0.title = title } }
            return true
        }
    }

    func setFavorite(_ ids: Set<ItemID>, _ isFavorite: Bool, undoManager: UndoManager?) {
        let plan = favoritePlan(ids, isFavorite)
        tellSkipped(plan.skips, didChange: !plan.changing.isEmpty, failing: "Can’t Change Favorites")
        change(plan.changing) { item in
            if isFavorite { item.tags.insert(ItemTag.favorite) } else { item.tags.remove(ItemTag.favorite) }
        }
    }

    /// What the fake reserves besides the favorite tag.
    var extraReservedTags: Set<String> = []
    var reservedTags: Set<String> { extraReservedTags.union([ItemTag.favorite]) }

    var knownTagCounts: [String: Int] {
        items.filter { $0.state == .active }.flatMap(\.tags).filter { !reservedTags.contains($0) }
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
    }

    var knownTags: [String] {
        let counts = knownTagCounts
        return counts.keys.sorted { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : $0 < $1 }
    }

    /// The tag writes the fake was asked for, in order.
    var tagWrites: [(tag: String, on: Bool, ids: Set<ItemID>)] = []

    @discardableResult
    func addTag(_ tag: String, to ids: Set<ItemID>, undoManager: UndoManager?) -> ItemTag.Refusal? {
        switch checkedTag(tag, adding: ids) {
        case .failure(let refusal): return refusal
        case .success(let (tag, changing, skips)):
            tellSkipped(skips, didChange: true, failing: "Can’t Add Tag")
            tagWrites.append((tag, true, changing))
            change(changing) { $0.tags.insert(tag) }
            return nil
        }
    }

    func removeTag(_ tag: String, from ids: Set<ItemID>, undoManager: UndoManager?) {
        let changing = Set(ids.filter { item($0).map { $0.allows(.tags) && $0.tags.contains(tag) } ?? false })
        guard !reservedTags.contains(tag), !changing.isEmpty else { return }
        tagWrites.append((tag, false, changing))
        change(changing) { $0.tags.remove(tag) }
    }

    func moreItemsTaken(with ids: Set<ItemID>) async -> Int? { nil }

    func registerNewItemUndo(_ id: ItemID, undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { library in library.delete([id], undoManager: nil) }
        undoManager?.setActionName("New Item")
    }

    func delete(_ ids: Set<ItemID>, undoManager: UndoManager?) {
        let plan = deletePlan(ids)
        tellSkipped(plan.skips, didChange: !plan.moving.isEmpty, failing: "Can’t Delete")
        change(plan.moving) { item in
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
        itemsToPurge.subtract(ids)
    }

    /// Each batch attached, by the item it was attached to and the file names, in order.
    private(set) var attachedBatches: [(item: ItemID, names: [String])] = []

    func attach(_ files: [(name: String, data: Data)], to id: ItemID) async -> AttachReport {
        attachedBatches.append((item: id, names: files.map(\.name)))
        return await attaching?() ?? AttachReport()
    }

    /// Every file attached one at a time, by name, and the names whose attach throws.
    private(set) var attachedFiles: [(name: String, data: Data, item: ItemID)] = []
    var refusedAttachments: Set<String> = []

    func attach(file: URL, to id: ItemID) async throws -> Embed {
        let name = file.lastPathComponent
        if refusedAttachments.contains(name) { throw SourceFailure(kind: .failed, message: "The upload failed.") }
        attachedFiles.append((name, try Data(contentsOf: file), id))
        return Embed(link: name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name, name: name)
    }

    func editField(_ plan: FieldEditPlan) async -> TypeSchemaFailure? {
        if let fieldFailure { return fieldFailure }
        editedFields.append(plan)
        catalogue = catalogue.applying(plan)
        return nil
    }

    func answerIcon() {
        heldIconAnswer?.resume()
        heldIconAnswer = nil
    }

    func setIcon(_ icon: String?, ofType type: TypeID) async -> TypeIconFailure? {
        if holdsIconAnswers { await withCheckedContinuation { heldIconAnswer = $0 } }
        if let iconFailure { return iconFailure }
        chosenIcons.append((type, icon))
        catalogue = catalogue.choosingIcon(icon, ofType: type)
        return nil
    }

    func refreshSources() async {
        sourceRefreshes += 1
        if let serverSources { sources = serverSources }
    }

    func updateSource(_ code: String, name: SourceFieldChange?, mark: SourceFieldChange?) async -> SourceEditFailure? {
        if let sourceFailure { return sourceFailure }
        sourceChanges.append((code, name, mark))
        let old = sources.info(code)
        let newName: String
        var origin = old.nameOrigin
        switch name {
        case .set(let text)?: newName = text; origin = .set
        case .clear?: newName = code; origin = .code
        case nil: newName = old.name
        }
        let newMark: String?
        switch mark {
        case .set(let id)?: newMark = id
        case .clear?: newMark = nil
        case nil: newMark = old.mark
        }
        sources = sources.updating(SourceInfo(code: code, name: newName, mark: newMark, nameOrigin: origin))
        return nil
    }

    func createView(_ settings: LibraryViewSettings) async -> LibraryView? {
        await inViewWrite?()
        if let viewFailure {
            notices.tell("Can’t Save View", viewFailure.message)
            return nil
        }
        let view = LibraryView(id: ItemID.mint(), title: settings.title, version: 1, query: settings.query, sort: settings.sort, group: settings.group)
        views = LibraryView.ordered(views + [view])
        return view
    }

    func changeView(_ id: ItemID, _ change: LibraryViewChange, baseVersion: Int64) async -> Result<LibraryView, ViewWriteFailure> {
        await inViewChange?()
        guard var view = views.first(where: { $0.id == id }) else { return .failure(ViewWriteFailure(kind: .gone, message: "Gone")) }
        var merges = false
        if let elsewhere = changedElsewhere {
            changedElsewhere = nil
            let before = view
            elsewhere(&view)
            view.version += 1
            views = LibraryView.ordered(views.filter { $0.id != id } + [view])
            let clashes = (change.title != nil && view.title != before.title) || (change.query != nil && view.query != before.query)
                || (change.sort != nil && view.sort != before.sort) || (change.group != nil && view.group != before.group)
            merges = baseVersion == before.version && !clashes
        }
        let current = view.version == baseVersion || merges
        let failure = viewFailure ?? (current ? nil : ViewWriteFailure(kind: .conflict, message: "Changed elsewhere"))
        if let failure {
            notices.tell("Can’t Update View", failure.message)
            return .failure(failure)
        }
        if let title = change.title { view.title = title }
        if let query = change.query { view.query = query }
        if let sort = change.sort { view.sort = sort }
        switch change.group {
        case .set(let group): view.group = group
        case .clear: view.group = nil
        case nil: break
        }
        view.version += 1
        views = LibraryView.ordered(views.filter { $0.id != id } + [view])
        return .success(view)
    }

    func deleteView(_ id: ItemID) async -> Bool {
        if let viewFailure {
            notices.tell("Can’t Delete View", viewFailure.message)
            return false
        }
        views.removeAll { $0.id == id }
        await inViewWrite?()
        return true
    }

    /// Every file added, and whether adding one is refused.
    private(set) var addedFiles: [(name: String, data: Data, title: String?, parent: ItemID?)] = []
    /// The tier each file was added to, in step with `addedFiles`.
    private(set) var addedTiers: [Tier] = []
    /// The tags each file was added with, in step with `addedFiles`.
    private(set) var addedFileTags: [[String]] = []
    var refusesFiles = false
    /// Names of files that are added but whose items the library does not hold until `showWithheld()`, as a library
    /// fed by a server holds an item only once its source says so.
    var withheldFiles: Set<String> = []
    private(set) var withheld: [Item] = []

    func showWithheld() {
        items.append(contentsOf: withheld)
        withheld = []
    }
    /// Awaited before a file is added, so a test can act while it is being sent.
    var sendingFile: (() async -> Void)?

    func addFile(_ file: URL, title: String?, parentID: ItemID?, tier: Tier, tags: [String]) async -> ItemID? {
        await sendingFile?()
        guard !refusesFiles else {
            notices.tell("Can’t Add File", "Refused")
            return nil
        }
        let name = file.lastPathComponent
        guard let data = try? Data(contentsOf: file) else {
            notices.tell("Can’t Add File", "Unreadable")
            return nil
        }
        addedFiles.append((name, data, title, parentID))
        addedTiers.append(tier)
        addedFileTags.append(tags)
        let id = ItemID.mint()
        let parent = parentID.map { Edge(id: EdgeID("child-of-\(id.rawValue)"), type: "child-of", from: id, to: .item($0), origin: .property("child-of")) }
        let made = Item(
            id: id, type: .file, title: title ?? name, titleRule: .property("title"), content: .file(.data, byteCount: Int64(data.count)),
            version: ItemVersion(1), created: now(), modified: now(), edgesOut: parent.map { [$0] } ?? [])
        if withheldFiles.contains(name) { withheld.append(made) } else { items.append(made) }
        return id
    }

    // MARK: Tier and state

    func setTier(_ ids: Set<ItemID>, to tier: Tier, undoManager: UndoManager?, moved: ((CommandOutcome) -> Void)?) {
        let move: ItemMove = tier == .library ? .keep : .moveToFeed
        let plan = tierPlan(ids, to: tier)
        tellSkipped(plan.skips, didChange: !plan.changing.isEmpty, failing: move.failing)
        let before = Dictionary(uniqueKeysWithValues: plan.changing.compactMap { id in item(id).map { (id, $0.tier) } })
        change(plan.changing) { $0.tier = tier }
        undoManager?.registerUndo(withTarget: self) { library in
            for (id, old) in before { library.change([id]) { $0.tier = old } }
        }
        undoManager?.setActionName(move.name)
        moved?(CommandOutcome(plan.changing, skips: plan.skips))
    }

    /// What Move to Feed and Unarchive ask first, which a test sets.
    var feedLimit: FeedLimitQuestion?

    func feedLimitQuestion(_ move: ItemMove, for ids: Set<ItemID>) -> FeedLimitQuestion? { feedLimit }

    func archive(_ ids: Set<ItemID>, beneath: Bool, undoManager: UndoManager?, moved: ((CommandOutcome) -> Void)?) {
        let plan = archivePlan(ids)
        let moving = beneath ? plan.archiving.union(plan.beneath) : plan.archiving
        tellSkipped(plan.skips, didChange: !moving.isEmpty, failing: ItemMove.archive.failing)
        moveState(moving, to: .archived, name: ItemMove.archive.name, undoManager: undoManager)
        moved?(CommandOutcome(moving, skips: plan.skips))
    }

    func unarchive(_ ids: Set<ItemID>, undoManager: UndoManager?, moved: ((CommandOutcome) -> Void)?) {
        let plan = unarchivePlan(ids)
        tellSkipped(plan.skips, didChange: !plan.changing.isEmpty, failing: ItemMove.unarchive.failing)
        moveState(plan.changing, to: .active, name: ItemMove.unarchive.name, undoManager: undoManager)
        moved?(CommandOutcome(plan.changing, skips: plan.skips))
    }

    private func moveState(_ ids: Set<ItemID>, to state: ItemState, name: String, undoManager: UndoManager?) {
        let back: ItemState = state == .archived ? .active : .archived
        change(ids) { $0.state = state }
        undoManager?.registerUndo(withTarget: self) { library in library.moveState(ids, to: back, name: name, undoManager: undoManager) }
        undoManager?.setActionName(name)
    }

    // MARK: Collections

    var collections: [Item] {
        items.filter { $0.state == .active && catalogue.isCollection($0.type) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var joinableCollections: [Item] {
        items.filter { $0.state != .trashed && catalogue.isCollection($0.type) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func addToCollection(_ ids: Set<ItemID>, _ collection: ItemID, undoManager: UndoManager?) -> Bool {
        guard joinableCollections.contains(where: { $0.id == collection }) else {
            notices.tell("Can’t Add to Collection", "Refused")
            return false
        }
        let plan = collectionPlan(ids, joining: collection)
        tellSkipped(plan.skips, didChange: !plan.joining.isEmpty, failing: "Can’t Add to Collection")
        let joining = Set(plan.joining.map(\.id))
        for index in items.indices where joining.contains(items[index].id) {
            let id = items[index].id
            items[index].edgesOut.append(Edge(
                id: EdgeID("in-collection-\(id.rawValue)-\(collection.rawValue)"), type: MarfaMapping.collectionEdge,
                from: id, to: .item(collection), origin: .property(MarfaMapping.collectionEdge)))
        }
        return !joining.isEmpty || plan.skips.isEmpty
    }

    func removeFromCollection(_ ids: Set<ItemID>, _ collection: ItemID, undoManager: UndoManager?) -> Bool {
        var removed = false
        var skips = BatchSkips()
        for index in items.indices where ids.contains(items[index].id) {
            guard items[index].collectionIDs.contains(collection) else { continue }
            if let reason = items[index].obstacle(to: .collections) {
                skips.skip(reason)
                continue
            }
            items[index].edgesOut.removeAll { $0.type == MarfaMapping.collectionEdge && $0.to == .item(collection) }
            removed = true
        }
        tellSkipped(skips, didChange: removed, failing: "Can’t Remove from Collection")
        return removed
    }

    private func change(_ ids: Set<ItemID>, _ body: (inout Item) -> Void) {
        for index in items.indices where ids.contains(items[index].id) {
            body(&items[index])
            items[index].version = ItemVersion(items[index].version.rawValue + 1)
        }
    }
}

extension FakeItemLibrary {
    func makeCounts() -> ItemCounts {
        ItemCounts { [weak self] ids, query in
            try await MainActor.run {
                guard let self else { throw ItemCountUnavailable() }
                return try self.countAnswers(ids, query)
            }
        }
    }

    func countAnswers(_ ids: [ItemID], _ query: CountQuery) throws -> [ItemID: ItemCountAnswer] {
        var answers: [ItemID: ItemCountAnswer] = [:]
        for id in ids {
            let counted: [Item]
            switch query {
            case .children: counted = items.filter { $0.parentID == id && $0.state == .active }
            case .members: counted = items.filter { $0.collectionIDs.contains(id) && $0.state == .active }
            case .rows: answers[id] = ItemCountAnswer(total: 0, groups: nil); continue
            }
            var groups = ItemCountAnswer.Groups()
            for item in counted {
                guard let info = catalogue.itemTypes[item.type], let status = info.statusField,
                      let word = item.value(of: status.key)?.string, let group = status.statusGroup(of: word) else { continue }
                switch group {
                case .notStarted: groups.notStarted += 1
                case .inProgress: groups.inProgress += 1
                case .completed: groups.completed += 1
                case .canceled: groups.canceled += 1
                }
            }
            answers[id] = ItemCountAnswer(total: counted.count, groups: groups)
        }
        return answers
    }
}

/// Holds the fetch of a file until a test calls `open()`.
@MainActor final class FetchGate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func passed() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        for continuation in waiting { continuation.resume() }
        waiting = []
    }
}
