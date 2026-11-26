import Foundation
import Observation

/// What a count counts, as Marfa is asked: the items filed under an item (`parent-of`), the members of a collection
/// (`in-collection`), or the rows an item holds in one of its tables.
nonisolated enum CountQuery: Hashable, Sendable {
    case children
    case members
    case rows(table: String)
}

/// What Marfa answered for one item: how many there are, and for linked items how many of them are in each status group.
nonisolated struct ItemCountAnswer: Hashable, Sendable {
    nonisolated struct Groups: Hashable, Sendable {
        var notStarted = 0
        var inProgress = 0
        var completed = 0
        var canceled = 0

        /// The items that have a status in a group, which "of N" counts. An item with none adds to the total only.
        var withStatus: Int { notStarted + inProgress + completed + canceled }
        /// Completed and canceled both finish an item.
        var finished: Int { completed + canceled }
    }

    var total: Int
    /// Nil for a table's rows, which have no status.
    var groups: Groups?
}

/// A source that could not answer, as when the copy cannot be sure and the server cannot be asked. It is told as no count,
/// never as zero.
nonisolated struct ItemCountUnavailable: Error, Hashable {}

/// The counts a library has worked out for the items on screen: what each answer was the last time Marfa was asked.
///
/// Drawing never waits for a count, and never asks for one. A view reads `answer(of:_:)`, which is nil until Marfa has
/// answered. A row, card or cell that is on screen says what it wants with `want(_:_:)` when it appears and lets go with
/// `release(_:_:)` when it goes, both outside drawing. The questions go out in batches of at most `batch` ids, off the main
/// thread, one at a time. An answer is redrawn by the observation of `revision`. A count Marfa cannot answer holds nothing,
/// so a view draws nothing in its place, never a zero or an old number.
///
/// The last view to release a count leaves its answer cached. The next view to request it can draw that answer
/// while a fresh request is in flight.
@MainActor @Observable
final class ItemCounts {
    typealias Answering = @Sendable ([ItemID], CountQuery) async throws -> [ItemID: ItemCountAnswer]

    /// The most ids one question names, which is what Marfa answers in one request.
    nonisolated static let batch = 100
    /// How long a run of changes is let settle before the counts on screen are asked again.
    nonisolated static let settling = Duration.milliseconds(150)
    /// Exceeding this limit evicts all answers that no view currently needs.
    nonisolated static let kept = 5_000

    private struct Key: Hashable {
        let id: ItemID
        let query: CountQuery
    }

    /// What a change asks again for: everything wanted, or only what counts a table's rows.
    private enum Scope { case rows, all }

    /// Counts the answers that changed, which a view reads to be told when to draw again.
    private(set) var revision = 0
    /// Which items each step of `revision` answered anew (`changedItems(since:)`).
    @ObservationIgnored private var changeLog = ItemChangeLog()

    @ObservationIgnored private let answering: Answering
    @ObservationIgnored private var answers: [Key: ItemCountAnswer] = [:]
    /// How many views want each count. A count nobody wants is neither asked nor asked again.
    @ObservationIgnored private var wanted: [Key: Int] = [:]
    /// Answers kept for counts nobody wants now, which `want` asks again.
    @ObservationIgnored private var unheld: Set<Key> = []
    @ObservationIgnored private var pending: [CountQuery: [ItemID]] = [:]
    @ObservationIgnored private var queued: Set<Key> = []
    /// What the changes that have not yet settled ask again for. A later change joins it rather than replacing it.
    @ObservationIgnored private var stale: Scope?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var settle: Task<Void, Never>?
    /// How many questions have gone out, for tests to see that a pass that wants nothing new asks nothing.
    @ObservationIgnored private(set) var questions = 0

    init(answering: @escaping Answering) {
        self.answering = answering
    }

    /// The last answer for the item, or nil where Marfa has none to give yet.
    func answer(of id: ItemID, _ query: CountQuery) -> ItemCountAnswer? {
        _ = revision
        return answers[Key(id: id, query: query)]
    }

    /// A returning view can have an old answer even when another view still holds it.
    /// Call on appearance. Views that ask before the next batch share its answer.
    func want(_ ids: some Sequence<ItemID>, _ query: CountQuery) {
        var asking = false
        for id in ids {
            let key = Key(id: id, query: query)
            wanted[key, default: 0] += 1
            unheld.remove(key)
            if !queued.contains(key) {
                enqueue(key)
                asking = true
            }
        }
        if asking { work() }
    }

    /// Releases one view's claim on the counts. Other views can still need the same answers.
    func release(_ ids: some Sequence<ItemID>, _ query: CountQuery) {
        for id in ids {
            let key = Key(id: id, query: query)
            guard let holders = wanted[key] else { continue }
            guard holders == 1 else {
                wanted[key] = holders - 1
                continue
            }
            wanted[key] = nil
            queued.remove(key)
            if answers[key] != nil { unheld.insert(key) }
        }
        if unheld.count > Self.kept {
            for key in unheld { answers[key] = nil }
            unheld = []
            // Cached table rows can still contain an evicted answer.
            revision += 1
            changeLog.restart(at: revision)
        }
    }

    /// Asks again for what is wanted once changes have settled: a child or an edge changed, or a table did (`rowsOnly`), or
    /// Marfa can be reached again. A request made while one waits joins it, so a table change never takes the place of a
    /// wider one. An answer held stays until the new one comes, so a count that has not changed does not flicker, and goes
    /// where Marfa can no longer answer it.
    func refresh(rowsOnly: Bool = false) {
        stale = rowsOnly && stale != .all ? .rows : .all
        guard settle == nil else { return }
        settle = Task { [weak self] in
            try? await Task.sleep(for: Self.settling)  // Lets a burst of changes end, so one question covers it.
            guard !Task.isCancelled, let self else { return }
            self.askAgain()
        }
    }

    private func askAgain() {
        let scope = stale ?? .all
        stale = nil
        settle = nil
        for key in wanted.keys {
            if scope == .rows { guard case .rows = key.query else { continue } }
            enqueue(key)
        }
        work()
    }

    // MARK: Asking

    private func enqueue(_ key: Key) {
        if queued.insert(key).inserted { pending[key.query, default: []].append(key.id) }
    }

    private func work() {
        guard worker == nil, !pending.isEmpty else { return }
        worker = Task { [weak self] in
            while let self, let (query, ids) = self.nextBatch() { self.take(await self.answer(ids, query), for: ids, query) }
            self?.worker = nil
        }
    }

    /// The next ids to ask for one query, leaving out any let go since they were queued.
    private func nextBatch() -> (CountQuery, [ItemID])? {
        while let query = pending.keys.first {
            var ids = pending[query] ?? []
            var batch: [ItemID] = []
            var read = 0
            while read < ids.count, batch.count < Self.batch {
                let id = ids[read]
                read += 1
                if queued.remove(Key(id: id, query: query)) != nil { batch.append(id) }
            }
            ids.removeFirst(read)
            pending[query] = ids.isEmpty ? nil : ids
            if !batch.isEmpty {
                questions += 1
                return (query, batch)
            }
        }
        return nil
    }

    /// Nil where the source could not answer.
    private func answer(_ ids: [ItemID], _ query: CountQuery) async -> [ItemID: ItemCountAnswer]? {
        try? await answering(ids, query)
    }

    /// Keeps what Marfa answered for the counts still wanted. One let go while it was asked is dropped.
    private func take(_ got: [ItemID: ItemCountAnswer]?, for ids: [ItemID], _ query: CountQuery) {
        var changed: Set<ItemID> = []
        for id in ids {
            let key = Key(id: id, query: query)
            guard wanted[key] != nil else { continue }
            if let answer = got?[id] {
                if answers.updateValue(answer, forKey: key) != answer { changed.insert(id) }
            } else if answers.removeValue(forKey: key) != nil {
                changed.insert(id)
            }
        }
        guard !changed.isEmpty else { return }
        revision += 1
        changeLog.record(changed, at: revision)
    }

    /// The items whose answers changed after `revision`, or nil where that cannot be said, as after answers were let go.
    func changedItems(since revision: Int) -> Set<ItemID>? {
        changeLog.changes(since: revision, now: self.revision)
    }
}
