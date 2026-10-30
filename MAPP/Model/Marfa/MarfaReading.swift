import Marfa
import struct MarfaCore.Item
import struct MarfaCore.Edge
import struct MarfaCore.ListFilters

/// Reads that can be incomplete during hydration, apart from the copy's queued writes.
nonisolated protocol MarfaReading: Sendable {
    func status() async throws -> Status
    func items() async throws -> Rows<Marfa.Item>
    func edges(ofTypes types: [String]) async throws -> [Marfa.Edge]
    func edges(touching id: String) async throws -> [Marfa.Edge]
    /// The views still in use, as the sidebar lists them; `.partial` while a hydration is still bringing them.
    func views() async throws -> Rows<LibraryView>
    func items(inView id: String) async throws -> [Marfa.Item]
    /// What the item's text names, from the copy alone.
    func links(in id: String) async throws -> BodyLinks
}

nonisolated struct MarfaRead: MarfaReading {
    let copy: WorkingCopy
    func status() async throws -> Status { try await copy.status() }
    func items() async throws -> Rows<Marfa.Item> { try await copy.items.list(ListFilters(allStates: true)) }
    func edges(ofTypes types: [String]) async throws -> [Marfa.Edge] {
        var edges: [Marfa.Edge] = []
        for type in types { edges += try await copy.edges.ofType(type) }
        return edges
    }
    func edges(touching id: String) async throws -> [Marfa.Edge] {
        try await copy.edges.from(id) + copy.edges.to(id)
    }
    func views() async throws -> Rows<LibraryView> {
        let views = try await copy.items.views()
        return Rows(views.rows.compactMap(MarfaMapping.view), completeness: views.completeness)
    }
    func items(inView id: String) async throws -> [Marfa.Item] { try await copy.items.list(inView: id).rows }
    func links(in id: String) async throws -> BodyLinks { try await copy.items.links(in: id) }
}
