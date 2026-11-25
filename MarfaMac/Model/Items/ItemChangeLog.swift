import Foundation

/// Which items each step of `contentRevision` changed, so a view that keeps something worked out from a place's items
/// remakes only those (`ItemLibrary.changedItems(since:)`). A step that reads the whole copy again, or changes the
/// catalogue, is a step no earlier revision can be followed across.
nonisolated struct ItemChangeLog {
    /// The most ids kept. Past it the oldest steps go, and a reader from before them works everything out again, which a
    /// sync that changes more than this asks for anyway.
    static let limit = 100_000

    /// The earliest revision the log can answer from.
    private(set) var start = 0
    private var steps: [(revision: Int, ids: Set<ItemID>)] = []
    private var held = 0

    mutating func record(_ ids: Set<ItemID>, at revision: Int) {
        steps.append((revision, ids))
        held += ids.count
        while held > Self.limit, !steps.isEmpty {
            let first = steps.removeFirst()
            held -= first.ids.count
            start = first.revision
        }
    }

    /// Nothing before `revision` can be followed past it.
    mutating func restart(at revision: Int) {
        steps = []
        held = 0
        start = revision
    }

    /// The ids changed after `revision` up to `now`, or nil where the log no longer reaches back to it.
    func changes(since revision: Int, now: Int) -> Set<ItemID>? {
        if revision == now { return [] }
        guard revision >= start, revision < now else { return nil }
        var ids: Set<ItemID> = []
        for step in steps.reversed() {
            guard step.revision > revision else { break }
            ids.formUnion(step.ids)
        }
        return ids
    }
}
