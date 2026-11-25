import Foundation

/// What the server's installed connectors say of the items they keep: for each source, the direction of each type it
/// writes. Read once for a library (`ItemLibrary.readConnectors`), since connectors change rarely.
nonisolated struct ConnectorKeepers: Equatable, Sendable {
    private var directions: [String: [TypeID: ConnectorDirection]] = [:]
    /// Every installed connector's source, whether or not it names a kind.
    private var sources: Set<String> = []

    /// Notes that a connector writes under `source`.
    mutating func add(connector source: String) { sources.insert(source) }

    /// Whether a connector the server runs writes under `source`.
    func isConnector(_ source: String) -> Bool { sources.contains(source) || directions[source] != nil }

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
