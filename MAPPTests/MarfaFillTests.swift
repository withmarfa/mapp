import Foundation
import Marfa
import Synchronization
import struct MarfaCore.Draft
import struct MarfaCore.Edit
import struct MarfaCore.Edge
import struct MarfaCore.Item
import Testing
@testable import MAPP

@Suite struct MarfaFillTests {
    @Test(arguments: [Completeness.partial, .stale])
    func incompleteRowsPaintAndSavesWorkWithoutEdgeReads(_ completeness: Completeness) async throws {
        let store = try TemporaryMarfaCopy()
        defer { store.remove() }
        let copy = try await store.open()
        try await copy.declareTypes([[
            "id": "example.note", "label": "Note", "title_field": "title", "body_field": "body",
            "fields": ["title": ["type": "string"], "body": ["type": "string"]],
        ]])
        let write = try await copy.items.create(Draft(type: "example.note", properties: ["title": "Arriving", "body": "First"]))
        let reads = FillingReads(copy: copy, completeness: completeness)
        let source = MarfaSource(copy: copy, connection: try MarfaConnection(address: "https://example.test"), reading: reads)
        let log = ChangeLog(source)
        source.events.yield(.paint)
        let painted = try #require(await log.wait { $0.item(titled: "Arriving") != nil })
        let item = try #require(painted.item(titled: "Arriving"))
        #expect(source.syncReport.fill?.state == (completeness == .stale ? .updating : .filling))
        #expect(source.syncReport.fill?.listed == 1)
        source.submit(.editBody(item.id, "Saved during fill", base: item.version, merge: .asRead), as: WriteID())
        await source.queueSubmitted()
        #expect(try await copy.items.get(try #require(write.itemId))?.body == "Saved during fill")
        #expect(reads.edgeReads.withLock { $0 } > 0)
        #expect(!log.current.changes.contains { if case .unavailable = $0 { true } else { false } })
        await source.close()
    }

    @Test func everyTypeIsOneStableSlice() {
        #expect(MarfaSync.slice == ["*"])
        #expect(MarfaSync.needsFill(Status(hydration: .never)))
        #expect(MarfaSync.needsFill(Status(sliceTypes: ["*"], sliceTier: .all, hydration: .inProgress)))
        #expect(MarfaSync.needsFill(Status(sliceTypes: ["*"], sliceTier: .all, hydration: .stale)))
        #expect(!MarfaSync.needsFill(Status(sliceTypes: ["*"], sliceTier: .all, hydration: .complete)))
    }

    @Test func progressUsesListedRowsAndKeepsUnknownTotalsUnknown() {
        let status = Status(hydration: .inProgress, items: 99, itemsExpected: 20, itemsListed: 4)
        let fill = LibraryFill(status, completeness: .partial)
        #expect(fill.listed == 4)
        #expect(fill.expected == 20)
        #expect(fill.state == .filling)
        #expect(LibraryFill(Status(hydration: .stale), completeness: .stale).state == .updating)
        #expect(LibraryFill(Status(hydration: .inProgress), completeness: .partial).expected == nil)
        #expect(FillWording.line(fill) == "4 of 20 items listed")
        #expect(FillWording.line(LibraryFill(state: .filling, listed: 4)) == "Items listed: 4")
    }

    @Test func unfinishedRefreshReadsRowsWithoutClearingTheFollowFailure() async throws {
        let store = try TemporaryMarfaCopy()
        defer { store.remove() }
        let copy = try await store.open()
        let source = MarfaSource(copy: copy, connection: try MarfaConnection(address: "https://example.test"))
        let log = ChangeLog(source)
        source.events.yield(.paint)
        _ = try #require(await log.wait { $0.snapshot != nil })
        try await copy.declareTypes([[
            "id": "example.note", "label": "Note", "title_field": "title", "body_field": "body",
            "fields": ["title": ["type": "string"], "body": ["type": "string"]],
        ]])
        let created = try await copy.items.create(Draft(type: "example.note", properties: ["title": "Arrived", "body": "First"]))
        source.events.yield(.change(Change(origin: .serverUnreachable(.network(message: "offline")), itemId: nil, edgeId: nil)))
        source.events.yield(.change(Change(origin: .refreshed(.unfinished), itemId: nil, edgeId: nil)))
        let painted = try #require(await log.wait { $0.item(titled: "Arrived") != nil })
        let item = try #require(painted.item(titled: "Arrived"))
        #expect(source.connectionState == .offline(reason: "offline"))
        source.submit(.editBody(item.id, "Kept", base: item.version, merge: .asRead), as: WriteID())
        await source.queueSubmitted()
        #expect(try await copy.items.get(try #require(created.itemId))?.body == "Kept")
        await source.close()
    }

    @Test @MainActor func arrivingItemsRemainEditableAndNewestFirst() async throws {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source)
        let older = LibraryFixture.item(ItemID("older"), LibraryFixture.note, "Older", age: 2)
        let newer = LibraryFixture.item(ItemID("newer"), LibraryFixture.note, "Newer", age: 1)
        source.report.update { $0.fill = LibraryFill(state: .filling, listed: 1, expected: 2) }
        source.send(.loaded(SourceSnapshot(items: [older], catalogue: LibraryFixture.catalogue)))
        for _ in 0..<100 where !library.isLoaded { try await Task.sleep(for: .milliseconds(10)) }
        source.send(.upserted([newer]))
        for _ in 0..<100 where library.item(newer.id) == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(library.items(in: .allNotes).map(\.id) == [newer.id, older.id])
        #expect(library.item(older.id)?.isWritable == true)
        #expect(library.syncReport.fill?.listed == 1)
        await source.close()
    }
}

private nonisolated final class FillingReads: MarfaReading {
    let copy: WorkingCopy
    let completeness: Completeness
    let edgeReads = Mutex(0)

    init(copy: WorkingCopy, completeness: Completeness) {
        self.copy = copy
        self.completeness = completeness
    }

    func status() async throws -> Status {
        Status(hydration: completeness == .stale ? .stale : .inProgress, items: 99, itemsExpected: 5, itemsListed: 1)
    }
    func items() async throws -> Rows<Marfa.Item> {
        Rows(try await copy.items.list().rows, completeness: completeness)
    }
    func edges(ofTypes types: [String]) async throws -> [Marfa.Edge] {
        edgeReads.withLock { $0 += 1 }
        throw MarfaError.hydrationIncomplete(message: "Edges are not ready")
    }
    func edges(touching id: String) async throws -> [Marfa.Edge] {
        edgeReads.withLock { $0 += 1 }
        throw MarfaError.hydrationIncomplete(message: "Edges are not ready")
    }
}
