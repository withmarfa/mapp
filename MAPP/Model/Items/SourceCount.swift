import Foundation

nonisolated struct SourceCount: Identifiable, Hashable {
    let code: String
    /// What the server names the source; its code while the server has not.
    let name: String
    let count: Int
    var id: String { code }
}

extension ItemLibrary {
    /// Sources visible through this library's active items, by name, never the owner's source registry. A source's
    /// count is the server's when it has answered, else the loaded items'.
    var sourceCounts: [SourceCount] {
        let directory = sources
        return IndexRows.groupedBySource(items(in: .allNotes)).map {
            SourceCount(code: $0.code, name: directory.name($0.code), count: directory.counts?[$0.code] ?? $0.items.count)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The name to show for the source `code`.
    func sourceName(_ code: String) -> String { sources.name(code) }
}
