import Foundation

/// Putting one entry of a list before another, which a drag in a panel's list and Move Up and Move Down both do.
nonisolated enum Reordering {
    /// `list` with `moved` taken out and put before `target`, or last where `target` is nil. A list that does not hold
    /// `moved`, or where the move changes nothing, is returned as it is.
    static func moving<Element: Equatable>(_ moved: Element, before target: Element?, in list: [Element]) -> [Element] {
        guard moved != target, list.contains(moved) else { return list }
        var rest = list.filter { $0 != moved }
        let index = target.flatMap { rest.firstIndex(of: $0) } ?? rest.count
        rest.insert(moved, at: index)
        return rest
    }

    /// `list` with `entry` moved one place up (negative) or down.
    static func moving<Element: Equatable>(_ entry: Element, by offset: Int, in list: [Element]) -> [Element] {
        guard let index = list.firstIndex(of: entry), list.indices.contains(index + offset) else { return list }
        var moved = list
        moved.swapAt(index, index + offset)
        return moved
    }
}
