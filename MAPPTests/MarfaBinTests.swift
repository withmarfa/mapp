import Foundation
import Marfa
import MarfaTesting
import Testing
@testable import MAPP

/// Recently Deleted is the working copy's bin: listed with the server away, newest binned first.
@MainActor
@Suite(.hangLimit)
struct MarfaBinTests {
    @Test func theBinListsFromTheCopyOfflineNewestBinnedFirstWhetherBinnedHereOrByTheServer() async throws {
        let fake = WorkingCopy.fake(itemTypes: SampleLibrary.itemTypes, edgeTypes: SampleLibrary.edgeTypes)
        var ids: [String: ItemID] = [:]
        for name in ["kept", "first", "second", "third"] {
            let queued = try await fake.copy.items.create(Draft(type: "core.note", properties: ["title": .string(name)]))
            ids[name] = ItemID(try #require(queued.itemId))
        }
        // Nothing here refreshes from a server, so every row is read from the copy. One item is binned through the library and two straight in the copy, as another writer's deletes reach it.
        let source = MarfaSource(copy: fake.copy, connection: SampleLibrary.connection)
        source.events.yield(.paint)
        let library = MarfaLibrary(source: source, notices: Notices())
        try #require(await eventually { library.isLoaded && library.item(ids["third"]!) != nil })
        library.delete([ids["first"]!], undoManager: nil)
        try #require(await eventually { library.item(ids["first"]!)?.state == .trashed })
        try await Task.sleep(for: .milliseconds(1_100))
        _ = try await fake.copy.items.delete(ids["second"]!.rawValue)
        try await Task.sleep(for: .milliseconds(1_100))
        _ = try await fake.copy.items.delete(ids["third"]!.rawValue)
        try #require(await eventually { library.items(in: .recentlyDeleted).count == 3 })

        let binned = library.items(in: .recentlyDeleted)
        #expect(NoteSort.dateEdited.sorted(binned).map(\.id) == [ids["third"]!, ids["second"]!, ids["first"]!])
        let row = try #require(try await fake.copy.items.get([ids["second"]!.rawValue], includingBin: true).first)
        #expect(binned.first { $0.id == ids["second"]! }?.trashed == row.trashedDate)
        #expect(binned.allSatisfy { $0.trashed != nil })
        #expect(library.items(in: .allNotes).map(\.id) == [ids["kept"]!])
        await source.close()
    }
}
