import Foundation
import Marfa
import Testing
@testable import MarfaMac

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

    private func answering(_ total: Counter, log: Log? = nil) -> ItemCounts {
        ItemCounts { ids, _ in
            if let log { await log.add(ids.map(\.rawValue)) }
            return Dictionary(uniqueKeysWithValues: ids.map { ($0, ItemCountAnswer(total: total.value, groups: nil)) })
        }
    }

    @Test func anAnswerIsHeldAndAnIdWantedTwiceIsAskedOnce() async {
        let log = Log()
        let total = Counter()
        total.value = 4
        let counts = answering(total, log: log)
        counts.want([ItemID("a")], .children)
        counts.want([ItemID("a")], .children)
        #expect(await eventually { counts.answer(of: ItemID("a"), .children)?.total == 4 })
        #expect(await log.asked == [["a"]])
    }

    @Test func aRowReturningToViewAsksAgainEvenWhileAnotherWindowStillShowsIt() async {
        let log = Log()
        let total = Counter()
        total.value = 1
        let counts = answering(total, log: log)
        let id = ItemID("a")
        counts.want([id], .rows(table: "t"))  // One window.
        #expect(await eventually { counts.answer(of: id, .rows(table: "t"))?.total == 1 })

        total.value = 2
        counts.want([id], .rows(table: "t"))  // Another window, or the first returning, while the first still holds it.
        #expect(await eventually { counts.answer(of: id, .rows(table: "t"))?.total == 2 })
        #expect(await log.asked == [["a"], ["a"]])
    }

    @Test func releasingMoreAnswersThanAreKeptAdvancesTheRevisionSoNoOldNumberIsDrawnFromACachedRow() async {
        let total = Counter()
        total.value = 1
        let counts = answering(total)
        let ids = (0...ItemCounts.kept).map { ItemID("i\($0)") }
        counts.want(ids, .children)
        #expect(await eventually { counts.answer(of: ids.last!, .children) != nil })
        let before = counts.revision
        counts.release(ids, .children)
        #expect(counts.revision > before)
        #expect(counts.answer(of: ids[0], .children) == nil)
    }

    @Test func aLongListIsAskedInBatchesOfAtMostAHundred() async {
        let log = Log()
        let total = Counter()
        let counts = answering(total, log: log)
        let ids = (0..<250).map { ItemID("i\($0)") }
        counts.want(ids, .children)
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
        counts.want([id], .children)
        #expect(await eventually { counts.questions == 1 })
        #expect(counts.answer(of: id, .children) == nil)

        works.set()
        counts.refresh()
        #expect(await eventually { counts.answer(of: id, .children)?.total == 2 })
    }

    @Test func aChangeAsksAgainAndTheNewNumberReplacesTheOldOne() async {
        let total = Counter()
        let counts = answering(total)
        let id = ItemID("a")
        total.value = 1
        counts.want([id], .members)
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
        counts.want([id], .children)
        counts.want([id], .rows(table: "messages"))
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

    @Test func aTableChangeDuringAWaitingRefreshDoesNotCancelTheWiderOne() async {
        let total = Counter()
        let counts = answering(total)
        let id = ItemID("parent")
        total.value = 1
        counts.want([id], .children)
        #expect(await eventually { counts.answer(of: id, .children)?.total == 1 })

        total.value = 2
        counts.refresh()
        counts.refresh(rowsOnly: true)
        #expect(await eventually { counts.answer(of: id, .children)?.total == 2 })
    }

    @Test func everyCountWantedIsAskedAgainHoweverManyThereAre() async {
        let total = Counter()
        let counts = answering(total)
        let ids = (0..<2_001).map { ItemID("p\($0)") }
        total.value = 1
        counts.want(ids, .children)
        #expect(await eventually { counts.answer(of: ids[2_000], .children)?.total == 1 })

        total.value = 2
        counts.refresh()
        #expect(await eventually { counts.answer(of: ids[0], .children)?.total == 2 && counts.answer(of: ids[2_000], .children)?.total == 2 })
    }

    @Test func aCountLetGoIsNotAskedAgainAndIsAskedAfreshWhenWantedAgain() async {
        let log = Log()
        let total = Counter()
        total.value = 1
        let counts = answering(total, log: log)
        let id = ItemID("a")
        let visible = ItemID("b")
        counts.want([id, visible], .children)
        #expect(await eventually { counts.answer(of: id, .children)?.total == 1 })

        counts.release([id], .children)
        total.value = 2
        counts.refresh()
        // The visible row's new answer proves the refresh ran while the other row was off screen.
        #expect(await eventually { counts.answer(of: visible, .children)?.total == 2 })
        #expect(await log.asked == [["a", "b"], ["b"]])

        total.value = 3
        counts.want([id], .children)
        #expect(await eventually { counts.answer(of: id, .children)?.total == 3 })
        #expect(await log.asked == [["a", "b"], ["b"], ["a"]])
    }

    @Test func aCountWantedByTwoViewsIsKeptUntilBothLetGo() async {
        let log = Log()
        let total = Counter()
        let counts = answering(total, log: log)
        let id = ItemID("a")
        counts.want([id], .children)
        counts.want([id], .children)
        counts.release([id], .children)
        total.value = 5
        counts.refresh()
        #expect(await eventually { counts.answer(of: id, .children)?.total == 5 })
    }

    @Test func aCountAnsweredAfterItWasLetGoIsNotKept() async {
        let gate = Gate()
        let counts = ItemCounts { ids, _ in
            await gate.wait()
            return Dictionary(uniqueKeysWithValues: ids.map { ($0, ItemCountAnswer(total: 9, groups: nil)) })
        }
        let id = ItemID("a")
        counts.want([id], .children)
        #expect(await eventually { counts.questions == 1 })
        counts.release([id], .children)
        await gate.open()
        // Allow the released request to finish before checking that its answer was discarded.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(counts.answer(of: id, .children) == nil)
    }
}

/// Holds an answer until the test lets it go.
private actor Gate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func open() {
        isOpen = true
        for continuation in waiting { continuation.resume() }
        waiting = []
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
