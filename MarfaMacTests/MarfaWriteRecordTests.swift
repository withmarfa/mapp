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

    /// A write still blocked may yet be made, but one refused never will be.
    @Test func aRefusalOutweighsABlockedWrite() {
        var record = MarfaWriteRecord()
        let id = WriteID()
        record.record(id, queued: ["a", "b"])

        // The blocked answer comes first, so the refusal must outweigh it rather than merely arrive first.
        #expect(record.answer("a", .blocked(.keySpent, nil)) == nil)
        #expect(record.answer("b", .refused(SyncProblem(code: "validation_error")))?.outcome == .refused(SyncProblem(code: "validation_error")))
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
