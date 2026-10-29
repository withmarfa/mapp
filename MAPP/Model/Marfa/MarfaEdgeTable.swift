import Foundation
import Marfa
import struct MarfaCore.Edge

/// The edges the engine holds, by identifier, and the edges touching each row, so mapping an item reads its own edges
/// rather than every edge. An edge keeps its identifier when it moves to other ends, so putting an edge in drops what
/// the table held under that identifier from its old ends first.
nonisolated struct MarfaEdgeTable: Sendable {
    private var byID: [String: Marfa.Edge] = [:]
    private var byItem: [String: Set<String>] = [:]

    subscript(id: String) -> Marfa.Edge? { byID[id] }
    var all: [Marfa.Edge] { Array(byID.values) }
    var count: Int { byID.count }

    /// The identifiers of the edges touching a row.
    func ids(touching item: String) -> Set<String> { byItem[item] ?? [] }

    func edges(touching item: String) -> [Marfa.Edge] { ids(touching: item).compactMap { byID[$0] } }

    mutating func insert(_ edge: Marfa.Edge) {
        _ = remove(edge.id)
        byID[edge.id] = edge
        byItem[edge.sourceId, default: []].insert(edge.id)
        byItem[edge.targetId, default: []].insert(edge.id)
    }

    @discardableResult
    mutating func remove(_ id: String) -> Marfa.Edge? {
        guard let edge = byID.removeValue(forKey: id) else { return nil }
        for end in [edge.sourceId, edge.targetId] {
            byItem[end]?.remove(id)
            if byItem[end]?.isEmpty == true { byItem[end] = nil }
        }
        return edge
    }

    mutating func removeAll() {
        byID = [:]
        byItem = [:]
    }
}
