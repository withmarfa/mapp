import Foundation

/// Reading the library: items and their text and places, as the views observe them.
extension MarfaLibrary {
    func item(_ id: ItemID) -> Item? {
        guard let record = records[id] else {
            _ = membershipRevision
            return nil
        }
        return record.isHeld ? record.item : nil
    }

    func headerItem(_ id: ItemID) -> Item? {
        guard let record = records[id] else {
            _ = membershipRevision
            return nil
        }
        guard record.isHeld else { return nil }
        _ = record.headerStamp
        return record.headerSnapshot
    }

    func itemVersion(_ id: ItemID) -> ItemVersion? {
        guard let record = records[id] else {
            _ = membershipRevision
            return nil
        }
        guard record.isHeld else { return nil }
        _ = record.versionStamp
        return record.versionSnapshot
    }

    func textIsEmpty(_ id: ItemID) -> Bool {
        guard let record = records[id] else {
            _ = membershipRevision
            return true
        }
        guard record.isHeld else { return true }
        return record.textIsEmpty
    }

    func bodyText(_ id: ItemID) -> String? {
        guard let record = records[id] else {
            _ = membershipRevision
            return nil
        }
        guard record.isHeld else { return nil }
        // Emptiness and presence, not the text. A keystroke that leaves text in the item changes neither.
        _ = record.hasBody
        _ = record.textIsEmpty
        return record.bodySnapshot?.text
    }

    /// Follows edges that touch `id`, including ones another item holds. An item not held follows membership until it arrives.
    func observeLinks(of id: ItemID) {
        guard let record = records[id] else {
            _ = membershipRevision
            return
        }
        _ = record.linkStamp
    }

    func boundEmbeds(of id: ItemID) -> [BoundEmbed] {
        guard let record = records[id] else {
            _ = membershipRevision
            return []
        }
        guard record.isHeld else { return [] }
        _ = record.embedStamp
        return record.embedSnapshot
    }

    /// A file's bytes are named by facts the server sets, which the inspector shows as its kind and size.
    func hiddenPropertyKeys(of item: Item) -> Set<String> {
        let keys = catalogue.pageKeys(of: item)
        return item.isFile ? keys.union(MarfaMapping.fileFacts) : keys
    }

    /// The items held among `ids`, observed as the lists are, for reads that gather many items at once.
    func heldItems(_ ids: some Sequence<ItemID>) -> [Item] {
        _ = contentRevision
        return ids.compactMap { records[$0]?.item }
    }

    func items(in place: SidebarItem) -> [Item] {
        if case .view(let id) = place { return items(inView: id) }
        let content = contentRevision
        let membership = membershipRevision
        if let held = listed[place], held.content == content { return held.items }
        // Which items are recent, and in what order, changes with any edit, not only with membership; so does a
        // collection's order, which falls back on titles.
        let isCollection: Bool = if case .collection = place { true } else { false }
        var listing = listed[place].flatMap { $0.membership == membership && place != .recents && !isCollection ? $0 : nil }
            ?? Listing(membership: membership, ids: listingOrder(of: place))
        listing.content = content
        listing.items = listing.ids.compactMap { records[$0]?.item }
        listed[place] = listing
        return listing.items
    }

    var deletedItems: [Item] {
        let content = contentRevision
        let membership = membershipRevision
        if let held = listedDeleted, held.content == content { return held.items }
        var listing = listedDeleted.flatMap { $0.membership == membership ? $0 : nil }
            ?? Listing(membership: membership, ids: Self.ordered(index.ids(in: .trashed).compactMap { records[$0]?.item }).map(\.id))
        listing.content = content
        listing.items = listing.ids.compactMap { records[$0]?.item }
        listedDeleted = listing
        return listing.items
    }

    var deletedCount: Int {
        _ = membershipRevision
        return index.ids(in: .trashed).count
    }

    func count(in place: SidebarItem) -> Int {
        if place == .recents { return min(index.ids(in: .active).count, Self.recentLimit) }
        if case .view = place { return items(in: place).count }
        let revision = membershipRevision
        if let held = counted[place], held.revision == revision { return held.count }
        let count = members(of: place).count
        counted[place] = (revision, count)
        return count
    }

    private func listingOrder(of place: SidebarItem) -> [ItemID] {
        switch place {
        case .recents: Self.recent(index.ids(in: .active).compactMap { records[$0]?.item }).map(\.id)
        case .collection(let id): membersInOrder(of: id, among: members(of: place).compactMap { records[$0]?.item })
        default: Self.ordered(members(of: place).compactMap { records[$0]?.item }).map(\.id)
        }
    }

    /// Newest first, as the source paints them; the views sort as the person chose.
    static func ordered(_ items: [Item]) -> [Item] {
        items.sorted { $0.created != $1.created ? $0.created > $1.created : $0.id.rawValue < $1.id.rawValue }
    }

    /// The Inbox is the feed tier. All Items is every active item in either tier. Both, a source's place and a type's
    /// place leave out a file attached to another item the library holds, which shows on that item's page instead; a
    /// file with no parent, or whose parent is not held, still shows, whoever added it (Marfa holds no other mark of
    /// one the person added), and Files and search list every file. Favorites stay unfiltered. A type's place holds that type's own items and no subtype's, so the sidebar's count is the list's length.
    private func members(of place: SidebarItem) -> Set<ItemID> {
        switch place {
        case .inbox: return index.standalone(index.feed)
        case .allItems: return index.standalone(index.ids(in: .active))
        case .sources, .collections: return []
        case .source(let name):
            return index.standalone(Set(index.ids(in: .active).filter { records[$0]?.item.source == name }))
        // Listed in its own order by `items(in:)` and counted by its limit, so never read here.
        case .recents: return []
        // Read from the copy by `items(inView:)`, so never read here.
        case .view: return []
        case .favorites: return index.favorites
        case .favoriteItem(let id): return index.favorites.contains(id) ? [id] : []
        case .itemType(let type): return index.standalone(index.activeByType[TypeID(type)] ?? [])
        case .files: return active(withSubtypesOf: MarfaMapping.fileType)
        // The active items filed in the collection through `in-collection`.
        case .collection(let id):
            return Set(index.links(to: id, type: MarfaMapping.collectionEdge).map(\.from)).intersection(index.ids(in: .active))
        }
    }

    private func active(withSubtypesOf type: TypeID) -> Set<ItemID> {
        catalogue.descendants(of: type).union([type]).reduce(into: Set<ItemID>()) { found, type in
            found.formUnion(index.activeByType[type] ?? [])
        }
    }

    func name(of place: SidebarItem) -> String {
        switch place {
        case .inbox: String(localized: "Inbox")
        case .recents: String(localized: "Recents")
        case .allItems: String(localized: "Items")
        case .sources: String(localized: "Sources")
        case .collections: String(localized: "Collections")
        case .source(let code): sources.name(code)
        case .favorites: String(localized: "Favorites")
        case .favoriteItem(let id), .collection(let id): item(id)?.displayTitle ?? ""
        case .itemType(let type): catalogue.plural(for: TypeID(type))
        case .files: String(localized: "Files")
        case .view(let id): views.first { $0.id == id }?.title ?? ""
        }
    }

    func isGone(_ id: ItemID?) -> Bool {
        isLoaded && id.flatMap { item($0) } == nil
    }

    func idsForWindows(_ ids: some Collection<ItemID>) -> [ItemID] {
        ids.filter { item($0) != nil }
    }

    func body(of id: ItemID) -> ItemBody? {
        guard let record = records[id] else {
            _ = membershipRevision
            return nil
        }
        return record.isHeld ? record.body : nil
    }
}
