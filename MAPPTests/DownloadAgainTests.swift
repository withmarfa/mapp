import Foundation
import Marfa
import MarfaTesting
import Synchronization
import Testing
@testable import MAPP

/// Download Everything Again hydrates the copy again and keeps what waits to be sent.
@Suite(.hangLimit) struct DownloadAgainTests {
    private actor Server: MarfaRefreshing {
        private(set) var calls: [String] = []
        /// The queue as the fill found it, and where the app handed it.
        private(set) var queuedDuringFill: [QueuedWrite]?
        var copy: WorkingCopy?
        let status = Status(
            sliceTypes: MarfaSync.slice, sliceTier: .all, sliceEdgeTypes: MarfaSync.sliceEdgeTypes, hydration: .complete)

        func use(_ copy: WorkingCopy) { self.copy = copy }
        func readStatus() -> Status { status }
        func hydrate(types: [String], tier: SliceTier, edgeTypes: [String]) async -> HydrateReport {
            calls.append("fill")
            queuedDuringFill = try? await copy?.queue.all()
            return HydrateReport(
                types: types, tier: tier, edgeTypes: edgeTypes, items: 1, edges: 0, pages: 1, pagesTotal: 1, resumed: false,
                restarted: nil, inPlace: false, cursor: "done")
        }
        func catchUp() { calls.append("catchUp") }
        func fetchKept() -> KeptFetch { KeptFetch(fetched: 0, fetchedBytes: 0, attachments: nil) }
    }

    @Test func aCompleteCopyIsFilledAgainAndItsQueueIsLeftAlone() async throws {
        let server = Server()
        let fake = WorkingCopy.fake()
        let copy = fake.copy
        try await copy.declareTypes([[
            "id": "example.note", "label": "Note", "title_field": "title", "body_field": "body",
            "fields": ["title": ["type": "string"], "body": ["type": "string"]],
        ]])
        _ = try await copy.items.create(Draft(type: "example.note", properties: ["title": "Not yet sent", "body": "Text"]))
        await server.use(copy)
        let queued = try await copy.queue.all()
        try #require(queued.count == 1)
        let sync = MarfaSync(copy: copy, hub: MarfaHub(), refreshing: server) { event in
            if case .update(_, let done) = event { done.resume() }
            if case .answers(let done) = event { done.resume() }
            return true
        }
        await sync.start()
        await sync.rehydrate()
        #expect(try await eventuallyAsking { sync.hooks.hydrations == 1 }, "the copy was filled again though it was complete")
        #expect(await server.calls.first == "fill")
        #expect(await server.queuedDuringFill == queued, "the fill met the write still waiting, and left it there")
        await sync.stop()
        await copy.close()
    }
}
