import Foundation
import Observation
@testable import MAPP

/// A library held in memory, with no folder and no store, so the views' models can be tested through
/// `ItemLibrary` alone. It keeps items and bodies as given and answers the places by their plain meaning.
@Observable
final class FakeItemLibrary: ItemLibrary {
    var items: [Item]
    var bodies: [ItemID: String]
    var folders: [Folder]
    var isLoaded = true
    var failure: (title: String, message: String)?
    var notesToPurge: Set<ItemID> = []
    var catalogue = WorkbenchSchema.catalogue
    var capabilities: SourceCapabilities = []
    var trashDays: Int?
    var completedImports: [UUID: ItemID] = [:]
    var syncReport = SyncReport(queueRead: true)
    let now: () -> Date
    /// What `attach` answers, which may wait or throw; nil attaches nothing.
    var attaching: (() async throws -> [Embed])?

    init(items: [Item] = [], bodies: [ItemID: String] = [:], folders: [Folder] = [], now: Date = .now) {
        self.items = items
        self.bodies = bodies
        self.folders = folders
        self.now = { now }
    }

    /// A note as the fake holds one: an active core note in the Inbox, edited at `modified`.
    static func note(
        _ title: String, modified: Date, in folder: Folder? = nil, isFavorite: Bool = false, state: ItemState = .active
    ) -> Item {
        Item(
            id: .mint(), type: TypeID("core.note"), title: title, titleRule: .firstLine, state: state,
            container: folder.map { ContainerID($0.id) }, tags: isFavorite ? [ItemTag.favorite] : [],
            version: ItemVersion(1), created: modified, modified: modified)
    }

    // MARK: Reading

    func item(_ id: ItemID) -> Item? { items.first { $0.id == id } }

    func items(in place: SidebarItem) -> [Item] {
        items.filter { item in
            switch place {
            case .inbox: item.state == .active && item.container == nil
            case .allNotes: item.state == .active
            case .favorites: item.state == .active && item.isFavorite
            case .favoriteItem(let id): item.id == id && item.state == .active && item.isFavorite
            case .folder(let id): item.state == .active && item.container == ContainerID(id)
            case .itemType(let type): item.state == .active && item.type == TypeID(type)
            case .project(let id): item.state == .active && item.id == id
            case .files: item.state == .active && item.isFile
            case .recentlyDeleted: item.state == .trashed
            case .marfaTypes: false
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
    func name(of place: SidebarItem) -> String { "\(place)" }
    func folder(_ id: ItemID) -> Folder? { folders.first { $0.id == id } }
    func folder(of item: Item) -> Folder? { item.container.flatMap { container in folders.first { ContainerID($0.id) == container } } }
    func isGone(_ id: ItemID?) -> Bool { isLoaded && id.flatMap(item) == nil }
    func idsForWindows(_ ids: some Collection<ItemID>) -> [ItemID] { ids.filter { item($0) != nil } }
    func body(of id: ItemID) -> ItemBody? {
        guard let item = item(id), !item.isFile else { return nil }
        return ItemBody(id: id, text: bodies[id] ?? "", version: item.version)
    }
    func resolveLink(_ link: NoteLink, in source: ItemID) -> NoteReferenceResolution {
        let name = link.name
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
    func relationships(for id: ItemID) -> [ItemRelationship] { [] }
    func relationshipCandidates(for id: ItemID, field: String) -> [Item] { [] }
    func bodyMentions(for id: ItemID) -> [ItemRelationshipTarget] { [] }
    func creationParentCandidates(typeID: String) -> [Item] { [] }
    func isItemTitleTaken(_ title: String) -> Bool {
        items.contains { $0.state == .active && $0.title.caseInsensitiveCompare(title) == .orderedSame }
    }
    func isNoteNameTaken(_ name: String, for id: ItemID) -> Bool { false }
    func isFolderNameTaken(_ name: String, except id: ItemID?) -> Bool {
        folders.contains { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    // MARK: Files

    var folderURL: URL? { nil }
    /// Files at hand, as a folder's are; `fetchable` are those that arrive only when asked for, as a server's do.
    var files: [ItemID: URL] = [:]
    var fetchable: [ItemID: URL] = [:]
    var fetchFails = false
    /// How long fetching each file takes, as a server's can.
    var fetchDelay: [ItemID: Duration] = [:]

    func fileURL(for id: ItemID) -> URL? { files[id] }
    func fileURL(of id: ItemID) async throws -> URL? {
        if fetchFails { throw SourceFailure(kind: .failed, message: "The server can’t be reached.") }
        if let delay = fetchDelay[id] { try await Task.sleep(for: delay) }
        return files[id] ?? fetchable[id]
    }
    func path(of id: ItemID) -> String? { nil }
    func fileName(of id: ItemID) -> String? { nil }
    func imageBase(of id: ItemID) -> String? { nil }

    // MARK: Writing

    func createItem(
        typeID: String, title: String, body: String, parentID: ItemID?, in place: SidebarItem, undoManager: UndoManager?
    ) -> ItemID? {
        guard !title.isEmpty, !isItemTitleTaken(title) else { return nil }
        let container: ContainerID? = if case .folder(let id) = place { ContainerID(id) } else { nil }
        let item = Item(
            id: .mint(), type: TypeID(typeID), title: title, titleRule: .property("title"), container: container,
            version: ItemVersion(1), created: now(), modified: now())
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

    func updateBody(of id: ItemID, to body: String, readAt: ItemVersion) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        bodies[id] = body
        items[index].version = ItemVersion(items[index].version.rawValue + 1)
        items[index].modified = now()
    }

    func leave(_ id: ItemID) {}
    func resolve(_ problem: SyncProblemEntry.ID, by action: SyncAction) async throws -> Bool { false }
    /// Creates refused after `createItem` answered, as a server's source refuses one it cannot queue.
    var refusedCreations: Set<ItemID> = []
    func finish() {}
    func wasRefused(creating id: ItemID) -> Bool { refusedCreations.contains(id) }
    func setItemProperty(_ id: ItemID, key: String, value: PropertyValue?, undoManager: UndoManager?) -> Bool { false }
    func setItemRelationship(_ id: ItemID, field: String, targetIDs: [ItemID], undoManager: UndoManager?) -> Bool { false }

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

    func move(_ ids: Set<ItemID>, to folderID: ItemID?, undoManager: UndoManager?) {
        change(ids) { $0.container = folderID.map(ContainerID.init) }
    }

    func renameNote(_ id: ItemID, to name: String, undoManager: UndoManager?) {
        change([id]) { $0.title = name }
    }

    func attach(_ files: [(name: String, data: Data)], to id: ItemID) async throws -> [Embed] {
        try await attaching?() ?? []
    }
    func importFiles(_ sources: [URL], folderID: ItemID?, requestID: UUID) {}
    func consumeImportCompletion(_ requestID: UUID) { completedImports[requestID] = nil }

    // MARK: Folders

    func newFolder(undoManager: UndoManager?) -> Folder {
        let folder = Folder(name: "New Folder")
        folders.append(folder)
        return folder
    }

    func rename(_ id: ItemID, to name: String, undoManager: UndoManager?) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].name = name
    }

    func deleteFolder(_ id: ItemID, undoManager: UndoManager?) {
        delete(Set(items.filter { $0.container == ContainerID(id) }.map(\.id)), undoManager: undoManager)
        folders.removeAll { $0.id == id }
    }

    func moveFolders(_ ids: [ItemID], before target: ItemID?, undoManager: UndoManager?) {}

    private func change(_ ids: Set<ItemID>, _ body: (inout Item) -> Void) {
        for index in items.indices where ids.contains(items[index].id) {
            body(&items[index])
            items[index].version = ItemVersion(items[index].version.rawValue + 1)
        }
    }
}
