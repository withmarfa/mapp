import Foundation
import Marfa

/// The one place the source changes what it holds. Writes, the copy's changes and refreshes arrive on one stream
/// and are taken one at a time, so a re-read never lands behind an older one.
actor MarfaEngine {
    nonisolated enum Event: Sendable {
        case paint
        case refresh
        case write(ItemWrite, WriteID)
        case change(Marfa.Change)
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

    /// One slice, the library tier. Marfa is to hold both tiers in one copy; the feed then joins this slice, never a
    /// second store.
    private static let tier = Marfa.Tier.library

    private let copy: WorkingCopy
    private let hub: MarfaHub
    private var catalogue = Catalogue()
    private var rows: [String: Marfa.Item] = [:]
    private var edges: [String: Marfa.Edge] = [:]
    private var items: [ItemID: Item] = [:]
    private var bodies: [ItemID: Int] = [:]
    private var places: [Place] = []
    private var sync: [ItemID: SyncState] = [:]
    /// Conflicts the queue forgets once answered, kept until a later edit of the item is taken.
    private var conflicts: [ItemID: SyncState] = [:]
    /// The app's write for each queued write it made, until every one of them is answered.
    private var submitted: [String: WriteID] = [:]
    private var outstanding: [WriteID: Set<String>] = [:]
    private var outcomes: [WriteID: WriteOutcome] = [:]
    private var following: Task<Void, Never>?
    private var painted = false
    private var closed = false

    init(copy: WorkingCopy, hub: MarfaHub) {
        self.copy = copy
        self.hub = hub
    }

    func run(_ events: AsyncStream<Event>) async {
        // The copy's changes join the same line as everything else.
        let (merged, input) = AsyncStream<Event>.makeStream()
        let forward = Task {
            for await event in events { input.yield(event) }
            input.finish()
        }
        self.input = input
        for await event in merged {
            if closed {
                if case .flush(let done) = event { done.resume() }
                if case .close(let done) = event { done.resume() }
                continue
            }
            switch event {
            case .paint: await paint()
            case .refresh: await refresh()
            case .write(let write, let id): await perform(write, as: id)
            case .change(let change): await handle(change)
            case .flush(let done):
                await drain()
                done.resume()
            case .close(let done):
                closed = true
                following?.cancel()
                await copy.close()
                hub.finish()
                input.finish()
                done.resume()
            }
        }
        forward.cancel()
    }

    private var input: AsyncStream<Event>.Continuation?

    // MARK: Reading

    /// Everything the copy holds, before any network: the first `.loaded`. Following the server starts after it.
    private func paint() async {
        await reload()
        guard following == nil, let input else { return }
        let changes = copy.changes()
        following = Task {
            for await change in changes { input.yield(.change(change)) }
        }
    }

    /// Reads the catalogue, every row in every state, their edges and the queue, and publishes what differs.
    private func reload() async {
        do {
            catalogue = try await MarfaMapping.catalogue(
                itemTypes: copy.catalog.itemTypes(), edgeTypes: copy.catalog.edgeTypes())
        } catch {
            // A copy without a catalogue yet still shows what it holds.
        }
        var rows: [String: Marfa.Item] = [:]
        var edges: [String: Marfa.Edge] = [:]
        do {
            for row in try await copy.items.list(ListFilters(allStates: true)) { rows[row.id] = row }
            for type in catalogue.edgeTypes.keys {
                for edge in try await copy.edges.ofType(type) { edges[edge.id] = edge }
            }
        } catch {
            // An interrupted or expired hydration answers no reads until the next one; show nothing until then.
            rows = [:]
            edges = [:]
        }
        self.rows = rows
        self.edges = edges
        await readQueue()
        publish(Set(items.keys).union(rows.keys.map { ItemID($0) }), catalogueChanged: true)
    }

    /// Reads again the rows a change names, with every edge they hold or are held by.
    private func reread(_ ids: Set<String>) async {
        var affected = Set(ids.map { ItemID($0) })
        for id in ids {
            do {
                var row = try await copy.items.get(id)
                if row == nil {
                    row = try await copy.items.list(ListFilters(state: .trashed)).first { $0.id == id }
                }
                rows[id] = row
                var held: [Marfa.Edge] = []
                if row != nil { held = try await copy.edges.from(id) + copy.edges.to(id) }
                let before = edges.values.filter { $0.sourceId == id || $0.targetId == id }
                for edge in before { edges[edge.id] = nil }
                for edge in held { edges[edge.id] = edge }
                for edge in before + held {
                    affected.insert(ItemID(edge.sourceId))
                    affected.insert(ItemID(edge.targetId))
                }
            } catch {
                await reload()
                return
            }
        }
        await readQueue()
        publish(affected)
    }

    private func readQueue() async {
        let queue = (try? await copy.queue.all()) ?? []
        let sync = MarfaMapping.syncStates(queue: queue, conflicts: conflicts)
        let changed = Set(sync.keys).union(self.sync.keys).filter { sync[$0] != self.sync[$0] }
        self.sync = sync
        pendingSync.formUnion(changed)
    }

    private var pendingSync: Set<ItemID> = []

    /// Maps `ids` again and tells readers what differs: the first time, everything as `.loaded`.
    private func publish(_ ids: Set<ItemID>, catalogueChanged: Bool = false) {
        let ids = ids.union(pendingSync)
        pendingSync = []
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
            let held = edges.values.filter { $0.sourceId == row.id || $0.targetId == row.id }
                .sorted { $0.createdAt < $1.createdAt }
            let item = MarfaMapping.item(
                row, edges: held, catalogue: catalogue, sync: sync[id] ?? .settled,
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
        guard painted else {
            painted = true
            self.places = places
            let ordered = items.values.sorted { $0.created > $1.created }
            hub.publish(.loaded(SourceSnapshot(items: ordered, catalogue: catalogue, places: places)))
            return
        }
        if !removed.isEmpty { hub.publish(.removed(removed)) }
        if !upserted.isEmpty { hub.publish(.upserted(upserted)) }
        for (id, version) in bodyChanged { hub.publish(.bodyChanged(id, version)) }
        if places != self.places {
            self.places = places
            hub.publish(.places(places))
        }
    }

    // MARK: The server

    private func refresh() async {
        if hub.connection != .online { hub.set(.connecting) }
        do {
            let status = try await copy.status()
            if status.hydration == .complete {
                _ = try await copy.catchUp()
                if Set(MarfaMapping.namespaces(of: try await currentCatalogue())) != Set(status.sliceTypes) {
                    try await hydrate()
                }
            } else {
                try await hydrate()
            }
            hub.set(.online)
            await reload()
            await drain()
        } catch let error as MarfaError {
            await failed(error)
        } catch {
            hub.set(.stopped(code: "failed", message: error.localizedDescription))
        }
    }

    /// A new copy holds only Marfa's built-in types, so its first slice is theirs; the server's catalogue then
    /// names every namespace, and the copy is hydrated again with them all.
    private func hydrate() async throws {
        var slice = MarfaMapping.namespaces(of: try await currentCatalogue())
        for _ in 0..<2 {
            _ = try await copy.hydrate(types: slice, tier: Self.tier)
            let wanted = MarfaMapping.namespaces(of: try await currentCatalogue())
            if Set(wanted) == Set(slice) { break }
            slice = wanted
        }
    }

    private func currentCatalogue() async throws -> Catalogue {
        try await MarfaMapping.catalogue(itemTypes: copy.catalog.itemTypes(), edgeTypes: copy.catalog.edgeTypes())
    }

    private func failed(_ error: MarfaError) async {
        switch error {
        case .network, .io, .unnamed, .redirected, .rateLimited:
            hub.set(.offline(reason: error.message))
        case .unauthorized, .forbidden, .signedOut:
            hub.set(.stopped(code: error.code(), message: error.message))
            hub.publish(.unavailable(SourceFailure(kind: .denied, message: error.message)))
        case .copyExpired:
            // The server asks for a new hydration, which keeps the queue.
            do {
                try await hydrate()
                hub.set(.online)
                await reload()
            } catch let error as MarfaError {
                hub.set(.stopped(code: error.code(), message: error.message))
            } catch {
                hub.set(.stopped(code: "failed", message: error.localizedDescription))
            }
        default:
            hub.set(.stopped(code: error.code(), message: error.message))
        }
    }

    private func handle(_ change: Marfa.Change) async {
        switch change.origin {
        // This engine makes every local write and every drain, and re-reads after each.
        case .local, .answered, .refreshed(.drained): break
        case .server(let event, _):
            switch event {
            case "server.reachable":
                hub.set(.online)
                await drain()
            case "server.unreachable":
                hub.set(.offline(reason: change.reason))
            default:
                if hub.connection != .online { hub.set(.online) }
                await reread(change)
            }
        case .saved, .refreshed: await reload()
        case .stopped(let error): await failed(error)
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
            let queued = try await queue(write)
            outstanding[id] = Set(queued.map(\.id))
            for written in queued { submitted[written.id] = id }
            await reread(Set(queued.flatMap { [$0.itemId, $0.targetId].compactMap(\.self) }))
            await drain()
        } catch let error as NotYet {
            hub.publish(.answered(id, .refused(SyncProblem(code: "unsupported", message: error.message))))
        } catch let error as MarfaError {
            // Refused before it was queued, such as a property the type does not allow: nothing is waiting.
            hub.publish(.answered(id, .refused(SyncProblem(code: error.code(), message: error.message))))
        } catch {
            hub.publish(.answered(id, .refused(SyncProblem(code: "failed", message: error.localizedDescription))))
        }
    }

    private func queue(_ write: ItemWrite) async throws -> [Marfa.QueuedWrite] {
        switch write {
        case .create(_, let draft):
            return try await create(draft)
        case .editBody(let id, let text, let base, let merge):
            guard let bodyField = catalogue.itemTypes[try itemType(of: id)]?.bodyField else {
                throw NotYet(message: String(localized: "This kind of item has no text to edit."))
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

    /// The core mints the id, since the server refuses ids that are not lowercase UUIDv7 and a refused create
    /// leaves a row the queue cannot discard; the app's id for the draft is not used yet.
    private func create(_ draft: ItemDraft) async throws -> [Marfa.QueuedWrite] {
        let info = catalogue.itemTypes[draft.type]
        var properties = draft.properties.mapValues(MarfaMapping.json)
        var body = draft.body
        if let titleField = MarfaMapping.titleField(of: info) {
            properties[titleField] = .string(draft.title)
        } else if !draft.title.isEmpty {
            body = body.isEmpty ? draft.title : draft.title + "\n\n" + body
        }
        if let bodyField = info?.bodyField, !body.isEmpty { properties[bodyField] = .string(body) }
        let created = try await copy.items.create(
            Draft(
                type: draft.type.rawValue, properties: properties, tags: draft.tags.sorted(),
                tier: draft.tier.map(MarfaMapping.marfaTier)))
        guard let parent = draft.parent, let child = created.itemId else { return [created] }
        let edge = try await copy.edges.create(from: parent.rawValue, to: child, type: MarfaMapping.parentEdge)
        return [created, edge]
    }

    /// An edit read at the version the copy holds is an ordinary update; one read earlier is merged by the server
    /// against what was read, where the editor allows that.
    private func edit(
        _ id: ItemID, _ properties: [String: JSONValue], base: ItemVersion, merge: BodyMerge
    ) async throws -> Marfa.QueuedWrite {
        let edit = Edit(properties: properties, baseVersion: base.rawValue)
        if merge == .asRead, let held = rows[id.rawValue]?.version, base.rawValue < held {
            return try await copy.items.updateAsRead(id.rawValue, edit)
        }
        return try await copy.items.update(id.rawValue, edit)
    }

    private func itemType(of id: ItemID) throws -> TypeID {
        guard let row = rows[id.rawValue] else {
            throw MarfaError.notFound(code: "item_not_found", message: String(localized: "This item isn’t in the library."))
        }
        return TypeID(row.type)
    }

    /// Sends the queue once, tells each verdict to the app's write, and only then forgets the answered writes, so a
    /// refused one is never cleared unseen. Refused writes that carried content stay queued until discarded.
    private func drain() async {
        if case .offline = hub.connection { return }
        do {
            let report = try await copy.queue.drain()
            for answer in report.verdicts {
                guard let verdict = answer.verdict, let outcome = MarfaMapping.outcome(verdict) else { continue }
                if let itemID = answer.itemId {
                    let item = ItemID(itemID)
                    switch outcome {
                    case .conflicted: conflicts[item] = outcome.syncState
                    case .accepted where answer.kind == .updateItem, .merged where answer.kind == .updateItem:
                        conflicts[item] = nil
                    default: break
                    }
                }
                answered(answer.id, outcome)
            }
            if let reason = report.unavailable, report.answered == 0, report.undelivered > 0 {
                hub.set(.offline(reason: reason))
            }
            _ = try await copy.queue.forgetAnswered()
            if !report.verdicts.isEmpty { await reload() }
        } catch let error as MarfaError {
            switch error {
            // A copy never hydrated cannot send yet; its writes wait for the first hydration.
            case .hydrationIncomplete, .noCursor: break
            default: await failed(error)
            }
        } catch {
            hub.set(.stopped(code: "failed", message: error.localizedDescription))
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
