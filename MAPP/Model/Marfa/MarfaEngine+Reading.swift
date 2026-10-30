import Foundation
import Marfa

/// Reading the copy into items, and hearing what changed in it.
extension MarfaEngine {
    /// Everything the copy holds, before any network: the first `.loaded`. Following the server starts after it.
    /// Asked again once painted, as a held undo does, it reads only what changed.
    func paint() async {
        if painted { await readChanged() } else { await reload() }
        guard following == nil else { return }
        following = MarfaFollow.start(copy.changes(), next: { [copy] in copy.changes() }, into: heard, tell: tell)
        await sync.start()
    }

    /// The least time between a hydration's whole reads while it runs.
    nonisolated static let fillReadSpacing = Duration.seconds(3)

    /// A step of a hydration under way. The fill is told at every step, so the window's word that the library is
    /// still loading stays true. The copy is read whole again only once `fillReadSpacing`, and four times as long
    /// as the last such read took, have passed, since each lists every row the copy holds and a hydration steps
    /// every half second. A fill that is complete is read at once, so the report never says complete before the
    /// library holds every row; the copy's own word that the hydration ended reads it whole again besides.
    func takeFillProgress() async {
        guard let status = try? await reading.status() else { return }
        let fill = LibraryFill(status, completeness: status.hydration == .stale ? .stale :
                                status.hydration == .complete ? .complete : .partial)
        guard hub.report.value.fill != fill else { return }
        guard fill.state == .complete || ContinuousClock.now >= fillReadAllowed else {
            hub.report.update { $0.fill = fill }
            return
        }
        let start = ContinuousClock.now
        await reload()
        let end = ContinuousClock.now
        fillReadAllowed = end + max(Self.fillReadSpacing, (end - start) * 4)
    }

    /// The most rows a batch of changes reads one by one; more ask the copy what changed (`readChanged`), which
    /// reads it whole where more changed than `changeLimit`, a list of every row rather than a read of each.
    nonisolated static let rereadLimit = 2000

    /// Whether reading `count` rows one by one would cost more than reading all of `held` again.
    nonisolated static func readsWhole(_ count: Int, of held: Int) -> Bool {
        count > rereadLimit || (count > 64 && count * 4 > held)
    }

    /// Rows the server destroyed, already let go, with each row as the engine last held it. The reads that follow
    /// tell their readers, and read again the links that named them, since the copy names no change to those.
    nonisolated struct Purged: Sendable {
        var ids: Set<String> = []
        var rows: [String: Marfa.Item] = [:]
    }

    /// What a batch of the follow's changes asks the engine to read again.
    private struct Batch {
        var ids: Set<String> = []
        /// Ids the server named, and edges, whose attachments may now be in the copy.
        var serverIDs: Set<String> = []
        var serverEdges: Set<String> = []
        var purged = Purged()
        /// Anything may have changed, so the copy is asked what did (`readChanged`).
        var anything = false
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
                batch.anything = true
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
                    batch.anything = true
                    continue
                }
                // An item the server destroyed leaves the copy and the bin.
                if let row = rows[id] ?? binned[id] { batch.purged.rows[id] = row }
                rows[id] = nil
                binned[id] = nil
                restoring[id] = nil
                batch.purged.ids.insert(id)
                batch.ids.insert(id)
                continue
            // A view written through the server changes the views alone.
            case .refreshed(.viewWritten): batch.views = true; continue
            // The copy forgot answers it held, which changes what each item shows of its writes and nothing else.
            case .refreshed(.forgotten): batch.queue = true; continue
            case .refreshed(.pinned), .refreshed(.unpinned):
                if let id = change.itemId { batch.ids.insert(id) } else { batch.anything = true }
                continue
            // A folder holds a device's sync settings and places no item.
            case .refreshed(.folderWritten): continue
            case .saved, .refreshed: batch.anything = true; continue
            }
            spoke = false
        }
        let taking = Telemetry.begin(.engine, "heard.batch", ("changes", batch.changes))
        let whole = batch.anything || Self.readsWhole(batch.ids.count, of: rows.count)
        defer { taking.end(("changes", batch.changes), ("ids", batch.ids.count), ("changed", whole ? 1 : 0)) }
        if whole {
            await readChanged(purged: batch.purged)
        } else if !batch.ids.isEmpty {
            await reread(batch.ids, purged: batch.purged)
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
    /// the engine does not hold names no row it knows, so with no item named the copy is asked what changed.
    private func name(_ change: Marfa.Change, in batch: inout Batch) {
        if let id = change.itemId { batch.ids.insert(id) }
        guard let edgeID = change.edgeId else { return }
        if let edge = edges[edgeID] {
            batch.ids.formUnion([edge.sourceId, edge.targetId])
        } else if change.itemId == nil {
            batch.anything = true
        }
    }

    /// Reads the catalogue, every row in every state, their edges and the queue, and publishes what differs. A
    /// copy that cannot be read keeps showing what it last held, and says why. What an item's text names is read
    /// again only where the item or its edges changed, a name in it was not yet bound to an item, its links could
    /// not be read before, or a change to another row may change what it names (`linkers`). A read that finds the
    /// copy whole takes a new `cursor`, taken before the rows are read, so a change made meanwhile is named again
    /// rather than missed. A row whose links cannot be read shows the edges it holds, and is asked again next time.
    func reload(purged: Purged = Purged()) async {
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
        let mark = try? await Self.asking(hub) { try await reading.changes(since: nil, most: 0) }.next
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
            publish(purged.ids.map { ItemID($0) })
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
        var touched = purged.ids.union(gone)
        // The rows that may change what another item's text names, as `take` finds them.
        var moved = purged.ids.union(gone)
        var arrived = false
        var files = purged.rows.values.contains { isFile($0) } || gone.contains { isFile(previousRows[$0]) }
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
        await readLinks(of: linked)
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
        let ids = everything ? Set(rows.keys).union(gone).union(binned.keys).union(purged.ids) : touched
        published = ids.count
        publish(ids.map { ItemID($0) }, catalogueChanged: true)
        publishing.end(("ids", published))
        // Held undos are judged on what this read found, so they wait until it found the copy whole.
        guard whole else { return }
        if let mark { cursor = mark }
        await releaseHeld()
    }

    /// The most rows of each kind a read of what changed rereads; where more changed, the copy is read whole, as
    /// `readsWhole` judges a batch: reading a quarter of the rows by name costs about as much as listing them all.
    var changeLimit: Int { min(Self.rereadLimit, max(64, rows.count / 4)) }

    /// Why a read of what changed reads the copy whole instead.
    private enum ReadWhole: Error {
        /// The copy is not whole, its catalogue changed, or it cannot name what changed.
        case unnamed
    }

    /// Asks the copy what changed since `cursor` and rereads only that, then takes the next cursor. Where the copy
    /// cannot say, isn't whole, or any read fails, it is read whole instead (`reload`), and the cursor is kept,
    /// since what it names has not been read. Once applied, the rows and edges held are what a whole read would
    /// find, so held undos are judged on them.
    ///
    /// A row whose links cannot be read, even alone, shows only the edges it holds: links read before may name
    /// what its text no longer does, so they are not kept. The copy is then read whole, from the cursor kept, which
    /// asks again for the links of every row that has none. A hydration begun since refuses every link read; the
    /// cursor is kept, and the hydration reads the copy whole once it ends.
    func readChanged(purged: Purged = Purged()) async {
        guard painted, let since = cursor else { return await reload(purged: purged) }
        let interval = Telemetry.begin(.engine, "changed")
        let status: Status
        let named: ChangedRows
        let next: ChangeCursor
        let found: [Marfa.Item]
        let held: [Marfa.Edge]
        do {
            (status, named, next, found, held) = try await Self.asking(hub) {
                let status = try await reading.status()
                guard status.hydration == .complete else { throw ReadWhole.unnamed }
                let catalogue = try await MarfaMapping.catalogue(
                    itemTypes: copy.catalog.itemTypes(), edgeTypes: copy.catalog.edgeTypes())
                guard catalogue == self.catalogue else { throw ReadWhole.unnamed }
                guard case .named(let named, let next) = try await reading.changes(since: since, most: changeLimit) else {
                    throw ReadWhole.unnamed
                }
                let found = try await reading.items(named.items)
                // A hydration begun since may not have brought every row back.
                guard found.completeness == .complete else { throw ReadWhole.unnamed }
                let held = try await reading.edges(named.edges)
                return (status, named, next, found.rows, held)
            }
        } catch {
            interval.end(("whole", 1))
            await reload(purged: purged)
            return
        }
        let (affected, links) = await take(named, rows: found, edges: held, purged: purged)
        hub.report.update { $0.fill = LibraryFill(status, completeness: .complete) }
        publish(affected.map { ItemID($0) })
        if links == .read { cursor = next }
        interval.end(("whole", links == .failed ? 1 : 0), ("items", named.items.count + named.removedItems.count),
                     ("edges", named.edges.count + named.removedEdges.count), ("published", affected.count))
        if links == .failed { return await reload() }
        await releaseHeld()
    }

    /// Takes in the rows and edges a read of what changed found, and answers the rows whose items may now map
    /// differently: each named, both ends of each edge named, before and after, the rows at the other end of an
    /// edge whose row came or went, and the rows whose links now read differently; and how the links were read.
    private func take(
        _ named: ChangedRows, rows found: [Marfa.Item], edges held: [Marfa.Edge], purged: Purged
    ) async -> (affected: Set<String>, links: LinksRead) {
        var affected = purged.ids
        var viewsChanged = false
        var binChanged = false
        var present: [Marfa.Item] = []
        // A purged row went. The engine let it go on hearing the purge, so `gone` below finds it no longer held.
        var moved = purged.ids
        var came: Set<String> = []
        var arrived = false
        var files = purged.rows.values.contains { isFile($0) }
        var gone = Set(named.removedItems)
        let foundIDs = Set(found.map(\.id))
        // A row named but not found left the copy after it was named.
        gone.formUnion(named.items.filter { !foundIDs.contains($0) })
        for row in found {
            guard MarfaMapping.isLibraryItem(row) else {
                viewsChanged = true
                gone.insert(row.id)
                continue
            }
            let previous = rows[row.id]
            if previous == nil { came.insert(row.id) }
            if Self.arrives(previous, row) { arrived = true }
            if Self.movesNames(previous, row, catalogue: catalogue) {
                moved.insert(row.id)
                if isFile(previous) || isFile(row) { files = true }
            }
            present.append(row)
        }
        gone.subtract(present.map(\.id))
        for id in gone where rows[id] != nil {
            moved.insert(id)
            if isFile(rows[id]) { files = true }
        }
        if views.contains(where: { gone.contains($0.id.rawValue) }) { viewsChanged = true }
        // A whole read reads only the edges of the catalogue's types.
        let kept = held.filter { catalogue.edgeTypes[$0.edgeType] != nil }
        let keptByID = Dictionary(kept.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let presentByID = Dictionary(present.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for id in named.edges + named.removedEdges {
            for placed in Self.placed(edges[id], keptByID[id]) {
                moved.insert(placed)
                if isFile(presentByID[placed] ?? rows[placed]) { files = true }
            }
        }

        // Taken before the edges change, as the edges after are taken once they have.
        var ends = came.union(gone).union(moved).reduce(into: Set<String>()) { ends, id in
            for edge in edges.edges(touching: id) { ends.formUnion([edge.sourceId, edge.targetId]) }
        }
        var hosts = Self.hosts(of: moved, in: edges)
        for row in present {
            rows[row.id] = row
            binned[row.id] = nil
            affected.insert(row.id)
        }
        for id in gone {
            affected.insert(id)
            guard let previous = rows.removeValue(forKey: id) else { continue }
            if left(previous) { binChanged = true }
        }
        for id in named.edges + named.removedEdges {
            if let edge = edges.remove(id) { affected.formUnion([edge.sourceId, edge.targetId]) }
        }
        for edge in kept {
            edges.insert(edge)
            affected.formUnion([edge.sourceId, edge.targetId])
        }
        for id in came.union(gone).union(moved) {
            for edge in edges.edges(touching: id) { ends.formUnion([edge.sourceId, edge.targetId]) }
        }
        hosts.formUnion(Self.hosts(of: moved, in: edges))
        affected.formUnion(ends)

        await sync.unreadable(Set(present.filter { $0.unreadableProperties != nil }.map(\.id)))
        if binChanged { await sync.binChanged() }
        let linking = linkers(of: moved, arrived: arrived, files: files, hosts: hosts).subtracting(present.map(\.id))
        let before = linking.reduce(into: [String: BodyLinks]()) { before, id in before[id] = bodyLinks[id] }
        let links = await readLinks(of: present + linking.compactMap { rows[$0] })
        affected.formUnion(linking.filter { before[$0] != bodyLinks[$0] })
        if viewsChanged { await readViews() }
        await readConflictLinks(affected)
        await readQueue()
        return (affected, links)
    }

    /// Whether a row's coming, going or change could change what another item's text names. The package names an
    /// item by its ID, by its title property (the field its type's hints name, else `title`), by the file name of
    /// its placement in a folder (`placed`), and a file by its bytes, never by its text: so a change to the text
    /// alone names nothing new, unless the text is kept in the title property itself.
    nonisolated static func movesNames(_ previous: Marfa.Item?, _ now: Marfa.Item?, catalogue: Catalogue) -> Bool {
        guard let previous, let now else { return previous != nil || now != nil }
        guard previous.type == now.type, previous.state == now.state else { return true }
        let info = catalogue.itemTypes[TypeID(now.type)]
        var before = previous.properties, after = now.properties
        if let field = MarfaMapping.bodyField(of: info), field != info?.titleField ?? "title" {
            before.removeValue(forKey: field)
            after.removeValue(forKey: field)
        }
        return before != after
    }

    /// The placements of `id` among `edges`, in a fixed order.
    nonisolated static func placements(of id: String, in edges: [Marfa.Edge]) -> [Marfa.Edge] {
        edges.filter { $0.edgeType == MarfaMapping.placementEdge && $0.sourceId == id }.sorted { $0.id < $1.id }
    }

    /// The row whose placement an edge's change moved, which the package names by its placement's file name.
    nonisolated static func placed(_ before: Marfa.Edge?, _ after: Marfa.Edge?) -> Set<String> {
        guard before != after else { return [] }
        return Set([before, after].compactMap { edge in
            edge.flatMap { $0.edgeType == MarfaMapping.placementEdge ? $0.sourceId : nil }
        })
    }

    /// The rows whose text the package may read `ids` from, through an edge: the host of a link edge to one, and
    /// the item a file among them is attached to. Any other edge, such as a parent's, names nothing in the text.
    nonisolated static func hosts(of ids: Set<String>, in edges: MarfaEdgeTable) -> Set<String> {
        ids.reduce(into: []) { hosts, id in
            for edge in edges.edges(touching: id) {
                switch edge.edgeType {
                case MarfaMapping.bodyLinkEdge where edge.targetId == id: hosts.insert(edge.sourceId)
                case MarfaMapping.attachmentEdge where edge.sourceId == id: hosts.insert(edge.targetId)
                default: continue
                }
            }
        }
    }

    /// The rows held whose links may read differently because the rows `moved` came, went or changed how they are
    /// named, which the copy names no change to (`WorkingCopy.changes(since:most:)`). The package reads a link from
    /// the link edges at its host, which put the host among the `hosts`, or from an ID the copy holds outside the
    /// bin, so a link that names no item yet may name one only once a row `arrived` (`arrives`); and it reads an embed
    /// from its host's attachments, which put the host among the `hosts` too, or from every file held, so an embed
    /// it lists with no item may read differently once a file moved (`files`). So: the `hosts`, the rows whose links
    /// or embeds name one of the rows moved, and those rows with a link or embed that names no item.
    private func linkers(of moved: Set<String>, arrived: Bool, files: Bool, hosts: Set<String>) -> Set<String> {
        guard !moved.isEmpty else { return [] }
        func reads(_ names: [Marfa.BodyName], unbound: Bool) -> Bool {
            names.contains { name in
                if case .item(let target) = name.target { moved.contains(target) } else { unbound }
            }
        }
        var found = hosts
        for (id, links) in bodyLinks where reads(links.links, unbound: arrived) || reads(links.embeds, unbound: files) {
            found.insert(id)
        }
        return found.filter { rows[$0] != nil }
    }

    /// Whether a row arrived where the package can bind a link to it by ID: into the copy, or out of the bin, since
    /// the package binds an ID only to an item the copy holds outside the bin.
    nonisolated static func arrives(_ previous: Marfa.Item?, _ now: Marfa.Item?) -> Bool {
        guard let now else { return false }
        guard let previous else { return true }
        return previous.state == .trashed && now.state != .trashed
    }

    /// Whether a row is a file, which an embed may name by its title wherever it is held.
    private func isFile(_ row: Marfa.Item?) -> Bool {
        guard let row else { return false }
        let type = TypeID(row.type)
        return type == MarfaMapping.fileType || catalogue.isSubtype(type, ofAnyOf: [MarfaMapping.fileType])
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
        // Read from the bytes, since a first paint asks this of every row: `[[` or `![` is a `[` after `[` or `!`.
        var previous: UInt8 = 0
        for byte in body.utf8 {
            if byte == UInt8(ascii: "["), previous == UInt8(ascii: "[") || previous == UInt8(ascii: "!") { return true }
            previous = byte
        }
        return false
    }

    /// The most rows whose links are asked for in one read, so one read never holds the copy for long.
    nonisolated static let linkReadSize = 512

    /// How a read of rows' links ended.
    nonisolated enum LinksRead {
        case read
        /// A hydration under way refused it; the hydration reads the copy whole once it ends.
        case filling
        /// A row's links could not be read for another reason, even alone.
        case failed
    }

    /// Asks the package what each row's text names, many rows at a time. A row in the bin is left out of such a
    /// read, so it is asked for alone. Such a read also leaves out a row the copy does not hold or whose stored
    /// properties it cannot read, so it fails only as a whole; one that fails other than for a hydration is asked
    /// again row by row. A row whose links cannot be read shows the edges it holds, and no more: links read before
    /// may name what its text no longer does.
    @discardableResult
    private func readLinks(of rows: [Marfa.Item]) async -> LinksRead {
        var named: [Marfa.Item] = []
        for row in rows {
            if Self.mayName(row, catalogue: catalogue) { named.append(row) } else { bodyLinks[row.id] = nil }
        }
        var filling = false
        var failed = false
        for start in stride(from: 0, to: named.count, by: Self.linkReadSize) {
            let chunk = named[start..<min(start + Self.linkReadSize, named.count)]
            let ids = chunk.map(\.id)
            var read: [String: BodyLinks]?
            do {
                read = try await Self.asking(hub) { try await reading.links(in: ids) }
            } catch MarfaError.hydrationIncomplete {
                filling = true
            } catch {
                read = nil
            }
            for row in chunk {
                if let links = read?[row.id] {
                    bodyLinks[row.id] = links
                } else if (read == nil || row.state == .trashed) && !filling {
                    let (links, ended) = await readLinks(of: row.id)
                    bodyLinks[row.id] = links
                    if ended == .filling { filling = true }
                    if ended == .failed { failed = true }
                } else {
                    bodyLinks[row.id] = nil
                }
            }
        }
        return failed ? .failed : filling ? .filling : .read
    }

    /// Asks the package what one row's text names.
    private func readLinks(of id: String) async -> (BodyLinks?, LinksRead) {
        do {
            return (try await Self.asking(hub) { try await reading.links(in: id) }, .read)
        } catch MarfaError.notFound {
            // The row left the copy, and the read that finds it gone lets it go.
            return (nil, .read)
        } catch MarfaError.hydrationIncomplete {
            return (nil, .filling)
        } catch {
            return (nil, .failed)
        }
    }

    #if DEBUG
    /// Reads every row's links afresh, for `EngineCostTests`; answers how many rows could name a link.
    func readLinksOfEveryRow() async -> Int {
        let rows = Array(rows.values)
        await readLinks(of: rows)
        return rows.filter { Self.mayName($0, catalogue: catalogue) }.count
    }
    #endif

    /// The items whose links named nothing, or nothing yet, which a drain, a catch-up or a new item may have
    /// settled: those whose links now read differently.
    func settledLinks() async -> Set<String> {
        let unsettled = bodyLinks.filter { _, links in (links.links + links.embeds).contains { !$0.target.isItem } }
        await readLinks(of: unsettled.keys.compactMap { rows[$0] })
        return Set(unsettled.filter { bodyLinks[$0.key] != $0.value }.keys)
    }

    /// Reads again the rows named, with every edge they hold or are held by. All are read before any is taken in, and
    /// every edge held before is dropped before any is put back: an edge that moved to other ends is listed under
    /// the item it left, so taking the items in one at a time, in whatever order, could drop the edge as it is now
    /// after putting it back. A hydration under way may not have brought a row back yet, so a row it does not find
    /// is left as it was rather than taken as gone. A row whose links cannot be read has the copy read whole, as
    /// `readChanged` does.
    func reread(_ ids: Set<String>, purged: Purged = Purged()) async {
        var affected = Set(ids)
        let interval = Telemetry.begin(.engine, "reread", ("ids", ids.count))
        defer { interval.end(("ids", ids.count), ("affected", affected.count)) }
        var read: [(row: Marfa.Item?, id: String, held: [Marfa.Edge])] = []
        do {
            let found = try await Self.asking(hub) { try await reading.items(Array(ids)) }
            let byID = Dictionary(found.rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for id in ids {
                guard let row = byID[id] else {
                    if found.completeness != .partial { read.append((nil, id, [])) }
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
        // A purged row went, even where a hydration under way left it unread. The engine let it go on hearing the
        // purge, so the row it held is taken from `purged`.
        var moved = purged.ids
        var came = false
        var files = purged.rows.values.contains { isFile($0) }
        for (row, id, held) in read {
            let previous = rows[id] ?? purged.rows[id]
            let placed = row != nil && Self.placements(of: id, in: edges.edges(touching: id))
                != Self.placements(of: id, in: held)
            guard placed || Self.movesNames(previous, row, catalogue: catalogue) else { continue }
            moved.insert(id)
            if previous == nil, row != nil { came = true }
            if isFile(previous) || isFile(row) { files = true }
        }
        var hosts = Self.hosts(of: moved, in: edges)
        var binChanged = false
        for (row, id, _) in read {
            let previous = rows[id]
            rows[id] = row
            if row != nil {
                binned[id] = nil
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
        hosts.formUnion(Self.hosts(of: moved, in: edges))
        let present = read.compactMap(\.row)
        let linking = linkers(of: moved, arrived: arrived, files: files, hosts: hosts).subtracting(present.map(\.id))
        let before = linking.reduce(into: [String: BodyLinks]()) { before, id in before[id] = bodyLinks[id] }
        let links = await readLinks(of: present + linking.compactMap { rows[$0] })
        affected.formUnion(linking.filter { before[$0] != bodyLinks[$0] })
        await readConflictLinks(affected)
        await readQueue()
        publish(affected.map { ItemID($0) })
        if links == .failed { await reload() }
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
        var present: [(id: ItemID, row: Marfa.Item)] = []
        for id in ids {
            guard let row = rows[id.rawValue] ?? binned[id.rawValue] else {
                if items.removeValue(forKey: id) != nil { changes.removed.append(id) }
                bodies[id] = nil
                continue
            }
            present.append((id, row))
        }
        let mapped = Self.mapped(present, reading: Mapping(
            rows: rows, edges: edges, catalogue: catalogue, syncStates: syncStates, bodyLinks: bodyLinks))
        for (item, text, hash) in mapped {
            let id = item.id
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

    /// What mapping a row reads of the engine, copied out so several threads can map rows at once.
    nonisolated struct Mapping: Sendable {
        let rows: [String: Marfa.Item]
        let edges: MarfaEdgeTable
        let catalogue: Catalogue
        let syncStates: [ItemID: SyncState]
        let bodyLinks: [String: BodyLinks]
    }

    /// Below this many rows, spreading the work costs more than it saves.
    nonisolated static let serialMapping = 256

    /// Each row as the library shows it, with its text and the text's hash, in the order given. A whole read maps
    /// every row, which is most of a launch's paint, and each row maps alone, so a large batch is spread over the
    /// processor's cores.
    nonisolated static func mapped(
        _ present: [(id: ItemID, row: Marfa.Item)], reading state: Mapping
    ) -> [(item: Item, text: String?, hash: Int)] {
        func map(_ row: Marfa.Item, id: ItemID) -> (item: Item, text: String?, hash: Int) {
            let held = state.edges.edges(touching: row.id).sorted { $0.createdAt < $1.createdAt }
            let item = MarfaMapping.item(
                row, edges: held, catalogue: state.catalogue, sync: state.syncStates[id] ?? .settled,
                bodyLinks: state.bodyLinks[row.id], isHeld: { state.rows[$0] != nil })
            let text = MarfaMapping.body(of: row, catalogue: state.catalogue)
            return (item, text, text?.hashValue ?? 0)
        }
        guard present.count >= serialMapping else { return present.map { map($0.row, id: $0.id) } }
        let chunks = min(present.count / (serialMapping / 4), ProcessInfo.processInfo.activeProcessorCount * 4)
        // Each chunk fills its own slots, and the chunks together cover every slot once.
        return Array<(item: Item, text: String?, hash: Int)>(unsafeUninitializedCapacity: present.count) { buffer, count in
            nonisolated(unsafe) let slots = buffer
            DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
                let start = present.count * chunk / chunks, end = present.count * (chunk + 1) / chunks
                for index in start..<end { slots.initializeElement(at: index, to: map(present[index].row, id: present[index].id)) }
            }
            count = present.count
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
}
