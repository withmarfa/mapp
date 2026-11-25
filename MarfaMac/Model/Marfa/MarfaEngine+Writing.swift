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
                let created = try await Self.asking { try await create(itemID, draft) }
                record(id, [created])
                touched = [itemID.rawValue]
                if let parent = draft.parent {
                    await place(itemID, under: parent)
                    touched.insert(parent.rawValue)
                }
            } else {
                // An edge's delete names only the edge, and a move only the end it goes to, so the ends come from
                // the write, which the copy showed them at when it was judged.
                var ends: Set<String> = []
                switch write {
                case .unlink(let draft): ends = [draft.from.rawValue, draft.to.rawValue]
                case .moveEdge(_, _, let to, let from, let stays): ends = [to.rawValue, from.rawValue, stays.rawValue]
                default: break
                }
                let queued = try await Self.asking { try await queue(write) }
                record(id, queued)
                if group == nil { giveBackHeld(overtakenBy: write) }
                if case .moveEdge = write { for written in queued { movedEnds[written.id] = ends } }
                touched = ends.union(queued.flatMap { [$0.itemId, $0.toId].compactMap(\.self) })
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
        case .notFound(let code, _, _), .unauthorized(let code, _, _), .forbidden(let code, _, _),
            .validation(let code, _, _, _), .rateLimited(let code, _, _, _), .server(_, let code, _, _, _):
            code
        default:
            error.code()
        }
    }

    /// What the package refuses a move for before it queues anything, in the person's words: a self-loop, or a
    /// type whose end that stays can hold more than one edge. Anything else is the package's own.
    nonisolated static func moveProblem(_ error: MarfaError) -> SyncProblem? {
        guard case .validation(let code, _, _, _) = error else { return nil }
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

    private func record(_ id: WriteID, _ queued: [Marfa.QueuedWrite]) {
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
            // What proves a version holds the person's text proves it for one property (`OwnText`), so after a
            // retype that moved the text, the save goes as read.
            let follows = merge == .following && ownText[id]?.field == bodyField
            // Read before the edit is sent: an answer that lands during the send is not in the version it was sent
            // on, so it is counted later, as it comes.
            let answeredBefore = follows ? [] : try await answeredWrites(of: id)
            let queued: Marfa.QueuedWrite
            switch merge {
            case .ifUnchanged:
                queued = try await copy.items.update(id.rawValue, Edit(properties: properties, baseVersion: base.rawValue))
            case .following where follows:
                queued = try await send(id, properties) { try await self.followingVersion(id, otherwise: base) }
            case .asRead, .following:
                queued = try await send(id, properties) { base.rawValue }
            }
            var on = queued.baseVersion ?? base.rawValue
            // An answer counted while the save was sent proves a version of the person's text this save follows too.
            if follows, let own = ownText[id], own.field == bodyField { on = max(on, own.on) }
            ownText[id] = OwnText(text: text, field: bodyField, on: on)
            // A following edit counted the answers it saw as it chose its version (`followingVersion`).
            counted.formUnion(answeredBefore)
            return [queued]
        case .editProperties(let id, let changes, let base):
            let (properties, clearing) = Self.propertyEdit(changes)
            return [try await send(id, properties, clearing: clearing) { base.rawValue }]
        case .retype(let id, let type, let changes, let base):
            let (properties, clearing) = Self.propertyEdit(changes)
            return [try await send(id, properties, clearing: clearing, type: type.rawValue) { base.rawValue }]
        case .retier(let id, let tier, let base):
            try await judge(id, tier: tier == .library ? .feed : .library)
            return [try await send(id, JSONObject(), tier: MarfaMapping.marfaTier(tier)) { base.rawValue }]
        case .tag(let id, let tag, let on):
            return [
                on ? try await copy.tags.add(tag, to: id.rawValue) : try await copy.tags.remove(tag, from: id.rawValue)
            ]
        case .transition(let id, let state, let from):
            try await judge(id, state: from)
            if state == .trashed { return [try await copy.items.delete(id.rawValue)] }
            return [try await copy.items.transition(id.rawValue, to: MarfaMapping.marfaState(state))]
        case .restore(let id):
            // A row the copy does not hold, as one the slice let go, is restored by its id and shown nowhere until
            // the server answers.
            try await judge(id, state: .trashed)
            return [try await copy.items.restore(id.rawValue)]
        case .link(let draft):
            try await judge(edge: write)
            return [
                try await copy.edges.create(
                    from: draft.from.rawValue, to: draft.to.rawValue, type: draft.type,
                    properties: draft.position.map { [MarfaMapping.positionProperty: .number($0)] } ?? [:],
                    id: draft.id?.rawValue)
            ]
        case .unlink:
            guard let held = try await judge(edge: write) else { throw Self.skipped(.changedSince) }
            return [try await copy.edges.delete(held.id)]
        case .moveEdge(_, let end, let to, _, _):
            guard let held = try await judge(edge: write) else { throw Self.skipped(.changedSince) }
            let move: EdgeEdit.Move = end == .from ? .from(to.rawValue) : .to(to.rawValue)
            do {
                // On the copy's own version of the edge, since the move is refused on any other. A move to the end
                // the edge already holds queues nothing, so it is skipped and releases no removal waiting on it.
                guard let queued = try await copy.edges.update(held.id, EdgeEdit(baseVersion: held.version, move: move)) else {
                    throw Self.skipped(.changedSince)
                }
                return [queued]
            } catch let error as MarfaError {
                if let problem = Self.moveProblem(error) { throw Refused(problem: problem) }
                throw error
            }
        case .purge:
            preconditionFailure("a purge is made at the server by perform(_:as:)")
        }
    }

    /// The one rule for every write of a state or a tier, Undo and Redo among them: it is queued only while the copy,
    /// with the writes queued before it, shows the item as the command or step that sends it left it, in `state` and
    /// `tier` where given and out of Recently Deleted unless `state` is. Otherwise it is skipped (`skipped(_:)`), never
    /// taken, so nothing follows it. Marfa takes a transition with no state it expects (withmarfa/marfa#3523) and a tier
    /// with `conflict=auto`, so a change the copy has not yet learned of is still written over. A row the copy does not
    /// hold is left to the package.
    private func judge(_ id: ItemID, state: ItemState? = nil, tier: Tier? = nil) async throws {
        // `get` of one id does not answer a row in the bin, so a binned item would pass as one the copy does not hold.
        guard let row = try await copy.items.get([id.rawValue], includingBin: true).rows.first else { return }
        let now = MarfaMapping.state(row.state)
        if now == .trashed, state != .trashed { throw Self.skipped(.inBin) }
        if let state, now != state { throw Self.skipped(.changedSince) }
        if let tier, (row.tier.map(MarfaMapping.tier) ?? .library) != tier { throw Self.skipped(.changedSince) }
    }

    /// Reads the copy before queueing, including for Undo and Redo. An edge keeps its ID when it moves, so an unlink
    /// or move checks both ends and returns the edge as read. An ID-only delete can race a change after this read.
    @discardableResult
    private func judge(edge write: ItemWrite) async throws -> Marfa.Edge? {
        switch write {
        case .link(let draft):
            let joined = try await copy.edges.from(draft.from.rawValue).contains {
                $0.edgeType == draft.type && $0.toId == draft.to.rawValue
            }
            if joined { throw Self.skipped(.changedSince) }
            return nil
        case .unlink(let draft):
            guard let id = draft.id, let held = try await heldEdge(id.rawValue, between: (draft.from, draft.to)),
                held.edgeType == draft.type
            else { throw Self.skipped(.changedSince) }
            return held
        case .moveEdge(let id, let end, _, let from, let stays):
            let ends = end == .from ? (from, stays) : (stays, from)
            guard let held = try await heldEdge(id.rawValue, between: ends) else { throw Self.skipped(.changedSince) }
            return held
        default:
            return nil
        }
    }

    /// The edge `id` as the copy holds it, unsent writes included, where it still runs between `ends`. The copy holds
    /// every edge going out from an item it holds, and one to it where its type was hydrated whole.
    private func heldEdge(_ id: String, between ends: (from: ItemID, to: ItemID)) async throws -> Marfa.Edge? {
        var held = try await copy.edges.from(ends.from.rawValue).first { $0.id == id }
        if held == nil { held = try await copy.edges.to(ends.to.rawValue).first { $0.id == id } }
        guard let held, held.fromId == ends.from.rawValue, held.toId == ends.to.rawValue else { return nil }
        return held
    }

    /// A write the engine did not queue because its item no longer stands as the step left it, told with the
    /// command's other skips (`MarfaLibrary.gatheringSkips`).
    nonisolated static func skipped(_ reason: BatchSkips.Reason) -> Refused {
        Refused(problem: SyncProblem(code: skipCodes[reason] ?? skippedCode, message: BatchSkips.sentence(reason, count: 1)))
    }

    /// Why a write answered `code` was skipped, where it was.
    nonisolated static func skipReason(_ code: String) -> BatchSkips.Reason? {
        skipCodes.first { $0.value == code }?.key
    }

    private nonisolated static let skippedCode = "skipped_changed_since"
    private nonisolated static let skipCodes: [BatchSkips.Reason: String] = [.changedSince: skippedCode, .inBin: "skipped_in_bin"]

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
    /// trying the create again makes no second item. The edge is judged like every other (`judge(edge:)`), and
    /// followed to the server's answer, which tells a later refusal too (`answer(_:)`).
    func place(_ child: ItemID, under parent: ItemID) async {
        let draft = EdgeDraft(type: MarfaMapping.parentEdge, from: parent, to: child)
        let link = ParentLink(child: child, parent: parent)
        do {
            let queued = try await Self.asking {
                try await judge(edge: .link(draft))
                return try await copy.edges.create(from: parent.rawValue, to: child.rawValue, type: draft.type)
            }
            parentLinks.keep(link, for: queued.id)
        } catch {
            let reason = (error as? Refused)?.problem.message ?? Self.failure(error).message
            refusedParentLinks.append(ParentRefusal(link: link, reason: reason, listed: false))
        }
    }

    /// What the person is told of a refused parent link: the item and its parent, by the names last published, and
    /// why.
    func notice(for refusal: ParentRefusal) -> SourceFailure {
        let told = hub.told([refusal.link.child, refusal.link.parent])
        let item = told[refusal.link.child].map { "“\($0.item.displayTitle)”" } ?? String(localized: "The new item")
        let parent = told[refusal.link.parent].map { "“\($0.item.displayTitle)”" } ?? String(localized: "its parent")
        let message = refusal.listed
            ? String(localized: "\(item) was added, but Marfa refused to put it under \(parent): \(refusal.reason) The link is also listed in Settings.")
            : String(localized: "\(item) was added, but it couldn’t be put under \(parent): \(refusal.reason)")
        return SourceFailure(kind: .failed, message: message, title: String(localized: "Can’t Put Item Under Its Parent"))
    }

    /// Destroys an item in the bin at the server, which the package does only at once and only for an item whose
    /// writes have all been sent, so the writes submitted before it go first. It runs beside the engine, which
    /// takes no call to the server, and its verdict arrives as an event. The copy and the bin follow from the
    /// copy's own word that the item was purged.
    private func purge(_ id: ItemID, at version: ItemVersion, as write: WriteID) {
        Task { [copy, sync, tell] in
            await sync.flush()
            let outcome: WriteOutcome
            do {
                try await Self.asking { try await copy.items.purge(id.rawValue, version: version.rawValue) }
                outcome = .accepted
            } catch let error as MarfaError {
                outcome = .refused(SyncProblem(code: Self.refusalCode(of: error), message: Words.message(for: error)))
            } catch {
                outcome = .refused(SyncProblem(code: "failed", message: Words.syncFailed))
            }
            _ = tell(.answer(write, outcome))
        }
    }

    private func itemType(of id: ItemID) throws -> TypeID {
        guard let row = rows[id.rawValue] else {
            throw MarfaError.notFound(code: "item_not_found", message: String(localized: "This item isn’t in the library."), server: nil)
        }
        return TypeID(row.type)
    }
}
