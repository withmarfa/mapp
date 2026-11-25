import Foundation
import Marfa
import MarfaTesting
import SQLite3
import Testing
@testable import MarfaMac

/// The engine takes the answers the copy recorded with `Queue.takeAnswered`, whether a drain ended in a report or an
/// error. The queue is made to hold the answers the server would have recorded.
@Suite(.serialized, .hangLimit)
struct MarfaDrainAnswersTests {
    nonisolated static func recordAccepted(_ id: String, at url: URL) throws {
        try record(id, "UPDATE queue SET verdict = 'accepted', sent = 1 WHERE id = ?", at: url)
    }

    nonisolated static func recordBlocked(_ id: String, at url: URL) throws {
        try record(id, "UPDATE queue SET verdict = 'blocked', reason = 'key_spent', sent = 1 WHERE id = ?", at: url)
    }

    nonisolated static func record(_ id: String, _ sql: String, at url: URL) throws {
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        // The copy's own lifecycle may hold the file for a moment.
        sqlite3_busy_timeout(db, 5000)
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        _ = id.withCString { sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        #expect(sqlite3_step(statement) == SQLITE_DONE)
        #expect(sqlite3_changes(db) == 1)
    }

    private func open(
        at root: URL = URL.temporaryDirectory.appending(path: "MarfaDrainAnswers-\(UUID())")
    ) async throws -> (MarfaSource, ChangeLog, URL) {
        let connection = try MarfaConnection(address: "http://127.0.0.1:9")
        let location = MarfaStoreLocation(root: root)
        let source = try await MarfaSource.open(connection, signIns: ScriptedSignIns([connection.address: "unused"]), location: location)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        return (source, log, location.store(for: connection))
    }

    private func submit(_ source: MarfaSource, _ titles: [String]) async throws -> [(WriteID, Marfa.QueuedWrite)] {
        let ids = titles.map { _ in WriteID() }
        for (title, id) in zip(titles, ids) {
            source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: title, body: title)), as: id)
        }
        await source.queueSubmitted()
        let queued = try await source.copy.queue.all()
        #expect(queued.count == titles.count)
        return Array(zip(ids, queued))
    }

    @Test
    func theAnswersADrainRecordedBeforeItStoppedAreTakenAndTheRestWait() async throws {
        let (source, log, store) = try await open()
        defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }
        let writes = try await submit(source, ["First", "Second"])
        let (first, accepted) = writes[0]
        let (second, remaining) = writes[1]
        // The drain recorded the first answer, then stopped on a full store.
        try Self.recordAccepted(accepted.id, at: store)
        await source.tellAnswers()
        _ = try #require(await log.wait { $0.answer(to: first) == .accepted })
        #expect(log.current.answer(to: second) == nil)
        #expect(try await source.copy.queue.all().map(\.id) == [remaining.id])

        // A later drain answers the other.
        try Self.recordAccepted(remaining.id, at: store)
        await source.tellAnswers()
        _ = try #require(await log.wait { $0.answer(to: second) == .accepted })
        #expect(try await source.copy.queue.all().isEmpty)
        #expect(log.current.answer(to: first) == .accepted, "the first answer was lost")
        await source.close()
    }

    @Test
    func anAnswerIsToldOnceHoweverOftenTheEngineLooks() async throws {
        let (source, log, store) = try await open()
        defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }
        let writes = try await submit(source, ["First"])
        try Self.recordBlocked(writes[0].1.id, at: store)
        await source.tellAnswers()
        _ = try #require(await log.wait { $0.answer(to: writes[0].0) != nil })
        let told = log.current.changes.count { if case .answered = $0 { true } else { false } }
        await source.tellAnswers()
        await source.tellAnswers()
        #expect(log.current.changes.count { if case .answered = $0 { true } else { false } } == told)
        #expect(try await source.copy.queue.all().count == 1, "a blocked write is kept for release")
        await source.close()
    }

    @Test
    func theEngineNamesTheEventItIsTakingAndAQuitWaitsForWritesAlone() async throws {
        let (source, log, store) = try await open()
        defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }
        _ = log
        let activity = try #require(source.engineActivity)
        let writes = try await submit(source, ["First"])
        try Self.recordAccepted(writes[0].1.id, at: store)

        let holding = LiveMarfa.Flag()
        let (held, release) = AsyncStream<Void>.makeStream()
        defer { release.finish() }
        source.engine.hooks.answering.set {
            holding.set()
            // Holds the engine in this event, as a slow one would be held, until the test has made its checks.
            for await _ in held {}
        }
        Task { await source.tellAnswers() }
        #expect(await LiveMarfa.until { holding.isSet })
        // An update the first write set off can take the answers before `tellAnswers` does, so either event may hold.
        let holder = activity.snapshot().step
        #expect(holder == "answers" || holder == "update")
        // With no write told, a quit does not wait behind the slow read.
        await source.queueSubmitted()
        #expect(activity.snapshot().step == holder, "the quit waited for a read of the copy")
        let second = ItemID.mint()
        source.submit(.create(id: second, ItemDraft(type: TypeID("core.note"), title: "Second", body: "Second")), as: WriteID())
        #expect(activity.snapshot().waiting >= 1, "the write told behind the slow event is not counted as waiting")
        #expect(activity.snapshot().writes == 1)
        async let behind: Void = source.queueSubmitted()
        release.finish()
        await behind
        #expect(activity.snapshot().writes == 0)
        #expect(try await source.copy.queue.all().contains { $0.itemId == second.rawValue }, "the write was not queued once the quit's wait ended")
        source.engine.hooks.answering.set(nil)
        #expect(await LiveMarfa.until { activity.snapshot().step == nil })
        await source.close()
    }

    /// The copy clears a refused write that carried no content, such as a favorite, as it hands the answer over, so
    /// the engine keeps it before the person until they discard it.
    @Test
    func aRefusedWriteThatCarriedNoContentStaysAProblemUntilDiscarded() async throws {
        let (source, log, store) = try await open()
        defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }
        let created = try await submit(source, ["Favorite"])
        try Self.recordAccepted(created[0].1.id, at: store)
        await source.tellAnswers()
        _ = try #require(await log.wait { $0.answer(to: created[0].0) == .accepted })
        let item = try #require(log.current.item(titled: "Favorite")).id

        let tag = WriteID()
        source.submit(.tag(item, ItemTag.favorite, on: true), as: tag)
        await source.queueSubmitted()
        let queued = try #require(try await source.copy.queue.all().first)
        try Self.record(queued.id, "UPDATE queue SET verdict = 'refused', reason = 'item_not_found', sent = 1 WHERE id = ?", at: store)
        await source.tellAnswers()
        _ = try #require(await log.wait { $0.answer(to: tag) != nil })
        #expect(try await source.copy.queue.all().isEmpty, "the copy keeps only refused writes that carried content")

        #expect(await eventually { source.syncReport.problems.contains { $0.id == .write(queued.id) } }, "\(source.syncReport.problems)")
        let entry = try #require(source.syncReport.problems.first { $0.id == .write(queued.id) })
        #expect(entry.kind == .refused && entry.itemID == item)
        #expect(entry.actions.contains(.discard))
        #expect(try await source.resolve(entry.id, by: .discard))
        #expect(await eventually { !source.syncReport.problems.contains { $0.id == entry.id } })
        await source.close()
    }

    /// The create is answered on its own, so a parent link the server refuses later is told by itself, naming the
    /// item, its parent and the server's reason.
    @Test @MainActor
    func aParentLinkRefusedLaterIsToldAtTheItem() async throws {
        let (source, log, store) = try await open()
        defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }
        let library = MarfaLibrary(source: source, notices: Notices())
        try #require(await eventually { library.isLoaded })
        let parent = ItemID.mint()
        let child = ItemID.mint()
        source.submit(.create(id: parent, ItemDraft(type: TypeID("core.note"), title: "Garden", body: "Plans")), as: WriteID())
        source.submit(.create(id: child, ItemDraft(type: TypeID("core.note"), title: "Seeds", body: "List", parent: parent)), as: WriteID())
        await source.queueSubmitted()
        _ = try #require(await log.wait { $0.snapshot?.items.first { $0.id == child }?.edgesOut.isEmpty == false })
        #expect(library.notices.waiting.isEmpty, "queued, the link is not refused yet: \(library.notices.waiting.map(\.message))")
        let link = try #require(try await source.copy.queue.all().first { $0.kind == .createEdge })
        try Self.record(link.id, "UPDATE queue SET verdict = 'refused', reason = 'edge_constraint_violation', sent = 1 WHERE id = ?", at: store)
        await source.tellAnswers()

        let told = await eventually {
            library.notices.waiting.contains {
                $0.title == "Can’t Put Item Under Its Parent" && $0.message.contains("“Seeds”") && $0.message.contains("“Garden”")
            }
        }
        #expect(told, "told: \(library.notices.waiting.map(\.message))")
        #expect(library.item(child) != nil, "the item stays")
        await source.close()
    }

    /// The copy's queue does not say a link was a new item's, so the app keeps that with the write across a relaunch.
    @Test @MainActor
    func aParentLinkRefusedAfterARelaunchIsToldAtTheItem() async throws {
        let root = URL.temporaryDirectory.appending(path: "MarfaDrainAnswers-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let parent = ItemID.mint()
        let child = ItemID.mint()
        do {
            let (source, log, _) = try await open(at: root)
            source.submit(.create(id: parent, ItemDraft(type: TypeID("core.note"), title: "Garden", body: "Plans")), as: WriteID())
            source.submit(.create(id: child, ItemDraft(type: TypeID("core.note"), title: "Seeds", body: "List", parent: parent)), as: WriteID())
            await source.queueSubmitted()
            _ = try #require(await log.wait { $0.snapshot?.items.first { $0.id == child }?.edgesOut.isEmpty == false })
            await source.close()
        }
        let (source, _, store) = try await open(at: root)
        let library = MarfaLibrary(source: source, notices: Notices())
        try #require(await eventually { library.isLoaded })
        let link = try #require(try await source.copy.queue.all().first { $0.kind == .createEdge })
        try Self.record(link.id, "UPDATE queue SET verdict = 'refused', reason = 'edge_constraint_violation', sent = 1 WHERE id = ?", at: store)
        await source.tellAnswers()

        let told = await eventually {
            library.notices.waiting.contains {
                $0.title == "Can’t Put Item Under Its Parent" && $0.message.contains("“Seeds”") && $0.message.contains("“Garden”")
            }
        }
        #expect(told, "told: \(library.notices.waiting.map(\.message))")
        await source.close()
    }

    /// The queue lists a file's refused create, so a refusal after its window closed gives its draft back.
    @Test @MainActor
    func aFileRefusedLaterIsARefusedCreate() async throws {
        let (source, _, store) = try await open()
        defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }
        let library = MarfaLibrary(source: source, notices: Notices())
        try #require(await eventually { library.isLoaded })
        let file = store.deletingLastPathComponent().appending(path: "Plan.txt")
        try Data("plan".utf8).write(to: file)
        let id = try #require(await library.addFile(file, title: "Plan", parentID: nil, tier: .library, tags: []))
        let create = try #require(try await source.copy.queue.all().first { $0.kind == .createItem && $0.itemId == id.rawValue })
        try Self.record(create.id, "UPDATE queue SET verdict = 'refused', reason = 'validation_failed', sent = 1 WHERE id = ?", at: store)
        await source.tellAnswers()

        #expect(await eventually { library.refusedCreates.contains(id) })
        await source.close()
    }

    /// A file's upload refused for its own reason takes its create with it, folded into the upload's problem.
    @Test @MainActor
    func aFileWhoseUploadIsRefusedLaterIsARefusedCreate() async throws {
        let (source, _, store) = try await open()
        defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }
        let library = MarfaLibrary(source: source, notices: Notices())
        try #require(await eventually { library.isLoaded })
        let file = store.deletingLastPathComponent().appending(path: "Plan.txt")
        try Data("plan".utf8).write(to: file)
        let id = try #require(await library.addFile(file, title: "Plan", parentID: nil, tier: .library, tags: []))
        let writes = try await source.copy.queue.all()
        let upload = try #require(writes.first { $0.kind == .uploadBlob })
        let create = try #require(writes.first { $0.kind == .createItem && $0.itemId == id.rawValue })
        try #require(create.dependsOn.contains(upload.id))
        try Self.record(upload.id, "UPDATE queue SET verdict = 'refused', reason = 'The file is too large.', sent = 0 WHERE id = ?", at: store)
        try Self.record(create.id, "UPDATE queue SET verdict = 'refused', reason = 'the write it depends on was refused', sent = 0 WHERE id = ?", at: store)
        await source.tellAnswers()

        #expect(await eventually { library.refusedCreates.contains(id) }, "\(library.syncReport.problems)")
        #expect(library.refusalReason(creating: id) != nil)
        await source.close()
    }

    private static func parentLinks(at root: URL) throws -> URL {
        MarfaStoreLocation(root: root).directory(for: try MarfaConnection(address: "http://127.0.0.1:9"))
            .appending(path: "New Item Parent Links.json")
    }

    /// Queues a child under a parent, then closes the copy, as a quit does. Answers the link's write.
    private func queueChildAndQuit(at root: URL) async throws -> (Marfa.QueuedWrite, URL) {
        let (source, log, store) = try await open(at: root)
        let parent = ItemID.mint()
        let child = ItemID.mint()
        source.submit(.create(id: parent, ItemDraft(type: TypeID("core.note"), title: "Garden", body: "Plans")), as: WriteID())
        source.submit(.create(id: child, ItemDraft(type: TypeID("core.note"), title: "Seeds", body: "List", parent: parent)), as: WriteID())
        await source.queueSubmitted()
        _ = try #require(await log.wait { $0.snapshot?.items.first { $0.id == child }?.edgesOut.isEmpty == false })
        let link = try #require(try await source.copy.queue.all().first { $0.kind == .createEdge })
        await source.close()
        return (link, store)
    }

    /// A refusal is kept with its link before it is told, so a quit in between still tells it at the next launch.
    @Test @MainActor
    func aParentLinkRefusedJustBeforeAQuitIsToldAfterTheRelaunch() async throws {
        let root = URL.temporaryDirectory.appending(path: "MarfaDrainAnswers-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (link, store) = try await queueChildAndQuit(at: root)
        // As the engine leaves it when the app stops after the answer and before the notice: the refusal kept with
        // the link, and the write, which carried no content, gone from the queue.
        var links = ParentLinkStore(file: try Self.parentLinks(at: root))
        links.refuse(link.id, reason: "That kind can’t be under this one.")
        try Self.record(link.id, "DELETE FROM queue WHERE id = ?", at: store)

        let (source, _, _) = try await open(at: root)
        let library = MarfaLibrary(source: source, notices: Notices())
        let told = await eventually {
            library.notices.waiting.contains {
                $0.title == "Can’t Put Item Under Its Parent" && $0.message.contains("That kind can’t be under this one.")
                    && $0.message.contains("“Seeds”")
            }
        }
        #expect(told, "told: \(library.notices.waiting.map(\.message))")
        await source.close()
    }

    /// A link whose write left the queue with no answer the app took may not have been made, and is told so once.
    @Test @MainActor
    func aParentLinkWhoseWriteLeftTheQueueUnansweredIsTold() async throws {
        let root = URL.temporaryDirectory.appending(path: "MarfaDrainAnswers-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (link, store) = try await queueChildAndQuit(at: root)
        try Self.record(link.id, "DELETE FROM queue WHERE id = ?", at: store)

        do {
            let (source, _, _) = try await open(at: root)
            let library = MarfaLibrary(source: source, notices: Notices())
            let told = await eventually {
                library.notices.waiting.contains { $0.message.contains("“Seeds”") && $0.message.contains("may not have been made") }
            }
            #expect(told, "told: \(library.notices.waiting.map(\.message))")
            await source.close()
        }
        #expect(ParentLinkStore(file: try Self.parentLinks(at: root)).isEmpty, "then dropped")
    }

    /// A queue id names the link only while the write is that link, so a stale entry never matches another write.
    @Test
    func aParentLinkIsFoundOnlyByTheWriteThatMadeIt() {
        let parent = ItemID.mint()
        let child = ItemID.mint()
        let link = ParentLink(child: child, parent: parent)
        var links = ParentLinkStore(file: nil)
        links.keep(link, for: "w")
        func write(_ kind: WriteKind, _ item: ItemID, _ target: ItemID?) -> Marfa.QueuedWrite {
            Marfa.QueuedWrite(id: "w", kind: kind, itemId: item.rawValue, toId: target?.rawValue, idempotencyKey: "w", queuedAt: "2026-11-25T09:00:00Z")
        }
        #expect(links.link(for: write(.createItem, child, nil)) == nil)
        #expect(links.link(for: write(.createEdge, .mint(), child)) == nil)
        #expect(links.link(for: write(.createEdge, parent, .mint())) == nil)
        #expect(links.link(for: write(.createEdge, parent, child)) == link)
    }

    /// A blocked answer is one the copy keeps, since the write may be released, and a released write keeps its queue
    /// id. Its next answer is taken like any other, and a second refusal of it is told again.
    @Test
    func aReleasedWritesNewAnswerIsTakenAndARepeatedRefusalIsToldAgain() async throws {
        let (source, log, store) = try await open()
        defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }
        let writes = try await submit(source, ["Blocked"])
        let (id, write) = writes[0]
        try Self.recordBlocked(write.id, at: store)
        await source.tellAnswers()
        _ = try #require(await log.wait { $0.answer(to: id) != nil })
        #expect(try await source.copy.queue.all().first?.verdict != nil)

        #expect(try await source.copy.queue.release(write.id))
        try Self.recordAccepted(write.id, at: store)
        await source.tellAnswers()
        // The app's write was answered once, as blocked; the new answer is taken from the queue all the same.
        #expect(try await source.copy.queue.all().isEmpty)
        await source.close()
    }
}
