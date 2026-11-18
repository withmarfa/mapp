import Foundation
import Marfa
import Testing
@testable import MAPP

/// The store of counts and the one place that asks the package: a count Marfa cannot answer is nothing, a change asks
/// again, and a view that asks again for what it already asked costs no question.
@MainActor
@Suite(.hangLimit) struct ItemCountsTests {
    private actor Log {
        var asked: [[String]] = []
        func add(_ ids: [String]) { asked.append(ids) }
    }

    // MARK: The adapter

    @Test func theAdapterTellsACopyThatCannotAnswerAsUnavailableNotAsZero() async {
        struct Cannot: Error {}
        let counts = MarfaCounts { _, _ in throw Cannot() }
        await #expect(throws: ItemCountUnavailable.self) { try await counts.counts(of: [ItemID("a")], .children) }
    }

    @Test func theAdapterKeepsOnlyTheIdsAskedAndReadsTheGroups() async throws {
        let counts = MarfaCounts { _, _ in
            [
                Marfa.ItemCount(
                    id: "a", total: 5, statusGroups: StatusGroupCounts(notStarted: 1, completed: 2, canceled: 1), held: true),
                Marfa.ItemCount(id: "stranger", total: 9, held: true),
            ]
        }
        let answers = try await counts.counts(of: [ItemID("a"), ItemID("b")], .children)
        #expect(answers.keys.map(\.rawValue) == ["a"])
        #expect(answers[ItemID("a")]?.groups?.finished == 3)
        #expect(answers[ItemID("a")]?.total == 5)
    }

    @Test func theAdapterAsksForTheEdgeOrTheTableEachQueryNames() {
        #expect(MarfaCounts.counted(.children) == .backref(edgeType: "parent-of"))
        #expect(MarfaCounts.counted(.members) == .edge(edgeType: "in-collection"))
        #expect(MarfaCounts.counted(.rows(table: "messages")) == .rows(table: "messages"))
    }

    // MARK: The store

    @Test func anAnswerIsHeldAndAnIdAskedTwiceIsAskedOnce() async {
        let log = Log()
        let counts = ItemCounts { ids, _ in
            await log.add(ids.map(\.rawValue))
            return Dictionary(uniqueKeysWithValues: ids.map { ($0, ItemCountAnswer(total: 4, groups: nil)) })
        }
        counts.ask([ItemID("a")], .children)
        counts.ask([ItemID("a")], .children)
        #expect(await eventually { counts.answer(of: ItemID("a"), .children)?.total == 4 })
        counts.ask([ItemID("a")], .children)
        #expect(await log.asked == [["a"]])
    }

    @Test func aLongListIsAskedInBatchesOfAtMostAHundred() async {
        let log = Log()
        let counts = ItemCounts { ids, _ in
            await log.add(ids.map(\.rawValue))
            return Dictionary(uniqueKeysWithValues: ids.map { ($0, ItemCountAnswer(total: 1, groups: nil)) })
        }
        let ids = (0..<250).map { ItemID("i\($0)") }
        counts.ask(ids, .children)
        #expect(await eventually { counts.answer(of: ids[249], .children) != nil })
        #expect(await log.asked.map(\.count) == [100, 100, 50])
    }

    @Test func aCountThatCannotBeAnsweredStaysEmptyAndALaterChangeAsksAgain() async {
        let works = Flag()
        let counts = ItemCounts { ids, _ in
            guard works.isSet else { throw ItemCountUnavailable() }
            return Dictionary(uniqueKeysWithValues: ids.map { ($0, ItemCountAnswer(total: 2, groups: nil)) })
        }
        let id = ItemID("a")
        counts.ask([id], .children)
        #expect(await eventually { counts.questions == 1 })
        #expect(counts.answer(of: id, .children) == nil)

        works.set()
        counts.refresh()
        #expect(await eventually { counts.answer(of: id, .children)?.total == 2 })
    }

    @Test func aChangeAsksAgainAndTheNewNumberReplacesTheOldOne() async {
        let total = Counter()
        let counts = ItemCounts { ids, _ in
            Dictionary(uniqueKeysWithValues: ids.map { ($0, ItemCountAnswer(total: total.value, groups: nil)) })
        }
        let id = ItemID("a")
        total.value = 1
        counts.ask([id], .members)
        #expect(await eventually { counts.answer(of: id, .members)?.total == 1 })
        total.value = 2
        counts.refresh()
        #expect(await eventually { counts.answer(of: id, .members)?.total == 2 })
    }

    @Test func aChangeToATableAsksOnlyForRowsAndAnAnswerGoneWhereMarfaCanNoLongerAnswer() async {
        let works = Flag()
        works.set()
        let counts = ItemCounts { ids, query in
            guard works.isSet else { throw ItemCountUnavailable() }
            return Dictionary(uniqueKeysWithValues: ids.map { ($0, ItemCountAnswer(total: 3, groups: nil)) })
        }
        let id = ItemID("a")
        counts.ask([id], .children)
        counts.ask([id], .rows(table: "messages"))
        #expect(await eventually { counts.questions == 2 && counts.answer(of: id, .rows(table: "messages")) != nil })

        counts.refresh(rowsOnly: true)
        #expect(await eventually { counts.questions == 3 })
        // Allow a second batch to start if the table change also queued the child count.
        try? await Task.sleep(for: .milliseconds(300))
        #expect(counts.questions == 3)

        works.unset()
        counts.refresh()
        #expect(await eventually { counts.answer(of: id, .children) == nil && counts.answer(of: id, .rows(table: "messages")) == nil })
    }
}

/// A switch the test flips and the store's answering closure reads from another thread.
private nonisolated final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var on = false
    var isSet: Bool { lock.withLock { on } }
    func set() { lock.withLock { on = true } }
    func unset() { lock.withLock { on = false } }
}

private nonisolated final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var number = 0
    var value: Int {
        get { lock.withLock { number } }
        set { lock.withLock { number = newValue } }
    }
}
