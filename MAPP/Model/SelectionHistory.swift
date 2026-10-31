import Foundation

/// The single items a window has shown, oldest first, and which of them it shows now.
struct SelectionHistory {
    struct Entry: Equatable {
        let place: SidebarItem
        let id: ItemID
    }

    nonisolated enum Direction { case back, forward }

    private static let limit = 100
    private(set) var entries: [Entry] = []
    private var position = -1

    /// Notes the selection after a change. Only one item shown is an entry; showing it again leaves the history as
    /// it is, and showing another drops whatever lay ahead.
    mutating func record(_ selection: Set<ItemID>, in place: SidebarItem) {
        guard selection.count == 1, let id = selection.first else { return }
        if entries.indices.contains(position), entries[position].id == id { return }
        entries.removeSubrange((position + 1)...)
        entries.append(Entry(place: place, id: id))
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
        position = entries.count - 1
    }

    mutating func move(to index: Int) {
        guard entries.indices.contains(index) else { return }
        position = index
    }

    /// The nearest entry in a direction whose item still exists and is not the one shown now (the app can move the
    /// selection off the entry the history is at). A deleted item is not shown, since no place lists it.
    func target(_ direction: Direction, in library: any ItemLibrary, shown: Set<ItemID>) -> (index: Int, entry: Entry)? {
        let candidates = direction == .back ? Array(entries.indices.prefix(max(position, 0)).reversed()) : Array(entries.indices.dropFirst(position + 1))
        return candidates.lazy.map { ($0, entries[$0]) }.first { _, entry in
            guard shown != [entry.id], let item = library.item(entry.id) else { return false }
            return item.state != .trashed
        }
    }
}
