import Foundation
import Marfa

/// Reading only what the copy names as changed, and the rows a change reaches through links and placements.
extension MarfaEngine {
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
    /// A row whose links cannot be read shows only the edges it holds: links read before may name what its text
    /// no longer does, so they are not kept. The copy is then read whole, from the cursor kept, which asks again for
    /// the links of every row that has none. A hydration begun since refuses every link read; the
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
    func linkers(of moved: Set<String>, arrived: Bool, files: Bool, hosts: Set<String>) -> Set<String> {
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
    func isFile(_ row: Marfa.Item?) -> Bool {
        guard let row else { return false }
        let type = TypeID(row.type)
        return type == MarfaMapping.fileType || catalogue.isSubtype(type, ofAnyOf: [MarfaMapping.fileType])
    }

    /// Whether every name in an item's text is bound to an item, so it reads the same until the item or its edges
    /// change. A name not yet bound may be bound by a drain, a catch-up or another item arriving.
    nonisolated static func allBound(_ links: BodyLinks) -> Bool {
        (links.links + links.embeds).allSatisfy(\.target.isItem)
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
        var arrived = false
        var files = purged.rows.values.contains { isFile($0) }
        for (row, id, held) in read {
            let previous = rows[id] ?? purged.rows[id]
            let placed = row != nil && Self.placements(of: id, in: edges.edges(touching: id))
                != Self.placements(of: id, in: held)
            guard placed || Self.movesNames(previous, row, catalogue: catalogue) else { continue }
            moved.insert(id)
            if Self.arrives(previous, row) { arrived = true }
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
}
