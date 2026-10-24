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
}
