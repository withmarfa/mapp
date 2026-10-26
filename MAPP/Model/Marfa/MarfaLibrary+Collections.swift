import Foundation

/// Collections are Marfa's: an item whose type plays the `container` role, holding its members through
/// `in-collection` edges from each member. Collections are flat, so a collection is never a member of another.
extension MarfaLibrary {
    var collections: [Item] {
        let ids = catalogue.collectionTypes.reduce(into: Set<ItemID>()) { found, type in
            found.formUnion(index.activeByType[type] ?? [])
        }
        return Self.byTitle(heldItems(ids))
    }

    /// The members of a collection in the order Marfa keeps for them: by each edge's `position` where it has one,
    /// then the rest by title.
    func membersInOrder(of collection: ItemID, among members: [Item]) -> [ItemID] {
        let positions = positions(in: collection)
        return members.sorted { a, b in
            switch (positions[a.id], positions[b.id]) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return Self.titleOrder(a, b)
            }
        }.map(\.id)
    }

    private func positions(in collection: ItemID) -> [ItemID: Double] {
        index.links(to: collection, type: MarfaMapping.collectionEdge).reduce(into: [:]) { positions, link in
            guard let position = link.position else { return }
            positions[link.source] = min(positions[link.source] ?? position, position)
        }
    }

    /// One edge for each item not already in the collection. Where the collection orders its members, the new ones
    /// go after the last, in the order given. Nothing is written when any item can't be a member, and the person is
    /// told why.
    @discardableResult
    func addToCollection(_ ids: Set<ItemID>, _ collection: ItemID, undoManager: UndoManager?) -> Bool {
        let title = String(localized: "Can’t Add to Collection")
        guard let target = item(collection), target.state == .active, catalogue.isCollection(target.type) else {
            notices.tell(title, String(localized: "This collection isn’t in the library."))
            return false
        }
        let joining = ids.compactMap { item($0) }.filter { !$0.collectionIDs.contains(collection) }.sorted(by: Self.titleOrder)
        for member in joining {
            let draft = EdgeDraft(type: MarfaMapping.collectionEdge, source: member.id, target: collection)
            let type: TypeID? = member.state == .active && member.problem == nil ? member.type : nil
            if let problem = linkProblem(draft, sourceType: type, targetType: target.type) {
                notices.tell(title, problem)
                return false
            }
        }
        guard !joining.isEmpty else { return true }
        let last = positions(in: collection).values.max()
        let drafts = joining.enumerated().map { offset, member in
            EdgeDraft(
                type: MarfaMapping.collectionEdge, source: member.id, target: collection,
                position: last.map { $0 + Double(offset + 1) })
        }
        relink(
            RelationshipChange(adding: drafts), name: String(localized: "Add to Collection"), failing: title,
            undoManager: undoManager)
        return true
    }

    /// Removes the items' `in-collection` edges to the collection. An undo puts each back at its position.
    @discardableResult
    func removeFromCollection(_ ids: Set<ItemID>, _ collection: ItemID, undoManager: UndoManager?) -> Bool {
        let drafts = ids.compactMap { index.link(type: MarfaMapping.collectionEdge, source: $0, target: collection) }
            .map { EdgeDraft(type: $0.type, source: $0.source, target: $0.target, position: $0.position) }
            .sorted { $0.source.rawValue < $1.source.rawValue }
        guard !drafts.isEmpty else { return false }
        relink(
            RelationshipChange(removing: drafts), name: String(localized: "Remove from Collection"),
            failing: String(localized: "Can’t Remove from Collection"), undoManager: undoManager)
        return true
    }

    private static func byTitle(_ items: [Item]) -> [Item] {
        items.sorted(by: titleOrder)
    }

    nonisolated private static func titleOrder(_ a: Item, _ b: Item) -> Bool {
        let order = a.title.localizedStandardCompare(b.title)
        return order == .orderedSame ? a.id.rawValue < b.id.rawValue : order == .orderedAscending
    }
}
