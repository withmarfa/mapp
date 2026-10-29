import Foundation
import Marfa

/// Reading the copy into items, and hearing what changed in it.
extension MarfaEngine {
    /// Everything the copy holds, before any network: the first `.loaded`. Following the server starts after it.
    func paint() async {
        await reload()
        guard following == nil else { return }
        following = MarfaFollow.start(copy.changes(), next: { [copy] in copy.changes() }, tell: tell)
        await sync.start()
    }

    /// Reads the catalogue, every row in every state, their edges and the queue, and publishes what differs. A
    /// copy that cannot be read keeps showing what it last held, and says why.
    func reload() async {
        let reloading = Telemetry.begin(.engine, "reload")
        defer { reloading.end(("rows", self.rows.count), ("edges", self.edges.count), ("bodyLinks", self.bodyLinks.count)) }
        let rows: [String: Marfa.Item]
        let edges: [Marfa.Edge]
        let catalogue: Catalogue
        let whole: Bool
        do {
            (catalogue, rows, edges, whole) = try await Self.asking(hub) {
                let cataloguing = Telemetry.begin(.engine, "reload.catalogue")
                let catalogue = try await MarfaMapping.catalogue(
                    itemTypes: copy.catalog.itemTypes(), edgeTypes: copy.catalog.edgeTypes())
                cataloguing.end(("itemTypes", catalogue.itemTypes.count), ("edgeTypes", catalogue.edgeTypes.count))
                var rows: [String: Marfa.Item] = [:]
                var edges: [Marfa.Edge] = []
                let listing = Telemetry.begin(.engine, "reload.rows")
                let listed = try await reading.items()
                for row in listed where MarfaMapping.isLibraryItem(row) { rows[row.id] = row }
                listing.end(("rows", rows.count))
                let statusing = Telemetry.begin(.engine, "reload.status")
                let status = try await reading.status()
                statusing.end()
                let fill = LibraryFill(status, completeness: listed.completeness)
                hub.report.update { $0.fill = fill }
                var whole = fill.state == .complete
                let edging = Telemetry.begin(.engine, "reload.edges")
                do {
                    edges = try await reading.edges(ofTypes: Array(catalogue.edgeTypes.keys))
                } catch MarfaError.hydrationIncomplete {
                    // The rows can be read before their relationships. Keep known links through a refill.
                    edges = self.edges.all
                    whole = false
                }
                edging.end(("edges", edges.count))
                return (catalogue, rows, edges, whole)
            }
        } catch {
            readFailed(error)
            publish([])
            return
        }
        let gone = Set(self.rows.keys).subtracting(rows.keys)
        let departed = self.rows.filter { gone.contains($0.key) }.values
        self.catalogue = catalogue
        self.rows = rows
        await sync.unreadable(Set(rows.values.filter { $0.unreadableProperties != nil }.map(\.id)))
        self.edges.removeAll()
        for edge in edges { self.edges.insert(edge) }
        binned = binned.filter { rows[$0.key] == nil }
        for row in departed { await left(row) }
        bodyLinks = [:]
        let linking = Telemetry.begin(.engine, "reload.links")
        var linkReads = 0
        for row in rows.values where Self.mayName(row, catalogue: catalogue) {
            linkReads += 1
            await readLinks(of: row)
        }
        linking.end(("read", linkReads), ("kept", bodyLinks.count))
        let conflicts = Telemetry.begin(.engine, "reload.conflicts")
        await readConflictLinks(Set(rows.keys).union(linkedOriginals.keys))
        conflicts.end()
        let queueing = Telemetry.begin(.engine, "reload.queue")
        await readQueue()
        queueing.end()
        let viewing = Telemetry.begin(.engine, "reload.views")
        await readViews()
        viewing.end()
        let publishing = Telemetry.begin(.engine, "reload.publish")
        publish(Set(rows.keys).union(gone).union(binned.keys).map { ItemID($0) }, catalogueChanged: true)
        publishing.end()
        // Held undos are judged on what this read found, so they wait until it found the copy whole.
        if whole { await releaseHeld() }
    }

    /// Reads the views the copy holds, and tells readers once they differ. One view this build cannot read refuses
    /// them all (`invalid`), so the sidebar lists none rather than some; any other failure keeps the views last
    /// read. A hydration under way answers only the views that have arrived, so those join the views last read and
    /// none leaves until the answer is whole: a window on a view not yet back is not moved off it.
    func readViews() async {
        let views: [LibraryView]
        do {
            let read = try await Self.asking(hub) { try await reading.views() }
            switch read.completeness {
            // A stale copy holds every view it held, only perhaps older.
            case .complete, .stale:
                views = LibraryView.ordered(read.rows)
            case .partial:
                let arrived = Set(read.rows.map(\.id))
                views = LibraryView.ordered(read.rows + self.views.filter { !arrived.contains($0.id) })
            }
        } catch MarfaError.invalid {
            views = []
        } catch {
            return
        }
        guard views != self.views else { return }
        self.views = views
        if painted { hub.publish(.views(views)) }
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
    func settledLinks() async -> Set<String> {
        var changed: Set<String> = []
        for (id, links) in bodyLinks where (links.links + links.embeds).contains(where: { !$0.target.isItem }) {
            guard let row = rows[id] else { continue }
            await readLinks(of: row)
            if bodyLinks[id] != links { changed.insert(id) }
        }
        return changed
    }

    /// Reads again the rows named, with every edge they hold or are held by. All are read before any is taken in, and
    /// every edge held before is dropped before any is put back: an edge that moved to other ends is listed under
    /// the item it left, so taking the items in one at a time, in whatever order, could drop the edge as it is now
    /// after putting it back.
    func reread(_ ids: Set<String>) async {
        var affected = Set(ids)
        let interval = Telemetry.begin(.engine, "reread", ("ids", ids.count))
        defer { interval.end(("ids", ids.count), ("affected", affected.count)) }
        var read: [(row: Marfa.Item?, id: String, held: [Marfa.Edge])] = []
        do {
            for id in ids {
                let (row, held) = try await Self.asking(hub) {
                    var row = try await copy.items.get(id)
                    if row == nil {
                        row = try await copy.items.list(ListFilters(state: .trashed)).first { $0.id == id }
                    }
                    let held: [Marfa.Edge]
                    do { held = row == nil ? [] : try await reading.edges(touching: id) }
                    catch MarfaError.hydrationIncomplete {
                        held = edges.ids(touching: id).compactMap { edges[$0] }
                    }
                    return (row, held)
                }
                read.append((row, id, held))
            }
        } catch {
            readFailed(error)
        }
        // A view's row changes the views, never the items.
        let named = Set(read.map(\.id))
        if read.contains(where: { $0.row.map { !MarfaMapping.isLibraryItem($0) } ?? false })
            || views.contains(where: { named.contains($0.id.rawValue) }) {
            await readViews()
        }
        read = read.map { entry in
            entry.row.map(MarfaMapping.isLibraryItem) == false ? (row: nil, id: entry.id, held: []) : entry
        }
        await sync.unreadable(Set(read.compactMap { $0.row }.filter { $0.unreadableProperties != nil }.map(\.id)))
        for (row, id, _) in read {
            let previous = rows[id]
            rows[id] = row
            if let row {
                binned[id] = nil
                await readLinks(of: row)
            } else {
                bodyLinks[id] = nil
                if let previous { await left(previous) }
            }
            for edgeID in edges.ids(touching: id) {
                if let edge = remove(edgeID) { affected.formUnion([edge.sourceId, edge.targetId]) }
            }
        }
        for (_, _, held) in read {
            for edge in held {
                insert(edge)
                affected.formUnion([edge.sourceId, edge.targetId])
            }
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
    func take(bin found: [Marfa.Item], complete: Bool) {
        var next: [String: Marfa.Item] = complete ? [:] : binned
        for row in found where rows[row.id] == nil && restoring[row.id] == nil && row.state == .trashed
            && MarfaMapping.isLibraryItem(row) {
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
    func readQueue() async {
        do {
            queue = try await Self.asking(hub) { try await copy.queue.all() }
        } catch {
            readFailed(error)
            return
        }
        counted.formIntersection(queue.map(\.id))
        sentAsRead.formIntersection(queue.map(\.id))
        let forgettable = Set(queue.filter { $0.verdict.map(Self.canForget) ?? false }.map(\.id))
        takenAnswers.formIntersection(forgettable)
        if !readQueueOnce {
            readQueueOnce = true
            for write in queue {
                guard let verdict = write.verdict else { continue }
                if Self.canForget(verdict) { takenAnswers.insert(write.id) }
                guard let itemID = write.itemId else { continue }
                remember(MarfaMapping.outcome(verdict), of: write.kind, for: ItemID(itemID))
            }
        }
        for write in queue {
            if case .refused = write.verdict { refusals[write.id] = write } else { refusals[write.id] = nil }
        }
        queueRead = true
        restate()
    }

    func restate() {
        var states = MarfaMapping.syncStates(queue: queue, remembered: remembered.mapValues(\.state))
        // An original knows its copies, which outlive the write that made them, so it shows one after a relaunch. A
        // conflict outranks writes that merely wait, as an original with its own writes still queued shows it; a
        // refusal or a block of the original's own is shown instead, as it needs the person more.
        for (original, copies) in linkedCopies {
            guard let first = copies.first else { continue }
            let conflict = SyncState.conflicted(sibling: ItemID(first), fields: [])
            if MarfaMapping.rank(states[ItemID(original)]) < MarfaMapping.rank(conflict) { states[ItemID(original)] = conflict }
        }
        changedSync.formUnion(Set(states.keys).union(syncStates.keys).filter { states[$0] != syncStates[$0] })
        syncStates = states
    }

    private func insert(_ edge: Marfa.Edge) {
        edges.insert(edge)
    }

    private func remove(_ id: String) -> Marfa.Edge? {
        edges.remove(id)
    }

    /// Maps `ids` again and tells readers what differs: the first time, everything as `.loaded`. Failures gathered
    /// on the way follow as `.unavailable`.
    func publish(_ ids: some Sequence<ItemID>, catalogueChanged: Bool = false) {
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
            let held = edges.edges(touching: row.id).sorted { $0.createdAt < $1.createdAt }
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
        if !painted {
            painted = true
            let ordered = items.values.sorted { $0.created > $1.created }
            hub.publish(.loaded(SourceSnapshot(items: ordered, catalogue: catalogue, views: views)))
        } else {
            if !removed.isEmpty { hub.publish(.removed(removed)) }
            if !upserted.isEmpty { hub.publish(.upserted(upserted)) }
            for (id, version) in bodyChanged { hub.publish(.bodyChanged(id, version)) }
        }
        for failure in failures { hub.publish(.unavailable(failure)) }
        failures = []
        publishReport(copies)
    }

    func handle(_ change: Marfa.Change) async {
        switch change.origin {
        // This engine makes every local write and hears every drain's answers from `MarfaSync`.
        case .local, .answered, .refreshed(.drained): break
        case .serverReachable: await sync.reachable()
        case .serverUnreachable(let error): await sync.unreachable(error.message)
        // The copy drains what waited when the server is back; its answers are taken as a drain of the sync lane's.
        case .queueDrained(let report):
            if !report.verdicts.isEmpty { await answer(report) }
            await sync.drainedByFollow(report)
        case .queueNotDrained(let error): await sync.drainStopped(error, answersTaken: await takeAnswers(after: error))
        case .server:
            await sync.heard()
            await reread(change)
            // Reachability precedes replay. Fetch again once the copy holds the arriving attachment or its item.
            let changedEdges = change.itemId.map { edges.edges(touching: $0) } ?? []
            let namedEdge = change.edgeId.flatMap { edges[$0] }
            if (changedEdges + [namedEdge].compactMap { $0 }).contains(where: { $0.edgeType == MarfaMapping.attachmentEdge }) {
                await sync.fetchAttachments()
            }
        case .refreshed(.purged): await purged(change.itemId)
        // A view written through the server changes the views alone.
        case .refreshed(.viewWritten): await readViews()
        case .saved, .refreshed: await reload()
        case .stopped(let error): await sync.stopped(error)
        }
    }

    /// A drain that stops on an error has recorded the answers it got and tells none of them. They are read from the
    /// queue here, in the engine's own step, since `MarfaSync` would wait on this engine to take them. False where
    /// they could not be taken yet: an expired copy refuses the reads that taking them needs, and a queue may not
    /// be readable.
    private func takeAnswers(after error: MarfaError) async -> Bool {
        if case .copyExpired = error { return false }
        guard let queued = try? await copy.queue.all() else { return false }
        let report = MarfaSync.report(answeredIn: queued)
        if !report.verdicts.isEmpty { await answer(report) }
        return true
    }

    func reread(_ change: Marfa.Change) async {
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
}
