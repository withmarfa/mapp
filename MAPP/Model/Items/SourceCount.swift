import Foundation

nonisolated struct SourceCount: Identifiable, Hashable {
    let code: String
    /// What the server names the source; its code while the server has not.
    let name: String
    let count: Int
    var id: String { code }
}

extension ItemLibrary {
    /// The sources the library lists, by name (`SourceDirectory.listing`), never the owner's source registry.
    var sourceCounts: [SourceCount] {
        let loaded = IndexRows.groupedBySource(items(in: .allNotes)).reduce(into: [:]) { $0[$1.code] = $1.items.count }
        return sources.listing(loaded: loaded).map { SourceCount(code: $0.code, name: $0.name, count: $0.count) }
    }

    /// The name to show for the source `code`.
    func sourceName(_ code: String) -> String { sources.name(code) }
}
