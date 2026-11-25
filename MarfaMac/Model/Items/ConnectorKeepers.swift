import Foundation

/// What the server's installed connectors say of the items they keep: for each source, the direction of each type it
/// writes. Read once for a library (`ItemLibrary.readConnectors`), since connectors change rarely.
nonisolated struct ConnectorKeepers: Equatable, Sendable {
    private var directions: [String: [TypeID: ConnectorDirection]] = [:]

    /// One kind of `source`'s connector. A type that two kinds move in different ways moves both ways.
    mutating func add(source: String, type: TypeID, direction: ConnectorDirection) {
        let held = directions[source]?[type]
        directions[source, default: [:]][type] = held.map { $0 == direction ? $0 : .both } ?? direction
    }

    /// How the connector that writes under `source` moves items of `type`, or nil where none says.
    func direction(source: String, type: TypeID) -> ConnectorDirection? {
        directions[source]?[type]
    }
}
