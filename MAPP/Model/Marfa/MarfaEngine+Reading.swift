import Foundation
import Marfa

/// Reading the copy into items, and hearing what changed in it.
extension MarfaEngine {
    /// Everything the copy holds, before any network: the first `.loaded`. Following the server starts after it.
    func paint() async {
        await reload()
        guard following == nil else { return }
        following = MarfaFollow.start(copy.changes(), next: { [copy] in copy.changes() }, into: heard, tell: tell)
        await sync.start()
    }

    /// The most rows a batch of changes reads one by one; more read the copy whole (`reload`), which costs a list
    /// of every row rather than a read and an edge read for each.
    nonisolated static let rereadLimit = 2000

    /// Whether reading `count` rows one by one would cost more than reading all of `held` again.
    nonisolated static func readsWhole(_ count: Int, of held: Int) -> Bool {
        count > rereadLimit || (count > 64 && count * 4 > held)
    }

    /// What a batch of the follow's changes asks the engine to read again.
    private struct Batch {
        var ids: Set<String> = []
        /// Ids the server named, and edges, whose attachments may now be in the copy.
        var serverIDs: Set<String> = []
        var serverEdges: Set<String> = []
        /// Rows the server destroyed, already let go, which the reads that follow tell readers of.
        var purged: Set<String> = []
        var reload = false
        var views = false
        var queue = false
        var refresh = false
        var changes = 0
    }

    /// Takes everything the follow heard since the last take, in order. The server's word on reachability, the
    /// queue and the follow is acted on in place; the rows the changes name are read once each, after all of them,
    /// since what the copy holds now already reflects every change heard, so reading a row after a later change
    /// to it costs a read and tells nothing new.
    func takeHeard() async {
        let entries = heard.take()
        guard !entries.isEmpty else { return }
        var batch = Batch()
        // A server change says the server spoke, which `sync.heard()` takes as being online; it is told once for
        // each run of them, in its place among the reachability changes.
        var spoke = false
        for entry in entries {
            batch.changes += 1
            guard case .change(let change) = entry else {
                // What changed between the two streams was heard by neither.
                batch.reload = true
                batch.refresh = true
                continue
            }
            switch change.origin {
            // This engine makes every local write and hears every drain's answers from `MarfaSync`.
            case .local, .answered, .refreshed(.drained): continue
            case .serverReachable: await sync.reachable()
            case .serverUnreachable(let error): await sync.unreachable(error.message)
            // The copy drains what waited when the server is back; its answers are taken as a drain of the sync lane's.
            case .queueDrained(let report):
                if !report.verdicts.isEmpty { await answer(report) }
                await sync.drainedByFollow(report)
            case .queueNotDrained(let error): await sync.drainStopped(error, answersTaken: await takeAnswers(after: error))
            case .stopped(let error): await sync.stopped(error)
            case .server:
                if !spoke { await sync.heard() }
                spoke = true
                name(change, in: &batch)
                if let id = change.itemId { batch.serverIDs.insert(id) }
                if let id = change.edgeId { batch.serverEdges.insert(id) }
                continue
            case .refreshed(.purged):
                guard let id = change.itemId else {
                    batch.reload = true
                    continue
                }
                // An item the server destroyed leaves the copy and the bin.
                rows[id] = nil
                binned[id] = nil
                restoring[id] = nil
                batch.purged.insert(id)
                batch.ids.insert(id)
                continue
            // A view written through the server changes the views alone.
            case .refreshed(.viewWritten): batch.views = true; continue
            // The copy forgot answers it held, which changes what each item shows of its writes and nothing else.
            case .refreshed(.forgotten): batch.queue = true; continue
            case .refreshed(.pinned), .refreshed(.unpinned):
                if let id = change.itemId { batch.ids.insert(id) } else { batch.reload = true }
                continue
            // A folder holds a device's sync settings and places no item.
            case .refreshed(.folderWritten): continue
            case .saved, .refreshed: batch.reload = true; continue
            }
            spoke = false
        }
        let taking = Telemetry.begin(.engine, "heard.batch", ("changes", batch.changes))
        let whole = batch.reload || Self.readsWhole(batch.ids.count, of: rows.count)
        defer { taking.end(("changes", batch.changes), ("ids", batch.ids.count), ("reload", whole ? 1 : 0)) }
        if whole {
            await reload(publishing: batch.purged)
        } else if !batch.ids.isEmpty {
            await reread(batch.ids)
        } else if batch.queue {
            await readQueue()
            publish([])
        }
        if batch.views, !whole { await readViews() }
        // Reachability precedes replay. Fetch again once the copy holds the arriving attachment or its item.
        let arrived = batch.serverIDs.flatMap { edges.edges(touching: $0) } + batch.serverEdges.compactMap { edges[$0] }
        if arrived.contains(where: { $0.edgeType == MarfaMapping.attachmentEdge }) { await sync.fetchAttachments() }
        if batch.refresh { await sync.refresh() }
    }

    /// Adds the rows a server change names: its item, and both ends of its edge as the engine holds it. An edge
    /// the engine does not hold names no row it knows, so with no item named the copy is read whole.
    private func name(_ change: Marfa.Change, in batch: inout Batch) {
        if let id = change.itemId { batch.ids.insert(id) }
        guard let edgeID = change.edgeId else { return }
        if let edge = edges[edgeID] {
            batch.ids.formUnion([edge.sourceId, edge.targetId])
        } else if change.itemId == nil {
            batch.reload = true
        }
    }

    /// Reads the catalogue, every row in every state, their edges and the queue, and publishes what differs. A
    /// copy that cannot be read keeps showing what it last held, and says why. What an item's text names is read
    /// again only where the item or its edges changed, or a name in it was not yet bound to an item. `also` names
    /// rows already let go, whose readers are told with the rest.
    func reload(publishing also: Set<String> = []) async {
        let reloading = Telemetry.begin(.engine, "reload")
        var published = 0
        defer {
            reloading.end(
                ("rows", self.rows.count), ("edges", self.edges.count), ("bodyLinks", self.bodyLinks.count),
                ("published", published))
        }
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
            publish(also.map { ItemID($0) })
            return
        }
        let previousRows = self.rows
        let previousEdges = self.edges
        let previousBinned = binned
        let previousLinks = bodyLinks
        let everything = !painted || catalogue != self.catalogue
        self.catalogue = catalogue
        self.rows = rows
        await sync.unreadable(Set(rows.values.filter { $0.unreadableProperties != nil }.map(\.id)))
        self.edges.removeAll()
        for edge in edges { self.edges.insert(edge) }
        binned = binned.filter { rows[$0.key] == nil }
        let gone = Set(previousRows.keys).subtracting(rows.keys)
        var binChanged = false
        for id in gone {
            if let row = previousRows[id], left(row) { binChanged = true }
        }
        if binChanged { await sync.binChanged() }

        // The rows whose item may map differently: changed, come or gone, at either end of an edge that changed,
        // or at the other end of an edge whose row came or went, since an edge shows only where both ends are held.
        var touched = also.union(gone)
        for (id, row) in rows where previousRows[id] != row { touched.insert(id) }
        for edge in edges where previousEdges[edge.id] != edge {
            touched.formUnion([edge.sourceId, edge.targetId])
            if let old = previousEdges[edge.id] { touched.formUnion([old.sourceId, old.targetId]) }
        }
        for edge in previousEdges.all where self.edges[edge.id] == nil { touched.formUnion([edge.sourceId, edge.targetId]) }
        for id in gone.union(rows.keys.filter { previousRows[$0] == nil }) {
            for edge in previousEdges.edges(touching: id) + self.edges.edges(touching: id) {
                touched.formUnion([edge.sourceId, edge.targetId])
            }
        }

        let linking = Telemetry.begin(.engine, "reload.links")
        var linkReads = 0
        for (id, row) in rows where Self.mayName(row, catalogue: catalogue) {
            if !everything, !touched.contains(id), let links = previousLinks[id], Self.allBound(links) { continue }
            linkReads += 1
            await readLinks(of: row)
        }
        for id in Set(bodyLinks.keys).subtracting(rows.keys) { bodyLinks[id] = nil }
        for (id, row) in rows where bodyLinks[id] != nil && !Self.mayName(row, catalogue: catalogue) { bodyLinks[id] = nil }
        linking.end(("read", linkReads), ("kept", bodyLinks.count))
        touched.formUnion(Set(previousLinks.keys).union(bodyLinks.keys).filter { previousLinks[$0] != bodyLinks[$0] })
        touched.formUnion(Set(previousBinned.keys).union(binned.keys).filter { previousBinned[$0] != binned[$0] })

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
        let ids = everything ? Set(rows.keys).union(gone).union(binned.keys).union(also) : touched
        published = ids.count
        publish(ids.map { ItemID($0) }, catalogueChanged: true)
        publishing.end(("ids", published))
        // Held undos are judged on what this read found, so they wait until it found the copy whole.
        if whole { await releaseHeld() }
    }

    /// Whether every name in an item's text is bound to an item, so it reads the same until the item or its edges
    /// change. A name not yet bound may be bound by a drain, a catch-up or another item arriving.
    nonisolated static func allBound(_ links: BodyLinks) -> Bool {
        (links.links + links.embeds).allSatisfy(\.target.isItem)
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
    /// slice, which may have put it in the bin, so the bin is read again: true where it should be. The caller
    /// asks once for all the rows it read.
    private func left(_ row: Marfa.Item) -> Bool {
        bodyLinks[row.id] = nil
        guard restoring[row.id] == nil else { return false }
        if row.state == .trashed { binned[row.id] = row }
        return true
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
            var found: [String: Marfa.Item] = [:]
            var missing: [String] = []
            for id in ids {
                if let row = try await Self.asking(hub, { try await copy.items.get(id) }) { found[id] = row } else { missing.append(id) }
            }
            // A row the copy keeps only until its delete is answered is listed among the copy's trashed rows,
            // listed once for all of them.
            if !missing.isEmpty {
                let wanted = Set(missing)
                let trashed = try await Self.asking(hub) { try await copy.items.list(ListFilters(state: .trashed)) }
                for row in trashed where wanted.contains(row.id) { found[row.id] = row }
            }
            for id in ids {
                guard let row = found[id] else {
                    read.append((nil, id, []))
                    continue
                }
                let held: [Marfa.Edge]
                do { held = try await Self.asking(hub) { try await reading.edges(touching: id) } }
                catch MarfaError.hydrationIncomplete {
                    held = edges.edges(touching: id)
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
        var binChanged = false
        for (row, id, _) in read {
            let previous = rows[id]
            rows[id] = row
            if let row {
                binned[id] = nil
                await readLinks(of: row)
            } else {
                bodyLinks[id] = nil
                if let previous, left(previous) { binChanged = true }
            }
            for edgeID in edges.ids(touching: id) {
                if let edge = remove(edgeID) { affected.formUnion([edge.sourceId, edge.targetId]) }
            }
        }
        if binChanged { await sync.binChanged() }
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

    /// Maps `ids` again and tells readers what differs, in one change: the first time, everything as `.loaded`.
    /// An item's text goes with it where the item is new, its version moved or its text changed, so a page never
    /// shows a version with older text. Failures gathered on the way follow as `.unavailable`.
    func publish(_ ids: some Sequence<ItemID>, catalogueChanged: Bool = false) {
        hub.setBinned(binned)
        let copies = conflictedCopies()
        settleConflicts(copies)
        let ids = Set(ids).union(changedSync)
        changedSync = []
        if catalogueChanged, painted, hub.catalogue != catalogue { hub.publish(.catalogue(catalogue)) }
        var changes = ItemChanges()
        for id in ids {
            guard let row = rows[id.rawValue] ?? binned[id.rawValue] else {
                if items.removeValue(forKey: id) != nil { changes.removed.append(id) }
                bodies[id] = nil
                continue
            }
            let held = edges.edges(touching: row.id).sorted { $0.createdAt < $1.createdAt }
            let item = MarfaMapping.item(
                row, edges: held, catalogue: catalogue, sync: syncStates[id] ?? .settled, bodyLinks: bodyLinks[row.id],
                isHeld: { self.rows[$0] != nil })
            let text = MarfaMapping.body(of: row, catalogue: catalogue)
            let hash = text?.hashValue ?? 0
            let previous = items[id]
            if let text, previous?.version != item.version || bodies[id] != hash {
                changes.bodies.append(ItemBody(id: id, text: text, version: item.version))
            }
            bodies[id] = hash
            if previous != item {
                items[id] = item
                changes.upserted.append(item)
            }
        }
        if !painted {
            painted = true
            hub.publish(.loaded(SourceSnapshot(
                items: items.values.sorted(by: MarfaHub.newestFirst), catalogue: catalogue, views: views,
                bodies: Dictionary(changes.bodies.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last }))))
        } else if !changes.isEmpty {
            hub.publish(.changed(changes))
        }
        for failure in failures { hub.publish(.unavailable(failure)) }
        failures = []
        publishReport(copies)
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
}
