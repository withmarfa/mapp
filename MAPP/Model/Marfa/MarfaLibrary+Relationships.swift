import Foundation

/// Relationships are Marfa's edges. An item's own fields are the edges it holds, named as its end writes them,
/// such as `child-of` for the parent a child holds; its inverse fields, `inverse:` and the edge type, are the
/// edges other items hold that point at it, such as a parent's children. What an item's text links or embeds is
/// written as edges by the package, as the text is saved: a link is a `references` edge, which the item it names
/// shows as linked from, and an embedded file is an `attached-to` edge from the file to the item.
extension MarfaLibrary {
    static let inversePrefix = "inverse:"
    /// The contract refuses an edge that would close a cycle for these types only, and a self-loop for any type.
    static let acyclicEdges: Set<String> = [MarfaMapping.parentEdge, "supersedes"]

    /// A relationship field as one item sees it: the edge type, and whether the item is the edge's target.
    nonisolated struct FieldEnd {
        let info: EdgeTypeInfo
        let atTarget: Bool
        let isInverse: Bool
    }

    func fieldEnd(_ field: String) -> FieldEnd? {
        if field.hasPrefix(Self.inversePrefix) {
            guard let info = catalogue.edgeTypes[String(field.dropFirst(Self.inversePrefix.count))] else { return nil }
            return FieldEnd(info: info, atTarget: info.writtenAt == .source, isInverse: true)
        }
        guard let (info, isReverse) = catalogue.edgeType(named: field) else { return nil }
        return FieldEnd(info: info, atTarget: isReverse || info.writtenAt == .target, isInverse: false)
    }

    /// The edge `id` would hold, or be pointed at by, with `other` at the far end.
    private func draft(_ id: ItemID, _ other: ItemID, _ end: FieldEnd) -> EdgeDraft {
        end.atTarget
            ? EdgeDraft(type: end.info.id, source: other, target: id)
            : EdgeDraft(type: end.info.id, source: id, target: other)
    }

    private func others(of id: ItemID, _ end: FieldEnd) -> [ItemID] {
        held(by: id, end).map { end.atTarget ? $0.source : $0.target }
    }

    /// What one end of an edge type allows: the types named, with their subtypes, and the types that play a
    /// role named. An end naming neither allows any type.
    nonisolated struct EndConstraint {
        let types: Set<TypeID>
        let roles: Set<String>

        var allowsAny: Bool { types.isEmpty && roles.isEmpty }

        /// Only the server's own bookkeeping, such as its folders, which the copy never holds.
        var isServers: Bool { roles.isEmpty && !types.isEmpty && types.allSatisfy { $0.rawValue.hasPrefix("system.") } }
    }

    private func constraint(of info: EdgeTypeInfo, atTarget: Bool) -> EndConstraint {
        atTarget
            ? EndConstraint(types: info.targetTypes, roles: info.targetRoles)
            : EndConstraint(types: info.sourceTypes, roles: info.sourceRoles)
    }

    private func admits(_ type: TypeID, _ end: EndConstraint) -> Bool {
        end.allowsAny || end.types.contains(type) || catalogue.isSubtype(type, ofAnyOf: end.types)
            || !end.roles.isDisjoint(with: catalogue.itemTypes[type]?.roles ?? [])
    }

    /// Nil where the server would take the edge as far as the copy can tell; otherwise why not, in the person's
    /// words. Cardinality is the caller's, since it depends on what is replaced.
    func linkProblem(_ draft: EdgeDraft, sourceType: TypeID?, targetType: TypeID?) -> String? {
        guard draft.source != draft.target else { return String(localized: "An item can’t be linked to itself.") }
        guard let sourceType, let targetType else { return String(localized: "This item isn’t in the library.") }
        guard let info = catalogue.edgeTypes[draft.type] else { return nil }
        guard admits(sourceType, constraint(of: info, atTarget: false)), admits(targetType, constraint(of: info, atTarget: true))
        else {
            return String(localized: "This kind of item can’t be linked here.")
        }
        if Self.acyclicEdges.contains(info.id), index.reachable(from: draft.target, type: info.id).contains(draft.source) {
            return String(localized: "This would link the item back to itself through the items between them.")
        }
        return nil
    }

    // MARK: Reading

    /// The fields an item of `type` can hold, each named as its end writes it: body links are the text's, shown
    /// as mentions, and an edge whose far end can only be the server's own bookkeeping is never shown.
    private func ownFields(of type: TypeID) -> [(name: String, end: FieldEnd)] {
        catalogue.edgeTypes.values.compactMap { info -> (String, FieldEnd)? in
            guard info.id != MarfaMapping.bodyLinkEdge else { return nil }
            let atTarget = info.writtenAt == .target
            let far = constraint(of: info, atTarget: !atTarget)
            guard admits(type, constraint(of: info, atTarget: atTarget)), !far.isServers else { return nil }
            let name = atTarget ? info.reverseName ?? info.id : info.id
            return (name, FieldEnd(info: info, atTarget: atTarget, isInverse: false))
        }
    }

    /// The name Marfa gives the end of the link this field is: the edge type's `label` on its source end and its
    /// `reverseLabel` on its target end.
    private func label(_ end: FieldEnd) -> String {
        end.info.label(atTarget: end.atTarget)
    }

    private func target(_ id: ItemID) -> ItemRelationshipTarget {
        ItemRelationshipTarget(title: item(id)?.title ?? "", itemID: id, resolution: .resolved(id))
    }

    func relationships(for id: ItemID) -> [ItemRelationship] {
        guard let item = item(id) else { return [] }
        // Another item's edge can point here, so every item's change is watched.
        _ = heldItems([])
        var fields = ownFields(of: item.type)
        for edge in item.edgesOut where edge.origin != .body && !fields.contains(where: { $0.name == edge.type }) {
            if let end = fieldEnd(edge.type) { fields.append((edge.type, end)) }
        }
        var results = fields.map { name, end in
            ItemRelationship(
                field: name, label: label(end), targets: others(of: id, end).map(target),
                isEditable: item.isEditable, allowsMultiple: end.info.cardinality == .many)
        }
        let pointing = index.links(touching: id).filter { $0.holder != id }
        for type in Set(pointing.map(\.type)) {
            guard let end = fieldEnd(Self.inversePrefix + type) else { continue }
            let holders = pointing.filter { $0.type == type }.map { $0.holder }
            let targets = holders.filter { self.item($0) != nil }.map(target)
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            // A two-way relation reads the same from both items, so the links pointing here join the ones this item
            // holds in a single list.
            if end.info.isTwoWay, let own = fields.firstIndex(where: { !$0.end.isInverse && $0.end.info.id == type }) {
                let held = results[own]
                results[own] = ItemRelationship(
                    field: held.field, label: held.label,
                    targets: held.targets + targets.filter { incoming in !held.targets.contains { $0.id == incoming.id } },
                    isEditable: held.isEditable, allowsMultiple: held.allowsMultiple)
                continue
            }
            // The text that links an item is the linking item's to change, not a relationship of this one.
            results.append(ItemRelationship(
                field: Self.inversePrefix + type, label: label(end), targets: targets,
                isEditable: item.isEditable && type != MarfaMapping.bodyLinkEdge,
                allowsMultiple: end.info.reverseCardinality == .many))
        }
        return results.sorted { lhs, rhs in
            lhs.field.hasPrefix(Self.inversePrefix) != rhs.field.hasPrefix(Self.inversePrefix)
                ? !lhs.field.hasPrefix(Self.inversePrefix)
                : lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
        }
    }

    /// Active items the field could link to: of a type its far end allows, and none that would close a cycle.
    func relationshipCandidates(for id: ItemID, field: String) -> [Item] {
        guard let item = item(id), let end = fieldEnd(field) else { return [] }
        let far = constraint(of: end.info, atTarget: !end.atTarget)
        guard admits(item.type, constraint(of: end.info, atTarget: end.atTarget)) else { return [] }
        let loops: Set<ItemID> = Self.acyclicEdges.contains(end.info.id)
            ? (end.atTarget ? index.reachable(from: id, type: end.info.id) : index.reaching(id, type: end.info.id))
            : []
        return heldItems(index.ids(in: .active))
            .filter { $0.id != id && !loops.contains($0.id) && admits($0.type, far) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func bodyMentions(for id: ItemID) -> [ItemRelationshipTarget] {
        guard let item = item(id) else { return [] }
        return item.edgesOut.filter { $0.origin == .body }.map { edge in
            switch edge.target {
            case .item(let other): target(other)
            case .unresolved(let spelling, let ambiguous):
                ItemRelationshipTarget(title: spelling, itemID: nil, resolution: ambiguous ? .ambiguous([]) : .missing)
            case .pending(let spelling):
                ItemRelationshipTarget(title: spelling, itemID: nil, resolution: .pending)
            case .refused(let spelling, let reason):
                ItemRelationshipTarget(title: spelling, itemID: nil, resolution: .refused(reason))
            }
        }
    }

    func creationParentCandidates(typeID: String) -> [Item] {
        guard let info = catalogue.edgeTypes[MarfaMapping.parentEdge],
            admits(TypeID(typeID), constraint(of: info, atTarget: true))
        else { return [] }
        let parents = constraint(of: info, atTarget: false)
        return heldItems(index.ids(in: .active))
            .filter { admits($0.type, parents) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    // MARK: Writing

    /// What one change to a field does to the edges, each as one write.
    nonisolated struct RelationshipChange {
        /// One end of an edge replaced by another item, which the edge keeps its id and properties through.
        struct Move {
            let edge: EdgeID
            let end: EdgeTypeInfo.End
            let to: ItemID
            let from: ItemID
        }

        var adding: [EdgeDraft] = []
        var removing: [EdgeDraft] = []
        var moving: [Move] = []

        var isEmpty: Bool { adding.isEmpty && removing.isEmpty && moving.isEmpty }

        /// The change that puts everything back.
        var reversed: RelationshipChange {
            RelationshipChange(
                adding: removing, removing: adding,
                moving: moving.map { Move(edge: $0.edge, end: $0.end, to: $0.from, from: $0.to) })
        }
    }

    /// The edges of the field's type that `id` holds at the end `end` names.
    private func held(by id: ItemID, _ end: FieldEnd) -> [MarfaItemIndex.Link] {
        index.links(touching: id).filter { $0.type == end.info.id && (end.atTarget ? $0.target == id : $0.source == id) }
    }

    /// Makes the field link `id` to exactly `targetIDs`. A link is added where its ends have room and removed freely.
    /// An end that holds one link of its type has it replaced by moving the edge's other end (`edges/move-target`,
    /// `edges/move-source`), so a new parent is one write and the child never holds none or two (`edges/move-no-gap`):
    /// a replacement is a move, and so is taking an item whose own link points elsewhere, as a child chosen under a
    /// project. A link a third item holds as its own is never taken from it. A change the contract would refuse is told
    /// here and sent nowhere.
    @discardableResult
    func setItemRelationship(_ id: ItemID, field: String, targetIDs: [ItemID], undoManager: UndoManager?) -> Bool {
        guard let item = item(id), item.isEditable, let end = fieldEnd(field), Set(targetIDs).count == targetIDs.count
        else { return false }
        let cantChange = String(localized: "Can’t Change This Relationship")
        guard end.info.id != MarfaMapping.bodyLinkEdge else {
            failure = (cantChange, String(localized: "A link is changed in the text that holds it."))
            return false
        }
        let holds = end.info.cardinality(atTarget: end.atTarget)
        if holds == .one, targetIDs.count > 1 {
            failure = (cantChange, String(localized: "Only one item can be chosen here."))
            return false
        }
        let farEnd = FieldEnd(info: end.info, atTarget: !end.atTarget, isInverse: !end.isInverse)
        // A two-way relation is one list of the links this item holds and the ones pointing at it.
        let own = others(of: id, end)
        let incoming = !end.isInverse && end.info.isTwoWay ? others(of: id, farEnd) : []
        let current = own + incoming.filter { !own.contains($0) }
        let adding = targetIDs.filter { !current.contains($0) }
        let removing = current.filter { !targetIDs.contains($0) }
        var change = RelationshipChange(removing: removing.flatMap { other in
            (own.contains(other) ? [draft(id, other, end)] : []) + (incoming.contains(other) ? [draft(id, other, farEnd)] : [])
        })
        let farHolds = end.info.cardinality(atTarget: !end.atTarget)
        // Replacing this item's own link moves the far end; taking another item's link moves this item's end.
        let farIsTarget = !end.atTarget
        let replacingOwn = holds == .one && !removing.isEmpty && !adding.isEmpty
        for other in adding {
            let link = draft(id, other, end)
            let farType: TypeID? = self.item(other).flatMap { $0.state == .trashed ? nil : $0.type }
            let sourceType: TypeID? = end.atTarget ? farType : item.type
            let targetType: TypeID? = end.atTarget ? item.type : farType
            if let problem = linkProblem(link, sourceType: sourceType, targetType: targetType) {
                failure = (cantChange, problem)
                return false
            }
            let taken = farHolds == .one ? held(by: other, farEnd).filter { (farIsTarget ? $0.source : $0.target) != id } : []
            if let theirs = taken.first {
                let old = farIsTarget ? theirs.source : theirs.target
                // The item chosen holds its one link elsewhere. Where that link is its own, as a child's parent is,
                // the move changes it to this one. Where it is the third item's own, the move would take it from an
                // item the person is not looking at, so they are told which item holds it.
                guard end.isInverse else {
                    let chosen = self.item(other)?.title ?? ""
                    let holder = self.item(old)?.title ?? ""
                    failure = (
                        cantChange, String(localized: "“\(holder)” already holds this link to “\(chosen)”. Remove it there first.")
                    )
                    return false
                }
                guard !replacingOwn else {
                    failure = (cantChange, String(localized: "Both items already hold a link of this kind, so one can’t take the other’s."))
                    return false
                }
                change.moving.append(.init(edge: theirs.id, end: farIsTarget ? .source : .target, to: id, from: old))
            } else if replacingOwn {
                guard removing.count == 1 else {
                    failure = (cantChange, String(localized: "Choose one item here, or remove the link first."))
                    return false
                }
                // The end that stays holds one link, and its other end changes. A two-way link may point here instead,
                // and then the end that moves is the one on the far side of that edge.
                if let old = held(by: id, end).first(where: { (farIsTarget ? $0.target : $0.source) == removing[0] }) {
                    change.moving.append(.init(edge: old.id, end: farIsTarget ? .target : .source, to: other, from: removing[0]))
                } else if let old = held(by: id, farEnd).first(where: { (farIsTarget ? $0.source : $0.target) == removing[0] }) {
                    change.moving.append(.init(edge: old.id, end: farIsTarget ? .source : .target, to: other, from: removing[0]))
                } else {
                    failure = (cantChange, String(localized: "Choose one item here, or remove the link first."))
                    return false
                }
                change.removing = []
            } else {
                change.adding.append(link)
            }
        }
        guard !change.isEmpty else { return true }
        relink(change, name: String(localized: "Edit Relationship"), undoManager: undoManager)
        return true
    }

    /// Where links are added or moved and others removed, as when one item is chosen in place of another in a field
    /// that holds many, the new links go first and the old ones are removed only once the source has taken every new
    /// one, so a refusal leaves the field as it was rather than with the old link gone and the new one missing.
    private func relink(_ change: RelationshipChange, name: String, undoManager: UndoManager?) {
        let title = String(localized: "Can’t Change This Relationship")
        var links = change.adding.map { submit(.link($0, undoing: nil), failing: title) }
        links += change.moving.map { submit(.moveEdge($0.edge, end: $0.end, to: $0.to), failing: title) }
        if links.isEmpty {
            unlink(change.removing)
        } else if !change.removing.isEmpty {
            awaitLinks(Set(links), thenUnlink: change.removing)
        }
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.relink(change.reversed, name: name, undoManager: undoManager)
        }
    }

    func unlink(_ drafts: [EdgeDraft]) {
        let title = String(localized: "Can’t Change This Relationship")
        for draft in drafts {
            if let link = index.link(type: draft.type, source: draft.source, target: draft.target) {
                submit(.unlink(link.id), failing: title)
            }
        }
    }
}
