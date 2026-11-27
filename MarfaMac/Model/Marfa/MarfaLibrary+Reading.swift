import Foundation

/// Reading the library: items and their text and places, as the views observe them.
extension MarfaLibrary {
    func holdForOpening(_ id: ItemID) async -> Bool {
        if item(id) != nil { return true }
        do { try await source.pinForOpening(id) } catch { return false }
        return await waitUntilHolding([id], within: AlreadyInMarfa.limit)
    }

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

    /// A file's bytes are named by facts the server sets, which the panel shows as its kind and size.
    func hiddenPropertyKeys(of item: Item) -> Set<String> {
        let keys = catalogue.pageKeys(of: item)
        return item.isFile ? keys.union(MarfaMapping.fileFacts) : keys
    }

    func changedItems(since revision: Int) -> Set<ItemID>? {
        changeLog.changes(since: revision, now: contentRevision)
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

    func favoriteCount(in scope: ListScope) -> Int {
        _ = membershipRevision
        return members(of: ListingKey(place: .library, favorites: true, scope: scope, archived: .hidden, includingKinds: true)).count
    }

    func deferredListing(in place: PlaceView, listing: PlaceListing, preview: LibraryViewQuery?, above limit: Int) -> DeferredListing? {
        if let id = place.savedView { return deferredView(id, preview: preview, above: limit) }
        let key = listingKey(for: place, listing: listing)
        let content = contentRevision
        let membership = membershipRevision
        if let held = listed[key], !held.isProvisional, held.content == content || canPatch(key, since: held.content) { return nil }
        let showsEarlier = listed[key]?.isProvisional == true
        let ids = members(of: key)
        guard ids.count > limit else { return nil }
        let snapshots = index.items
        let positions: [ItemID: Double]?
        if case .collection(let id) = key.place, !key.favorites { positions = self.positions(in: id) }
        else { positions = nil }
        return DeferredListing(make: {
            let items = ids.compactMap { snapshots[$0] }
            if let positions { return Self.orderMembers(items, at: positions) }
            return Self.ordered(items)
        }, take: { [weak self] items in
            guard let self else { return }
            let isOutrun = contentRevision != content || membershipRevision != membership
            // A listing the library outran is kept only where nothing newer is listed and what changed since can
            // patch it, so a place that keeps changing still opens. A collection's order is not the patch's, so it is
            // provisional until a whole listing lands.
            if isOutrun { guard listed[key] == nil, changedItems(since: content) != nil else { return } }
            let isCollection: Bool = if case .collection = key.place { true } else { false }
            listed[key] = Listing(
                membership: membership, content: content, ids: items.map(\.id), items: items, isProvisional: isOutrun && isCollection)
        }, showsEarlier: showsEarlier)
    }

    func listed(_ ids: Set<ItemID>, in place: PlaceView, listing: PlaceListing) -> Set<ItemID> {
        if let view = place.savedView { return listedIDs(ids, inView: view) }
        let key = listingKey(for: place, listing: listing)
        if case .collection = key.place { return ids.intersection(members(of: key)) }
        return Set(ids.filter { isMember($0, of: key) })
    }

    private func listingKey(for place: PlaceView, listing: PlaceListing) -> ListingKey {
        ListingKey(
            place: place.place, favorites: place.view == .favorites, scope: listing.scope, archived: listing.archived,
            includingKinds: place.view == .favorites || listing.includesKinds)
    }

    private func canPatch(_ key: ListingKey, since content: Int) -> Bool {
        if case .collection = key.place { return false }
        return changedItems(since: content) != nil
    }

    private func listing(_ key: ListingKey) -> [Item] {
        let content = contentRevision
        let membership = membershipRevision
        if let held = listed[key], held.content == content { return held.items }
        // A collection's order falls back on titles, so it changes with any edit, not only with membership.
        let isCollection: Bool = if case .collection = key.place { true } else { false }
        if !isCollection || listed[key]?.isProvisional == true, var listing = listed[key], let changed = changedItems(since: listing.content) {
            Cost.measure(.listingPatch) { patch(&listing, of: key, changed: changed, membershipMoved: listing.membership != membership) }
            listing.membership = membership
            listing.content = content
            listed[key] = listing
            return listing.items
        }
        // Where the change history no longer reaches the listing, its order may be out of date too (a creation time
        // changes with no membership move), so it is made whole.
        var listing = Listing(membership: membership, ids: listingOrder(of: key))
        listing.content = content
        listing.items = listing.ids.compactMap { records[$0]?.item }
        listing.positions = nil
        listed[key] = listing
        return listing.items
    }

    /// Brings `listing` up to date with only the `changed` items: each takes its new value where it stays, and, where
    /// membership moved or its creation time changed, leaves or joins in the listing's order (`ordered`), which the others
    /// keep.
    private func patch(_ listing: inout Listing, of key: ListingKey, changed: Set<ItemID>, membershipMoved: Bool) {
        let positions = listing.positions ?? Dictionary(uniqueKeysWithValues: listing.ids.enumerated().map { ($1, $0) })
        // A collection's members are worked out whole, so once for every changed item.
        let collectionMembers: Set<ItemID>? = if case .collection = key.place, membershipMoved { members(of: key) } else { nil }
        var leaving: Set<ItemID> = []
        var joining: [Item] = []
        for id in changed {
            let isMember = membershipMoved ? collectionMembers?.contains(id) ?? isMember(id, of: key) : positions[id] != nil
            if let position = positions[id] {
                guard isMember, let item = records[id]?.item else { leaving.insert(id); continue }
                if item.created == listing.items[position].created {
                    listing.items[position] = item
                } else {
                    // The server can give a queued creation a different timestamp.
                    leaving.insert(id)
                    joining.append(item)
                }
            } else if isMember, let item = records[id]?.item {
                joining.append(item)
            }
        }
        guard !leaving.isEmpty || !joining.isEmpty else {
            listing.positions = positions
            return
        }
        let staying = leaving.isEmpty ? listing.items : listing.items.filter { !leaving.contains($0.id) }
        listing.items = Self.merged(staying, Self.ordered(joining))
        listing.ids = listing.items.map(\.id)
        listing.positions = nil
    }

    /// Two lists each in the listing's order (`ordered`), as one.
    static func merged(_ a: [Item], _ b: [Item]) -> [Item] {
        guard !b.isEmpty else { return a }
        var merged: [Item] = []
        merged.reserveCapacity(a.count + b.count)
        var (i, j) = (0, 0)
        while i < a.count, j < b.count {
            if precedes(b[j], a[i]) { merged.append(b[j]); j += 1 } else { merged.append(a[i]); i += 1 }
        }
        merged.append(contentsOf: a[i...])
        merged.append(contentsOf: b[j...])
        return merged
    }

    private static func precedes(_ a: Item, _ b: Item) -> Bool {
        a.created != b.created ? a.created > b.created : a.id.rawValue < b.id.rawValue
    }

    /// Whether the item is one `members(of:)` lists, asked of one item. A collection's members are worked out whole.
    private func isMember(_ id: ItemID, of key: ListingKey) -> Bool {
        guard records[id] != nil, index.isStandalone(id) else { return false }
        if key.favorites { return index.favorites.contains(id) && index.listed.contains(id, in: key.scope, key.archived) }
        switch key.place {
        case .library: return index.listed.contains(id, in: .library, key.archived)
        case .feed: return index.listed.contains(id, in: .feed, key.archived)
        case .archive: return index.listed.contains(id, in: .all, .only)
        case .types, .sources, .collections: return false
        case .source(let code): return index.bySource[code]?.contains(id, in: key.scope, key.archived) == true
        case .type(let type):
            return kinds(of: type, including: key.includingKinds).contains { index.byType[$0]?.contains(id, in: key.scope, key.archived) == true }
        case .collection: return members(of: key).contains(id)
        }
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
    nonisolated static func ordered(_ items: [Item]) -> [Item] {
        // The keys are read once, and positions sorted rather than items, which are large to move.
        let keys = items.map { (created: $0.created, id: $0.id.rawValue) }
        return items.indices.sorted { a, b in
            keys[a].created != keys[b].created ? keys[a].created > keys[b].created : keys[a].id < keys[b].id
        }.map { items[$0] }
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
