import Foundation

/// Library › Types, Collections and Sources: the places the Library holds, as rows (`IndexRow`).
extension Browser {
    /// The rows of the index the window shows, in no order, held while what they read stands: the window asks at every
    /// draw, and a source's or a type's rows read every item.
    func indexRows(in library: any ItemLibrary) -> [IndexRow] {
        let place = shown.place
        let key = IndexRowsKey(
            library: ObjectIdentifier(library), place: place, content: library.contentRevision, membership: library.membershipRevision,
            sources: library.sources.infos, connectors: library.connectors, views: library.views.map(\.id))
        if let held = indexRowsMemo, held.key == key { return held.rows }
        let rows = Self.indexRows(of: place, in: library)
        indexRowsMemo = (key, rows)
        return rows
    }

    private static func indexRows(of place: Place, in library: any ItemLibrary) -> [IndexRow] {
        let catalogue = library.catalogue
        switch place {
        case .types:
            return IndexRows.types(
                library.itemTypeCounts, items: library.activeItems, views: library.views, catalogue: catalogue,
                name: { library.name(of: .type($0)) })
        case .collections:
            return IndexRows.collections(
                library.collections, count: { library.count(in: .collection($0.id), scope: .all) }, catalogue: catalogue,
                directory: library.sources)
        case .sources:
            return IndexRows.sources(
                of: library.activeItems, catalogue: catalogue, directory: library.sources, connectors: library.connectors)
        default:
            return []
        }
    }

    struct IndexRowsKey: Equatable {
        let library: ObjectIdentifier
        let place: Place
        let content: Int
        let membership: Int
        let sources: [String: SourceInfo]
        let connectors: ConnectorKeepers?
        let views: [ItemID]
    }
}
