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

    /// One edge for each item not already in the collection, in one undo step. Where the collection orders its
    /// members, the new ones go after the last, in the order given. An item that can't be a member, or can't be
    /// changed, is left out and the person is told how many and why.
    @discardableResult
    func addToCollection(_ ids: Set<ItemID>, _ collection: ItemID, undoManager: UndoManager?) -> Bool {
        let title = String(localized: "Can’t Add to Collection")
        guard let target = item(collection), target.state == .active, catalogue.isCollection(target.type) else {
            notices.tell(title, String(localized: "This collection isn’t in the library."))
            return false
        }
        let planned = collectionPlan(ids, joining: collection)
        var skips = planned.skips
        var joining: [Item] = []
        for member in planned.joining {
            let draft = EdgeDraft(type: MarfaMapping.collectionEdge, source: member.id, target: collection)
            if linkProblem(draft, sourceType: member.type, targetType: target.type) == nil {
                joining.append(member)
            } else {
                skips.skip(.cantJoinCollection)
            }
        }
        tellSkipped(skips, didChange: !joining.isEmpty, failing: title)
        guard !joining.isEmpty else { return skips.isEmpty }
        joining.sort(by: Self.titleOrder)
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

    /// Removes the items' `in-collection` edges to the collection, in one undo step. An undo puts each back at its
    /// position. An item in the collection that can't be changed is left out and the person is told.
    @discardableResult
    func removeFromCollection(_ ids: Set<ItemID>, _ collection: ItemID, undoManager: UndoManager?) -> Bool {
        let title = String(localized: "Can’t Remove from Collection")
        var skips = BatchSkips()
        var drafts: [EdgeDraft] = []
        for id in ids {
            guard let link = index.link(type: MarfaMapping.collectionEdge, source: id, target: collection) else { continue }
            if let reason = item(id)?.writeObstacle {
                skips.skip(reason)
            } else {
                drafts.append(EdgeDraft(type: link.type, source: link.source, target: link.target, position: link.position))
            }
        }
        tellSkipped(skips, didChange: !drafts.isEmpty, failing: title)
        guard !drafts.isEmpty else { return false }
        drafts.sort { $0.source.rawValue < $1.source.rawValue }
        relink(RelationshipChange(removing: drafts), name: String(localized: "Remove from Collection"), failing: title, undoManager: undoManager)
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
