import Foundation
import Marfa

/// Reading the copy whole into items, and hearing what changed in it.
extension MarfaEngine {
    /// Everything the copy holds, before any network: the first `.loaded`. Following the server starts after it.
    /// Asked again once painted, as a held undo does, it reads only what changed.
    func paint() async {
        if painted { await readChanged() } else { await reload() }
        await sync.start()
    }

    /// The least time between a hydration's whole reads while it runs.
    nonisolated static let fillReadSpacing = Duration.seconds(3)

    /// The most rows a batch of changes reads one by one; more ask the copy what changed (`readChanged`), which
    /// reads it whole where more changed than `changeLimit`, a list of every row rather than a read of each.
    nonisolated static let rereadLimit = 2000

    /// Whether reading `count` rows one by one would cost more than reading all of `held` again.
    nonisolated static func readsWhole(_ count: Int, of held: Int) -> Bool {
        count > rereadLimit || (count > 64 && count * 4 > held)
    }

    /// Takes what the copy said changed. The package coalesces what arrives while this runs, so the update is
    /// acknowledged only once it is read. Rows are read from the engine's own cursor (`readChanged`), which names
    /// everything since the last read, so the update says only what kind of read is wanted.
    ///
    /// A hydration under way is told at every step, so the window's word that the library is still loading stays
    /// true. The copy is read whole again only once `fillReadSpacing`, and four times as long as the last such read
    /// took, have passed, since each lists every row the copy holds. A fill that ended is read at once, so the report
    /// never says complete before the library holds every row.
    func take(update: CopyUpdate) async {
        let taking = Telemetry.begin(.engine, "update")
        var everything = false
        var catalogueChanged = false
        var viewsChanged = false
        var queueChanged = false
        var rowsChanged = false
        let statusChanged = lastUpdateFilled || lastConnection != update.connection
        lastUpdateFilled = update.fill != nil
        lastConnection = update.connection
        defer { tookFirstUpdate = true }
        switch update.reread {
        case .everything:
            // The first update asks for what paint has just read; what changed since is read from the cursor.
            if painted, !tookFirstUpdate {
                rowsChanged = true
                queueChanged = true
            } else {
                everything = true
            }
        case .parts(let parts):
            rowsChanged = !parts.rows.isEmpty
            catalogueChanged = parts.catalog
            viewsChanged = parts.views
            queueChanged = parts.queue
        }
        defer {
            taking.end(
                ("everything", everything ? 1 : 0), ("rows", rowsChanged ? 1 : 0), ("filling", update.fill == nil ? 0 : 1))
        }
        let fill = update.fill.map {
            LibraryFill(
                state: hub.report.value.fill?.state == .updating ? .updating : .filling, listed: $0.listed,
                expected: $0.expected)
        }
        if let fill {
            hub.report.update { $0.fill = fill }
            if everything || rowsChanged, ContinuousClock.now < fillReadAllowed { return }
        }
        if !painted {
            // Nothing is read before the first paint, which reads the copy whole.
            return
        }
        let start = ContinuousClock.now
        if everything || catalogueChanged {
            await reload()
        } else if rowsChanged {
            await readChanged()
        } else {
            if viewsChanged { await readViews() }
            if queueChanged {
                await readQueue()
                publish([])
            }
        }
        if everything || queueChanged { await takeAnswers() }
        if update.fill != nil {
            let end = ContinuousClock.now
            fillReadAllowed = end + max(Self.fillReadSpacing, (end - start) * 4)
        }
        if update.fill == nil, statusChanged { await finishFill() }
    }

    /// The report says complete as soon as the copy reads whole with no fill under way. It is read when a fill has
    /// just ended or the connection changed, the two things that change the copy's status; a local write does not.
    private func finishFill() async {
        guard let status = try? await reading.status() else { return }
        let fill = LibraryFill(status, completeness: status.hydration == .stale ? .stale :
                                status.hydration == .complete ? .complete : .partial)
        hub.report.update { $0.fill = fill }
    }

    /// Reads the catalogue, every row in every state, their edges and the queue, and publishes what differs. A
    /// copy that cannot be read keeps showing what it last held, and says why. What an item's text names is read
    /// again only where the item or its edges changed, a name in it was not yet bound to an item, its links could
    /// not be read before, or a change to another row may change what it names (`linkers`). A read that finds the
    /// copy whole takes a new `cursor`, taken before the rows are read, so a change made meanwhile is named again
    /// rather than missed. A row whose links cannot be read shows the edges it holds; the read then leaves no cursor,
    /// so the next read is whole and asks again.
    func reload() async {
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
        // A copy that cannot name its changes, such as one part way through a hydration, gives none.
        let mark = try? await Self.asking { try await reading.changes(since: nil, most: 0) }.next
        do {
            (catalogue, rows, edges, whole) = try await Self.asking {
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
                hub.report.update {
                    $0.fill = fill
                    $0.lastSynced = status.lastSynced
                }
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
        var touched = gone
        // The rows that may change what another item's text names, as `take` finds them.
        var moved = gone
        var arrived = false
        var files = gone.contains { isFile(previousRows[$0]) }
        for (id, row) in rows where previousRows[id] != row {
            touched.insert(id)
            guard Self.movesNames(previousRows[id], row, catalogue: catalogue) else { continue }
            moved.insert(id)
            if Self.arrives(previousRows[id], row) { arrived = true }
            if isFile(previousRows[id]) || isFile(row) { files = true }
        }
        var changedEdges: [(before: Marfa.Edge?, after: Marfa.Edge?)] = []
        for edge in edges where previousEdges[edge.id] != edge {
            touched.formUnion([edge.sourceId, edge.targetId])
            if let old = previousEdges[edge.id] { touched.formUnion([old.sourceId, old.targetId]) }
            changedEdges.append((previousEdges[edge.id], edge))
        }
        for edge in previousEdges.all where self.edges[edge.id] == nil {
            touched.formUnion([edge.sourceId, edge.targetId])
            changedEdges.append((edge, nil))
        }
        for (before, after) in changedEdges {
            for placed in Self.placed(before, after) {
                moved.insert(placed)
                if isFile(rows[placed]) { files = true }
            }
        }
        for id in gone.union(rows.keys.filter { previousRows[$0] == nil }) {
            for edge in previousEdges.edges(touching: id) + self.edges.edges(touching: id) {
                touched.formUnion([edge.sourceId, edge.targetId])
            }
        }
        let relinked = everything ? [] : linkers(
            of: moved, arrived: arrived, files: files,
            hosts: Self.hosts(of: moved, in: previousEdges).union(Self.hosts(of: moved, in: self.edges)))

        let linking = Telemetry.begin(.engine, "reload.links")
        let linked = rows.values.filter { row in
            guard Self.mayName(row, catalogue: catalogue) else { return false }
            if !everything, !touched.contains(row.id), !relinked.contains(row.id), let links = previousLinks[row.id],
               Self.allBound(links) { return false }
            return true
        }
        let linkReads = linked.count
        let links = await readLinks(of: linked)
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
        let ids = everything ? Set(rows.keys).union(gone).union(binned.keys) : touched
        published = ids.count
        publish(ids.map { ItemID($0) }, catalogueChanged: true)
        publishing.end(("ids", published))
        // Held undos are judged on what this read found, so they wait until it found the copy whole.
        guard whole else { return }
        // A read of what changed asks no row for links it could not read, so the next read is whole until they are.
        if links == .failed { cursor = nil } else if let mark { cursor = mark }
        await releaseHeld()
    }

    /// Reads the views the copy holds, and tells readers once they differ. One view this build cannot read refuses
    /// them all (`invalid`), so the sidebar lists none rather than some; any other failure keeps the views last
    /// read. A hydration under way answers only the views that have arrived, so those join the views last read and
    /// none leaves until the answer is whole: a window on a view not yet back is not moved off it.
    func readViews() async {
        let views: [LibraryView]
        do {
            let read = try await Self.asking { try await reading.views() }
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
    func left(_ row: Marfa.Item) -> Bool {
        bodyLinks[row.id] = nil
        guard restoring[row.id] == nil else { return false }
        if row.state == .trashed { binned[row.id] = row }
        return true
    }

    /// Whether an item's text can hold a link or an embed: a `[[link]]` or an `![](embed)`. The package reads each
    /// body from the copy one at a time, so the items that cannot are not asked.
    static func mayName(_ row: Marfa.Item, catalogue: Catalogue) -> Bool {
        guard let body = MarfaMapping.body(of: row, catalogue: catalogue) else { return false }
        // Read from the bytes, since a first paint asks this of every row: `[[` or `![` is a `[` after `[` or `!`.
        var previous: UInt8 = 0
        for byte in body.utf8 {
            if byte == UInt8(ascii: "["), previous == UInt8(ascii: "[") || previous == UInt8(ascii: "!") { return true }
            previous = byte
        }
        return false
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
            queue = try await Self.asking { try await copy.queue.all() }
        } catch {
            readFailed(error)
            return
        }
        let held = Set(queue.map(\.id)).union(answeredHeld.keys)
        counted.formIntersection(held)
        sentAsRead.formIntersection(held)
        if !readQueueOnce {
            readQueueOnce = true
            for write in queue {
                guard let verdict = write.verdict else { continue }
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
}
