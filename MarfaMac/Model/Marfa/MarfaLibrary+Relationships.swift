import Foundation

/// Relationships are Marfa's edges. An item's own fields are the edges it holds, named as its end writes them,
/// such as `child-of` for the parent a child holds; its inverse fields, `inverse:` and the edge type, are the
/// edges other items hold that point at it, such as a parent's children. What an item's text links or embeds is
/// written as edges by the package, as the text is saved: a link is a `references` edge, which the item it names
/// shows as linked from, and an embedded file is an `attached-to` edge from the file to the item.
extension MarfaLibrary {
    static let inversePrefix = "inverse:"

    /// A relationship field as one item sees it: the edge type, and whether the item is the edge's `to` end.
    nonisolated struct FieldEnd {
        let info: EdgeTypeInfo
        let atTo: Bool
        let isInverse: Bool
    }

    func fieldEnd(_ field: String) -> FieldEnd? {
        if field.hasPrefix(Self.inversePrefix) {
            guard let info = catalogue.edgeTypes[String(field.dropFirst(Self.inversePrefix.count))] else { return nil }
            return FieldEnd(info: info, atTo: info.writtenFrom == .from, isInverse: true)
        }
        guard let (info, isReverse) = catalogue.edgeType(named: field) else { return nil }
        return FieldEnd(info: info, atTo: isReverse || info.writtenFrom == .to, isInverse: false)
    }

    /// The edge `id` would hold, or be pointed at by, with `other` at the far end.
    private func draft(_ id: ItemID, _ other: ItemID, _ end: FieldEnd) -> EdgeDraft {
        end.atTo
            ? EdgeDraft(type: end.info.id, from: other, to: id)
            : EdgeDraft(type: end.info.id, from: id, to: other)
    }

    private func others(of id: ItemID, _ end: FieldEnd) -> [ItemID] {
        held(by: id, end).map { end.atTo ? $0.from : $0.to }
    }

    /// What one end of an edge type allows: the types named, with their subtypes, and the types that play a
    /// role named. An end naming neither allows any type.
    nonisolated struct EndConstraint {
        let types: Set<TypeID>
        let roles: Set<String>

        /// Only the server's own bookkeeping, such as its folders, which the copy never holds.
        var isServers: Bool { roles.isEmpty && !types.isEmpty && types.allSatisfy { $0.rawValue.hasPrefix("system.") } }
    }

    private func constraint(of info: EdgeTypeInfo, atTo: Bool) -> EndConstraint {
        atTo
            ? EndConstraint(types: info.toTypes, roles: info.toRoles)
            : EndConstraint(types: info.fromTypes, roles: info.fromRoles)
    }

    private func admits(_ type: TypeID, _ end: EndConstraint) -> Bool {
        catalogue.admits(type, types: end.types, roles: end.roles)
    }

    /// Whether an item of `type` may hold the end `atTo` names of the edge type `info`. The core refuses a flat
    /// edge type's `from` end a type its `to` end admits, so the field is not offered there.
    private func admits(_ type: TypeID, _ info: EdgeTypeInfo, atTo: Bool) -> Bool {
        atTo ? admits(type, constraint(of: info, atTo: true)) : catalogue.admits(type, from: info)
    }

    /// What the core says of linking `id` through `field` to `other`, as the change would be made: a field that holds one
    /// link has it replaced by moving an end, which the core judges as a move, and any other link as a new one. Judged
    /// on what the copy holds, with no server and nothing queued, so a picker can ask of each row.
    func relationshipVerdict(for id: ItemID, field: String, to other: ItemID) async -> EdgeVerdict {
        guard let end = fieldEnd(field) else { return .unknown }
        let current = linked(to: id, end)
        guard !current.contains(other) else { return .taken }
        // A picker of a field that holds one link replaces it with the item chosen.
        let replaced = end.info.cardinality(atTo: end.atTo) == .one ? current : []
        switch plan(id, field: field, adding: [other], removing: replaced) {
        case .unavailable: return await source.edgeVerdict(draft(id, other, end))
        case .refused(let reason): return .refused(reason)
        case .change(_, let made):
            for link in made {
                let verdict = await verdict(of: link)
                if verdict != .taken { return verdict }
            }
            return .taken
        }
    }

    private func verdict(of link: MadeLink) async -> EdgeVerdict {
        switch link {
        case .added(let draft): await source.edgeVerdict(draft)
        case .moved(let move): await source.edgeVerdict(moving: move.edge, end: move.end, to: move.to)
        }
    }

    /// The edge is checked to the id the item will be given, which the copy does not hold yet: the core then judges
    /// the parent (held, not in the bin, a type that may be one, not flat) and skips the to item's type.
    func newChildVerdict(under parent: ItemID) async -> EdgeVerdict {
        await source.edgeVerdict(EdgeDraft(type: MarfaMapping.parentEdge, from: parent, to: ItemID.mint(at: now())))
    }

    // MARK: Reading

    /// The fields an item of `type` can hold, each named as its end writes it: body links are the text's, shown
    /// as mentions, and an edge whose far end can only be the server's own bookkeeping is never shown.
    private func ownFields(of type: TypeID) -> [(name: String, end: FieldEnd)] {
        catalogue.edgeTypes.values.compactMap { info -> (String, FieldEnd)? in
            guard info.id != MarfaMapping.bodyLinkEdge else { return nil }
            let atTo = info.writtenFrom == .to
            let far = constraint(of: info, atTo: !atTo)
            guard admits(type, info, atTo: atTo), !far.isServers else { return nil }
            let name = atTo ? info.reverseName ?? info.id : info.id
            return (name, FieldEnd(info: info, atTo: atTo, isInverse: false))
        }
    }

    /// The name Marfa gives the end of the link this field is: the edge type's `label` on its `from` end and its
    /// `reverseLabel` on its `to` end.
    private func label(_ end: FieldEnd) -> String {
        end.info.label(atTo: end.atTo)
    }

    /// A link keeps its item's ID whether or not the copy holds the item, so it can still be removed: one it does not
    /// hold is shown as not found, and one in the bin as deleted.
    private func target(_ id: ItemID) -> ItemRelationshipTarget {
        guard let item = headerItem(id) else { return ItemRelationshipTarget(title: "", itemID: id, resolution: .missing) }
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

    func childIDs(of id: ItemID) -> [ItemID] {
        observeLinks(of: id)
        return index.links(from: id, type: MarfaMapping.parentEdge).map(\.to)
    }

    func relationships(for id: ItemID) -> [ItemRelationship] {
        Cost.measure(.relationships) { readRelationships(for: id) }
    }

    private func readRelationships(for id: ItemID) -> [ItemRelationship] {
        guard let item = headerItem(id) else { return [] }
        // Another item's edge can point here without changing a field this header shows. `observeLinks` follows that
        // edge. Each named item is read with `headerItem`, so a title there is followed and an unrelated item is not.
        observeLinks(of: id)
        var fields = ownFields(of: item.type)
        for edge in item.edgesOut where edge.origin != .body && !fields.contains(where: { $0.name == edge.type }) {
            if let end = fieldEnd(edge.type) { fields.append((edge.type, end)) }
        }
        var results = fields.map { name, end in
            ItemRelationship(
                field: name, label: label(end), targets: Self.ordered(others(of: id, end).map(target)),
                isEditable: item.allows(.links), allowsMultiple: end.info.cardinality == .many)
        }
        let pointing = index.links(touching: id).filter { $0.holder != id }
        for type in Set(pointing.map(\.type)) {
            guard let end = fieldEnd(Self.inversePrefix + type) else { continue }
            let holders = pointing.filter { $0.type == type }.map { $0.holder }
            let targets = Self.ordered(holders.filter { self.headerItem($0) != nil }.map(target))
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
                isEditable: item.allows(.links) && type != MarfaMapping.bodyLinkEdge,
                allowsMultiple: end.info.reverseCardinality == .many))
        }
        return results.sorted { lhs, rhs in
            lhs.field.hasPrefix(Self.inversePrefix) != rhs.field.hasPrefix(Self.inversePrefix)
                ? !lhs.field.hasPrefix(Self.inversePrefix)
                : lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
        }
    }

    func relationFields(of id: ItemID) -> [RelationField] {
        Cost.measure(.relationships) { readRelationFields(of: id) }
    }

    /// Every field Marfa lets the item hold, or that it already holds, own or inverse. A two-way type's links read the
    /// same from both ends, so its inverse joins its own field, unless only the inverse end admits the item.
    /// Filled fields come first. Within each group, sort own fields before inverses, then by label and field name.
    private func readRelationFields(of id: ItemID) -> [RelationField] {
        guard let item = headerItem(id) else { return [] }
        observeLinks(of: id)
        var ends: [String: FieldEnd] = [:]
        for info in catalogue.edgeTypes.values {
            let written = info.writtenFrom == .to
            let own = admits(item.type, info, atTo: written)
            if own {
                ends[written ? info.reverseName ?? info.id : info.id] = FieldEnd(info: info, atTo: written, isInverse: false)
            }
            if !(info.isTwoWay && own), admits(item.type, info, atTo: !written) {
                ends[Self.inversePrefix + info.id] = FieldEnd(info: info, atTo: !written, isInverse: true)
            }
        }
        for link in index.links(touching: id) {
            guard let held = fieldEnd(link.holder == id ? link.type : Self.inversePrefix + link.type) else { continue }
            if held.isInverse, held.info.isTwoWay, ends.values.contains(where: { $0.info.id == held.info.id && !$0.isInverse }) {
                continue
            }
            if ends.values.contains(where: { $0.info.id == held.info.id && $0.atTo == held.atTo }) { continue }
            let name = held.isInverse ? Self.inversePrefix + held.info.id : held.atTo ? held.info.reverseName ?? held.info.id : held.info.id
            ends[name] = held
        }
        let fields = ends.map { field, end -> RelationField in
            let linked = end.isInverse ? others(of: id, end).filter { headerItem($0) != nil } : linked(to: id, end)
            let allowed = catalogue.itemTypes.keys.filter { !$0.isHidden && admits($0, end.info, atTo: !end.atTo) }
            return RelationField(
                field: field, label: label(end), cardinality: end.info.cardinality(atTo: end.atTo),
                allowedTypes: allowed.sorted { $0.rawValue < $1.rawValue }, targets: Self.ordered(linked.map(target)),
                editability: obstacle(item, end).map { .readOnly($0) } ?? .editable)
        }
        return fields.sorted { lhs, rhs in
            if lhs.targets.isEmpty != rhs.targets.isEmpty { return !lhs.targets.isEmpty }
            let lhsInverse = lhs.field.hasPrefix(Self.inversePrefix)
            if lhsInverse != rhs.field.hasPrefix(Self.inversePrefix) { return !lhsInverse }
            switch lhs.label.localizedStandardCompare(rhs.label) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return lhs.field < rhs.field
            }
        }
    }

    /// The items a link may reach: active and archived, never in the bin, since Marfa links an archived item as any
    /// other ("What an item allows").
    private var linkable: Set<ItemID> { index.ids(in: .active).union(index.ids(in: .archived)) }

    /// Active and archived items of a type the field's far end allows. Which of them the core would refuse, such as one
    /// that would close a cycle, is asked of each (`relationshipVerdict`).
    func relationshipCandidates(for id: ItemID, field: String) -> [Item] {
        guard let item = item(id), let end = fieldEnd(field) else { return [] }
        guard admits(item.type, end.info, atTo: end.atTo) else { return [] }
        return heldItems(linkable)
            .filter { $0.id != id && admits($0.type, end.info, atTo: !end.atTo) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func bodyMentions(for id: ItemID) -> [ItemRelationshipTarget] {
        // Body links are edges, which the header follows. The version and the text are not what a mention row shows.
        guard let item = headerItem(id) else { return [] }
        return item.edgesOut.filter { $0.origin == .body }.map { edge in
            switch edge.to {
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
            admits(TypeID(typeID), constraint(of: info, atTo: true))
        else { return [] }
        let parents = constraint(of: info, atTo: false)
        return heldItems(linkable)
            .filter { admits($0.type, parents) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func canHaveParent(typeID: String) -> Bool {
        guard let info = catalogue.edgeTypes[MarfaMapping.parentEdge],
            admits(TypeID(typeID), constraint(of: info, atTo: true))
        else { return false }
        let parents = constraint(of: info, atTo: false)
        return linkable.contains { id in heldItems(CollectionOfOne(id)).first.map { admits($0.type, parents) } ?? false }
    }

    // MARK: Writing

    /// What one change to a field does to the edges, each as one write.
    nonisolated struct RelationshipChange {
        /// One end of an edge replaced by another item, which the edge keeps its id and properties through.
        struct Move: Hashable {
            let edge: EdgeID
            let end: EdgeTypeInfo.End
            let to: ItemID
            let from: ItemID
            /// The edge's other end, which the move leaves where it is.
            let stays: ItemID

            var reversed: Move { Move(edge: edge, end: end, to: from, from: to, stays: stays) }
        }

        var adding: [EdgeDraft] = []
        var removing: [EdgeDraft] = []
        var moving: [Move] = []

        var isEmpty: Bool { adding.isEmpty && removing.isEmpty && moving.isEmpty }
    }

    /// A link a change makes, which the core is asked about as it would be written: a new link, or an end moved.
    nonisolated enum MadeLink: Hashable {
        case added(EdgeDraft)
        case moved(RelationshipChange.Move)
    }

    /// What working out a change comes to.
    private enum Planning {
        /// The field or the item is not one the library holds; nothing is told.
        case unavailable
        /// The item or the field takes no change, in the words to tell the person.
        case refused(String)
        /// The edges to write, and every link they make.
        case change(RelationshipChange, made: [MadeLink])
    }

    /// The edges of the field's type that `id` holds at the end `end` names.
    private func held(by id: ItemID, _ end: FieldEnd) -> [MarfaItemIndex.Link] {
        index.links(touching: id).filter { $0.type == end.info.id && (end.atTo ? $0.to == id : $0.from == id) }
    }

    /// Changes the field of `id` by what the person changed: `adding` items to link and `removing` items to unlink,
    /// relative to what they saw, never the whole list they saw, which a change made since would be undone by.
    /// A link is removed freely; the core judges every link added, and how many an end may hold.
    /// An end that holds one link of its type has it replaced by moving the edge's other end (`edges/move-to`,
    /// `edges/move-from`), so a new parent is one write and the child never holds none or two (`edges/move-no-gap`):
    /// a replacement is a move, and so is taking an item whose own link points elsewhere, as a child chosen under a
    /// project. A link a third item holds as its own is never taken from it.
    ///
    /// The change is worked out, the core asked of every link it makes (`Edges.check(from:to:type:)` of a new link,
    /// `Edges.check(_:moving:)` of a move), and then worked out again from the links the copy holds then and written in
    /// the same step, with its undo, so an earlier change that landed meanwhile is kept and not repeated, and a move's
    /// old parent is the one it left. A link new in that second look is asked too.
    /// Changes run one after another in the order they were made, each once the copy has taken the writes of the one
    /// before (see `relationshipChain`). Nothing is written until the core has answered.
    ///
    /// The verdict is `taken` where the change is written or there was nothing to change; `refused` where the item, the
    /// field or the core refuses it; `incomplete` while the copy is not whole; `unknown` for an item or field the
    /// library does not hold, or a source that took nothing. Every verdict but `taken` and `unknown` is also told, and
    /// leaves the field as it was. A change that asks nothing of the core, as a removal, answers only once the copy has
    /// taken or refused its writes, and is `refused` where the copy skipped one, as a link already gone.
    /// `finish` waits for a change in flight.
    @discardableResult
    func changeLinks(
        _ id: ItemID, field: String, adding: [ItemID], removing: [ItemID], undoManager: UndoManager?
    ) async -> EdgeVerdict {
        relationshipChangesInFlight += 1
        let previous = relationshipChain
        let work = Task { () -> (verdict: EdgeVerdict, writes: Set<WriteID>) in
            await previous?.value
            let done = await self.applyRelationship(id, field: field, adding: adding, removing: removing, undoManager: undoManager)
            self.relationshipChangesInFlight -= 1
            return done
        }
        // The next change reads the copy, which shows this one's writes once the source has taken or answered each.
        relationshipChain = Task {
            await self.untilSettled(work.value.writes)
        }
        return await work.value.verdict
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
    ) async -> (verdict: EdgeVerdict, writes: Set<WriteID>) {
        let cantChange = String(localized: "Can’t Change This Relationship")
        var asked: Set<MadeLink> = []
        while true {
            let plan: (change: RelationshipChange, made: [MadeLink])
            switch self.plan(id, field: field, adding: adding, removing: removing) {
            case .unavailable: return (.unknown, [])
            case .refused(let reason):
                notices.tell(cantChange, reason)
                return (.refused(reason), [])
            case .change(let change, let made): plan = (change, made)
            }
            guard !plan.change.isEmpty else { return (.taken, []) }
            let unasked = plan.made.filter { !asked.contains($0) }
            guard !unasked.isEmpty else {
                let name = fieldEnd(field).map { String(localized: "Change \(label($0))") } ?? cantChange
                var made: LinkStep?
                gatheringSkips(failing: cantChange) {
                    made = relink(plan.change, name: name, failing: cantChange, undoManager: undoManager)
                }
                guard let step = made else { return (.unknown, []) }
                guard plan.made.isEmpty else { return (.taken, step.sent) }
                // Nothing was asked of the core, as for a removal, so the copy's judgement of the writes is the verdict.
                guard !step.sent.isEmpty else { return (.unknown, []) }
                await untilSettled(step.sent)
                return (step.verdict, step.sent)
            }
            for link in unasked {
                switch await verdict(of: link) {
                case .refused(let reason):
                    notices.tell(cantChange, reason)
                    return (.refused(reason), [])
                case .incomplete:
                    notices.tell(cantChange, MarfaEngine.notCurrent)
                    return (.incomplete, [])
                case .taken, .unknown:
                    asked.insert(link)
                }
            }
        }
    }

    /// The items `id` is linked to through the end `end` names; for a two-way relation, the ones it holds and the ones
    /// pointing at it, as a single list.
    private func linked(to id: ItemID, _ end: FieldEnd) -> [ItemID] {
        let own = others(of: id, end)
        guard !end.isInverse, end.info.isTwoWay else { return own }
        let farEnd = FieldEnd(info: end.info, atTo: !end.atTo, isInverse: !end.isInverse)
        return own + others(of: id, farEnd).filter { !own.contains($0) }
    }

    /// Why the field of `item` takes no change, or nil where it does: what the item allows (`Item.obstacle(to:)`), a
    /// link the item's text holds, or one whose far end only Marfa keeps, as a synced folder.
    private func obstacle(_ item: Item, _ end: FieldEnd) -> String? {
        if let reason = item.obstacle(to: .links) { return BatchSkips.sentence(reason, count: 1) }
        if end.info.id == MarfaMapping.bodyLinkEdge { return String(localized: "A link is changed in the text that holds it.") }
        if constraint(of: end.info, atTo: !end.atTo).isServers { return String(localized: "Marfa keeps this link itself.") }
        return nil
    }

    /// What the edges would be changed by, and every link it makes, whether added or made by moving an end: what the
    /// core is asked about. The app decides only which edges to write: an end that holds one link of its type has it
    /// replaced by a move, and a link another item holds as its own is never taken. How many links an end may hold is
    /// the core's to judge, of the links this makes.
    private func plan(_ id: ItemID, field: String, adding wanted: [ItemID], removing unwanted: [ItemID]) -> Planning {
        guard let item = item(id), let end = fieldEnd(field) else { return .unavailable }
        if let reason = obstacle(item, end) { return .refused(reason) }
        let holds = end.info.cardinality(atTo: end.atTo)
        let farEnd = FieldEnd(info: end.info, atTo: !end.atTo, isInverse: !end.isInverse)
        // A two-way relation is one list of the links this item holds and the ones pointing at it.
        let own = others(of: id, end)
        let incoming = !end.isInverse && end.info.isTwoWay ? others(of: id, farEnd) : []
        let current = linked(to: id, end)
        // What the field holds now, with the person's change on it: read here, on every pass, so a change that landed
        // since the person looked is kept.
        var targetIDs = current.filter { !unwanted.contains($0) }
        for other in wanted where !targetIDs.contains(other) && !unwanted.contains(other) { targetIDs.append(other) }
        let adding = targetIDs.filter { !current.contains($0) }
        let removing = current.filter { !targetIDs.contains($0) }
        let farHolds = end.info.cardinality(atTo: !end.atTo)
        // Replacing this item's own link moves the far end; taking another item's link moves this item's end.
        let farIsTo = !end.atTo
        let replacingOwn = holds == .one && !removing.isEmpty && !adding.isEmpty
        var unlinking = removing
        var change = RelationshipChange()
        // Every link the change makes, whether added or made by moving an end: what the core is asked about.
        var made: [MadeLink] = []
        for other in adding {
            let taken = farHolds == .one ? held(by: other, farEnd).filter { (farIsTo ? $0.from : $0.to) != id } : []
            if let theirs = taken.first, !end.isInverse {
                // The item chosen holds its one link elsewhere, and it is the third item's own: the move would take it from
                // an item the person is not looking at, so they are told which item holds it. Where that link is the
                // chosen item's own, as a child's parent is, the move changes it to this one.
                let old = farIsTo ? theirs.from : theirs.to
                let chosen = self.item(other)?.title ?? ""
                let holder = self.item(old)?.title ?? ""
                return .refused(String(localized: "“\(holder)” already holds this link to “\(chosen)”. Remove it there first."))
            }
            // The end that stays holds one link, and its other end changes. A two-way link may point here instead, and
            // then the end that moves is the one on the far side of that edge.
            let replaced = replacingOwn ? unlinking.compactMap { old -> (ItemID, RelationshipChange.Move)? in
                if let edge = held(by: id, end).first(where: { (farIsTo ? $0.to : $0.from) == old }) {
                    return (old, .init(edge: edge.id, end: farIsTo ? .to : .from, to: other, from: old, stays: id))
                }
                if let edge = held(by: id, farEnd).first(where: { (farIsTo ? $0.from : $0.to) == old }) {
                    return (old, .init(edge: edge.id, end: farIsTo ? .from : .to, to: other, from: old, stays: id))
                }
                return nil
            }.first : nil
            if let (old, move) = replaced {
                unlinking.removeAll { $0 == old }
                change.moving.append(move)
                made.append(.moved(move))
            } else if let theirs = taken.first {
                let old = farIsTo ? theirs.from : theirs.to
                let move = RelationshipChange.Move(edge: theirs.id, end: farIsTo ? .from : .to, to: id, from: old, stays: other)
                change.moving.append(move)
                made.append(.moved(move))
            } else {
                let link = draft(id, other, end)
                change.adding.append(link)
                made.append(.added(link))
            }
        }
        // A link that a move replaced is not removed as well.
        change.removing = unlinking.flatMap { other in
            (own.contains(other) ? [draft(id, other, end)] : []) + (incoming.contains(other) ? [draft(id, other, farEnd)] : [])
        }
        return .change(change, made: made)
    }

    /// Where links are added or moved and others removed, as when one item is chosen in place of another in a field
    /// that holds many, the new links go first and the old ones are removed only once the source has taken every new
    /// one, so a refusal leaves the field as it was rather than with the old link gone and the new one missing.
    /// Each new edge gets an id minted here, so its undo removes that edge and no other. Each edge to remove is named
    /// now by the id and ends this Mac sees, so a removal sent later never takes a link made since in its place.
    ///
    /// The step registered in return reverses only what the copy took of it (`LinkStep`), each write judged against the
    /// copy as it is queued (`MarfaEngine.judge(edge:)`), so a link changed elsewhere since is left as it is.
    ///
    /// The step's `sent` are the writes sent now that the source took, which a following change waits for: the adds,
    /// the moves and any unlink sent at once. An unlink held back for the new links is not one of them, since it is
    /// sent only after the server answers them, which can be long, and a write the source refused to take is not either.
    @discardableResult
    func relink(
        _ change: RelationshipChange, name: String, failing title: String = String(localized: "Can’t Change This Relationship"),
        undoManager: UndoManager?
    ) -> LinkStep {
        let step = LinkStep()
        var links: [WriteID] = []
        for var draft in change.adding {
            draft.id = EdgeID.mint(at: now())
            let write = submit(.link(draft), failing: title)
            follow(write, .added(draft), in: step)
            links.append(write)
        }
        for move in change.moving {
            let write = submit(.moveEdge(move.edge, end: move.end, to: move.to, from: move.from, stays: move.stays), failing: title)
            follow(write, .moved(move), in: step)
            links.append(write)
        }
        let removing = change.removing.compactMap(seen)
        var sent = Set(links)
        if links.isEmpty {
            sent.formUnion(unlink(removing, failing: title, recordingIn: step))
        } else if !removing.isEmpty {
            awaitLinks(Set(links), thenUnlink: removing, failing: title, recordingIn: step)
        }
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.reverse(step, name: name, failing: title, undoManager: undoManager)
        }
        // A write that was not queued, as after the source closed, was told to the person and gets no answer.
        step.sent = sent.filter { isFollowed($0) }
        unsettled.formUnion(step.sent)
        return step
    }

    /// The edge a removal names, by the id the draft carries or the one the library holds between its ends, with its
    /// position, so an undo puts a collection member back where it was. Nil where no such edge is held.
    private func seen(_ draft: EdgeDraft) -> EdgeDraft? {
        if draft.id != nil { return draft }
        guard let link = index.link(type: draft.type, from: draft.from, to: draft.to) else { return nil }
        var seen = draft
        seen.id = link.id
        seen.position = draft.position ?? link.position
        return seen
    }

    /// Removes each edge by the id and ends the draft names, which the engine judges against the copy as it is queued.
    @discardableResult
    func unlink(
        _ drafts: [EdgeDraft], failing title: String = String(localized: "Can’t Change This Relationship"), recordingIn step: LinkStep? = nil
    ) -> [WriteID] {
        drafts.compactMap { draft in
            guard let id = draft.id else { return nil }
            let write = submit(.unlink(EdgeDraft(type: draft.type, from: draft.from, to: draft.to, id: id)), failing: title)
            if let step { follow(write, .removed(draft), in: step) }
            return write
        }
    }
}
