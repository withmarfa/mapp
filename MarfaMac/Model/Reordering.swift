import Foundation

/// Putting one entry of a list before another, which a drag in a panel's list and Move Up and Move Down both do.
nonisolated enum Reordering {
    /// `list` with `moved` dropped on `target`, as a drag onto a row: it takes the target's place, so a row dragged down
    /// lands after the target and one dragged up before it, and every place can be reached. A list that does not hold
    /// both is returned as it is.
    static func moving<Element: Equatable>(_ moved: Element, onto target: Element, in list: [Element]) -> [Element] {
        guard moved != target, let from = list.firstIndex(of: moved), let to = list.firstIndex(of: target) else { return list }
        var result = list
        result.insert(result.remove(at: from), at: to)
        return result
    }

    /// The element `moved` sits before once dropped on `target` (`moving(_:onto:in:)`), for a list that moves an element
    /// before another: the target for a row dragged up, the one after the target for a row dragged down, nil (last)
    /// where the target is last.
    static func anchor<Element: Equatable>(dropping moved: Element, onto target: Element, in list: [Element]) -> Element? {
        guard let from = list.firstIndex(of: moved), let to = list.firstIndex(of: target), from < to else { return target }
        return list.indices.contains(to + 1) ? list[to + 1] : nil
    }

    /// `list` with `entry` moved one place up (negative) or down.
    static func moving<Element: Equatable>(_ entry: Element, by offset: Int, in list: [Element]) -> [Element] {
        guard let index = list.firstIndex(of: entry), list.indices.contains(index + offset) else { return list }
        var moved = list
        moved.swapAt(index, index + offset)
        return moved
    }
}
