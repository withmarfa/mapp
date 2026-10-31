import Foundation
import Marfa

/// Reading the links in each row's text, and keeping the edges held.
extension MarfaEngine {
    /// The most rows whose links are asked for in one read, so one read never holds the copy for long.
    nonisolated static let linkReadSize = 512

    /// How a read of rows' links ended.
    nonisolated enum LinksRead {
        case read
        /// A hydration under way refused it; the hydration reads the copy whole once it ends.
        case filling
        /// A read of rows' links failed for another reason, so the copy cannot be used as it stands.
        case failed
    }

    /// Asks the package what each row's text names, many rows at a time. A row in the bin is left out of such a
    /// read, so it is asked for alone. Such a read also leaves out a row the copy does not hold or whose stored
    /// properties it cannot read, so it fails only as a whole, where the copy cannot be used: asking its rows one
    /// by one would fail again for each. A row whose links cannot be read shows the edges it holds, and no more:
    /// links read before may name what its text no longer does.
    @discardableResult
    func readLinks(of rows: [Marfa.Item]) async -> LinksRead {
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
            if read == nil, !filling { failed = true }
            for row in chunk {
                if let links = read?[row.id] {
                    bodyLinks[row.id] = links
                } else if read != nil, row.state == .trashed, !filling {
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
    func readLinks(of id: String) async -> (BodyLinks?, LinksRead) {
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

    /// Asks the package which item each of these rows, if a conflicted copy, was made from, and which copies each
    /// of those originals has. A copy kept or binned, or one that left the copy, no longer links its original.
    func readConflictLinks(_ ids: Set<String>) async {
        var originalsToRead: Set<String> = []
        var unread = 0
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
                if !(error is CancellationError) { unread += 1 }
                continue
            }
        }
        for original in originalsToRead {
            do {
                let copies = try await Self.asking(hub) { try await copy.items.conflictedCopies(of: original) }.map(\.id)
                linkedCopies[original] = copies.isEmpty ? nil : copies
            } catch {
                if !(error is CancellationError) { unread += 1 }
                continue
            }
        }
        if unread > 0 { Telemetry.conflictLinksUnread(count: unread) }
        if !originalsToRead.isEmpty { restate() }
    }

    func insert(_ edge: Marfa.Edge) {
        edges.insert(edge)
    }

    func remove(_ id: String) -> Marfa.Edge? {
        edges.remove(id)
    }
}
