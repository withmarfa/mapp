import Foundation
import Marfa
import SQLite3
import Testing
@testable import MAPP

/// A drain the copy runs itself ends in a report or an error, and every answer the queue holds is taken before any is
/// forgotten. The queue is made to hold the answers the server would have recorded.
@Suite(.serialized)
struct MarfaDrainAnswersTests {
    private func recordAccepted(_ id: String, at url: URL) throws {
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(db, "UPDATE queue SET verdict = 'accepted', sent = 1 WHERE id = ?", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        _ = id.withCString { sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        #expect(sqlite3_step(statement) == SQLITE_DONE)
        #expect(sqlite3_changes(db) == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func aDrainThatStopsOnAnErrorLeavesItsRecordedAnswersToBeTaken() async throws {
        let root = URL.temporaryDirectory.appending(path: "MarfaDrainAnswers-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let connection = try MarfaConnection(address: "http://127.0.0.1:9")
        let location = try MarfaStoreLocation(root: root)
        let source = try await MarfaSource.open(connection, keys: MemoryKeyStore([connection: "unused"]), location: location)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        let first = WriteID()
        let second = WriteID()
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "First", body: "First text")), as: first)
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "Second", body: "Second text")), as: second)
        await source.queueSubmitted()
        let queued = try await source.copy.queue.all()
        #expect(queued.count == 2)
        let accepted = try #require(queued.first)
        let remaining = try #require(queued.last)
        // The drain recorded the first answer, then stopped on a full store.
        try recordAccepted(accepted.id, at: location.store(for: connection))
        source.events.yield(.change(Change(origin: .queueNotDrained(.storageFull(message: "full")), itemId: nil, edgeId: nil)))
        await source.queueSubmitted()
        _ = try #require(await log.wait(for: .seconds(10)) { $0.answer(to: first) == .accepted })
        #expect(log.current.answer(to: second) == nil)

        // A later drain reports only the write it answered.
        try recordAccepted(remaining.id, at: location.store(for: connection))
        let report = MarfaSync.report(answeredIn: try await source.copy.queue.all().filter { $0.id == remaining.id })
        source.events.yield(.change(Change(origin: .queueDrained(report), itemId: nil, edgeId: nil)))
        await source.queueSubmitted()
        _ = try #require(await log.wait { $0.answer(to: second) == .accepted })
        #expect(try await source.copy.queue.all().isEmpty)
        #expect(log.current.answer(to: first) == .accepted, "the first write was forgotten without being answered")
        await source.close()
    }

    @Test(.timeLimit(.minutes(1)))
    func anEarlierReportDoesNotForgetAnswersARunningDrainRecorded() async throws {
        let root = URL.temporaryDirectory.appending(path: "MarfaDrainAnswers-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let connection = try MarfaConnection(address: "http://127.0.0.1:9")
        let location = try MarfaStoreLocation(root: root)
        let source = try await MarfaSource.open(connection, keys: MemoryKeyStore([connection: "unused"]), location: location)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        let first = WriteID()
        let second = WriteID()
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "First", body: "First")), as: first)
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "Second", body: "Second")), as: second)
        await source.queueSubmitted()
        let queued = try await source.copy.queue.all()
        let accepted = try #require(queued.first)
        let remaining = try #require(queued.last)
        try recordAccepted(accepted.id, at: location.store(for: connection))
        let firstReport = MarfaSync.report(answeredIn: try await source.copy.queue.all())
        let holding = LiveMarfa.Flag()
        await source.engine.whenAnswering {
            holding.set()
            try? await Task.sleep(for: .milliseconds(500))
        }
        source.events.yield(.change(Change(origin: .queueDrained(firstReport), itemId: nil, edgeId: nil)))
        #expect(await LiveMarfa.until { holding.isSet })
        // The copy's next drain can record answers while the engine is still taking the earlier report.
        try recordAccepted(remaining.id, at: location.store(for: connection))
        source.events.yield(.change(Change(origin: .queueNotDrained(.copyExpired(reason: "read_view_changed", message: "expired")), itemId: nil, edgeId: nil)))
        await source.queueSubmitted()
        _ = try #require(await log.wait { $0.answer(to: first) == .accepted })
        #expect(log.current.answer(to: second) == nil)
        #expect(try await source.copy.queue.all().contains { $0.id == remaining.id }, "the earlier report forgot the later answer before it could be taken")
        await source.close()
    }
}
