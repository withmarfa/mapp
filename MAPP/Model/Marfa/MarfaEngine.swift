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
        /// Resumed once every event before it is taken, so each write submitted before it is in the queue or
        /// refused; it never waits on the network, so quitting offline does not wait for a server.
        case queued(CheckedContinuation<Void, Never>)
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
        /// The server's bin as `MarfaSync` read it, which the copy never holds; `complete` where every page was read.
        case binned([Marfa.Item], complete: Bool)
        /// The verdict on a write made at the server at once rather than queued, such as a purge.
        case answer(WriteID, WriteOutcome)
        /// Attaches a file, which the package queues as an upload, a file item and an edge.
        case attach(URL, ItemID, CheckedContinuation<Result<Embed, SourceFailure>, Never>)
    }

    /// A write only a files library makes, such as a move, or one the type cannot take.
    private nonisolated struct Unsupported: Error {
        var message = MarfaEngine.filesOnly
    }

    /// A write the package refused before queueing it, in the person's words.
    private nonisolated struct Refused: Error {
        var problem: SyncProblem
    }

    /// The person's latest edit of an item's text, and the version of the item their own writes account for: the
    /// version that edit was typed on, moved on by each answer to this device's writes of the item.
    nonisolated struct OwnText: Equatable {
        var text: String
        var on: Int64
    }

    nonisolated static var filesOnly: String {
        String(localized: "This change can’t be made in a Marfa library.")
    }

    nonisolated static var notCurrent: String {
        String(localized: "This library is being brought up to date. Try again in a moment.")
    }

    nonisolated static var closedLibrary: String {
        String(localized: "This library is closed.")
    }

    /// The code of the refusal a write gets when it reaches the engine after the copy closed.
    nonisolated static let closedCode = "closed"

    /// A write that reached the source after it closed, which no queue holds.
    nonisolated static var notKept: String {
        String(localized: "This library was closed before the change could be kept.")
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
    /// Rows the server holds in its bin that the copy does not: Recently Deleted's items once their delete is
    /// answered, which the copy lets go of. Read from the server, kept as it last said and as the copy last held.
    private var binned: [String: Marfa.Item] = [:]
    /// Binned rows whose restore is queued: shown nowhere until the server answers, then in the copy or back in the bin.
    private var restoring: [String: Marfa.Item] = [:]
    /// What each item's text names, read by the package from the copy, for the items whose text can name anything.
    private var bodyLinks: [String: BodyLinks] = [:]
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
    /// The item each conflicted copy was made from, as its verdict named it, which is known before the copy's link has reached the copy.
    private var originals: [String: String] = [:]
    /// The item each conflicted copy was made from, and the copies each original has that are not in the bin, as
    /// the package reads the copy's `derived-from` link: a copy and its original know each other from the copy
    /// alone, offline and after a relaunch.
    private var linkedOriginals: [String: String] = [:]
    private var linkedCopies: [String: [String]] = [:]
    /// The items an edge move touched, read again once its answer is taken: the two ends it left and the one it went
    /// to, since a refusal puts the edge back and the answer names only its source.
    private var movedEnds: [String: Set<String>] = [:]
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
                if case .write(_, let id) = event {
                    hub.publish(.answered(id, .refused(SyncProblem(code: Self.closedCode, message: Self.notKept))))
                }
                if case .flush(let done) = event { done.resume() }
                if case .queued(let done) = event { done.resume() }
                if case .close(let done) = event { done.resume() }
                if case .drained(_, let taken) = event { taken.resume() }
                if case .discard(_, let done) = event { done.resume(returning: .success(false)) }
                if case .release(_, let done) = event { done.resume(returning: .success(false)) }
                if case .unsent(let done) = event { done.resume(returning: nil) }
                if case .closeAgreeing(_, let done) = event { done.resume(returning: .closed) }
                if case .attach(_, _, let done) = event {
                    done.resume(returning: .failure(SourceFailure(kind: .missing, message: Self.closedLibrary)))
                }
                continue
            }
            switch event {
            case .paint: await paint()
            case .write(let write, let id): await perform(write, as: id)
            case .change(let change): await handle(change)
            case .binned(let found, let complete): take(bin: found, complete: complete)
            case .answer(let write, let outcome): hub.publish(.answered(write, outcome))
            case .attach(let file, let item, let done): done.resume(returning: await attach(file, to: item))
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
            case .queued(let done): done.resume()
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
        // Finished only once the events that came after the close are answered, so a write made too late is told
        // to its library rather than dropped unseen.
        hub.finish()
    }

    /// Read from the queue itself, since the last report can hold a count from before a read that failed.
    private func unsentWrites() async -> UnsentWrites? {
        guard let queue = try? await Self.asking(hub, { try await copy.queue.all() }) else { return nil }
        let named = Set(queue.compactMap(\.itemId))
        let types = Dictionary(uniqueKeysWithValues: named.compactMap { id in rows[id].map { (id, TypeID($0.type)) } })
        return UnsentWrites(
            ids: MarfaProblems.unsent(queue), texts: MarfaProblems.unsentTexts(queue, catalogue: catalogue, types: types))
    }

    private func shutDown() async {
        closed = true
        following?.cancel()
        await sync.stop()
        await copy.close()
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
        let departed = self.rows.filter { gone.contains($0.key) }.values
        self.catalogue = catalogue
        self.rows = rows
        self.edges = [:]
        edgesByItem = [:]
        for edge in edges { insert(edge) }
        binned = binned.filter { rows[$0.key] == nil }
        for row in departed { await left(row) }
        bodyLinks = [:]
        for row in rows.values where Self.mayName(row, catalogue: catalogue) { await readLinks(of: row) }
        await readConflictLinks(Set(rows.keys).union(linkedOriginals.keys))
        await readQueue()
        publish(Set(rows.keys).union(gone).union(binned.keys).map { ItemID($0) }, catalogueChanged: true)
    }

    /// A row that left the copy: one in the bin went there with its delete answered, so Recently Deleted keeps it,
    /// as the copy last held it, until the server's bin is read; any other was deleted elsewhere or fell out of the
    /// slice, which may have put it in the bin, so the bin is read again.
    private func left(_ row: Marfa.Item) async {
        bodyLinks[row.id] = nil
        guard restoring[row.id] == nil else { return }
        if row.state == .trashed { binned[row.id] = row }
        await sync.binChanged()
    }

    /// Whether an item's text can hold a link or an embed: a `[[link]]` or an `![](embed)`. The package reads each
    /// body from the copy one at a time, so the items that cannot are not asked.
    static func mayName(_ row: Marfa.Item, catalogue: Catalogue) -> Bool {
        guard let body = MarfaMapping.body(of: row, catalogue: catalogue) else { return false }
        return body.contains("[[") || body.contains("![")
    }

    /// Asks the package what the item's text names, from the copy alone.
    private func readLinks(of row: Marfa.Item) async {
        guard Self.mayName(row, catalogue: catalogue) else {
            bodyLinks[row.id] = nil
            return
        }
        do {
            bodyLinks[row.id] = try await Self.asking(hub) { try await copy.items.links(in: row.id) }
        } catch {
            // An item the copy cannot name links for shows the edges it holds, and no more.
            bodyLinks[row.id] = nil
        }
    }

    /// The items whose links named nothing, or nothing yet, which a drain, a catch-up or a new item may have
    /// settled: those whose links now read differently.
    private func settledLinks() async -> Set<String> {
        var changed: Set<String> = []
        for (id, links) in bodyLinks where (links.links + links.embeds).contains(where: { !$0.target.isItem }) {
            guard let row = rows[id] else { continue }
            await readLinks(of: row)
            if bodyLinks[id] != links { changed.insert(id) }
        }
        return changed
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
                let previous = rows[id]
                rows[id] = row
                if let row {
                    binned[id] = nil
                    await readLinks(of: row)
                } else {
                    bodyLinks[id] = nil
                    if let previous { await left(previous) }
                }
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
        await readConflictLinks(affected)
        await readQueue()
        publish(affected.map { ItemID($0) })
    }

    /// Asks the package which item each of these rows, if a conflicted copy, was made from, and which copies each
    /// of those originals has. A copy kept or binned, or one that left the copy, no longer links its original.
    private func readConflictLinks(_ ids: Set<String>) async {
        var originalsToRead: Set<String> = []
        for id in ids {
            guard let row = rows[id], row.state == .active, row.tags.contains(MarfaProblems.conflictedCopyTag) else {
                if let previous = linkedOriginals.removeValue(forKey: id) { originalsToRead.insert(previous) }
                continue
            }
            do {
                let original = try await Self.asking(hub) { try await copy.items.original(ofConflictedCopy: id) }
                if let previous = linkedOriginals[id], previous != original { originalsToRead.insert(previous) }
                linkedOriginals[id] = original
                if let original { originalsToRead.insert(original) }
            } catch {
                // What was read before stands.
                continue
            }
        }
        for original in originalsToRead {
            do {
                let copies = try await Self.asking(hub) { try await copy.items.conflictedCopies(of: original) }.map(\.id)
                linkedCopies[original] = copies.isEmpty ? nil : copies
            } catch {
                continue
            }
        }
        if !originalsToRead.isEmpty { restate() }
    }

    /// The server's bin, as the copy last said it: what it holds is the copy's to say, so only the rest is kept,
    /// and a restore waiting for its answer keeps its row hidden.
    private func take(bin found: [Marfa.Item], complete: Bool) {
        var next: [String: Marfa.Item] = complete ? [:] : binned
        for row in found where rows[row.id] == nil && restoring[row.id] == nil && row.state == .trashed {
            next[row.id] = row
        }
        let changed = Set(binned.keys).union(next.keys).filter { binned[$0] != next[$0] }
        guard !changed.isEmpty else { return }
        binned = next
        publish(changed.map { ItemID($0) })
    }

    /// An item the server destroyed leaves the copy and the bin.
    private func purged(_ id: String?) async {
        guard let id else { return await reload() }
        rows[id] = nil
        binned[id] = nil
        restoring[id] = nil
        await reread([id])
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
        var states = MarfaMapping.syncStates(queue: queue, remembered: remembered.mapValues(\.state))
        // An original knows its copies, which outlive the write that made them, so it shows one after a relaunch.
        for (original, copies) in linkedCopies where states[ItemID(original)] == nil {
            if let first = copies.first { states[ItemID(original)] = .conflicted(sibling: ItemID(first), fields: []) }
        }
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
        hub.setBinned(binned)
        let copies = conflictedCopies()
        settleConflicts(copies)
        let ids = Set(ids).union(changedSync)
        changedSync = []
        if catalogueChanged, painted, hub.snapshot?.catalogue != catalogue { hub.publish(.catalogue(catalogue)) }
        var upserted: [Item] = []
        var removed: [ItemID] = []
        var bodyChanged: [(ItemID, ItemVersion)] = []
        for id in ids {
            guard let row = rows[id.rawValue] ?? binned[id.rawValue] else {
                if items.removeValue(forKey: id) != nil { removed.append(id) }
                bodies[id] = nil
                continue
            }
            let held = (edgesByItem[row.id] ?? []).compactMap { edges[$0] }.sorted { $0.createdAt < $1.createdAt }
            let item = MarfaMapping.item(
                row, edges: held, catalogue: catalogue, sync: syncStates[id] ?? .settled, bodyLinks: bodyLinks[row.id],
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
            MarfaProblems.ConflictedCopy(row: row, original: (linkedOriginals[row.id] ?? originals[row.id]).map { ItemID($0) })
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
        case .serverReachable: await sync.reachable()
        case .serverUnreachable(let error): await sync.unreachable(error.message)
        case .server:
            await sync.heard()
            await reread(change)
        case .refreshed(.purged): await purged(change.itemId)
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
        if case .purge(let item, let version) = write {
            purge(item, at: version, as: id)
            return
        }
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
            await sync.drain()
        } catch let error as Unsupported {
            hub.publish(.answered(id, .refused(SyncProblem(code: "unsupported", message: error.message))))
        } catch let error as Refused {
            hub.publish(.answered(id, .refused(error.problem)))
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
        outstanding[id] = Set(queued.map(\.id))
        for written in queued { submitted[written.id] = id }
    }

    private func queue(_ write: ItemWrite) async throws -> [Marfa.QueuedWrite] {
        switch write {
        case .create:
            preconditionFailure("a create is queued by perform(_:as:)")
        case .editBody(let id, let text, let base, let merge):
            guard let bodyField = MarfaMapping.bodyField(of: catalogue.itemTypes[try itemType(of: id)]) else {
                throw Unsupported(message: Self.noText)
            }
            let properties = Edit.Properties.merge(JSONObject([(bodyField, .string(text))]))
            // Read before the edit is sent: an answer that lands during the send is not in the version it was sent
            // on, so it is counted later, as it comes.
            let answeredBefore = merge == .following && ownText[id] != nil ? [] : try await answeredWrites(of: id)
            let queued: Marfa.QueuedWrite
            switch merge {
            case .ifUnchanged:
                queued = try await copy.items.update(id.rawValue, Edit(properties, baseVersion: base.rawValue))
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
            return [try await send(id, try properties(editing: id, by: changes)) { base.rawValue }]
        case .retype(let id, let type, let base):
            return [try await send(id, .merge(JSONObject()), type: type.rawValue) { base.rawValue }]
        case .retier(let id, let tier, let base):
            return [try await send(id, .merge(JSONObject()), tier: MarfaMapping.marfaTier(tier)) { base.rawValue }]
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
                    from: draft.source.rawValue, to: draft.target.rawValue, type: draft.type)
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
                // The edge is already there, as when an undo follows a refused move. The package would queue an
                // update that changes nothing, which the server refuses.
                if (end == .source ? held.sourceId : held.targetId) == to.rawValue { return [] }
                return [try await copy.edges.update(edge.id, EdgeEdit(baseVersion: held.version, move: move))]
            } catch let error as MarfaError {
                if let problem = Self.moveProblem(error) { throw Refused(problem: problem) }
                throw error
            }
        case .purge:
            preconditionFailure("a purge is made at the server by perform(_:as:)")
        case .move, .place:
            throw Unsupported()
        }
    }

    /// The item keeps the id the app minted, a lowercase UUIDv7 as the server requires. A body for a type with
    /// no body field is refused rather than dropped.
    private func create(_ id: ItemID, _ draft: ItemDraft) async throws -> Marfa.QueuedWrite {
        let info = catalogue.itemTypes[draft.type]
        var properties = JSONObject(draft.properties.sorted { $0.key < $1.key }.map { ($0.key, MarfaMapping.json($0.value)) })
        var body = draft.body
        if let titleField = MarfaMapping.titleField(of: info) {
            properties[titleField] = .string(draft.title)
        } else if !draft.title.isEmpty {
            body = body.isEmpty ? draft.title : draft.title + "\n\n" + body
        }
        if !body.isEmpty {
            guard let bodyField = MarfaMapping.bodyField(of: info) else { throw Unsupported(message: Self.noText) }
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

    /// The package queues the upload, the file's item and its edge to this one, and says what to write in the text
    /// to embed it. The title is the file's name unless another attachment of the item has it, since an embed must
    /// name one file alone; the text itself is the page's to place, and the editor saves it as it does any typing.
    private func attach(_ file: URL, to id: ItemID) async -> Result<Embed, SourceFailure> {
        do {
            guard let row = rows[id.rawValue], row.state == .active || row.state == .archived else {
                throw SourceFailure(kind: .missing, message: String(localized: "This item isn’t in the library."))
            }
            let title = attachmentTitle(for: file, on: row)
            let attached = try await Self.asking(hub) {
                try await copy.items.attach(to: id.rawValue, file: file, Attachment(title: title))
            }
            await reread(Set([id.rawValue] + [attached.item.itemId].compactMap(\.self)))
            await sync.drain()
            // Where the package says no embed names the file alone, the file is attached all the same, so the text
            // still links it by its title rather than the person being told it failed and attaching it twice.
            let name = attached.embed.flatMap(Self.embeddedName) ?? title
            return .success(Embed(link: Self.link(to: name), name: name))
        } catch let error as SourceFailure {
            return .failure(error)
        } catch {
            return .failure(Self.failure(error))
        }
    }

    /// The file's name, or that name with a number when another attachment of the item already has it.
    private func attachmentTitle(for file: URL, on host: Marfa.Item) -> String {
        let taken = Set(
            (edgesByItem[host.id] ?? []).compactMap { edges[$0] }
                .filter { $0.edgeType == MarfaMapping.attachmentEdge && $0.targetId == host.id }
                .compactMap { rows[$0.sourceId]?.title?.lowercased() })
        let name = file.lastPathComponent
        let stem = file.deletingPathExtension().lastPathComponent
        let ext = file.pathExtension
        var title = Self.embeddable(name)
        var number = 1
        while taken.contains(title.lowercased()) {
            number += 1
            title = Self.embeddable(ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)")
        }
        return title
    }

    /// An embed names its file between `![[` and `]]`, where `[`, `]`, `|`, `#` and `^` mean something else, so a
    /// title that holds them could not be embedded. The file keeps its name on disk; only its title in Marfa changes.
    nonisolated static func embeddable(_ name: String) -> String {
        String(name.map { "[]|#^".contains($0) ? "-" : $0 })
    }

    /// The name inside `![[name]]`, which the package writes for an embed.
    nonisolated static func embeddedName(_ embed: String) -> String? {
        guard embed.hasPrefix("![["), embed.hasSuffix("]]"), embed.count > 5 else { return nil }
        return String(embed.dropFirst(3).dropLast(2))
    }

    /// The name as a markdown destination: the page writes `![name](link)`, and the core reads the percent
    /// escapes of a path back to the name.
    nonisolated static func link(to name: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        // The destination of `![alt](path)` ends at the first closing parenthesis, so a name's own must be escaped.
        allowed.remove(charactersIn: "()")
        return name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
    }

    /// An edit is sent on the version of the text it was typed on: as an ordinary update where the copy holds that
    /// version, and otherwise said to be read there, so the server merges it against what was read rather than
    /// laying it over a change the person never saw (queue-and-verdicts 43). An edit queued behind the person's own
    /// on the version the copy holds moves onto that edit's answer (42). The copy moves as answers and catch-ups
    /// land, so the version is decided against one reading of the copy, and again if the copy moved meanwhile.
    private func send(
        _ id: ItemID, _ properties: Edit.Properties, type: String? = nil, tier: Marfa.Tier? = nil,
        typedOn: () async throws -> Int64
    ) async throws -> Marfa.QueuedWrite {
        var attempt = 0
        while true {
            attempt += 1
            let held = try await heldVersion(id)
            let version = try await typedOn()
            let steady = try await heldVersion(id) == held && version <= held
            let edit = Edit(properties, baseVersion: version, type: type, tier: tier)
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

    /// A property is given a value or taken away. A merge keeps a property it names no value for, and a null clears
    /// nothing, so taking one away replaces the item's properties with those it holds less that one.
    private func properties(editing id: ItemID, by changes: [String: PropertyValue?]) throws -> Edit.Properties {
        func clears(_ value: PropertyValue?) -> Bool {
            guard let value else { return true }
            return value == .null
        }
        let given = changes.sorted { $0.key < $1.key }.compactMap { key, value -> (String, JSONValue)? in
            guard let value, !clears(value) else { return nil }
            return (key, MarfaMapping.json(value))
        }
        let cleared = changes.filter { clears($0.value) }.keys
        guard !cleared.isEmpty else { return .merge(JSONObject(given)) }
        guard var whole = rows[id.rawValue]?.properties else {
            throw MarfaError.notFound(code: "item_not_found", message: String(localized: "This item isn’t in the library."))
        }
        for key in cleared { whole.removeValue(forKey: key) }
        for (key, value) in given { whole[key] = value }
        return .replace(whole)
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
        guard let own = ownText[id] else { return }
        var taken = counted
        ownText[id] = try await Self.counting(queue, for: id, own: own, counted: &taken, sentAsRead: sentAsRead) {
            try await self.heldVersion(id)
        }
        counted.formUnion(taken)
    }

    /// `own` moved past the answers in `queue` not yet in `counted`. Each is put in `counted` only once its effect
    /// is known, so an answer whose version cannot be read, as while the copy is hydrated again, is counted later.
    nonisolated static func counting(
        _ queue: [Marfa.QueuedWrite], for id: ItemID, own: OwnText, counted: inout Set<String>, sentAsRead: Set<String>,
        held: () async throws -> Int64
    ) async rethrows -> OwnText {
        let answered = queue.filter {
            $0.itemId == id.rawValue && [.createItem, .updateItem].contains($0.kind) && $0.verdict != nil
                && !counted.contains($0.id)
        }
        guard !answered.isEmpty else { return own }
        let landedElsewhere = answered.contains { write in
            if case .merged = write.verdict { return true }
            return write.verdict == .accepted && sentAsRead.contains(write.id)
        }
        var own = own
        own.on = landedElsewhere ? try await held() : own.on + Int64(answered.count { $0.verdict == .accepted })
        counted.formUnion(answered.map(\.id))
        return own
    }

    private func answeredWrites(of id: ItemID) async throws -> [String] {
        try await copy.queue.all().filter { $0.itemId == id.rawValue && $0.verdict != nil }.map(\.id)
    }

    private func heldEdge(_ edge: Marfa.Edge) async throws -> Marfa.Edge {
        if let held = try await copy.edges.from(edge.sourceId).first(where: { $0.id == edge.id }) { return held }
        if let held = try await copy.edges.to(edge.targetId).first(where: { $0.id == edge.id }) { return held }
        if let held = try await copy.edges.ofType(edge.edgeType).first(where: { $0.id == edge.id }) { return held }
        throw MarfaError.notFound(code: "edge_not_found", message: String(localized: "This link isn’t in the library."))
    }

    private func hasLeft(_ raw: String) async -> Bool {
        guard rows[raw] == nil else { return false }
        return (try? await copy.items.get(raw)) == nil
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
        // The copy lets an item go once its delete is answered, which may be only as the answers are forgotten.
        var leaving: Set<String> = []
        for answer in report.verdicts {
            if let itemID = answer.itemId, [.deleteItem, .restoreItem].contains(answer.kind) { leaving.insert(itemID) }
            guard let verdict = answer.verdict, let outcome = MarfaMapping.outcome(verdict) else { continue }
            ids.formUnion(movedEnds.removeValue(forKey: answer.id) ?? [])
            if let itemID = answer.itemId {
                ids.insert(itemID)
                remember(outcome, of: answer.kind, for: ItemID(itemID))
                if answer.kind == .restoreItem, let row = restoring.removeValue(forKey: itemID) {
                    // Taken, the item arrives in the copy; otherwise it is still in the bin.
                    switch outcome {
                    case .accepted, .merged: break
                    default: binned[itemID] = row
                    }
                }
            }
            if case .conflicted(let sibling, _) = outcome {
                ids.insert(sibling.rawValue)
                if let itemID = answer.itemId { originals[sibling.rawValue] = itemID }
            }
            answered(answer.id, outcome)
        }
        await reread(ids.union(await settledLinks()))
        // An answer the person's text cannot yet be moved past stays in the queue, to be counted by the next save
        // or the next answer, since forgetting it would leave the text on a version it has passed.
        var uncounted = false
        if let queued = try? await copy.queue.all() {
            for raw in Set(queued.compactMap(\.itemId)) where ownText[ItemID(raw)] != nil {
                do {
                    try await count(answers: queued, for: ItemID(raw))
                } catch {
                    // An item the copy has let go, as when its delete was answered in this drain, has no version to
                    // count against and never will, so its text is forgotten rather than holding every answer back.
                    if await hasLeft(raw) {
                        ownText[ItemID(raw)] = nil
                        counted.formUnion(queued.filter { $0.itemId == raw }.map(\.id))
                    } else {
                        uncounted = true
                    }
                }
            }
        } else {
            uncounted = true
        }
        if !uncounted {
            do {
                _ = try await Self.asking(hub) { try await copy.queue.forgetAnswered() }
            } catch {
                failures.append(Self.failure(error))
            }
        }
        if !leaving.isEmpty { await reread(leaving) }
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
