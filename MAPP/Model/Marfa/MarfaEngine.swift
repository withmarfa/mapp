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
        /// Resumed once the answers are taken and forgotten.
        case drained(DrainReport, CheckedContinuation<Void, Never>)
        case failed(SourceFailure)
        case flush(CheckedContinuation<Void, Never>)
        case close(CheckedContinuation<Void, Never>)
        /// Takes a refused write, and those refused only for it, out of the queue.
        case discard(String, CheckedContinuation<Result<Bool, SourceFailure>, Never>)
        /// Sends a stopped write again.
        case release(String, CheckedContinuation<Result<Bool, SourceFailure>, Never>)
        /// The writes not sent, read from the queue once every event before it is taken, so every write
        /// submitted before it counts; nil where the queue cannot be read.
        case unsent(CheckedContinuation<UnsentWrites?, Never>)
        /// Closes, as `close` does, only if every write not sent, read from the queue in the same step, is one
        /// of those agreed to; nil agrees to whatever the copy holds.
        case closeAgreeing(UnsentWrites?, CheckedContinuation<CloseOutcome, Never>)
    }

    /// A write the package does not offer yet, or this source does not make yet.
    private nonisolated struct NotYet: Error {
        var message = MarfaEngine.notYet
    }

    /// The person's latest edit of an item's text, and the version of the item their own writes account for: the
    /// version that edit was typed on, moved on by each answer to this device's writes of the item.
    private nonisolated struct OwnText {
        var text: String
        var on: Int64
    }

    nonisolated static var notYet: String {
        String(localized: "This change can’t be made in a Marfa library yet.")
    }

    nonisolated static var notCurrent: String {
        String(localized: "This library is being brought up to date. Try again in a moment.")
    }

    nonisolated static var noText: String {
        String(localized: "This kind of item has no text to edit.")
    }

    let sync: MarfaSync
    private let copy: WorkingCopy
    private let hub: MarfaHub
    private let tell: @Sendable (Event) -> Bool
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
    /// Refusals and conflicts answered, which the queue forgets unless the write carried content, kept until a later
    /// write of the same kind, or an edit, is accepted or merged. Answers already in the queue at launch, from a
    /// launch that closed before forgetting them, are taken in at the first read of the queue.
    private var remembered: [ItemID: (state: SyncState, kind: WriteKind)] = [:]
    private var readQueueOnce = false
    /// Until the queue is first read, nothing can be said of what waits.
    private var queueRead = false
    /// Refused writes as last read, kept once the queue forgets those that carried no content, so each stays
    /// before the person until they discard it or a later write of its kind lands.
    private var refusals: [String: Marfa.QueuedWrite] = [:]
    /// The item each conflicted copy was made from, as its verdict named it.
    private var originals: [String: String] = [:]
    /// The app's write for each queued write it made, until every one of them is answered.
    private var submitted: [String: WriteID] = [:]
    private var outstanding: [WriteID: Set<String>] = [:]
    private var outcomes: [WriteID: WriteOutcome] = [:]
    private var failures: [SourceFailure] = []
    /// The person's latest edit of each item's text, which their next edit of it follows.
    private var ownText: [ItemID: OwnText] = [:]
    /// Answered writes already taken into `ownText`, so none is counted twice.
    private var counted: Set<String> = []
    /// Edits queued as read on a version older than the copy held, whose answer lands on whatever the server held.
    private var sentAsRead: Set<String> = []
    private var following: Task<Void, Never>?
    private var painted = false
    private var closed = false
    /// Run before each drain's answers are taken, for the tests.
    private var answering: (@Sendable () async -> Void)?

    func whenAnswering(_ hook: (@Sendable () async -> Void)?) {
        answering = hook
    }

    init(copy: WorkingCopy, hub: MarfaHub, tell: @escaping @Sendable (Event) -> Bool) {
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
                if case .drained(_, let taken) = event { taken.resume() }
                if case .discard(_, let done) = event { done.resume(returning: .success(false)) }
                if case .release(_, let done) = event { done.resume(returning: .success(false)) }
                if case .unsent(let done) = event { done.resume(returning: nil) }
                if case .closeAgreeing(_, let done) = event { done.resume(returning: .closed) }
                continue
            }
            switch event {
            case .paint: await paint()
            case .write(let write, let id): await perform(write, as: id)
            case .change(let change): await handle(change)
            case .drained(let report, let taken):
                await answer(report)
                taken.resume()
            case .failed(let failure):
                failures.append(failure)
                publish([])
            case .flush(let done):
                Task { [sync] in
                    await sync.flush()
                    done.resume()
                }
            case .discard(let id, let done): done.resume(returning: await discard(id))
            case .release(let id, let done): done.resume(returning: await release(id))
            case .unsent(let done):
                done.resume(returning: await unsentWrites())
            case .closeAgreeing(let agreed, let done):
                let unsent = await unsentWrites()
                let covered = if let unsent { agreed.map { unsent.ids.isSubset(of: $0.ids) } ?? true } else { agreed == nil }
                if covered {
                    await shutDown()
                    done.resume(returning: .closed)
                } else {
                    done.resume(returning: .waiting(unsent))
                }
            case .close(let done):
                await shutDown()
                done.resume()
            }
        }
    }

    /// Read from the queue itself, since the last report can hold a count from before a read that failed.
    private func unsentWrites() async -> UnsentWrites? {
        guard let queue = try? await Self.asking(hub, { try await copy.queue.all() }) else { return nil }
        return UnsentWrites(ids: MarfaProblems.unsent(queue))
    }

    private func shutDown() async {
        closed = true
        following?.cancel()
        await sync.stop()
        await copy.close()
        hub.finish()
    }

    /// The package refuses every call while the copy changes its key, as `invalid`, and asks for it again; that
    /// is a wait, never a refusal or a failure to show. Any other `invalid` is passed on.
    nonisolated static func asking<T>(_ hub: MarfaHub, _ work: () async throws -> T) async throws -> T {
        while true {
            let mark = hub.keyChanges
            do {
                return try await work()
            } catch let error as MarfaError {
                guard case .invalid = error, hub.keyChanged(since: mark) else { throw error }
                // Throws once the task is cancelled, which ends the asking.
                try await Task.sleep(for: .milliseconds(20))
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
            for await change in changes {
                if !tell(.change(change)) { return }
            }
        }
        await sync.start()
    }

    /// Reads the catalogue, every row in every state, their edges and the queue, and publishes what differs. A
    /// copy that cannot be read keeps showing what it last held, and says why.
    private func reload() async {
        let rows: [String: Marfa.Item]
        let edges: [Marfa.Edge]
        let catalogue: Catalogue
        do {
            (catalogue, rows, edges) = try await Self.asking(hub) {
                let catalogue = try await MarfaMapping.catalogue(
                    itemTypes: copy.catalog.itemTypes(), edgeTypes: copy.catalog.edgeTypes())
                var rows: [String: Marfa.Item] = [:]
                var edges: [Marfa.Edge] = []
                for row in try await copy.items.list(ListFilters(allStates: true)) { rows[row.id] = row }
                for type in catalogue.edgeTypes.keys { edges += try await copy.edges.ofType(type) }
                return (catalogue, rows, edges)
            }
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
                let (row, held) = try await Self.asking(hub) {
                    var row = try await copy.items.get(id)
                    if row == nil {
                        row = try await copy.items.list(ListFilters(state: .trashed)).first { $0.id == id }
                    }
                    return (row, row == nil ? [] : try await copy.edges.from(id) + copy.edges.to(id))
                }
                rows[id] = row
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
            queue = try await Self.asking(hub) { try await copy.queue.all() }
        } catch {
            failures.append(Self.failure(error))
            return
        }
        counted.formIntersection(queue.map(\.id))
        sentAsRead.formIntersection(queue.map(\.id))
        if !readQueueOnce {
            readQueueOnce = true
            for write in queue {
                guard let itemID = write.itemId, let verdict = write.verdict, let outcome = MarfaMapping.outcome(verdict)
                else { continue }
                remember(outcome, of: write.kind, for: ItemID(itemID))
            }
        }
        for write in queue {
            if case .refused = write.verdict { refusals[write.id] = write } else { refusals[write.id] = nil }
        }
        queueRead = true
        restate()
    }

    private func restate() {
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
        let copies = conflictedCopies()
        settleConflicts(copies)
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
        publishReport(copies)
    }

    // MARK: Problems

    private func conflictedCopies() -> [MarfaProblems.ConflictedCopy] {
        rows.values.filter { $0.state == .active && $0.tags.contains(MarfaProblems.conflictedCopyTag) }.map { row in
            let derived = (edgesByItem[row.id] ?? []).compactMap { edges[$0] }
                .first { $0.edgeType == MarfaProblems.derivedFromEdge && $0.sourceId == row.id }?.targetId
            return MarfaProblems.ConflictedCopy(row: row, original: (originals[row.id] ?? derived).map { ItemID($0) })
        }
    }

    /// An item stops showing its conflict once the person has kept or binned the copy it names.
    private func settleConflicts(_ copies: [MarfaProblems.ConflictedCopy]) {
        let open = Set(copies.map { ItemID($0.row.id) })
        var settled = false
        for (item, held) in remembered {
            guard case .conflicted(let sibling?, _) = held.state, rows[sibling.rawValue] != nil, !open.contains(sibling)
            else { continue }
            remembered[item] = nil
            originals[sibling.rawValue] = nil
            settled = true
        }
        if settled { restate() }
    }

    private func publishReport(_ copies: [MarfaProblems.ConflictedCopy]) {
        guard queueRead else { return }
        let named = Set((queue + Array(refusals.values)).compactMap(\.itemId))
        let types = Dictionary(uniqueKeysWithValues: named.compactMap { id in rows[id].map { (id, TypeID($0.type)) } })
        let report = MarfaProblems.report(
            queue: queue, kept: Array(refusals.values), conflictedCopies: copies, catalogue: catalogue, types: types)
        hub.report.update { current in
            let phase = current.phase
            current = report
            current.phase = phase
        }
    }

    private func entry(_ id: String) -> SyncProblemEntry? {
        hub.report.value.problems.first { $0.id == .write(id) }
    }

    /// Those refused only for it go first, since the queue keeps a write another still depends on.
    private func discard(_ id: String) async -> Result<Bool, SourceFailure> {
        guard let entry = entry(id), entry.actions.contains(.discard) else { return .success(false) }
        let held = Set(queue.map(\.id))
        do {
            for write in entry.dependents + [id] {
                if held.contains(write) {
                    guard try await Self.asking(hub, { try await copy.queue.discard(write) }) else { continue }
                }
                refusals[write] = nil
            }
        } catch {
            return .failure(Self.failure(error))
        }
        if let item = entry.itemID, !refusals.values.contains(where: { $0.itemId == item.rawValue }),
            case .refused = remembered[item]?.state
        {
            remembered[item] = nil
        }
        await readQueue()
        publish(entry.itemID.map { [$0] } ?? [])
        return .success(refusals[id] == nil)
    }

    private func release(_ id: String) async -> Result<Bool, SourceFailure> {
        guard let entry = entry(id), entry.actions.contains(.tryAgain) else { return .success(false) }
        let released: Bool
        do {
            released = try await Self.asking(hub) { try await copy.queue.release(id) }
        } catch {
            return .failure(Self.failure(error))
        }
        await readQueue()
        publish(entry.itemID.map { [$0] } ?? [])
        if released { await sync.drain() }
        return .success(released)
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
                let created = try await Self.asking(hub) { try await create(itemID, draft) }
                record(id, [created])
                touched = [itemID.rawValue]
                if let parent = draft.parent {
                    await place(itemID, under: parent)
                    touched.insert(parent.rawValue)
                }
            } else {
                // An edge's ends are read before it goes, since its delete names only the edge.
                var ends: Set<String> = []
                if case .unlink(let edgeID) = write, let edge = edges[edgeID.rawValue] {
                    ends = [edge.sourceId, edge.targetId]
                }
                let queued = try await Self.asking(hub) { try await queue(write) }
                record(id, queued)
                touched = ends.union(queued.flatMap { [$0.itemId, $0.targetId].compactMap(\.self) })
            }
            await reread(touched)
            await sync.drain()
        } catch let error as NotYet {
            hub.publish(.answered(id, .refused(SyncProblem(code: "unsupported", message: error.message))))
        } catch let error as MarfaError {
            // Refused before it was queued, such as a property the type does not allow: nothing is waiting.
            hub.publish(.answered(id, .refused(Self.problem(for: error))))
            switch error {
            case .hydrationIncomplete, .copyExpired: await sync.refresh()
            default: break
            }
        } catch {
            hub.publish(.answered(id, .refused(SyncProblem(code: "failed", message: error.localizedDescription))))
        }
    }

    /// A copy that expired, or whose hydration was cut short, takes no writes until it is hydrated again; the
    /// package says so in its own words, which the person is spared. The app keeps the text it tried to save.
    nonisolated static func problem(for error: MarfaError) -> SyncProblem {
        switch error {
        case .hydrationIncomplete, .copyExpired: SyncProblem(code: error.code(), message: notCurrent)
        default: SyncProblem(code: error.code(), message: error.message)
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
            guard let bodyField = MarfaMapping.bodyField(of: catalogue.itemTypes[try itemType(of: id)]) else {
                throw NotYet(message: Self.noText)
            }
            let properties: [String: JSONValue] = [bodyField: .string(text)]
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
            // Answers already in the copy are in the version this edit was sent on.
            for write in try await copy.queue.all() where write.itemId == id.rawValue && write.verdict != nil {
                counted.insert(write.id)
            }
            return [queued]
        case .editProperties(let id, let changes, let base, _):
            let properties = changes.mapValues { $0.map(MarfaMapping.json) ?? .null }
            return [try await send(id, properties) { base.rawValue }]
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
        case .link(let draft, _):
            return [
                try await copy.edges.create(
                    from: draft.source.rawValue, to: draft.target.rawValue, type: draft.type)
            ]
        case .unlink(let edgeID):
            return [try await copy.edges.delete(edgeID.rawValue)]
        case .retype, .retier, .move, .purge, .attach, .place:
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
            guard let bodyField = MarfaMapping.bodyField(of: info) else { throw NotYet(message: Self.noText) }
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
            _ = try await Self.asking(hub) {
                try await copy.edges.create(from: parent.rawValue, to: child.rawValue, type: MarfaMapping.parentEdge)
            }
        } catch {
            let reason = Self.failure(error).message
            failures.append(SourceFailure(
                kind: .failed, message: String(localized: "The item was made, but it couldn’t be put under its parent: \(reason)")))
        }
    }

    /// An edit is sent on the version of the text it was typed on: as an ordinary update where the copy holds that
    /// version, and otherwise said to be read there, so the server merges it against what was read rather than
    /// laying it over a change the person never saw (queue-and-verdicts 43). An edit queued behind the person's own
    /// on the version the copy holds moves onto that edit's answer (42). The copy moves as answers and catch-ups
    /// land, so the version is decided against one reading of the copy, and again if the copy moved meanwhile.
    private func send(
        _ id: ItemID, _ properties: [String: JSONValue], typedOn: () async throws -> Int64
    ) async throws -> Marfa.QueuedWrite {
        var attempt = 0
        while true {
            attempt += 1
            let held = try await heldVersion(id)
            let version = try await typedOn()
            let steady = try await heldVersion(id) == held && version <= held
            let edit = Edit(properties: properties, baseVersion: version)
            do {
                if steady, version < held {
                    let queued = try await copy.items.updateAsRead(id.rawValue, edit)
                    sentAsRead.insert(queued.id)
                    return queued
                }
                if steady || attempt == 3 { return try await copy.items.update(id.rawValue, edit) }
            } catch where attempt < 3 {
                continue
            }
        }
    }

    /// The version an edit that follows the person's last edit of the text was typed on: the version their own
    /// writes account for. Where the copy holds that version it holds only the person's text over what they read;
    /// where it holds a later one, another device's change came in, and the edit is merged against it. While the
    /// person's own edits of it still wait, a later version cannot yet say whether the server will take them or
    /// keep the other device's text, so the answer is waited for a moment, as the drain under way brings it; one
    /// that does not come leaves the edit merged against the older version, which never overwrites.
    private func followingVersion(_ id: ItemID, otherwise base: ItemVersion) async throws -> Int64 {
        guard ownText[id] != nil else { return base.rawValue }
        func waiting(_ queue: [Marfa.QueuedWrite]) -> Bool {
            queue.contains { $0.itemId == id.rawValue && [.createItem, .updateItem].contains($0.kind) && $0.verdict == nil }
        }
        var queue = try await copy.queue.all()
        try await count(answers: queue, for: id)
        if let own = ownText[id], try await heldVersion(id) > own.on, waiting(queue) {
            let clock = ContinuousClock()
            let end = clock.now + .seconds(2)
            while waiting(queue), clock.now < end {
                try await Task.sleep(for: .milliseconds(50))
                queue = try await copy.queue.all()
            }
            try await count(answers: queue, for: id)
        }
        return ownText[id]?.on ?? base.rawValue
    }

    /// Moves the version the person's own writes account for past the answers the copy has taken. A create or
    /// update the server took on the version it held moves the item one version on (versions.md 2); one merged, or
    /// sent as read on an older version, lands on whatever the server held, which the copy now shows with every
    /// answer taken so far. Any other answer leaves the item where it was.
    private func count(answers queue: [Marfa.QueuedWrite], for id: ItemID) async throws {
        guard var own = ownText[id] else { return }
        let answered = queue.filter {
            $0.itemId == id.rawValue && [.createItem, .updateItem].contains($0.kind) && $0.verdict != nil
                && !counted.contains($0.id)
        }
        guard !answered.isEmpty else { return }
        counted.formUnion(answered.map(\.id))
        let landedElsewhere = answered.contains { write in
            if case .merged = write.verdict { return true }
            return write.verdict == .accepted && sentAsRead.contains(write.id)
        }
        if landedElsewhere {
            own.on = try await heldVersion(id)
        } else {
            own.on += Int64(answered.count { $0.verdict == .accepted })
        }
        ownText[id] = own
    }

    private func heldVersion(_ id: ItemID) async throws -> Int64 {
        if let row = try await copy.items.get(id.rawValue) { return row.version }
        guard let row = rows[id.rawValue] else {
            throw MarfaError.notFound(code: "item_not_found", message: String(localized: "This item isn’t in the library."))
        }
        return row.version
    }

    private func itemType(of id: ItemID) throws -> TypeID {
        guard let row = rows[id.rawValue] else {
            throw MarfaError.notFound(code: "item_not_found", message: String(localized: "This item isn’t in the library."))
        }
        return TypeID(row.type)
    }

    /// Tells each verdict to the app's write and shows it on its item while the queue still holds it, and only
    /// then forgets the answered writes. A refusal or conflict stays shown after that through `remembered`, and
    /// refused writes that carried content stay queued until discarded.
    private func answer(_ report: DrainReport) async {
        await answering?()
        var ids: Set<String> = []
        for answer in report.verdicts {
            guard let verdict = answer.verdict, let outcome = MarfaMapping.outcome(verdict) else { continue }
            if let itemID = answer.itemId {
                ids.insert(itemID)
                remember(outcome, of: answer.kind, for: ItemID(itemID))
            }
            if case .conflicted(let sibling, _) = outcome {
                ids.insert(sibling.rawValue)
                if let itemID = answer.itemId { originals[sibling.rawValue] = itemID }
            }
            answered(answer.id, outcome)
        }
        await reread(ids)
        if let queued = try? await copy.queue.all() {
            for raw in Set(report.verdicts.compactMap(\.itemId)) where ownText[ItemID(raw)] != nil {
                try? await count(answers: queued, for: ItemID(raw))
            }
        }
        do {
            _ = try await Self.asking(hub) { try await copy.queue.forgetAnswered() }
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
            let queued = Set(queue.map(\.id))
            refusals = refusals.filter { id, write in
                queued.contains(id) || write.itemId != item.rawValue || (write.kind != kind && kind != .updateItem)
            }
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
