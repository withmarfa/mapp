import Foundation
import UniformTypeIdentifiers

/// An item made from a note or file, kept until that note or file changes or its references are resolved again.
nonisolated struct CachedItem {
    let revision: Int64
    let connectionGeneration: Int
    let item: Item
}

/// Every item in the order of the notes, then the files, and where each one is.
nonisolated struct ItemCollection {
    let stamp: Int
    let connectionGeneration: Int
    let items: [Item]
    let positions: [ItemID: Int]
}

/// How many items each place holds, counted in one pass, since the sidebar asks for every place at once.
nonisolated struct ItemCounts {
    let stamp: Int
    var active = 0
    var inbox = 0
    var favorites = 0
    var files = 0
    var trashed = 0
    var containers: [ContainerID: Int] = [:]
    var types: [TypeID: Int] = [:]

    init(_ items: [Item], stamp: Int) {
        self.stamp = stamp
        for item in items {
            guard item.state == .active else {
                if item.state == .trashed { trashed += 1 }
                continue
            }
            active += 1
            if let container = item.container { containers[container, default: 0] += 1 } else { inbox += 1 }
            if item.isFavorite { favorites += 1 }
            if item.isFile { files += 1 }
            types[item.type, default: 0] += 1
        }
    }
}

/// The connection index and what each record held when it was made: enough to tell, without making it again,
/// whether a change could alter a name or a reference.
nonisolated struct Connections {
    struct Key: Equatable {
        var title: String
        var path: String
        var frontMatter: String
        var referenceLines: [Substring]
    }

    var index: NoteConnectionIndex
    var generation: Int
    var stamp: Int
    var keys: [ItemID: (revision: Int64, key: Key)]
}

extension NoteLibrary {
    /// The files library's types: the workbench schema, and files as Marfa's core types.
    var catalogue: Catalogue { WorkbenchSchema.catalogue }

    // MARK: Items

    /// Every item, those in Recently Deleted among them. Each is made once and kept until its note or file
    /// changes, so reading the collection again after one edit makes one item, not all of them.
    var allItems: [Item] { collection.items }

    func item(_ id: ItemID) -> Item? {
        let collection = collection
        return collection.positions[id].map { collection.items[$0] }
    }

    func items(in place: SidebarItem) -> [Item] {
        guard let belongs = predicate(for: place) else { return [] }
        return allItems.filter(belongs)
    }

    func count(in place: SidebarItem) -> Int {
        let items = allItems
        let counts = itemCounts.flatMap { $0.stamp == contentStamp ? $0 : nil } ?? ItemCounts(items, stamp: contentStamp)
        itemCounts = counts
        switch place {
        case .inbox: return counts.inbox
        case .allNotes: return counts.active
        case .favorites: return counts.favorites
        case .files: return counts.files
        case .recentlyDeleted: return counts.trashed
        case .folder(let id): return counts.containers[ContainerID(id), default: 0]
        case .itemType(let type): return counts.types[TypeID(type), default: 0]
        case .favoriteItem, .project:
            guard let belongs = predicate(for: place) else { return 0 }
            return items.reduce(0) { belongs($1) ? $0 + 1 : $0 }
        }
    }

    /// Search covers every item that has not been deleted, whichever sidebar item is selected: a note by its
    /// title and text, a file by its name.
    func items(matching query: String) -> [Item] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var found: Set<ItemID> = []
        for note in notes where !note.isDeleted
            && (note.body.range(of: query, options: options) != nil || note.title.range(of: query, options: options) != nil) {
            found.insert(note.id)
        }
        for file in files where file.title.range(of: query, options: options) != nil {
            found.insert(file.id)
        }
        return allItems.filter { found.contains($0.id) }
    }

    /// A note's text for the editor, with the version it is at. A file has none.
    func body(of id: ItemID) -> ItemBody? {
        note(id).map { ItemBody(id: $0.id, text: $0.body, version: ItemVersion($0.revision)) }
    }

    /// The folder an item is in; nil for one in the Inbox.
    func folder(of item: Item) -> Folder? {
        item.container.flatMap { container in folders.first { $0.id.rawValue == container.rawValue } }
    }

    /// Where a note's relative links start: the directory its file is in.
    func imageBase(of id: ItemID) -> String? {
        note(id)?.directory
    }

    /// The item's file, relative to the notes folder.
    func path(of id: ItemID) -> String? {
        note(id)?.path ?? files.first { $0.id == id }?.path
    }

    /// The name Rename Note offers: the note's file name without its extension.
    func fileName(of id: ItemID) -> String? {
        note(id)?.fileTitle
    }

    func fileURL(for id: ItemID) -> URL? {
        guard let file = files.first(where: { $0.id == id }) else { return nil }
        return store?.fileURL(for: file.path)
    }

    /// A file in the folder is always at hand.
    func fileURL(of id: ItemID) async throws -> URL? { fileURL(for: id) }

    var folderURL: URL? { (store as? FolderStore)?.root }

    private func predicate(for place: SidebarItem) -> ((Item) -> Bool)? {
        switch place {
        case .inbox: return { $0.state == .active && $0.container == nil }
        case .allNotes: return { $0.state == .active }
        case .favorites: return { $0.state == .active && $0.isFavorite }
        case .favoriteItem(let id): return { $0.id == id && $0.state == .active && $0.isFavorite }
        case .folder(let id):
            let container = ContainerID(id)
            return { $0.state == .active && $0.container == container }
        case .recentlyDeleted: return { $0.state == .trashed }
        case .files: return { $0.state == .active && $0.isFile }
        case .itemType(let type):
            let type = TypeID(type)
            return { $0.state == .active && $0.type == type }
        case .project(let id):
            let members = projectDescendants(id).union([id])
            return { $0.state == .active && members.contains($0.id) }
        }
    }

    private func projectDescendants(_ id: ItemID) -> Set<ItemID> {
        let edges = connectionIndex.edges.filter { $0.name == "parent-of" }
        var result: Set<ItemID> = []
        var pending = [id]
        while let current = pending.popLast() {
            for edge in edges where edge.sourceID == current && !result.contains(edge.targetID) && edge.targetID != id {
                result.insert(edge.targetID)
                pending.append(edge.targetID)
            }
        }
        return result
    }

    // MARK: Making items

    private var collection: ItemCollection {
        // Read on every call, so a view stays subscribed to the notes and files whether or not the cache answers.
        let notes = self.notes
        let files = self.files
        let index = connectionIndex
        let generation = connections?.generation ?? 0
        if let itemCollection, itemCollection.stamp == contentStamp, itemCollection.connectionGeneration == generation {
            return itemCollection
        }
        // An item is its note's or file's revision made once: one still at its place in the last collection is
        // taken from there, and one that moved is found by its identifier, so an edit makes only its own item.
        let previous = itemCollection.flatMap { $0.connectionGeneration == generation ? $0 : nil }
        var sameLayout = previous?.items.count == notes.count + files.count
        var items: [Item] = []
        items.reserveCapacity(notes.count + files.count)
        func take(_ id: ItemID, _ revision: Int64, make: () -> Item) {
            let offset = items.count
            if let previous, offset < previous.items.count, previous.items[offset].id == id {
                if previous.items[offset].version.rawValue == revision {
                    items.append(previous.items[offset])
                    return
                }
            } else {
                sameLayout = false
            }
            if let entry = cachedItems[id], entry.revision == revision, entry.connectionGeneration == generation {
                items.append(entry.item)
                return
            }
            let item = make()
            cachedItems[id] = CachedItem(revision: revision, connectionGeneration: generation, item: item)
            items.append(item)
        }
        for note in notes { take(note.id, note.revision) { makeItem(note, index: index) } }
        for file in files { take(file.id, file.revision) { makeItem(file) } }
        let positions: [ItemID: Int]
        if sameLayout, let previous {
            positions = previous.positions
        } else {
            var unique: [Item] = []
            var found: [ItemID: Int] = [:]
            for item in items where found[item.id] == nil {
                found[item.id] = unique.count
                unique.append(item)
            }
            items = unique
            positions = found
            if cachedItems.count > items.count { cachedItems = cachedItems.filter { positions[$0.key] != nil } }
        }
        let collection = ItemCollection(stamp: contentStamp, connectionGeneration: generation, items: items, positions: positions)
        itemCollection = collection
        return collection
    }

    private func makeItem(_ note: Note, index: NoteConnectionIndex) -> Item {
        let projection = itemProjection(note)
        let type = TypeID(projection.declaredType ?? "core.note")
        var fields = projection.fields ?? [:]
        // The item carries its type itself. The tags field stays as written, since Marfa may not read it, and
        // its order and spelling are the person's.
        fields["type"] = nil
        let problem: ItemProblem? = if case .invalid(let error) = projection.frontMatter {
            ItemProblem(message: error.message)
        } else {
            nil
        }
        return Item(
            // A note following its first line goes by the line as it is typed, as the list always showed it;
            // references resolve against the projection's title, which takes the line once the note is left.
            id: note.id, type: type, title: note.followsFirstLine ? note.title : projection.title,
            titleRule: note.file.title != nil ? .property("title") : .firstLine,
            properties: catalogue.ordered(fields, for: type), preview: note.preview, content: .markdown,
            state: note.isDeleted ? .trashed : .active, tier: .library, container: note.folderID.map(ContainerID.init),
            tags: Set(note.file.tags ?? []), version: ItemVersion(note.revision), created: note.created,
            modified: note.modified, trashed: note.deleted, edgesOut: Self.edges(of: note.id, in: index), problem: problem)
    }

    private func makeItem(_ file: AppFile) -> Item {
        let type = file.isImage ? WorkbenchSchema.imageType : file.isPDF ? WorkbenchSchema.pdfType : WorkbenchSchema.fileType
        return Item(
            id: file.id, type: type, title: file.title, titleRule: .firstLine,
            content: .file(file.contentType, byteCount: file.stored.byteCount), container: file.folderID.map(ContainerID.init),
            version: ItemVersion(file.revision), created: file.stored.created, modified: file.stored.modified)
    }

    /// Each reference the item makes, held as it writes it: a front matter field under its own name, a link in
    /// the text as Marfa's folder device records one.
    private static func edges(of id: ItemID, in index: NoteConnectionIndex) -> [Edge] {
        (index.referencesBySource[id] ?? []).enumerated().map { offset, reference in
            let target: EdgeTarget = switch reference.resolution {
            case .resolved(let target): .item(target)
            case .missing: .unresolved(spelling: reference.targetTitle, ambiguous: false)
            case .ambiguous: .unresolved(spelling: reference.targetTitle, ambiguous: true)
            // A folder resolves every name at once; only a server's lookup waits or is refused.
            case .pending, .refused: .unresolved(spelling: reference.targetTitle, ambiguous: false)
            }
            let (type, origin): (String, EdgeOrigin) = switch reference.origin {
            case .body: (MarfaMapping.bodyLinkEdge, .body)
            case .header(let field): (field, .property(field))
            }
            return Edge(id: EdgeID("\(id.rawValue)/\(offset)"), type: type, source: id, target: target, origin: origin)
        }
    }

    func itemProjection(_ note: Note) -> NoteProjection {
        if let cached = cachedItemProjections[note.id], cached.revision == note.revision { return cached.projection }
        let projection = NoteProjection(note: note)
        cachedItemProjections[note.id] = (note.revision, projection)
        return projection
    }

    // MARK: Connections

    /// References resolve by names, so the index is made again only when a name, a front matter field or a line
    /// holding a reference changes, or an item comes or goes; typing elsewhere in a note leaves it as it was.
    var connectionIndex: NoteConnectionIndex {
        let notes = self.notes
        let files = self.files
        if let connections, connections.stamp == contentStamp { return connections.index }
        if var current = connections, let keys = unchangedKeys(current.keys, notes: notes, files: files) {
            current.keys = keys
            current.stamp = contentStamp
            connections = current
            return current.index
        }
        var keys: [ItemID: (revision: Int64, key: Connections.Key)] = [:]
        for note in notes where !note.isDeleted { keys[note.id] = (note.revision, key(of: note)) }
        for file in files { keys[file.id] = (file.revision, Self.key(of: file)) }
        let index = NoteConnectionIndex(records: connectionRecords(), rulesByType: WorkbenchSchema.rulesByType)
        connections = Connections(index: index, generation: (connections?.generation ?? 0) + 1, stamp: contentStamp, keys: keys)
        return index
    }

    /// The records the index is made from: every note not deleted, and every file by its name.
    func connectionRecords() -> [NoteProjection] {
        notes.filter { !$0.isDeleted }.map(itemProjection)
            + files.map { NoteProjection(id: $0.id, file: NoteFile(text: ""), fallbackTitle: $0.title, filePath: $0.path) }
    }

    /// The keys brought up to date, or nil when a change could alter what the index holds.
    private func unchangedKeys(
        _ keys: [ItemID: (revision: Int64, key: Connections.Key)], notes: [Note], files: [AppFile]
    ) -> [ItemID: (revision: Int64, key: Connections.Key)]? {
        var keys = keys
        var records = 0
        for note in notes where !note.isDeleted {
            records += 1
            guard let held = keys[note.id] else { return nil }
            guard held.revision != note.revision else { continue }
            let current = key(of: note)
            guard current == held.key else { return nil }
            keys[note.id] = (note.revision, current)
        }
        for file in files {
            records += 1
            guard let held = keys[file.id] else { return nil }
            guard held.revision != file.revision else { continue }
            let key = Self.key(of: file)
            guard key == held.key else { return nil }
            keys[file.id] = (file.revision, key)
        }
        return records == keys.count ? keys : nil
    }

    /// The title is the one the index names the note by, so a line typed under a `title` property remakes nothing.
    private func key(of note: Note) -> Connections.Key {
        Connections.Key(
            title: itemProjection(note).title, path: note.path, frontMatter: note.file.frontMatter,
            referenceLines: NoteConnectionIndex.referenceLines(in: note.body))
    }

    private static func key(of file: AppFile) -> Connections.Key {
        Connections.Key(title: file.title, path: file.path, frontMatter: "", referenceLines: [])
    }
}

nonisolated extension Item {
    /// Whether its properties and relationships can be changed. Files mode writes only to notes; a file, a deleted
    /// note or front matter that does not parse is read only.
    var isEditable: Bool { state == .active && problem == nil && !isFile }

    /// Whether its text can be written in: front matter that does not parse leaves the text as writable as ever, but
    /// text the library could not read is not shown, so nothing typed over the empty page is written.
    var isWritable: Bool { state == .active && !isFile && problem?.withholdsText != true }

    var isFile: Bool {
        if case .file = content { true } else { false }
    }

    /// What the library says a file item is, which is nil for a note and `.data` where it does not know.
    var fileType: UTType? {
        if case .file(let type, _) = content { type } else { nil }
    }
}

nonisolated extension ContainerID {
    /// A files library's containers are its folders, known by their identifiers.
    init(_ folder: ItemID) { self.init(folder.rawValue) }
}
