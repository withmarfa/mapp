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

    func items(in place: Place, scope: ListScope, archived: ArchivedItems, includingKinds: Bool) -> [Item] {
        listing(ListingKey(place: place, scope: scope, archived: archived, includingKinds: includingKinds))
    }

    func favoriteItems(in scope: ListScope, archived: ArchivedItems) -> [Item] {
        listing(ListingKey(place: .library, favorites: true, scope: scope, archived: archived, includingKinds: true))
    }

    private func listing(_ key: ListingKey) -> [Item] {
        let content = contentRevision
        let membership = membershipRevision
        if let held = listed[key], held.content == content { return held.items }
        // A collection's order falls back on titles, so it changes with any edit, not only with membership.
        let isCollection: Bool = if case .collection = key.place { true } else { false }
        var listing = listed[key].flatMap { $0.membership == membership && !isCollection ? $0 : nil }
            ?? Listing(membership: membership, ids: listingOrder(of: key))
        listing.content = content
        listing.items = listing.ids.compactMap { records[$0]?.item }
        listed[key] = listing
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

    func count(in place: Place, scope: ListScope) -> Int {
        switch place {
        case .library: scopeCounts(in: place).library
        case .feed: scopeCounts(in: place).feed
        case .collections: standaloneCounts.collections
        case .sources: listedSourceCount
        default: scopeCounts(in: place).count(in: scope)
        }
    }

    /// How many sources the Sources page lists: the server's that hold items once it has answered, else those of the
    /// items loaded (`SourceDirectory.listing`).
    private var listedSourceCount: Int {
        let held = sources.counts ?? standaloneCounts.bySource.mapValues(\.all)
        return held.filter { !$0.key.isEmpty && $0.value > 0 }.count
    }

    /// What `place` lists in each tier: its active items, or the Archive's archived ones, as its listing has them.
    func scopeCounts(in place: Place) -> ScopeCounts {
        let revision = membershipRevision
        if let held = counted[place], held.revision == revision { return held.counts }
        let alone = standaloneCounts
        let counts: ScopeCounts = switch place {
        case .library, .feed: alone.active
        case .archive: alone.archived
        case .types, .collections, .sources: ScopeCounts(library: 0, feed: 0)
        case .type(let type): kinds(of: type).reduce(ScopeCounts(library: 0, feed: 0)) { $0 + (alone.byType[$1] ?? .zero) }
        case .source(let code): alone.bySource[code] ?? .zero
        case .collection:
            ScopeCounts(
                library: members(of: ListingKey(place: place, scope: .library, archived: .hidden, includingKinds: true)).count,
                feed: members(of: ListingKey(place: place, scope: .feed, archived: .hidden, includingKinds: true)).count)
        }
        counted[place] = (revision, counts)
        return counts
    }

    /// Counts by tier and state, with attached files removed once per membership revision.
    private var standaloneCounts: StandaloneCounts {
        let revision = membershipRevision
        if let held = countedAlone, held.revision == revision { return held.counts }
        func counts(_ split: MarfaItemIndex.Split, _ archived: ArchivedItems = .hidden) -> ScopeCounts {
            ScopeCounts(library: split.count(in: .library, archived), feed: split.count(in: .feed, archived))
        }
        var alone = StandaloneCounts(
            active: counts(index.listed), archived: counts(index.listed, .only),
            byType: index.byType.mapValues { counts($0) }, bySource: index.bySource.mapValues { counts($0) },
            collections: catalogue.collectionTypes.reduce(0) { $0 + index.active(ofType: $1).count })
        for id in index.attachedToHeld() {
            guard let item = records[id]?.item else { continue }
            switch item.state {
            case .archived: alone.archived.take(item.tier)
            case .active:
                alone.active.take(item.tier)
                alone.byType[item.type]?.take(item.tier)
                if let source = item.source { alone.bySource[source]?.take(item.tier) }
            case .trashed: break
            }
        }
        countedAlone = (revision, alone)
        return alone
    }

    private func kinds(of type: TypeID, including: Bool = true) -> [TypeID] {
        including ? [type] + catalogue.descendants(of: type) : [type]
    }

    private func listingOrder(of key: ListingKey) -> [ItemID] {
        let found = members(of: key).compactMap { records[$0]?.item }
        if case .collection(let id) = key.place, !key.favorites { return membersInOrder(of: id, among: found) }
        return Self.ordered(found).map(\.id)
    }

    /// Newest first, as the source paints them; the views sort as the person chose.
    static func ordered(_ items: [Item]) -> [Item] {
        items.sorted { $0.created != $1.created ? $0.created > $1.created : $0.id.rawValue < $1.id.rawValue }
    }

    /// A file attached to an item the library holds appears on that item's page. A file whose parent is missing still
    /// appears in places so it can be found. Search includes both.
    private func members(of key: ListingKey) -> Set<ItemID> {
        if key.favorites {
            return index.standalone(index.favorites.filter { index.listed.contains($0, in: key.scope, key.archived) })
        }
        switch key.place {
        case .library: return index.standalone(index.listed.ids(in: .library, key.archived))
        case .feed: return index.standalone(index.listed.ids(in: .feed, key.archived))
        case .archive: return index.standalone(index.listed.ids(in: .all, .only))
        case .types, .sources, .collections: return []
        case .source(let code): return index.standalone(index.bySource[code]?.ids(in: key.scope, key.archived) ?? [])
        case .type(let type):
            return index.standalone(kinds(of: type, including: key.includingKinds).reduce(into: Set<ItemID>()) { found, type in
                found.formUnion(index.byType[type]?.ids(in: key.scope, key.archived) ?? [])
            })
        // The items filed in the collection through `in-collection`.
        case .collection(let id):
            return index.standalone(Set(index.links(to: id, type: MarfaMapping.collectionEdge).map(\.from)).filter {
                index.listed.contains($0, in: key.scope, key.archived)
            })
        }
    }

    func name(of place: Place) -> String {
        switch place {
        case .library: String(localized: "Library")
        case .feed: String(localized: "Feed")
        case .types: String(localized: "Types")
        case .sources: String(localized: "Sources")
        case .collections: String(localized: "Collections")
        case .archive: String(localized: "Archive")
        case .source(let code): sources.name(code)
        case .collection(let id): item(id)?.displayTitle ?? ""
        case .type(let type): catalogue.plural(for: type)
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

/// Standalone items by tier: active ones for the library, each type and each source, and archived ones for the Archive.
nonisolated struct StandaloneCounts {
    var active: ScopeCounts
    var archived: ScopeCounts
    var byType: [TypeID: ScopeCounts]
    var bySource: [String: ScopeCounts]
    /// The active collections, which the Collections page lists.
    var collections: Int
}

private nonisolated extension ScopeCounts {
    static let zero = ScopeCounts(library: 0, feed: 0)

    static func + (a: ScopeCounts, b: ScopeCounts) -> ScopeCounts {
        ScopeCounts(library: a.library + b.library, feed: a.feed + b.feed)
    }

    mutating func take(_ tier: Tier) {
        switch tier {
        case .library: library -= 1
        case .feed: feed -= 1
        }
    }
}
