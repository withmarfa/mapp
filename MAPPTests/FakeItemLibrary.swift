import Foundation
import Observation
import UniformTypeIdentifiers
@testable import MAPP

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
    var notesToPurge: Set<ItemID> = []
    var catalogue = FakeItemLibrary.testCatalogue { didSet { contentRevision += 1; membershipRevision += 1 } }
    var views: [LibraryView] = []
    /// What each view lists, by view.
    var viewMembers: [ItemID: [ItemID]] = [:]
    var reachesServer = true
    /// What the next icon choice answers: nil keeps it, a failure refuses it.
    var iconFailure: TypeIconFailure?
    private(set) var chosenIcons: [(type: TypeID, icon: String?)] = []
    /// While set, an icon choice waits for `answerIcon()` before it answers.
    var holdsIconAnswers = false
    private var heldIconAnswer: CheckedContinuation<Void, Never>?
    /// What every view write fails with while set.
    var viewFailure: ViewWriteFailure?
    var trashDays: Int?
    /// What `relationships(for:)` answers, by item.
    var relationshipsByItem: [ItemID: [ItemRelationship]] = [:]
    /// Whether `setItemRelationship` takes a write, and the writes it was asked for.
    var acceptsRelationships = false
    var relationshipWrites: [(item: ItemID, field: String, targets: [ItemID])] = []
    var syncReport = SyncReport(queueRead: true)
    let now: () -> Date
    /// What `attach` answers, which may wait; nil attaches nothing.
    var attaching: (() async -> AttachReport)?

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

    /// Notes, tasks with a status, projects that hold them, collections, and files, as a server's catalogue might
    /// have them.
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
            id: "parent-of", label: "Children", reverseLabel: "Parent", reverseName: "child-of", cardinality: .one, writtenAt: .target,
            sourceTypes: [], targetTypes: [])
        let collection = EdgeTypeInfo(
            id: "in-collection", label: "In collection", reverseLabel: "Contents", reverseName: nil, cardinality: .many,
            writtenAt: .source, sourceTypes: [], targetTypes: [], targetRoles: ["container"])
        return Catalogue(itemTypes: types, edgeTypes: [parent, collection])
    }()

    static let collectionType = TypeID("test.collection")

    /// An active collection, of the catalogue's container type.
    static func collection(_ title: String, id: ItemID = .mint(), state: ItemState = .active) -> Item {
        Item(
            id: id, type: collectionType, title: title, titleRule: .property("title"), state: state,
            version: ItemVersion(1), created: .distantPast, modified: .distantPast)
    }

    // MARK: Reading

    func item(_ id: ItemID) -> Item? { items.first { $0.id == id } }

    /// How often a place's items were listed, for tests of what is kept rather than asked for again.
    @ObservationIgnored private(set) var placeReads = 0

    func items(in place: SidebarItem) -> [Item] {
        placeReads += 1
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
            case .collection(let id): item.state == .active && item.collectionIDs.contains(id)
            case .files: item.state == .active && item.isFile
            case .view(let id): item.state == .active && viewMembers[id]?.contains(item.id) == true
            case .recentlyDeleted: item.state == .trashed
            }
        }
    }

    func search(_ query: String, in scope: SearchScope) -> SearchResults {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .none }
        let place = if case .place(let place) = scope { Set(items(in: place).map(\.id)) } else { nil as Set<ItemID>? }
        return SearchResults(items: items.filter {
            $0.state == .active && place?.contains($0.id) != false && ($0.title.localizedCaseInsensitiveContains(query)
                || bodies[$0.id]?.localizedCaseInsensitiveContains(query) == true)
        })
    }

    func count(in place: SidebarItem) -> Int { items(in: place).count }
    func name(of place: SidebarItem) -> String {
        switch place {
        case .favoriteItem(let id), .collection(let id): item(id)?.title ?? ""
        case .itemType(let type): catalogue.itemTypes[TypeID(type)]?.label ?? type
        case .view(let id): views.first { $0.id == id }?.title ?? ""
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
    func canHaveParent(typeID: String) -> Bool { !creationParentCandidates(typeID: typeID).isEmpty }

    // MARK: Files

    /// The file each file item fetches as.
    var files: [ItemID: URL] = [:]
    var fetchFails = false
    /// How many times a file was asked for.
    @ObservationIgnored var fetches = 0
    /// How long fetching each file takes, as a server's can.
    var fetchDelay: [ItemID: Duration] = [:]

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
        _ text: String, in note: ItemID, file: URL? = nil, resolution: NoteReferenceResolution = .missing, bound: Bool = true
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
            file.edgesOut.contains { $0.type == MarfaMapping.attachmentEdge && $0.target == .item(id) }
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
            edgesOut: [Edge(id: EdgeID("attached-\(id.rawValue)"), type: MarfaMapping.attachmentEdge, source: id, target: .item(host), origin: .body)]))
        files[id] = file
        return id
    }

    func fileURL(of id: ItemID) async throws -> URL? {
        fetches += 1
        if fetchFails { throw SourceFailure(kind: .failed, message: "The server can’t be reached.") }
        if let delay = fetchDelay[id] { try await Task.sleep(for: delay) }
        return files[id]
    }

    // MARK: Writing

    /// While set, `createItem` refuses every create and tells the person, as a library does a type it cannot make.
    var refusesCreations = false

    func createItem(
        typeID: String, title: String, body: String, properties: [String: PropertyValue], parentID: ItemID?,
        in place: SidebarItem, undoManager: UndoManager?
    ) -> ItemID? {
        guard !title.isEmpty else { return nil }
        guard !refusesCreations else {
            notices.tell("Can’t Create Item", "Refused")
            return nil
        }
        let id = ItemID.mint()
        let parent = parentID.map { Edge(id: EdgeID("child-of-\(id.rawValue)"), type: "child-of", source: id, target: .item($0), origin: .property("child-of")) }
        let item = Item(
            id: id, type: TypeID(typeID), title: title, titleRule: .property("title"),
            properties: properties.sorted { $0.key < $1.key }.map { Property(key: $0.key, value: $0.value) },
            tier: place == .inbox ? .feed : .library,
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
    func setItemProperty(_ id: ItemID, key: String, value: PropertyValue?, undoManager: UndoManager?) -> Bool { false }
    func setItemRelationship(_ id: ItemID, field: String, targetIDs: [ItemID], undoManager: UndoManager?) -> Bool {
        relationshipWrites.append((id, field, targetIDs))
        return acceptsRelationships
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

    var knownTags: [String] {
        let counts = items.filter { $0.state == .active }.flatMap(\.tags).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.keys.filter { !reservedTags.contains($0) }
            .sorted { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : $0 < $1 }
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
        let changing = Set(ids.filter { item($0).map { $0.canEditTags && $0.tags.contains(tag) } ?? false })
        guard !reservedTags.contains(tag), !changing.isEmpty else { return }
        tagWrites.append((tag, false, changing))
        change(changing) { $0.tags.remove(tag) }
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

    func attach(_ files: [(name: String, data: Data)], to id: ItemID) async -> AttachReport {
        await attaching?() ?? AttachReport()
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

    func createView(_ settings: LibraryViewSettings) async -> LibraryView? {
        if let viewFailure {
            notices.tell("Can’t Save View", viewFailure.message)
            return nil
        }
        let view = LibraryView(id: ItemID.mint(), title: settings.title, version: 1, query: settings.query, sort: settings.sort, group: settings.group)
        views = LibraryView.ordered(views + [view])
        return view
    }

    func changeView(_ id: ItemID, _ change: LibraryViewChange, baseVersion: Int64) async -> Result<LibraryView, ViewWriteFailure> {
        guard var view = views.first(where: { $0.id == id }) else { return .failure(ViewWriteFailure(kind: .gone, message: "Gone")) }
        let failure = viewFailure ?? (view.version == baseVersion ? nil : ViewWriteFailure(kind: .conflict, message: "Changed elsewhere"))
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
        return true
    }

    /// Every file added, and whether adding one is refused.
    private(set) var addedFiles: [(name: String, data: Data, title: String?, parent: ItemID?)] = []
    var refusesFiles = false
    /// Awaited before a file is added, so a test can act while it is being sent.
    var sendingFile: (() async -> Void)?

    func addFile(_ file: URL, title: String?, parentID: ItemID?, in place: SidebarItem) async -> ItemID? {
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
        let id = ItemID.mint()
        let parent = parentID.map { Edge(id: EdgeID("child-of-\(id.rawValue)"), type: "child-of", source: id, target: .item($0), origin: .property("child-of")) }
        items.append(Item(
            id: id, type: .file, title: title ?? name, titleRule: .property("title"), content: .file(.data, byteCount: Int64(data.count)),
            version: ItemVersion(1), created: now(), modified: now(), edgesOut: parent.map { [$0] } ?? []))
        return id
    }

    // MARK: Collections

    var collections: [Item] {
        items.filter { $0.state == .active && catalogue.isCollection($0.type) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func addToCollection(_ ids: Set<ItemID>, _ collection: ItemID, undoManager: UndoManager?) -> Bool {
        guard collections.contains(where: { $0.id == collection }) else {
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
                source: id, target: .item(collection), origin: .property(MarfaMapping.collectionEdge)))
        }
        return !joining.isEmpty || plan.skips.isEmpty
    }

    func removeFromCollection(_ ids: Set<ItemID>, _ collection: ItemID, undoManager: UndoManager?) -> Bool {
        var removed = false
        var skips = BatchSkips()
        for index in items.indices where ids.contains(items[index].id) {
            guard items[index].collectionIDs.contains(collection) else { continue }
            if let reason = items[index].writeObstacle {
                skips.skip(reason)
                continue
            }
            items[index].edgesOut.removeAll { $0.type == MarfaMapping.collectionEdge && $0.target == .item(collection) }
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
