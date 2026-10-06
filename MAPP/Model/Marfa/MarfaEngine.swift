import Foundation
import Marfa

/// The one place the source changes what it holds. Writes, the copy's changes and the server's answers arrive on
/// one stream and are taken one at a time, so a re-read never lands behind an older one. Each step reads or writes
/// only the copy; the server is `MarfaSync`'s, so nothing here waits on the network.
actor MarfaEngine {
    nonisolated enum Event: Sendable {
        case paint
        case write(ItemWrite, WriteID)
        case change(Marfa.Change)
        case drained(DrainReport)
        case failed(SourceFailure)
        case flush(CheckedContinuation<Void, Never>)
        case close(CheckedContinuation<Void, Never>)
    }

    /// A write the package does not offer yet, or this source does not make yet.
    private nonisolated struct NotYet: Error {
        var message = MarfaEngine.notYet
    }

    nonisolated static var notYet: String {
        String(localized: "This change can’t be made in a Marfa library yet.")
    }

    nonisolated static var noText: String {
        String(localized: "This kind of item has no text to edit.")
    }

    let sync: MarfaSync
    private let copy: WorkingCopy
    private let hub: MarfaHub
    private let tell: @Sendable (Event) -> Void
    private var catalogue = Catalogue()
    private var rows: [String: Marfa.Item] = [:]
    private var edges: [String: Marfa.Edge] = [:]
    /// The edges touching each row, so mapping an item reads its own edges rather than every edge.
    private var edgesByItem: [String: Set<String>] = [:]
    private var queue: [Marfa.QueuedWrite] = []
    private var items: [ItemID: Item] = [:]
    private var bodies: [ItemID: Int] = [:]
    private var places: [Place] = []
    private var syncStates: [ItemID: SyncState] = [:]
    private var changedSync: Set<ItemID> = []
    /// Refusals and conflicts a drain answered, which the queue forgets unless the write carried content, kept until
    /// a later write of the same kind, or an edit, is accepted or merged.
    private var remembered: [ItemID: (state: SyncState, kind: WriteKind)] = [:]
    /// The app's write for each queued write it made, until every one of them is answered.
    private var submitted: [String: WriteID] = [:]
    private var outstanding: [WriteID: Set<String>] = [:]
    private var outcomes: [WriteID: WriteOutcome] = [:]
    private var failures: [SourceFailure] = []
    private var following: Task<Void, Never>?
    private var painted = false
    private var closed = false

    init(copy: WorkingCopy, hub: MarfaHub, tell: @escaping @Sendable (Event) -> Void) {
        self.copy = copy
        self.hub = hub
        self.tell = tell
        sync = MarfaSync(copy: copy, hub: hub, tell: tell)
    }

    func run(_ events: AsyncStream<Event>) async {
        for await event in events {
            if closed {
                if case .flush(let done) = event { done.resume() }
                if case .close(let done) = event { done.resume() }
                continue
            }
            switch event {
            case .paint: await paint()
            case .write(let write, let id): await perform(write, as: id)
            case .change(let change): await handle(change)
            case .drained(let report): await answer(report)
            case .failed(let failure):
                failures.append(failure)
                publish([])
            case .flush(let done):
                Task { [sync] in
                    await sync.flush()
                    done.resume()
                }
            case .close(let done):
                closed = true
                following?.cancel()
                await sync.stop()
                await copy.close()
                hub.finish()
                done.resume()
            }
        }
    }

    // MARK: Reading

    /// Everything the copy holds, before any network: the first `.loaded`. Following the server starts after it.
    private func paint() async {
        await reload()
        guard following == nil else { return }
        let changes = copy.changes()
        following = Task { [tell] in
            for await change in changes { tell(.change(change)) }
        }
        await sync.start()
    }

    /// Reads the catalogue, every row in every state, their edges and the queue, and publishes what differs. A
    /// copy that cannot be read keeps showing what it last held, and says why.
    private func reload() async {
        var rows: [String: Marfa.Item] = [:]
        var edges: [Marfa.Edge] = []
        let catalogue: Catalogue
        do {
            catalogue = try await MarfaMapping.catalogue(
                itemTypes: copy.catalog.itemTypes(), edgeTypes: copy.catalog.edgeTypes())
            for row in try await copy.items.list(ListFilters(allStates: true)) { rows[row.id] = row }
            for type in catalogue.edgeTypes.keys { edges += try await copy.edges.ofType(type) }
        } catch {
            failures.append(Self.failure(error))
            publish([])
            return
        }
        let gone = Set(self.rows.keys).subtracting(rows.keys)
        self.catalogue = catalogue
        self.rows = rows
        self.edges = [:]
        edgesByItem = [:]
        for edge in edges { insert(edge) }
        await readQueue()
        publish(Set(rows.keys).union(gone).map { ItemID($0) }, catalogueChanged: true)
    }

    /// Reads again the rows named, with every edge they hold or are held by.
    private func reread(_ ids: Set<String>) async {
        var affected = Set(ids)
        do {
            for id in ids {
                var row = try await copy.items.get(id)
                if row == nil {
                    row = try await copy.items.list(ListFilters(state: .trashed)).first { $0.id == id }
                }
                rows[id] = row
                let held = row == nil ? [] : try await copy.edges.from(id) + copy.edges.to(id)
                for edgeID in edgesByItem[id] ?? [] {
                    if let edge = remove(edgeID) { affected.formUnion([edge.sourceId, edge.targetId]) }
                }
                for edge in held {
                    insert(edge)
                    affected.formUnion([edge.sourceId, edge.targetId])
                }
            }
        } catch {
            failures.append(Self.failure(error))
        }
        await readQueue()
        publish(affected.map { ItemID($0) })
    }

    /// A queue that cannot be read leaves each item's sync as it was, rather than settling it.
    private func readQueue() async {
        do {
            queue = try await copy.queue.all()
        } catch {
            failures.append(Self.failure(error))
            return
        }
        let states = MarfaMapping.syncStates(queue: queue, remembered: remembered.mapValues(\.state))
        changedSync.formUnion(Set(states.keys).union(syncStates.keys).filter { states[$0] != syncStates[$0] })
        syncStates = states
    }

    private func insert(_ edge: Marfa.Edge) {
        edges[edge.id] = edge
        edgesByItem[edge.sourceId, default: []].insert(edge.id)
        edgesByItem[edge.targetId, default: []].insert(edge.id)
    }

    private func remove(_ id: String) -> Marfa.Edge? {
        guard let edge = edges.removeValue(forKey: id) else { return nil }
        edgesByItem[edge.sourceId]?.remove(id)
        edgesByItem[edge.targetId]?.remove(id)
        return edge
    }

    /// Maps `ids` again and tells readers what differs: the first time, everything as `.loaded`. Failures gathered
    /// on the way follow as `.unavailable`.
    private func publish(_ ids: some Sequence<ItemID>, catalogueChanged: Bool = false) {
        let ids = Set(ids).union(changedSync)
        changedSync = []
        if catalogueChanged, painted, hub.snapshot?.catalogue != catalogue { hub.publish(.catalogue(catalogue)) }
        var upserted: [Item] = []
        var removed: [ItemID] = []
        var bodyChanged: [(ItemID, ItemVersion)] = []
        for id in ids {
            guard let row = rows[id.rawValue] else {
                if items.removeValue(forKey: id) != nil { removed.append(id) }
                bodies[id] = nil
                continue
            }
            let held = (edgesByItem[row.id] ?? []).compactMap { edges[$0] }.sorted { $0.createdAt < $1.createdAt }
            let item = MarfaMapping.item(
                row, edges: held, catalogue: catalogue, sync: syncStates[id] ?? .settled,
                isHeld: { self.rows[$0] != nil })
            let body = MarfaMapping.body(of: row, catalogue: catalogue)?.hashValue ?? 0
            if let previous = bodies[id], previous != body { bodyChanged.append((id, item.version)) }
            bodies[id] = body
            if items[id] != item {
                items[id] = item
                upserted.append(item)
            }
        }
        let places = MarfaMapping.places(items: items.values, catalogue: catalogue)
        if !painted {
            painted = true
            self.places = places
            let ordered = items.values.sorted { $0.created > $1.created }
            hub.publish(.loaded(SourceSnapshot(items: ordered, catalogue: catalogue, places: places)))
        } else {
            if !removed.isEmpty { hub.publish(.removed(removed)) }
            if !upserted.isEmpty { hub.publish(.upserted(upserted)) }
            for (id, version) in bodyChanged { hub.publish(.bodyChanged(id, version)) }
            if places != self.places {
                self.places = places
                hub.publish(.places(places))
            }
        }
        for failure in failures { hub.publish(.unavailable(failure)) }
        failures = []
    }

    private static func failure(_ error: any Error) -> SourceFailure {
        if let failure = error as? SourceFailure { return failure }
        return SourceFailure(kind: .failed, message: (error as? MarfaError)?.message ?? error.localizedDescription)
    }

    private func handle(_ change: Marfa.Change) async {
        switch change.origin {
        // This engine makes every local write and hears every drain's answers from `MarfaSync`.
        case .local, .answered, .refreshed(.drained): break
        case .server(let event, _):
            switch event {
            case "server.reachable": await sync.reachable()
            case "server.unreachable": await sync.unreachable(change.reason)
            default:
                await sync.heard()
                await reread(change)
            }
        case .saved, .refreshed: await reload()
        case .stopped(let error): await sync.stopped(error)
        }
    }

    private func reread(_ change: Marfa.Change) async {
        var ids = Set(change.itemId.map { [$0] } ?? [])
        if let edgeID = change.edgeId {
            guard let edge = edges[edgeID] else {
                // An edge the copy did not hold names no item to read again.
                if ids.isEmpty { await reload() } else { await reread(ids) }
                return
            }
            ids.formUnion([edge.sourceId, edge.targetId])
        }
        if !ids.isEmpty { await reread(ids) }
    }

    // MARK: Writing

    private func perform(_ write: ItemWrite, as id: WriteID) async {
        do {
            var touched: Set<String>
            if case .create(let itemID, let draft) = write {
                let created = try await create(itemID, draft)
                record(id, [created])
                touched = [itemID.rawValue]
                if let parent = draft.parent {
                    await place(itemID, under: parent)
                    touched.insert(parent.rawValue)
                }
            } else {
                let queued = try await queue(write)
                record(id, queued)
                touched = Set(queued.flatMap { [$0.itemId, $0.targetId].compactMap(\.self) })
            }
            await reread(touched)
            await sync.drain()
        } catch let error as NotYet {
            hub.publish(.answered(id, .refused(SyncProblem(code: "unsupported", message: error.message))))
        } catch let error as MarfaError {
            // Refused before it was queued, such as a property the type does not allow: nothing is waiting.
            hub.publish(.answered(id, .refused(SyncProblem(code: error.code(), message: error.message))))
        } catch {
            hub.publish(.answered(id, .refused(SyncProblem(code: "failed", message: error.localizedDescription))))
        }
    }

    private func record(_ id: WriteID, _ queued: [Marfa.QueuedWrite]) {
        outstanding[id] = Set(queued.map(\.id))
        for written in queued { submitted[written.id] = id }
    }

    private func queue(_ write: ItemWrite) async throws -> [Marfa.QueuedWrite] {
        switch write {
        case .create:
            preconditionFailure("a create is queued by perform(_:as:)")
        case .editBody(let id, let text, let base, let merge):
            guard let bodyField = catalogue.itemTypes[try itemType(of: id)]?.bodyField else {
                throw NotYet(message: Self.noText)
            }
            return [try await edit(id, [bodyField: .string(text)], base: base, merge: merge)]
        case .editProperties(let id, let changes, let base, _):
            let properties = changes.mapValues { $0.map(MarfaMapping.json) ?? .null }
            return [try await edit(id, properties, base: base, merge: .asRead)]
        case .tag(let id, let tag, let on):
            return [
                on ? try await copy.tags.add(tag, to: id.rawValue) : try await copy.tags.remove(tag, from: id.rawValue)
            ]
        case .transition(let id, let state):
            switch state {
            case .trashed: return [try await copy.items.delete(id.rawValue)]
            case .active where rows[id.rawValue]?.state == .trashed:
                return [try await copy.items.restore(id.rawValue)]
            case .active, .archived:
                return [try await copy.items.transition(id.rawValue, to: MarfaMapping.marfaState(state))]
            }
        case .retype, .retier, .move, .purge, .link, .unlink, .attach, .place:
            throw NotYet()
        }
    }

    /// The item keeps the id the app minted, a lowercase UUIDv7 as the server requires. A body for a type with
    /// no body field is refused rather than dropped.
    private func create(_ id: ItemID, _ draft: ItemDraft) async throws -> Marfa.QueuedWrite {
        let info = catalogue.itemTypes[draft.type]
        var properties = draft.properties.mapValues(MarfaMapping.json)
        var body = draft.body
        if let titleField = MarfaMapping.titleField(of: info) {
            properties[titleField] = .string(draft.title)
        } else if !draft.title.isEmpty {
            body = body.isEmpty ? draft.title : draft.title + "\n\n" + body
        }
        if !body.isEmpty {
            guard let bodyField = info?.bodyField else { throw NotYet(message: Self.noText) }
            properties[bodyField] = .string(body)
        }
        return try await copy.items.create(
            Draft(
                type: draft.type.rawValue, properties: properties, tags: draft.tags.sorted(),
                tier: draft.tier.map(MarfaMapping.marfaTier), id: id.rawValue))
    }

    /// The create is already queued and answered on its own, so a parent that cannot be linked is told apart and
    /// trying the create again makes no second item.
    private func place(_ child: ItemID, under parent: ItemID) async {
        do {
            _ = try await copy.edges.create(from: parent.rawValue, to: child.rawValue, type: MarfaMapping.parentEdge)
        } catch {
            let reason = Self.failure(error).message
            failures.append(SourceFailure(
                kind: .failed, message: String(localized: "The item was made, but it couldn’t be put under its parent: \(reason)")))
        }
    }

    /// An edit read at the version the copy holds is an ordinary update; one read earlier is merged by the server
    /// against what was read. Behind an edit of the same row still waiting, it goes on the held version and is moved
    /// onto that edit's answer, since an edit said to be read earlier is never moved.
    private func edit(
        _ id: ItemID, _ properties: [String: JSONValue], base: ItemVersion, merge: BodyMerge
    ) async throws -> Marfa.QueuedWrite {
        if merge == .asRead, let held = rows[id.rawValue]?.version, base.rawValue < held {
            let waiting = queue.contains { $0.kind == .updateItem && $0.itemId == id.rawValue && $0.verdict == nil }
            if waiting { return try await copy.items.update(id.rawValue, Edit(properties: properties, baseVersion: held)) }
            return try await copy.items.updateAsRead(id.rawValue, Edit(properties: properties, baseVersion: base.rawValue))
        }
        return try await copy.items.update(id.rawValue, Edit(properties: properties, baseVersion: base.rawValue))
    }

    private func itemType(of id: ItemID) throws -> TypeID {
        guard let row = rows[id.rawValue] else {
            throw MarfaError.notFound(code: "item_not_found", message: String(localized: "This item isn’t in the library."))
        }
        return TypeID(row.type)
    }

    /// Tells each verdict to the app's write and shows it on its item while the queue still holds it, and only
    /// then forgets the answered writes, so no refusal is cleared unseen, whichever launch made the write. Refused
    /// writes that carried content stay queued until discarded.
    private func answer(_ report: DrainReport) async {
        var ids: Set<String> = []
        for answer in report.verdicts {
            guard let verdict = answer.verdict, let outcome = MarfaMapping.outcome(verdict) else { continue }
            if let itemID = answer.itemId {
                ids.insert(itemID)
                remember(outcome, of: answer.kind, for: ItemID(itemID))
            }
            if case .conflicted(let sibling, _) = outcome { ids.insert(sibling.rawValue) }
            answered(answer.id, outcome)
        }
        await reread(ids)
        do {
            _ = try await copy.queue.forgetAnswered()
        } catch {
            failures.append(Self.failure(error))
        }
        await readQueue()
        publish([])
    }

    private func remember(_ outcome: WriteOutcome, of kind: WriteKind, for item: ItemID) {
        switch outcome {
        case .refused, .conflicted:
            remembered[item] = (outcome.syncState, kind)
        case .accepted, .merged:
            if let held = remembered[item], held.kind == kind || kind == .updateItem { remembered[item] = nil }
        case .blocked, .dead:
            // The queue keeps these until they are released or withdrawn.
            break
        }
    }

    /// A write the app made as several queued writes is answered once, with the first answer that was not taken.
    private func answered(_ queued: String, _ outcome: WriteOutcome) {
        guard let id = submitted.removeValue(forKey: queued) else { return }
        if Self.weight(outcome) > outcomes[id].map(Self.weight) ?? -1 { outcomes[id] = outcome }
        outstanding[id]?.remove(queued)
        guard outstanding[id]?.isEmpty ?? true else { return }
        outstanding[id] = nil
        if let outcome = outcomes.removeValue(forKey: id) { hub.publish(.answered(id, outcome)) }
    }

    private static func weight(_ outcome: WriteOutcome) -> Int {
        switch outcome {
        case .accepted: 0
        case .merged: 1
        default: 2
        }
    }
}
