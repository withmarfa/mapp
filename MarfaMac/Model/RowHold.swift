import Foundation

/// Where a row of a table, or a card of a board, was seen: its group or lane, and its place in it as drawn.
nonisolated struct HeldRow: Hashable, Sendable {
    let id: ItemID
    /// The group or lane it stood in; nil in a table that is not grouped.
    let group: String?
    let index: Int
}

/// The rows a window keeps where the person saw them, so a change does not carry a row from under them: the row under the
/// pointer, the one the keyboard chose, and the items just typed in place (`InPlaceRow`). A row stays held until it is
/// left; the next drawing puts it where its order and filters say.
nonisolated struct RowHold: Equatable, Sendable {
    /// The row under the pointer.
    var pointer: HeldRow?
    /// The one row the keyboard chose.
    var keyboard: HeldRow?
    /// The items typed in place and added, in order, which stand where they were typed: after a table's last row, or at
    /// the top of the lane they were typed in.
    var added: [ItemID] = []
    /// Where the added items were typed: the lane, or nil for a table.
    var addedIn: String?
    /// The held rows a drawing moved, so letting one go draws again.
    var moved: Set<ItemID> = []

    var anchored: [HeldRow] { [keyboard, pointer].compactMap { $0 } }

    /// Every held item.
    var ids: Set<ItemID> { Set(anchored.map(\.id)).union(added) }

    /// `rows` of `group` with each held row put back where it was seen, found by `row` where the order or the filters took
    /// it away, and every other held row taken out, so none is drawn twice. The items added in place stand after the
    /// rest, or at the top of a lane (`atTop`). Notes which rows it moved.
    mutating func holding<Row: Identifiable>(
        _ rows: [Row], group: String?, atTop: Bool = false, row: (ItemID) -> Row?
    ) -> [Row] where Row.ID == ItemID {
        let held = ids
        guard !held.isEmpty else { return rows }
        var kept = rows.filter { !held.contains($0.id) }
        for anchor in anchored.sorted(by: { $0.index < $1.index }) where anchor.group == group {
            guard !added.contains(anchor.id), let found = row(anchor.id) else { continue }
            let at = min(anchor.index, kept.count)
            if rows.firstIndex(where: { $0.id == anchor.id }) != anchor.index { moved.insert(anchor.id) }
            kept.insert(found, at: at)
        }
        if addedIn == group {
            let typed = added.compactMap(row)
            kept = atTop ? typed + kept : kept + typed
            moved.formUnion(typed.map(\.id))
        }
        return kept
    }

    /// Lets the row under the pointer go, answering whether a drawing had moved it.
    mutating func releasePointer() -> Bool { release(\.pointer) }

    /// Lets the keyboard's row go, answering whether a drawing had moved it.
    mutating func releaseKeyboard() -> Bool { release(\.keyboard) }

    /// Lets the items added in place go, as the row they were typed in is left.
    mutating func releaseAdded() -> Bool {
        guard !added.isEmpty else { return false }
        let wasMoved = !moved.isDisjoint(with: added)
        moved.subtract(added)
        added = []
        addedIn = nil
        return wasMoved
    }

    private mutating func release(_ path: WritableKeyPath<RowHold, HeldRow?>) -> Bool {
        guard let held = self[keyPath: path] else { return false }
        self[keyPath: path] = nil
        guard !anchored.contains(where: { $0.id == held.id }) else { return false }
        return moved.remove(held.id) != nil
    }
}
