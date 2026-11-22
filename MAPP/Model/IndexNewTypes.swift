import Foundation

/// The types the New row of the Items page offers, and their order. A Mac setting kept as one string of type
/// identifiers in the defaults (`key`), never written to Marfa. While none is kept the row holds the starting seven the
/// library has; a list the person has changed is kept as it is, even when empty. The catalogue offers no "favorite"
/// types, so the starting seven are named here, the one place that does, and skipped where the library lacks one.
nonisolated enum NewRowTypes {
    static let key = "indexNewTypes"

    /// What the row holds until the person edits it: a note, a table, a task, a bookmark, an event, a person and a place.
    static let starting = ["core.note", "core.table", "core.task", "core.bookmark", "core.event", "core.entity.person", "core.entity.place"]

    /// The list a kept string holds, or nil where none is kept.
    static func decode(_ kept: String?) -> [String]? {
        kept.map { $0.split(separator: ",").map(String.init) }
    }

    static func encode(_ ids: [String]) -> String { ids.joined(separator: ",") }

    /// The types the row shows, in order: the kept list, or the starting seven, less any that `offered` lacks (a type
    /// the library does not have, or no one can make) and any repeat.
    static func shown(_ offered: [ItemTypeOption], kept: String?) -> [ItemTypeOption] {
        var seen = Set<String>()
        return (decode(kept) ?? starting).compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return offered.first { $0.id.rawValue == id }
        }
    }

    /// What the Edit popover lists: first the types in the row, in its order, then the rest of `offered` in its own.
    static func listed(_ offered: [ItemTypeOption], kept: String?) -> (inRow: [ItemTypeOption], others: [ItemTypeOption]) {
        let inRow = shown(offered, kept: kept)
        let held = Set(inRow.map(\.id))
        return (inRow, offered.filter { !held.contains($0.id) })
    }

    /// The kept string with `id` put in at the end of the row, or taken out where it is in. The row as shown is the
    /// start, so a first change keeps the starting seven less what it removes.
    static func toggled(_ id: String, row: [ItemTypeOption]) -> String {
        let ids = row.map(\.id.rawValue)
        return encode(ids.contains(id) ? ids.filter { $0 != id } : ids + [id])
    }

    /// The kept string with the row's entries at `offsets` moved to `destination`, as `onMove` hands them.
    static func moved(_ row: [ItemTypeOption], from offsets: IndexSet, to destination: Int) -> String {
        let ids = row.map(\.id.rawValue)
        let moving = offsets.sorted().map { ids[$0] }
        var rest = ids.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        rest.insert(contentsOf: moving, at: destination - offsets.filter { $0 < destination }.count)
        return encode(rest)
    }
}
