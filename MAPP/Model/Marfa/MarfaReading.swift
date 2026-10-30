import Marfa
import struct MarfaCore.Item
import struct MarfaCore.Edge
import struct MarfaCore.ListFilters

/// Reads that can be incomplete during hydration, apart from the copy's queued writes.
nonisolated protocol MarfaReading: Sendable {
    func status() async throws -> Status
    func items() async throws -> Rows<Marfa.Item>
    /// Each of these rows the copy holds, in the bin or out; `.partial` while a hydration may not have brought one yet.
    func items(_ ids: [String]) async throws -> Rows<Marfa.Item>
    func edges(ofTypes types: [String]) async throws -> [Marfa.Edge]
    func edges(touching id: String) async throws -> [Marfa.Edge]
    /// Each of these edges the copy holds.
    func edges(_ ids: [String]) async throws -> [Marfa.Edge]
    /// The views still in use, as the sidebar lists them; `.partial` while a hydration is still bringing them.
    func views() async throws -> Rows<LibraryView>
    func items(inView id: String) async throws -> [Marfa.Item]
    /// What each item's text names, from the copy alone, leaving out an item in the bin or one it cannot read.
    func links(in ids: [String]) async throws -> [String: BodyLinks]
    /// What one item's text names, in the bin or out.
    func links(in id: String) async throws -> BodyLinks
    /// The rows that changed since `cursor`, or `.everything` where the copy cannot name them.
    func changes(since cursor: ChangeCursor?, most: Int) async throws -> CopyChanges
}

nonisolated struct MarfaRead: MarfaReading {
    let copy: WorkingCopy
    func status() async throws -> Status { try await copy.status() }
    func items() async throws -> Rows<Marfa.Item> { try await copy.items.list(ListFilters(allStates: true)) }
    func items(_ ids: [String]) async throws -> Rows<Marfa.Item> { try await copy.items.get(ids, includingBin: true) }
    func edges(ofTypes types: [String]) async throws -> [Marfa.Edge] {
        var edges: [Marfa.Edge] = []
        for type in types { edges += try await copy.edges.ofType(type) }
        return edges
    }
    func edges(touching id: String) async throws -> [Marfa.Edge] {
        try await copy.edges.from(id) + copy.edges.to(id)
    }
    func edges(_ ids: [String]) async throws -> [Marfa.Edge] { try await copy.edges.get(ids) }
    func views() async throws -> Rows<LibraryView> {
        let views = try await copy.items.views()
        return Rows(views.rows.compactMap(MarfaMapping.view), completeness: views.completeness)
    }
    func items(inView id: String) async throws -> [Marfa.Item] { try await copy.items.list(inView: id).rows }
    func links(in ids: [String]) async throws -> [String: BodyLinks] { try await copy.items.links(in: ids) }
    func links(in id: String) async throws -> BodyLinks { try await copy.items.links(in: id) }
    func changes(since cursor: ChangeCursor?, most: Int) async throws -> CopyChanges {
        try await copy.changes(since: cursor, most: most)
    }
}
