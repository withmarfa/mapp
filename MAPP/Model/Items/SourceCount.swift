import Foundation

nonisolated struct SourceCount: Identifiable, Hashable {
    let name: String
    let count: Int
    var id: String { name }
}

extension ItemLibrary {
    /// Sources visible through this library's active items, never the owner's source registry.
    var sourceCounts: [SourceCount] {
        IndexRows.groupedBySource(items(in: .allNotes)).map { SourceCount(name: $0.name, count: $0.items.count) }
    }
}
