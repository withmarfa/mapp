import Foundation
import Marfa
import MarfaTesting
import Synchronization
import struct MarfaCore.Draft
import struct MarfaCore.Edit
import struct MarfaCore.Item
import Testing
@testable import MAPP

/// The engine takes everything the follow heard in one step (`MarfaEngine.takeHeard`): it reads each row a batch
/// names once, or the copy whole for a large batch, and tells readers once. These tests check that what it shows
/// afterwards is what the copy holds, and that the person's writes are never held up or lost by it.
@Suite(.serialized, .hangLimit) struct MarfaEngineCoalescingTests {
    /// The fake copy's reads, counting each whole read and able to hold the engine inside a reread, where a batch
    /// waits on the copy. Its server is never reached, so a drain happens only when a test runs one.
    private nonisolated final class Reads: MarfaReading, MarfaRefreshing {
        let read: MarfaRead
        /// How many times the engine listed every row, and how many rows it read the edges of one by one.
        let wholeReads = Mutex(0)
        let rowReads = Mutex(0)
        private let gate = Mutex((closed: false, waiting: [CheckedContinuation<Void, Never>]()))

        init(copy: WorkingCopy) { read = MarfaRead(copy: copy) }

        /// Holds every reread at its read of the edges until `letGo`.
        func hold() { gate.withLock { $0.closed = true } }

        func letGo() {
            let waiting = gate.withLock { gate in
                gate.closed = false
                defer { gate.waiting = [] }
                return gate.waiting
            }
            for reader in waiting { reader.resume() }
        }

        var holding: Int { gate.withLock { $0.waiting.count } }

        private func pass() async {
            await withCheckedContinuation { reader in
                let waits = gate.withLock { gate in
                    guard gate.closed else { return false }
                    gate.waiting.append(reader)
                    return true
                }
                if !waits { reader.resume() }
            }
        }

        /// The copy's hydration and how many rows it has listed of those expected, as the engine reads them.
        let fill = Mutex((hydration: Hydration.complete, listed: UInt64?.none, expected: UInt64?.none))

        func status() async throws -> Status {
            let fill = fill.withLock { $0 }
            return Status(
                sliceTypes: MarfaSync.slice, sliceTier: .all, sliceEdgeTypes: MarfaSync.sliceEdgeTypes,
                hydration: fill.hydration, itemsExpected: fill.expected, itemsListed: fill.listed)
        }

        func items() async throws -> Rows<Marfa.Item> {
            wholeReads.withLock { $0 += 1 }
            return try await read.items()
        }

        func edges(ofTypes types: [String]) async throws -> [Marfa.Edge] { try await read.edges(ofTypes: types) }

        func edges(touching id: String) async throws -> [Marfa.Edge] {
            rowReads.withLock { $0 += 1 }
            await pass()
            return try await read.edges(touching: id)
        }

        func views() async throws -> Rows<LibraryView> { try await read.views() }
        func items(inView id: String) async throws -> [Marfa.Item] { try await read.items(inView: id) }

        /// A copy still filling, as the sync lane reads it, so the lane never drains the fake itself.
        func readStatus() async throws -> Status {
            Status(sliceTypes: MarfaSync.slice, sliceTier: .all, sliceEdgeTypes: MarfaSync.sliceEdgeTypes, hydration: .inProgress)
        }

        func hydrate(types: [String], tier: SliceTier, edgeTypes: [String]) async throws -> HydrateReport {
            throw FakeCopyError.unsupported(call: "hydrate")
        }

        func catchUp() async throws {}
        func fetchKept() async throws -> KeptFetch { KeptFetch(fetched: 0, fetchedBytes: 0, attachments: nil) }
    }

    private struct Scene {
        let fake: FakeCopy
        let reads: Reads
        let source: MarfaSource
        let log: ChangeLog

        var copy: WorkingCopy { fake.copy }
        var wholeReads: Int { reads.wholeReads.withLock { $0 } }
        var rowReads: Int { reads.rowReads.withLock { $0 } }
        var binReads: Int { get async { await source.engine.sync.binReads } }
        var shown: SourceSnapshot? { log.current.snapshot }

        /// Holds the engine in a reread of `id`, so everything heard until `letGo` is taken as one batch.
        func holdEngine(reading id: String) async throws {
            reads.hold()
            hearServer(id)
            try #require(await eventually { reads.holding > 0 }, "the engine never reached the held read")
        }

        func letGo() { reads.letGo() }

        func hearServer(_ id: String, event: String = "item.updated") {
            source.hear(Change(origin: .server(event: event, cursor: "1"), itemId: id, edgeId: nil))
        }

        func hear(_ refresh: Change.Refresh, item id: String? = nil) {
            source.hear(Change(origin: .refreshed(refresh), itemId: id, edgeId: nil))
        }

        /// How many `.changed` the source told after the first `marked` changes.
        func publishes(after marked: Int) -> Int {
            log.current.changes.dropFirst(marked).filter { if case .changed = $0 { true } else { false } }.count
        }

        /// Accepts every write waiting in the copy, as the server would, and forgets the answers.
        func drainAccepting() async throws {
            fake.verdict = { _ in .accepted }
            _ = try await copy.queue.drain()
            _ = try await copy.queue.forgetAnswered()
        }

        /// Makes `id`, one of `makeDoomed`'s rows, leave the copy as a row deleted on another device does, and
        /// hears it as one batch. The fake keeps a row deleted through it in its bin, so the row is refused instead.
        func deleteElsewhere(_ id: String) async throws {
            fake.verdict = { write in write.itemId == id ? .refused(Refusal(reason: "deleted elsewhere")) : nil }
            _ = try await copy.queue.drain()
            for write in try await copy.queue.all() where write.itemId == id { _ = try await copy.queue.discard(write.id) }
            #expect(try await copy.items.get(id) == nil, "a row deleted elsewhere stayed in the copy")
            hearServer(id, event: "item.deleted")
            await source.engineTook()
        }

        func item(_ id: String) -> MAPP.Item? { shown?.items.first { $0.id.rawValue == id } }

        func close() async { await source.close() }
    }

    private static let stamp = "2026-10-29T09:00:00Z"

    private static func row(_ id: String, title: String, body: String = "") -> Marfa.Item {
        Marfa.Item(
            id: id, type: "core.note", properties: ["title": .string(title), "body": .string(body)], state: .active,
            tier: .library, version: 1, schemaVersion: 1, source: "test", sourceId: nil, occurredAt: stamp,
            createdAt: stamp, updatedAt: stamp, tags: [])
    }

    private static func fake(_ rows: [Marfa.Item]) -> FakeCopy {
        WorkingCopy.fake(items: rows, itemTypes: SampleLibrary.itemTypes, edgeTypes: SampleLibrary.edgeTypes)
    }

    private static func open(_ fake: FakeCopy) async throws -> Scene {
        let reads = Reads(copy: fake.copy)
        let source = MarfaSource(copy: fake.copy, connection: SampleLibrary.connection, reading: reads, refreshing: reads)
        let log = ChangeLog(source)
        source.events.yield(.paint)
        _ = try #require(await log.wait { $0.snapshot != nil })
        return Scene(fake: fake, reads: reads, source: source, log: log)
    }

    /// Where what `scene` shows differs from what a source painted afresh from the same copy shows, at most ten.
    /// The fresh source is closed after, which closes the copy, so it is the last thing a test reads.
    private static func differencesFromAFreshRead(_ scene: Scene) async throws -> [String] {
        await scene.source.engineTook()
        let shown = try #require(scene.shown)
        let fresh = try await open(scene.fake)
        let copy = try #require(fresh.shown)
        await fresh.close()
        func describe(_ item: MAPP.Item?) -> String {
            guard let item else { return "none" }
            return "\(item.title) v\(item.version) \(item.state) \(item.sync) parent \(item.parentID?.rawValue ?? "none")"
        }
        let held = Dictionary(shown.items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let read = Dictionary(copy.items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var found: [String] = []
        for id in Set(held.keys).union(read.keys) where held[id] != read[id] {
            found.append("\(id.rawValue): shown \(describe(held[id])), copy \(describe(read[id]))")
        }
        for id in Set(shown.bodies.keys).union(copy.bodies.keys) where shown.bodies[id]?.text != copy.bodies[id]?.text {
            found.append("\(id.rawValue): text shown \(shown.bodies[id]?.text ?? "none"), copy \(copy.bodies[id]?.text ?? "none")")
        }
        if shown.items.count != copy.items.count || shown.items.count != held.count {
            found.append("counts: shown \(shown.items.count) (\(held.count) ids), copy \(copy.items.count)")
        }
        return Array(found.sorted().prefix(10))
    }

    /// Makes changes of each kind on the copy, as the server would have sent them, and hears each: `creates` new
    /// rows, edited rows, rows sent to the bin, and rows the server destroyed (`doomed`, made unanswered before the
    /// paint and refused now, so they leave the copy). Answers the new rows' ids, in order.
    private static func changeEverything(
        _ scene: Scene, creates: Int, edits: Range<Int>, deletes: Range<Int>, doomed: [String]
    ) async throws -> [String] {
        let refused = Set(doomed)
        scene.fake.verdict = { write in
            refused.contains(write.itemId ?? "") ? .refused(Refusal(reason: "destroyed on the server")) : nil
        }
        _ = try await scene.copy.queue.drain()
        for write in try await scene.copy.queue.all() where refused.contains(write.itemId ?? "") {
            _ = try await scene.copy.queue.discard(write.id)
        }
        for id in doomed { #expect(try await scene.copy.items.get(id) == nil, "a doomed row stayed in the copy") }

        // Drained a few hundred at a time: a fake drain that answers about a thousand writes overflows its thread's
        // stack.
        var made = 0
        func drained() async throws {
            made += 1
            if made.isMultiple(of: 250) { try await scene.drainAccepting() }
        }
        let created = (0..<creates).map { _ in ItemID.mint().rawValue }
        for (index, id) in created.enumerated() {
            _ = try await scene.copy.items.create(
                Draft(type: "core.note", properties: ["title": .string("New \(index)"), "body": .string("Arrived \(index)")], id: id))
            try await drained()
        }
        for index in edits {
            _ = try await scene.copy.items.update("kept-\(index)", Edit(properties: ["title": .string("Edited \(index)")], baseVersion: 1))
            try await drained()
        }
        for index in deletes {
            _ = try await scene.copy.items.delete("kept-\(index)")
            try await drained()
        }
        try await scene.drainAccepting()

        for id in created { scene.hearServer(id, event: "item.created") }
        for index in edits { scene.hearServer("kept-\(index)") }
        for index in deletes { scene.hearServer("kept-\(index)", event: "item.deleted") }
        for id in doomed { scene.hear(.purged, item: id) }
        return created
    }

    /// Rows made on this device before the paint and never answered, which a test can make leave the copy.
    private static func makeDoomed(_ count: Int, in fake: FakeCopy) async throws -> [String] {
        var doomed: [String] = []
        for index in 0..<count {
            let id = ItemID.mint().rawValue
            _ = try await fake.copy.items.create(
                Draft(type: "core.note", properties: ["title": .string("Doomed \(index)"), "body": .string("Gone")], id: id))
            doomed.append(id)
        }
        return doomed
    }

    // MARK: A flood

    @Test(.timeLimit(.minutes(5)))
    func aFloodOfServerChangesLeavesTheLibraryAsTheCopyWithFewPublishesAndKeepsAWriteMadeDuringIt() async throws {
        let fake = Self.fake((0..<3000).map { Self.row("kept-\($0)", title: "Kept \($0)", body: "Body \($0)") })
        // Few enough for one fake drain to refuse; see changeEverything.
        let doomed = try await Self.makeDoomed(200, in: fake)
        let scene = try await Self.open(fake)
        #expect(scene.shown?.items.count == 3200)
        let painted = scene.wholeReads
        let marked = scene.log.current.changes.count

        try await scene.holdEngine(reading: "kept-2999")
        let created = try await Self.changeEverything(scene, creates: 2000, edits: 0..<1000, deletes: 1000..<2000, doomed: doomed)

        // With no write of the person's waiting, a quit does not wait behind the engine's reads.
        await scene.source.queueSubmitted()
        #expect(scene.reads.holding > 0, "the engine was let go before the quit's wait returned")

        let typed = ItemID.mint()
        let write = WriteID()
        scene.source.submit(
            .create(id: typed, ItemDraft(type: TypeID("core.note"), title: "Typed during the flood", body: "Kept text")), as: write)
        #expect(scene.source.engineActivity?.snapshot().writes == 1)
        scene.letGo()
        await scene.source.queueSubmitted()
        #expect(scene.fake.writes.contains { $0.itemId == typed.rawValue }, "the write made during the flood was not queued")
        await scene.source.engineTook()
        #expect(scene.wholeReads <= painted + 2, "the flood read the copy whole \(scene.wholeReads - painted) times")

        let report = try await scene.copy.queue.drain()
        scene.source.hear(Change(origin: .queueDrained(report), itemId: nil, edgeId: nil))
        let answered = try #require(await scene.log.wait { $0.answer(to: write) != nil })
        #expect(answered.answer(to: write) == .accepted)
        #expect(scene.shown?.bodies[typed]?.text == "Kept text")
        #expect(scene.item(typed.rawValue)?.title == "Typed during the flood")
        let publishes = scene.publishes(after: marked)
        #expect(publishes <= 6, "the flood was told in \(publishes) changes")
        #expect(scene.item(created[1999])?.title == "New 1999")
        #expect(scene.item("kept-999")?.title == "Edited 999")
        #expect(scene.item(doomed[0]) == nil)

        let differences = try await Self.differencesFromAFreshRead(scene)
        #expect(differences.isEmpty, "\(differences)")
        await scene.close()
    }

    @Test(.timeLimit(.minutes(5)))
    func aSmallBatchReadsOnlyTheRowsItNamesAndLeavesTheLibraryAsTheCopy() async throws {
        let fake = Self.fake((0..<1000).map { Self.row("kept-\($0)", title: "Kept \($0)", body: "Body \($0)") })
        let doomed = try await Self.makeDoomed(50, in: fake)
        let scene = try await Self.open(fake)
        let painted = scene.wholeReads
        let marked = scene.log.current.changes.count

        try await scene.holdEngine(reading: "kept-999")
        let created = try await Self.changeEverything(scene, creates: 50, edits: 0..<50, deletes: 100..<150, doomed: doomed)
        scene.letGo()
        await scene.source.engineTook()
        #expect(scene.wholeReads == painted, "a batch of 200 changes read the copy whole")
        #expect(scene.publishes(after: marked) <= 3)
        #expect(scene.item(created[49])?.title == "New 49")
        #expect(scene.item("kept-49")?.title == "Edited 49")
        #expect(scene.item(doomed[0]) == nil)

        let differences = try await Self.differencesFromAFreshRead(scene)
        #expect(differences.isEmpty, "\(differences)")
        await scene.close()
    }

    // MARK: Edges

    @Test func anEdgeMovedBackAndForthInOneBatchEndsWhereTheCopySays() async throws {
        let fake = Self.fake([
            Self.row("first", title: "First"), Self.row("second", title: "Second"), Self.row("child", title: "Child"),
            Self.row("other", title: "Other"),
        ])
        let made = try await fake.copy.edges.create(from: "first", to: "child", type: MarfaMapping.parentEdge)
        let edgeID = try #require(made.edgeId)
        fake.verdict = { _ in .accepted }
        _ = try await fake.copy.queue.drain()
        _ = try await fake.copy.queue.forgetAnswered()
        let scene = try await Self.open(fake)
        #expect(scene.item("child")?.parentID == ItemID("first"))
        let painted = scene.wholeReads

        try await scene.holdEngine(reading: "other")
        for parent in ["second", "first", "second"] {
            let edge = try #require(try await scene.copy.edges.to("child").first { $0.id == edgeID })
            _ = try await scene.copy.edges.update(edgeID, EdgeEdit(baseVersion: edge.version, move: .source(parent)))
            try await scene.drainAccepting()
            scene.source.hear(Change(origin: .server(event: "edge.updated", cursor: "1"), itemId: nil, edgeId: edgeID))
        }
        scene.letGo()
        await scene.source.engineTook()
        #expect(scene.item("child")?.parentID == ItemID("second"))
        #expect(scene.wholeReads == painted, "an edge the engine holds was read by a whole read")

        // An edge the engine has never held names no row it knows, so the copy is read whole, once.
        let added = try await scene.copy.edges.create(from: "first", to: "other", type: MarfaMapping.parentEdge)
        try await scene.drainAccepting()
        scene.source.hear(Change(origin: .server(event: "edge.created", cursor: "2"), itemId: nil, edgeId: try #require(added.edgeId)))
        try #require(await eventually { scene.item("other")?.parentID == ItemID("first") })
        await scene.source.engineTook()
        #expect(scene.wholeReads == painted + 1)

        let differences = try await Self.differencesFromAFreshRead(scene)
        #expect(differences.isEmpty, "\(differences)")
        await scene.close()
    }

    // MARK: The queue alone

    @Test func forgottenAnswersChangeSyncStatesWithoutAWholeReadAndARefusalStaysUntilDiscarded() async throws {
        let scene = try await Self.open(Self.fake([Self.row("kept", title: "Kept"), Self.row("refused", title: "Refused")]))
        for id in ["kept", "refused"] {
            scene.source.submit(.editProperties(ItemID(id), ["title": .string("\(id) again")], base: ItemVersion(1), undoing: nil), as: WriteID())
        }
        await scene.source.engineTook()
        #expect(scene.item("kept")?.sync == .waiting(writes: 1))
        let painted = scene.wholeReads

        // Answered by a drain the engine is not told of, so only the forgetting tells it.
        scene.fake.verdict = { write in
            write.itemId == "refused" ? .refused(Refusal(reason: "not taken", code: "validation_failed", message: "Not taken")) : .accepted
        }
        _ = try await scene.copy.queue.drain()
        _ = try await scene.copy.queue.forgetAnswered()
        try #require(await eventually { scene.item("kept")?.sync == .settled })
        try #require(await eventually { if case .refused = scene.item("refused")?.sync { true } else { false } })
        #expect(scene.wholeReads == painted)

        scene.hear(.forgotten)
        await scene.source.engineTook()
        if case .refused = scene.item("refused")?.sync {} else { Issue.record("a refusal went with a later forgetting") }

        let refusal = try #require(try await scene.copy.queue.all().first { $0.itemId == "refused" })
        #expect(try await scene.source.resolve(.write(refusal.id), by: .discard))
        try #require(await eventually { scene.item("refused")?.sync == .settled })
        #expect(scene.wholeReads == painted)
        await scene.close()
    }

    // MARK: Whole reads

    @Test func aBatchNamingMoreThanAQuarterOfTheRowsReadsTheCopyWholeOnceAndNoRowAlone() async throws {
        let scene = try await Self.open(Self.fake((0..<400).map { Self.row("kept-\($0)", title: "Kept \($0)") }))
        await scene.source.engineTook()
        let painted = scene.wholeReads
        try await scene.holdEngine(reading: "kept-399")
        let named = scene.rowReads

        // 150 of 400 rows: past `readsWhole`'s floor of 64 and a quarter of the rows, and far below `rereadLimit`.
        for index in 0..<150 {
            _ = try await scene.copy.items.update("kept-\(index)", Edit(properties: ["title": .string("Edited \(index)")], baseVersion: 1))
        }
        try await scene.drainAccepting()
        for index in 0..<150 { scene.hearServer("kept-\(index)") }
        scene.letGo()
        await scene.source.engineTook()
        #expect(scene.wholeReads == painted + 1, "the batch read the copy whole \(scene.wholeReads - painted) times")
        #expect(scene.rowReads == named, "the batch read \(scene.rowReads - named) rows one by one")
        #expect(scene.item("kept-149")?.title == "Edited 149")

        let differences = try await Self.differencesFromAFreshRead(scene)
        #expect(differences.isEmpty, "\(differences)")
        await scene.close()
    }

    @Test func aHydrationHeardInABatchReadsTheCopyWholeOnce() async throws {
        let scene = try await Self.open(Self.fake([Self.row("one", title: "One"), Self.row("two", title: "Two")]))
        let painted = scene.wholeReads
        try await scene.holdEngine(reading: "two")
        _ = try await scene.copy.items.update("one", Edit(properties: ["title": .string("One again")], baseVersion: 1))
        try await scene.drainAccepting()
        scene.hearServer("one")
        scene.hear(.hydrated)
        scene.hearServer("two")
        scene.hear(.unfinished)
        scene.hear(.caughtUp)
        scene.letGo()
        await scene.source.engineTook()
        #expect(scene.wholeReads == painted + 1)
        #expect(scene.item("one")?.title == "One again")
        await scene.close()
    }

    @Test func aHydrationsStepsTellTheFillEachTimeAndReadTheCopyWholeRarely() async throws {
        let scene = try await Self.open(Self.fake((0..<200).map { Self.row("row\($0)", title: "Row \($0)") }))
        await scene.source.engineTook()
        let painted = scene.wholeReads
        func step(_ hydration: Hydration, listed: UInt64) async {
            scene.reads.fill.withLock { $0 = (hydration: hydration, listed: listed, expected: 4000) }
            await withCheckedContinuation { done in _ = scene.source.events.yield(.fillProgress(done)) }
        }
        for listed in stride(from: UInt64(100), through: 4000, by: 100) {
            await step(.inProgress, listed: listed)
            #expect(scene.source.syncReport.fill == LibraryFill(state: .filling, listed: listed, expected: 4000))
        }
        // The first step may read the copy whole, and a slow runner may pass `fillReadSpacing` once.
        #expect(scene.wholeReads - painted <= 2)
        let filling = scene.wholeReads
        await step(.complete, listed: 4000)
        #expect(scene.source.syncReport.fill == LibraryFill(state: .complete, listed: 4000, expected: 4000))
        #expect(scene.wholeReads == filling + 1)
        await scene.close()
    }

    // MARK: The bin

    @Test func rowsDeletedElsewhereInSeparateBatchesReadTheBinOnceTheChangesPause() async throws {
        let fake = Self.fake([Self.row("kept", title: "Kept")])
        let doomed = try await Self.makeDoomed(5, in: fake)
        let scene = try await Self.open(fake)
        await scene.source.engineTook()
        let quiet = Duration.milliseconds(500)
        await scene.source.engine.sync.setBinWait(quiet: quiet, longest: .seconds(30))
        let before = await scene.binReads

        for id in doomed { try await scene.deleteElsewhere(id) }
        try #require(try await eventuallyAsking { await scene.binReads > before }, "the bin was never read")
        // Waits past another pause, to see that no deletion of the five reads the bin again.
        try await Task.sleep(for: quiet * 2)
        let read = await scene.binReads - before
        #expect(read == 1, "five deletions read the bin \(read) times")
        await scene.close()
    }

    @Test func aFloodOfDeletionsThatNeverPausesReadsTheBinWithinTheLongestWait() async throws {
        let fake = Self.fake([Self.row("kept", title: "Kept")])
        let doomed = try await Self.makeDoomed(400, in: fake)
        let scene = try await Self.open(fake)
        await scene.source.engineTook()
        let quiet = Duration.milliseconds(400)
        let longest = Duration.milliseconds(1500)
        await scene.source.engine.sync.setBinWait(quiet: quiet, longest: longest)
        let before = await scene.binReads

        // One deletion after another for twice the longest wait, so the changes never pause for `quiet`.
        let start = ContinuousClock.now
        var index = 0
        while ContinuousClock.now - start < longest * 2 {
            try #require(index < doomed.count, "\(index) deletions took less than \(longest * 2)")
            try await scene.deleteElsewhere(doomed[index])
            index += 1
        }
        let read = await scene.binReads - before
        #expect(read >= 1, "a flood of \(index) deletions over \(ContinuousClock.now - start) never read the bin")
        #expect(read <= 3, "a flood of \(index) deletions read the bin \(read) times")
        await scene.close()
    }

    // MARK: The person's writes

    @Test @MainActor func aTextSaveRacingAServerChangeStillMerges() async throws {
        let scene = try await Self.open(Self.fake([Self.row("note", title: "Note", body: "Base"), Self.row("other", title: "Other")]))
        let library = MarfaLibrary(source: scene.source, notices: Notices())
        try #require(await eventually { library.isLoaded })
        let id = ItemID("note")

        try await scene.holdEngine(reading: "other")
        _ = try await scene.copy.items.update("note", Edit(properties: ["body": .string("Theirs")], baseVersion: 1))
        try await scene.drainAccepting()
        scene.hearServer("note")
        library.saveText("Mine", of: id, readAt: ItemVersion(1), failing: "Note")
        scene.letGo()
        try #require(await eventually { library.item(id)?.version == ItemVersion(2) })
        #expect(library.body(of: id)?.text == "Mine", "the person's text gave way to a read that raced it")
        await scene.source.queueSubmitted()
        let save = try #require(try await scene.copy.queue.all().first { $0.itemId == "note" })
        #expect(save.baseVersion == 1, "the save was not sent on the version it was typed on")

        scene.fake.verdict = { _ in .merged(fields: ["body"]) }
        let report = try await scene.copy.queue.drain()
        scene.source.hear(Change(origin: .queueDrained(report), itemId: nil, edgeId: nil))
        try #require(await eventually { library.body(of: id)?.version == ItemVersion(3) })
        #expect(library.body(of: id)?.text == "Mine")
        await scene.close()
    }

    @Test func aCopyClosingMidBatchAnswersTheWritesAfterItAsClosed() async throws {
        let scene = try await Self.open(Self.fake([Self.row("one", title: "One")]))
        let activity = try #require(scene.source.engineActivity)
        try await scene.holdEngine(reading: "one")
        let before = ItemID.mint()
        scene.source.submit(.create(id: before, ItemDraft(type: TypeID("core.note"), title: "Before", body: "First")), as: WriteID())
        let closing = Task { await scene.source.close(agreeing: nil) }
        try #require(await eventually { activity.snapshot().waiting >= 2 })
        let after = WriteID()
        scene.source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "After", body: "Second")), as: after)
        scene.hearServer("one")
        scene.letGo()

        #expect(await closing.value == .closed)
        #expect(scene.fake.writes.contains { $0.itemId == before.rawValue }, "the write told before the close was not queued")
        let answered = try #require(await scene.log.wait { $0.answer(to: after) != nil })
        if case .refused(let problem) = answered.answer(to: after) {
            #expect(problem.code == MarfaEngine.closedCode)
        } else {
            Issue.record("the write told after the close was answered \(String(describing: answered.answer(to: after)))")
        }
    }
}
