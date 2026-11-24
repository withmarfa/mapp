@testable import MarfaMac
import Testing

struct MarfaWriteRecordTests {
    @Test func aWriteMadeOfSeveralIsAnsweredOnceWithTheWeightiestAnswer() throws {
        var record = MarfaWriteRecord()
        let id = WriteID()
        record.record(id, queued: ["a", "b", "c"])

        let first = record.answer("a", .accepted)
        let second = record.answer("b", .merged(fields: ["title"]))
        let last = record.answer("c", .accepted)
        #expect(first == nil && second == nil, "nothing is answered while a queued write waits")
        let answer = try #require(last)
        #expect(answer.id == id)
        #expect(answer.outcome == .merged(fields: ["title"]))
    }

    @Test func aRefusalOutweighsAMerge() throws {
        var record = MarfaWriteRecord()
        let id = WriteID()
        record.record(id, queued: ["a", "b"])

        let first = record.answer("a", .dead)
        let last = record.answer("b", .merged(fields: []))
        #expect(first == nil)
        let answer = try #require(last)
        #expect(answer.outcome == .dead)
    }

    /// A write still blocked may yet be made, but one refused never will be. The blocked answer comes first or last, so
    /// the refusal must outweigh it rather than merely arrive first or last.
    @Test(arguments: [true, false]) func aRefusalOutweighsABlockedWrite(blockedFirst: Bool) {
        var record = MarfaWriteRecord()
        let id = WriteID()
        record.record(id, queued: ["a", "b"])
        let refusal = WriteOutcome.refused(SyncProblem(code: "validation_error"))

        let answers = [("a", WriteOutcome.blocked(.keySpent, nil)), ("b", refusal)]
        let ordered = blockedFirst ? answers : answers.reversed()
        #expect(record.answer(ordered[0].0, ordered[0].1) == nil)
        #expect(record.answer(ordered[1].0, ordered[1].1)?.outcome == refusal)
    }

    /// Of answers that weigh the same, the one to the write answered first is given, whatever the writes are called.
    @Test(arguments: [["a", "b", "c"], ["c", "b", "a"]]) func ofAnswersThatWeighTheSameTheFirstIsGiven(order: [String]) {
        var record = MarfaWriteRecord()
        let id = WriteID()
        record.record(id, queued: order)
        let first = WriteOutcome.refused(SyncProblem(code: "first"))

        #expect(record.answer(order[0], first) == nil)
        #expect(record.answer(order[1], .refused(SyncProblem(code: "second"))) == nil)
        #expect(record.answer(order[2], .conflicted(sibling: ItemID("copy"), fields: ["title"]))?.outcome == first)
    }

    /// A blocked write answered first and then refused keeps its place, so its refusal is the one given.
    @Test func aWriteAnsweredAgainKeepsItsPlace() {
        var record = MarfaWriteRecord()
        let id = WriteID()
        record.record(id, queued: ["a", "b"])
        let refusal = WriteOutcome.refused(SyncProblem(code: "first"))

        #expect(record.answer("a", .blocked(.keySpent, nil)) == nil)
        #expect(record.answer("b", .blocked(.keySpent, nil))?.outcome == .blocked(.keySpent, nil))
        #expect(record.answer("b", .refused(SyncProblem(code: "second")))?.outcome == .refused(SyncProblem(code: "second")))
        #expect(record.answer("a", refusal)?.outcome == refusal, "a was answered first")
    }

    @Test func theAnswersSayWhatTheItemHoldsTheLaterOverTheEarlier() {
        var record = MarfaWriteRecord()
        let id = WriteID()
        record.record(id, queued: ["a", "b", "c"])

        #expect(record.answer("a", .accepted, holding: ["title": .string("One"), "summary": .string("Old")]) == nil)
        #expect(record.answer("b", .accepted) == nil)
        let answer = record.answer("c", .accepted, holding: ["summary": .string("New")])
        #expect(answer?.holding == ["title": .string("One"), "summary": .string("New")])
    }

    /// A blocked write is sent again once released, so what it was waiting for hears its final answer too.
    @Test func aBlockedWriteIsAnsweredAgainWhenItsFinalAnswerComes() {
        var record = MarfaWriteRecord()
        let id = WriteID()
        record.record(id, queued: ["a", "b"])

        #expect(record.answer("a", .accepted) == nil)
        #expect(record.answer("b", .blocked(.keySpent, nil))?.outcome == .blocked(.keySpent, nil))
        #expect(record.answer("b", .refused(SyncProblem(code: "validation_error")))?.outcome == .refused(SyncProblem(code: "validation_error")))
        #expect(record.answer("b", .accepted) == nil, "a final answer is given once")
    }

    @Test func aQueuedWriteTheRecordDoesNotHoldGivesNothing() {
        var record = MarfaWriteRecord()
        let id = WriteID()
        record.record(id, queued: ["a"])

        let elsewhere = record.answer("elsewhere", .accepted)
        let first = record.answer("a", .accepted)
        let again = record.answer("a", .accepted)
        #expect(elsewhere == nil)
        #expect(first?.id == id)
        #expect(again == nil, "an answer already given is not given twice")
    }
}
