import Foundation

/// Relationships are Marfa's edges. An item's own fields are the edges it holds, named as its end writes them,
/// such as `child-of` for the parent a child holds; its inverse fields, `inverse:` and the edge type, are the
/// edges other items hold that point at it, such as a parent's children. What an item's text links or embeds is
/// written as edges by the package, as the text is saved: a link is a `references` edge, which the item it names
/// shows as linked from, and an embedded file is an `attached-to` edge from the file to the item.
extension MarfaLibrary {
    static let inversePrefix = "inverse:"

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

        /// Only the server's own bookkeeping, such as its folders, which the copy never holds.
        var isServers: Bool { roles.isEmpty && !types.isEmpty && types.allSatisfy { $0.rawValue.hasPrefix("system.") } }
    }

    private func constraint(of info: EdgeTypeInfo, atTarget: Bool) -> EndConstraint {
        atTarget
            ? EndConstraint(types: info.targetTypes, roles: info.targetRoles)
            : EndConstraint(types: info.sourceTypes, roles: info.sourceRoles)
    }

    private func admits(_ type: TypeID, _ end: EndConstraint) -> Bool {
        catalogue.admits(type, types: end.types, roles: end.roles)
    }

    /// Whether an item of `type` may hold the end `atTarget` names of the edge type `info`. The core refuses a flat
    /// edge type's source a type its target end admits, so the field is not offered there.
    private func admits(_ type: TypeID, _ info: EdgeTypeInfo, atTarget: Bool) -> Bool {
        atTarget ? admits(type, constraint(of: info, atTarget: true)) : catalogue.admits(type, source: info)
    }

    /// What the core says of linking `id` through `field` to `other`. Judged on what the copy holds, with no server and
    /// nothing queued, so a picker can ask of each row.
    func relationshipVerdict(for id: ItemID, field: String, to other: ItemID) async -> EdgeVerdict {
        guard let end = fieldEnd(field) else { return .unknown }
        return await source.edgeVerdict(draft(id, other, end))
    }

    /// The edge is checked to the id the item will be given, which the copy does not hold yet: the core then judges
    /// the parent (held, not in the bin, a type that may be one, not flat) and skips the target's type.
    func newChildVerdict(under parent: ItemID) async -> EdgeVerdict {
        await source.edgeVerdict(EdgeDraft(type: MarfaMapping.parentEdge, source: parent, target: ItemID.mint(at: now())))
    }

    // MARK: Reading

    /// The fields an item of `type` can hold, each named as its end writes it: body links are the text's, shown
    /// as mentions, and an edge whose far end can only be the server's own bookkeeping is never shown.
    private func ownFields(of type: TypeID) -> [(name: String, end: FieldEnd)] {
        catalogue.edgeTypes.values.compactMap { info -> (String, FieldEnd)? in
            guard info.id != MarfaMapping.bodyLinkEdge else { return nil }
            let atTarget = info.writtenAt == .target
            let far = constraint(of: info, atTarget: !atTarget)
            guard admits(type, info, atTarget: atTarget), !far.isServers else { return nil }
            let name = atTarget ? info.reverseName ?? info.id : info.id
            return (name, FieldEnd(info: info, atTarget: atTarget, isInverse: false))
        }
    }

    /// The name Marfa gives the end of the link this field is: the edge type's `label` on its source end and its
    /// `reverseLabel` on its target end.
    private func label(_ end: FieldEnd) -> String {
        end.info.label(atTarget: end.atTarget)
    }

    /// A link keeps its item's ID whether or not the copy holds the item, so it can still be removed: one it does not
    /// hold is shown as not found, and one in the bin as deleted.
    private func target(_ id: ItemID) -> ItemRelationshipTarget {
        guard let item = item(id) else { return ItemRelationshipTarget(title: "", itemID: id, resolution: .missing) }
        return ItemRelationshipTarget(
            title: item.name ?? "", itemID: id, resolution: .resolved(id), isDeleted: item.state == .trashed)
    }

    /// By title, and by ID among equal titles, so the same links come first each time a group is drawn.
    private static func ordered(_ targets: [ItemRelationshipTarget]) -> [ItemRelationshipTarget] {
        targets.sorted {
            switch $0.title.localizedStandardCompare($1.title) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: $0.id < $1.id
            }
        }
    }

    func relationships(for id: ItemID) -> [ItemRelationship] {
        Cost.measure(.relationships) { readRelationships(for: id) }
    }

    private func readRelationships(for id: ItemID) -> [ItemRelationship] {
        guard let item = item(id) else { return [] }
        // Another item's edge can point here; its title and state are followed through its own record.
        _ = linksRevision
        var fields = ownFields(of: item.type)
        for edge in item.edgesOut where edge.origin != .body && !fields.contains(where: { $0.name == edge.type }) {
            if let end = fieldEnd(edge.type) { fields.append((edge.type, end)) }
        }
        var results = fields.map { name, end in
            ItemRelationship(
                field: name, label: label(end), targets: Self.ordered(others(of: id, end).map(target)),
                isEditable: item.isEditable, allowsMultiple: end.info.cardinality == .many)
        }
        let pointing = index.links(touching: id).filter { $0.holder != id }
        for type in Set(pointing.map(\.type)) {
            guard let end = fieldEnd(Self.inversePrefix + type) else { continue }
            let holders = pointing.filter { $0.type == type }.map { $0.holder }
            let targets = Self.ordered(holders.filter { self.item($0) != nil }.map(target))
            // A two-way relation reads the same from both items, so the links pointing here join the ones this item
            // holds in a single list.
            if end.info.isTwoWay, let own = fields.firstIndex(where: { !$0.end.isInverse && $0.end.info.id == type }) {
                let held = results[own]
                results[own] = ItemRelationship(
                    field: held.field, label: held.label,
                    targets: Self.ordered(
                        held.targets + targets.filter { incoming in !held.targets.contains { $0.id == incoming.id } }),
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

    /// Active items of a type the field's far end allows. Which of them the core would refuse, such as one that
    /// would close a cycle, is asked of each (`relationshipVerdict`).
    func relationshipCandidates(for id: ItemID, field: String) -> [Item] {
        guard let item = item(id), let end = fieldEnd(field) else { return [] }
        guard admits(item.type, end.info, atTarget: end.atTarget) else { return [] }
        return heldItems(index.ids(in: .active))
            .filter { $0.id != id && admits($0.type, end.info, atTarget: !end.atTarget) }
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

    func canHaveParent(typeID: String) -> Bool {
        guard let info = catalogue.edgeTypes[MarfaMapping.parentEdge],
            admits(TypeID(typeID), constraint(of: info, atTarget: true))
        else { return false }
        let parents = constraint(of: info, atTarget: false)
        return index.ids(in: .active).contains { id in heldItems(CollectionOfOne(id)).first.map { admits($0.type, parents) } ?? false }
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

    /// Changes the field of `id` by what the person changed: `adding` items to link and `removing` items to unlink,
    /// relative to what they saw, never the whole list they saw, which a change made since would be undone by.
    /// A link is added where its ends have room and removed freely.
    /// An end that holds one link of its type has it replaced by moving the edge's other end (`edges/move-target`,
    /// `edges/move-source`), so a new parent is one write and the child never holds none or two (`edges/move-no-gap`):
    /// a replacement is a move, and so is taking an item whose own link points elsewhere, as a child chosen under a
    /// project. A link a third item holds as its own is never taken from it.
    ///
    /// The change is worked out, the core asked of every link it makes, and then worked out again from the links the
    /// copy holds then and written in the same step, with its undo, so an earlier change that landed meanwhile is
    /// kept and not repeated, and a move's old parent is the one it left. A link new in that second look is asked too.
    /// Changes run one after another in the order they were made, each once the copy has taken the writes of the one
    /// before (see `relationshipChain`). Nothing is written until the core has answered.
    /// True means the core accepted the change and it is written, or there was nothing to change; false means it was
    /// refused and told, by MAPP's own rules (the cardinality rules in `plan`, since `Edges.check` does not judge how
    /// many an end holds) or by the core's, and the field is as it was. `finish` waits for a change in flight.
    @discardableResult
    func changeItemRelationship(
        _ id: ItemID, field: String, adding: [ItemID], removing: [ItemID], undoManager: UndoManager?
    ) async -> Bool {
        relationshipChangesInFlight += 1
        let previous = relationshipChain
        let work = Task { () -> (kept: Bool, writes: Set<WriteID>) in
            await previous?.value
            let done = await self.applyRelationship(id, field: field, adding: adding, removing: removing, undoManager: undoManager)
            self.relationshipChangesInFlight -= 1
            return done
        }
        // The next change reads the copy, which shows this one's writes once the source has taken or answered each.
        relationshipChain = Task {
            await self.untilSettled(work.value.writes)
        }
        return await work.value.kept
    }

    /// Returns once each write has been taken into the copy (`SourceChange.taken`) or answered before that
    /// (`.answered`, as a refusal is). It ends for a write the source refused to take at all, which is never waited
    /// for, for a source that closes (the engine answers every write it holds `closed`), and when the source's
    /// changes end (`endWaits`), so it never waits on a write nothing will answer.
    private func untilSettled(_ writes: Set<WriteID>) async {
        let pending = writes.intersection(unsettled)
        guard !pending.isEmpty else { return }
        await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
            waiters.append(Waiter(pending: pending, resume: waiter))
        }
    }

    private func applyRelationship(
        _ id: ItemID, field: String, adding: [ItemID], removing: [ItemID], undoManager: UndoManager?
    ) async -> (kept: Bool, writes: Set<WriteID>) {
        let cantChange = String(localized: "Can’t Change This Relationship")
        var asked: Set<EdgeDraft> = []
        while true {
            guard let plan = plan(id, field: field, adding: adding, removing: removing) else { return (false, []) }
            guard !plan.change.isEmpty else { return (true, []) }
            let unasked = plan.made.filter { !asked.contains($0) }
            guard !unasked.isEmpty else {
                let writes = relink(plan.change, name: String(localized: "Edit Relationship"), undoManager: undoManager)
                return (true, writes)
            }
            for link in unasked {
                if case .refused(let reason) = await source.edgeVerdict(link) {
                    notices.tell(cantChange, reason)
                    return (false, [])
                }
                asked.insert(link)
            }
        }
    }

    /// What the edges would be changed by, and every link it makes, whether added or made by moving an end: what the
    /// core is asked about. Nil where MAPP's own rules refuse, and the person is told.
    private func plan(_ id: ItemID, field: String, adding wanted: [ItemID], removing unwanted: [ItemID]) -> (change: RelationshipChange, made: [EdgeDraft])? {
        guard let item = item(id), item.isEditable, let end = fieldEnd(field) else { return nil }
        let cantChange = String(localized: "Can’t Change This Relationship")
        guard end.info.id != MarfaMapping.bodyLinkEdge else {
            notices.tell(cantChange, String(localized: "A link is changed in the text that holds it."))
            return nil
        }
        let holds = end.info.cardinality(atTarget: end.atTarget)
        let farEnd = FieldEnd(info: end.info, atTarget: !end.atTarget, isInverse: !end.isInverse)
        // A two-way relation is one list of the links this item holds and the ones pointing at it.
        let own = others(of: id, end)
        let incoming = !end.isInverse && end.info.isTwoWay ? others(of: id, farEnd) : []
        let current = own + incoming.filter { !own.contains($0) }
        // What the field holds now, with the person's change on it: read here, on every pass, so a change that landed
        // since the person looked is kept.
        var targetIDs = current.filter { !unwanted.contains($0) }
        for other in wanted where !targetIDs.contains(other) && !unwanted.contains(other) { targetIDs.append(other) }
        guard holds != .one || targetIDs.count <= 1 else {
            notices.tell(cantChange, String(localized: "Only one item can be chosen here."))
            return nil
        }
        let adding = targetIDs.filter { !current.contains($0) }
        let removing = current.filter { !targetIDs.contains($0) }
        var change = RelationshipChange(removing: removing.flatMap { other in
            (own.contains(other) ? [draft(id, other, end)] : []) + (incoming.contains(other) ? [draft(id, other, farEnd)] : [])
        })
        let farHolds = end.info.cardinality(atTarget: !end.atTarget)
        // Replacing this item's own link moves the far end; taking another item's link moves this item's end.
        let farIsTarget = !end.atTarget
        let replacingOwn = holds == .one && !removing.isEmpty && !adding.isEmpty
        // Every link the change makes, whether added or made by moving an end: what the core is asked about.
        var made: [EdgeDraft] = []
        for other in adding {
            let link = draft(id, other, end)
            made.append(link)
            let taken = farHolds == .one ? held(by: other, farEnd).filter { (farIsTarget ? $0.source : $0.target) != id } : []
            if let theirs = taken.first {
                let old = farIsTarget ? theirs.source : theirs.target
                // The item chosen holds its one link elsewhere. Where that link is its own, as a child's parent is,
                // the move changes it to this one. Where it is the third item's own, the move would take it from an
                // item the person is not looking at, so they are told which item holds it.
                guard end.isInverse else {
                    let chosen = self.item(other)?.title ?? ""
                    let holder = self.item(old)?.title ?? ""
                    notices.tell(
                        cantChange, String(localized: "“\(holder)” already holds this link to “\(chosen)”. Remove it there first.")
                    )
                    return nil
                }
                guard !replacingOwn else {
                    notices.tell(cantChange, String(localized: "Both items already hold a link of this kind, so one can’t take the other’s."))
                    return nil
                }
                change.moving.append(.init(edge: theirs.id, end: farIsTarget ? .source : .target, to: id, from: old))
            } else if replacingOwn {
                guard removing.count == 1 else {
                    notices.tell(cantChange, String(localized: "Choose one item here, or remove the link first."))
                    return nil
                }
                // The end that stays holds one link, and its other end changes. A two-way link may point here instead,
                // and then the end that moves is the one on the far side of that edge.
                if let old = held(by: id, end).first(where: { (farIsTarget ? $0.target : $0.source) == removing[0] }) {
                    change.moving.append(.init(edge: old.id, end: farIsTarget ? .target : .source, to: other, from: removing[0]))
                } else if let old = held(by: id, farEnd).first(where: { (farIsTarget ? $0.source : $0.target) == removing[0] }) {
                    change.moving.append(.init(edge: old.id, end: farIsTarget ? .source : .target, to: other, from: removing[0]))
                } else {
                    notices.tell(cantChange, String(localized: "Choose one item here, or remove the link first."))
                    return nil
                }
                change.removing = []
            } else {
                change.adding.append(link)
            }
        }
        return (change, made)
    }

    /// Where links are added or moved and others removed, as when one item is chosen in place of another in a field
    /// that holds many, the new links go first and the old ones are removed only once the source has taken every new
    /// one, so a refusal leaves the field as it was rather than with the old link gone and the new one missing.
    ///
    /// Returns the writes sent now that the source took, which a following change waits for: the adds, the moves and
    /// any unlink sent at once. An unlink held back for the new links is not one of them, since it is sent only after
    /// the server answers them, which can be long, and a write the source refused to take is not either.
    @discardableResult
    func relink(
        _ change: RelationshipChange, name: String, failing title: String = String(localized: "Can’t Change This Relationship"),
        undoManager: UndoManager?
    ) -> Set<WriteID> {
        var links = change.adding.map { submit(.link($0, undoing: nil), failing: title) }
        links += change.moving.map { submit(.moveEdge($0.edge, end: $0.end, to: $0.to), failing: title) }
        var sent = Set(links)
        if links.isEmpty {
            sent.formUnion(unlink(change.removing, failing: title))
        } else if !change.removing.isEmpty {
            awaitLinks(Set(links), thenUnlink: change.removing)
        }
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.relink(change.reversed, name: name, failing: title, undoManager: undoManager)
        }
        // A write that was not queued, as after the source closed, was told to the person and gets no answer.
        sent = sent.filter { isFollowed($0) }
        unsettled.formUnion(sent)
        return sent
    }

    @discardableResult
    func unlink(_ drafts: [EdgeDraft], failing title: String = String(localized: "Can’t Change This Relationship")) -> [WriteID] {
        drafts.compactMap { draft in
            index.link(type: draft.type, source: draft.source, target: draft.target).map { submit(.unlink($0.id), failing: title) }
        }
    }
}
