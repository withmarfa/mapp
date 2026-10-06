import Foundation

/// Relationships are Marfa's edges. An item's own fields are the edges it holds, named as its end writes them,
/// such as `child-of` for the parent a child holds; its inverse fields, `inverse:` and the edge type, are the
/// edges other items hold that point at it, such as a parent's children.
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
        index.links(touching: id)
            .filter { $0.type == end.info.id && (end.atTarget ? $0.target == id : $0.source == id) }
            .map { end.atTarget ? $0.source : $0.target }
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

    private func label(of name: String, _ end: FieldEnd) -> String {
        if end.isInverse {
            return switch end.info.id {
            case MarfaMapping.parentEdge: "Children"
            case "about": "Items About This"
            default: "Incoming " + end.info.label
            }
        }
        let known = WorkbenchSchema.label(for: name)
        if known != name { return known }
        return name == end.info.id ? end.info.label : MarfaMapping.label(forField: name)
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
                field: name, label: label(of: name, end), targets: others(of: id, end).map(target),
                isEditable: item.isEditable, allowsMultiple: end.info.cardinality == .many)
        }
        let pointing = index.links(touching: id).filter { $0.holder != id && $0.type != MarfaMapping.bodyLinkEdge }
        for type in Set(pointing.map(\.type)) {
            guard let end = fieldEnd(Self.inversePrefix + type) else { continue }
            let holders = pointing.filter { $0.type == type }.map { $0.holder }
            let targets = holders.filter { self.item($0) != nil }.map(target)
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            results.append(ItemRelationship(
                field: Self.inversePrefix + type, label: label(of: type, end), targets: targets,
                isEditable: item.isEditable, allowsMultiple: end.info.reverseCardinality == .many))
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

    /// Makes the field link `id` to exactly `targetIDs`. An item that writes the edge and may hold only one gives
    /// up the one it has, as choosing a new parent replaces the old one; an item at the other end that may be
    /// pointed at only once, such as what one item supersedes, is refused while another points at it.
    @discardableResult
    func setItemRelationship(_ id: ItemID, field: String, targetIDs: [ItemID], undoManager: UndoManager?) -> Bool {
        guard let item = item(id), item.isEditable, let end = fieldEnd(field), Set(targetIDs).count == targetIDs.count
        else { return false }
        let cantChange = String(localized: "Can’t Change This Relationship")
        let holds = end.isInverse ? end.info.reverseCardinality : end.info.cardinality
        if holds == .one, targetIDs.count > 1 {
            failure = (cantChange, String(localized: "Only one item can be chosen here."))
            return false
        }
        let current = others(of: id, end)
        var removing = current.filter { !targetIDs.contains($0) }.map { draft(id, $0, end) }
        var adding: [EdgeDraft] = []
        for other in targetIDs where !current.contains(other) {
            let link = draft(id, other, end)
            let farType: TypeID? = self.item(other).flatMap { $0.state == .trashed ? nil : $0.type }
            let sourceType: TypeID? = end.atTarget ? farType : item.type
            let targetType: TypeID? = end.atTarget ? item.type : farType
            if let problem = linkProblem(link, sourceType: sourceType, targetType: targetType) {
                failure = (cantChange, problem)
                return false
            }
            let farEnd = FieldEnd(info: end.info, atTarget: !end.atTarget, isInverse: !end.isInverse)
            let farHolds = end.isInverse ? end.info.cardinality : end.info.reverseCardinality
            let taken = others(of: other, farEnd).filter { $0 != id }
            if farHolds == .one, !taken.isEmpty {
                guard end.isInverse else {
                    failure = (cantChange, String(localized: "The item chosen is already linked this way, and can be only once."))
                    return false
                }
                removing += taken.map { draft(other, $0, farEnd) }
            }
            adding.append(link)
        }
        guard !removing.isEmpty || !adding.isEmpty else { return true }
        relink(adding: adding, removing: removing, name: String(localized: "Edit Relationship"), undoManager: undoManager)
        return true
    }

    /// Removals go first, so an end that holds one edge is free before the new one arrives.
    private func relink(adding: [EdgeDraft], removing: [EdgeDraft], name: String, undoManager: UndoManager?) {
        let title = String(localized: "Can’t Change This Relationship")
        for draft in removing {
            if let link = index.link(type: draft.type, source: draft.source, target: draft.target) {
                submit(.unlink(link.id), failing: title)
            }
        }
        for draft in adding { submit(.link(draft, undoing: nil), failing: title) }
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.relink(adding: removing, removing: adding, name: name, undoManager: undoManager)
        }
    }
}
