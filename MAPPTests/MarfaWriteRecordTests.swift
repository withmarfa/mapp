@testable import MAPP
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
