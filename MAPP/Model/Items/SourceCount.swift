import Foundation

nonisolated struct SourceCount: Identifiable, Hashable {
    let name: String
    let count: Int
    var id: String { name }
}

extension ItemLibrary {
    /// Sources visible through this library's active items, never the owner's source registry.
    var sourceCounts: [SourceCount] {
        let counts = items(in: .allNotes).reduce(into: [String: Int]()) { counts, item in
            if let source = item.source, !source.isEmpty { counts[source, default: 0] += 1 }
        }
        return counts.map { SourceCount(name: $0.key, count: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
