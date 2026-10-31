import Foundation
import Marfa

/// Making the app's writes in the copy's queue.
extension MarfaEngine {
    /// True where the write belongs to an undo or a redo (`group`) and the copy refused it for being brought up to
    /// date, so it is held (`MarfaEngine+Holding`) and has no answer yet. `standing` is how the held write found what it
    /// touches when it was first made, which a later try keeps.
    @discardableResult
    func perform(_ write: ItemWrite, as id: WriteID, holding group: UndoGroup? = nil, standing: Stand? = nil) async -> Bool {
        if case .purge(let item, let version) = write {
            purge(item, at: version, as: id)
            return false
        }
        if let group, standing == nil, !held.isEmpty {
            // The copy is still refusing an earlier undo or redo. This write waits behind it unattempted, since the
            // package queues an item's edit at once but refuses a link's, and made first it would be made out of order.
            await hold(write, as: id, in: group, standing: nil)
            return true
        }
        do {
            #if DEBUG
            if let error = hooks.refusing.current?(write) { throw error }
            #endif
            var touched: Set<String>
            if case .create(let itemID, let draft) = write {
                let created = try await Self.asking(hub) { try await create(itemID, draft) }
                record(id, [created])
                touched = [itemID.rawValue]
                if let parent = draft.parent {
                    await place(itemID, under: parent)
                    touched.insert(parent.rawValue)
                }
            } else {
                // An edge's ends are read before it goes, since its delete names only the edge, and a move names
                // only the end it goes to.
                var ends: Set<String> = []
                switch write {
                case .unlink(let edgeID):
                    if let edge = edges[edgeID.rawValue] { ends = [edge.sourceId, edge.targetId] }
                case .moveEdge(let edgeID, _, let to):
                    ends = [to.rawValue]
                    if let edge = edges[edgeID.rawValue] { ends.formUnion([edge.sourceId, edge.targetId]) }
                default: break
                }
                let queued = try await Self.asking(hub) { try await queue(write) }
                record(id, queued)
                if case .moveEdge = write { for written in queued { movedEnds[written.id] = ends } }
                touched = ends.union(queued.flatMap { [$0.itemId, $0.targetId].compactMap(\.self) })
            }
            await reread(touched)
            hub.publish(.taken(id))
            await sync.drain()
        } catch let error as Unsupported {
            hub.publish(.answered(id, .refused(SyncProblem(code: "unsupported", message: error.message, notQueued: true))))
        } catch let error as Refused {
            var problem = error.problem
            problem.notQueued = true
            hub.publish(.answered(id, .refused(problem)))
        } catch let error as MarfaError {
            if let group, Self.isBeingBroughtUpToDate(error) {
                await hold(write, as: id, in: group, standing: standing)
                return true
            }
            // Refused before it was queued, such as a property the type does not allow: nothing is waiting.
            var problem = Self.problem(for: error)
            problem.notQueued = true
            hub.publish(.answered(id, .refused(problem)))
            switch error {
            case .hydrationIncomplete, .copyExpired: await sync.refresh()
            default: break
            }
        } catch {
            hub.publish(.answered(id, .refused(SyncProblem(code: "failed", message: error.localizedDescription, notQueued: true))))
        }
        return false
    }

    /// An unavailable row or an edge write can need a complete copy. The app keeps any text it tried to save.
    nonisolated static func problem(for error: MarfaError) -> SyncProblem {
        switch error {
        case .hydrationIncomplete, .copyExpired: SyncProblem(code: error.code(), message: notCurrent)
        default: SyncProblem(code: refusalCode(of: error), message: error.message)
        }
    }

    /// The server's code for a refusal, as a drain's verdict names it, where the package refused a write the same way
    /// before queueing it; `code()` names only the kind of error, such as `forbidden` for `type_not_permitted`.
    nonisolated static func refusalCode(of error: MarfaError) -> String {
        switch error {
        case .notFound(let code, _), .unauthorized(let code, _), .forbidden(let code, _), .validation(let code, _),
            .rateLimited(let code, _, _), .server(_, let code, _):
            code
        default:
            error.code()
        }
    }

    /// What the package refuses a move for before it queues anything, in the person's words: a self-loop, or a
    /// type whose end that stays can hold more than one edge. Anything else is the package's own.
    nonisolated static func moveProblem(_ error: MarfaError) -> SyncProblem? {
        guard case .validation(let code, _) = error else { return nil }
        switch code {
        case "edge_cycle":
            return SyncProblem(code: code, message: String(localized: "An item can’t be linked to itself."))
        case "validation_error":
            return SyncProblem(
                code: code,
                message: String(localized: "This link can’t be replaced by moving one end, because the item that stays can hold more than one."))
        default:
            return nil
        }
    }

    /// A write that needed nothing queued, such as a move to the end the edge already holds, is taken at once.
    private func record(_ id: WriteID, _ queued: [Marfa.QueuedWrite]) {
        guard !queued.isEmpty else { return hub.publish(.answered(id, .accepted)) }
        writes.record(id, queued: queued.map(\.id))
    }

    private func queue(_ write: ItemWrite) async throws -> [Marfa.QueuedWrite] {
        switch write {
        case .create:
            preconditionFailure("a create is queued by perform(_:as:)")
        case .editBody(let id, let text, let base, let merge):
            guard let bodyField = MarfaMapping.bodyField(of: catalogue.itemTypes[try itemType(of: id)]) else {
                throw Unsupported(message: Self.noText)
            }
            let properties = JSONObject([(bodyField, .string(text))])
            // Read before the edit is sent: an answer that lands during the send is not in the version it was sent
            // on, so it is counted later, as it comes.
            let answeredBefore = merge == .following && ownText[id] != nil ? [] : try await answeredWrites(of: id)
            let queued: Marfa.QueuedWrite
            switch merge {
            case .ifUnchanged:
                queued = try await copy.items.update(id.rawValue, Edit(properties: properties, baseVersion: base.rawValue))
            case .asRead:
                queued = try await send(id, properties) { base.rawValue }
            case .following:
                queued = try await send(id, properties) { try await self.followingVersion(id, otherwise: base) }
            }
            ownText[id] = OwnText(text: text, on: queued.baseVersion ?? base.rawValue)
            // A following edit counted the answers it saw as it chose its version (`followingVersion`).
            counted.formUnion(answeredBefore)
            return [queued]
        case .editProperties(let id, let changes, let base, _):
            let (properties, replacing) = try Self.propertyEdit(changes, of: rows[id.rawValue])
            return [try await send(id, properties, replacing: replacing) { base.rawValue }]
        case .retype(let id, let type, let changes, let base):
            let (properties, replacing) = try Self.propertyEdit(changes, of: rows[id.rawValue])
            return [try await send(id, properties, replacing: replacing, type: type.rawValue) { base.rawValue }]
        case .retier(let id, let tier, let base):
            return [try await send(id, JSONObject(), tier: MarfaMapping.marfaTier(tier)) { base.rawValue }]
        case .tag(let id, let tag, let on):
            return [
                on ? try await copy.tags.add(tag, to: id.rawValue) : try await copy.tags.remove(tag, from: id.rawValue)
            ]
        case .transition(let id, let state):
            switch state {
            case .trashed: return [try await copy.items.delete(id.rawValue)]
            case .active where rows[id.rawValue]?.state == .trashed || rows[id.rawValue] == nil:
                // A row the copy lets go of after its delete is answered is restored by its id, and shown nowhere
                // until the server answers.
                let row = binned[id.rawValue]
                let queued = try await copy.items.restore(id.rawValue)
                if let row {
                    binned[id.rawValue] = nil
                    restoring[id.rawValue] = row
                }
                return [queued]
            case .active, .archived:
                return [try await copy.items.transition(id.rawValue, to: MarfaMapping.marfaState(state))]
            }
        case .link(let draft, _):
            return [
                try await copy.edges.create(
                    from: draft.source.rawValue, to: draft.target.rawValue, type: draft.type,
                    properties: draft.position.map { [MarfaMapping.positionProperty: .number($0)] } ?? [:])
            ]
        case .unlink(let edgeID):
            return [try await copy.edges.delete(edgeID.rawValue)]
        case .moveEdge(let edgeID, let end, let to):
            guard let edge = edges[edgeID.rawValue] else {
                throw MarfaError.notFound(code: "edge_not_found", message: String(localized: "This link isn’t in the library."))
            }
            let move: EdgeEdit.Move = end == .source ? .source(to.rawValue) : .target(to.rawValue)
            do {
                // The copy's own version of the edge, since the move is refused on any other; an edge it shows
                // moved by a move still waiting is read from its new ends.
                let held = try await heldEdge(edge)
                // The edge is already there, as when an undo follows a refused move: the package queues nothing.
                return try await copy.edges.update(edge.id, EdgeEdit(baseVersion: held.version, move: move)).map { [$0] } ?? []
            } catch let error as MarfaError {
                if let problem = Self.moveProblem(error) { throw Refused(problem: problem) }
                throw error
            }
        case .purge:
            preconditionFailure("a purge is made at the server by perform(_:as:)")
        }
    }

    /// The item keeps the id the app minted, a lowercase UUIDv7 as the server requires. A body for a type with
    /// no body field is refused rather than dropped.
    private func create(_ id: ItemID, _ draft: ItemDraft) async throws -> Marfa.QueuedWrite {
        let properties = try Self.creationProperties(draft, catalogue: catalogue)
        return try await copy.items.create(
            Draft(
                type: draft.type.rawValue, properties: properties, tags: draft.tags.sorted(),
                tier: draft.tier.map(MarfaMapping.marfaTier), id: id.rawValue))
    }

    /// The create is already queued and answered on its own, so a parent that cannot be linked is told apart and
    /// trying the create again makes no second item.
    func place(_ child: ItemID, under parent: ItemID) async {
        do {
            _ = try await Self.asking(hub) {
                try await copy.edges.create(from: parent.rawValue, to: child.rawValue, type: MarfaMapping.parentEdge)
            }
        } catch {
            let reason = Self.failure(error).message
            failures.append(SourceFailure(
                kind: .failed, message: String(localized: "The item was made, but it couldn’t be put under its parent: \(reason)")))
        }
    }

    /// Destroys an item in the bin at the server, which the package does only at once and only for an item whose
    /// writes have all been sent, so the writes submitted before it go first. It runs beside the engine, which
    /// takes no call to the server, and its verdict arrives as an event. The copy and the bin follow from the
    /// copy's own word that the item was purged.
    private func purge(_ id: ItemID, at version: ItemVersion, as write: WriteID) {
        Task { [copy, hub, sync, tell] in
            await sync.flush()
            let outcome: WriteOutcome
            do {
                try await Self.asking(hub) { try await copy.items.purge(id.rawValue, version: version.rawValue) }
                outcome = .accepted
            } catch let error as MarfaError {
                outcome = .refused(Self.problem(for: error))
            } catch {
                outcome = .refused(SyncProblem(code: "failed", message: error.localizedDescription))
            }
            _ = tell(.answer(write, outcome))
        }
    }

    private func heldEdge(_ edge: Marfa.Edge) async throws -> Marfa.Edge {
        if let held = try await copy.edges.from(edge.sourceId).first(where: { $0.id == edge.id }) { return held }
        if let held = try await copy.edges.to(edge.targetId).first(where: { $0.id == edge.id }) { return held }
        if let held = try await copy.edges.ofType(edge.edgeType).first(where: { $0.id == edge.id }) { return held }
        throw MarfaError.notFound(code: "edge_not_found", message: String(localized: "This link isn’t in the library."))
    }

    private func itemType(of id: ItemID) throws -> TypeID {
        guard let row = rows[id.rawValue] else {
            throw MarfaError.notFound(code: "item_not_found", message: String(localized: "This item isn’t in the library."))
        }
        return TypeID(row.type)
    }
}
