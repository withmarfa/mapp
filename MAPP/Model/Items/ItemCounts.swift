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
/// Drawing never waits for a count. A view reads `answer(of:_:)`, which is nil until Marfa has answered, and says what it
/// wants with `ask(_:_:)`, which returns at once: the question goes out in batches of at most `batch` ids, off the main
/// thread, one at a time. An answer is redrawn by the observation of `revision`. A count Marfa cannot answer holds
/// nothing, so a view draws nothing in its place, never a zero or an old number.
@MainActor @Observable
final class ItemCounts {
    typealias Answering = @Sendable ([ItemID], CountQuery) async throws -> [ItemID: ItemCountAnswer]

    /// The most ids one question names, which is what Marfa answers in one request.
    nonisolated static let batch = 100
    /// How long a run of changes is let settle before the counts on screen are asked again.
    nonisolated static let settling = Duration.milliseconds(150)
    /// How many ids of each query are remembered for asking again after a change: more than a window shows.
    nonisolated static let remembered = 2_000

    private struct Key: Hashable {
        let id: ItemID
        let query: CountQuery
    }

    /// Counts the answers that changed, which a view reads to be told when to draw again.
    private(set) var revision = 0

    @ObservationIgnored private let answering: Answering
    @ObservationIgnored private var answers: [Key: ItemCountAnswer] = [:]
    /// Asked for and not yet answered, or answered with nothing: not asked for again until something changes.
    @ObservationIgnored private var asked: Set<Key> = []
    /// What the views last wanted, in the order they asked, to ask again after a change.
    @ObservationIgnored private var wanted: [CountQuery: [ItemID]] = [:]
    @ObservationIgnored private var pending: [CountQuery: [ItemID]] = [:]
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

    /// Says the items' counts are wanted. Ids already asked for are not asked again until `refresh()`. It changes nothing a
    /// view observes, so a view may call it while drawing.
    func ask(_ ids: some Sequence<ItemID>, _ query: CountQuery) {
        var fresh: [ItemID] = []
        for id in ids where asked.insert(Key(id: id, query: query)).inserted { fresh.append(id) }
        guard !fresh.isEmpty else { return }
        var held = wanted[query, default: []]
        held += fresh
        if held.count > Self.remembered { held.removeFirst(held.count - Self.remembered) }
        wanted[query] = held
        pending[query, default: []] += fresh
        work()
    }

    /// Asks again for everything the views last wanted, once changes have settled: a child or an edge changed, or a table
    /// did (`rowsOnly`), or Marfa can be reached again. An answer held stays until the new one comes, so a count that
    /// has not changed does not flicker, and goes where Marfa can no longer answer it.
    func refresh(rowsOnly: Bool = false) {
        settle?.cancel()
        settle = Task { [weak self] in
            try? await Task.sleep(for: Self.settling)  // Lets a burst of changes end, so one question covers it.
            guard !Task.isCancelled, let self else { return }
            self.askAgain(rowsOnly: rowsOnly)
        }
    }

    private func askAgain(rowsOnly: Bool) {
        for (query, ids) in wanted {
            if rowsOnly { guard case .rows = query else { continue } }
            let queued = Set(pending[query] ?? [])
            pending[query, default: []] += ids.filter { !queued.contains($0) }
        }
        work()
    }

    // MARK: Asking

    private func work() {
        guard worker == nil, !pending.isEmpty else { return }
        worker = Task { [weak self] in
            while let self, let (query, ids) = self.nextBatch() { await self.take(await self.answer(ids, query), for: ids, query) }
            self?.worker = nil
        }
    }

    private func nextBatch() -> (CountQuery, [ItemID])? {
        guard let query = pending.keys.first, var ids = pending[query] else { return nil }
        let batch = Array(ids.prefix(Self.batch))
        ids.removeFirst(batch.count)
        pending[query] = ids.isEmpty ? nil : ids
        questions += 1
        return (query, batch)
    }

    /// Nil where the source could not answer.
    private func answer(_ ids: [ItemID], _ query: CountQuery) async -> [ItemID: ItemCountAnswer]? {
        try? await answering(ids, query)
    }

    private func take(_ got: [ItemID: ItemCountAnswer]?, for ids: [ItemID], _ query: CountQuery) {
        var changed = false
        for id in ids {
            let key = Key(id: id, query: query)
            if let answer = got?[id] {
                if answers.updateValue(answer, forKey: key) != answer { changed = true }
            } else if answers.removeValue(forKey: key) != nil {
                changed = true
            }
        }
        if changed { revision += 1 }
    }
}
