import Foundation
import Testing
@testable import MarfaMac

/// The link list keeps the identity of unresolved targets.
@MainActor
@Suite(.hangLimit) struct LinkListTests {
    typealias F = LibraryFixture

    // MARK: What the library gives the group

    private static func loaded(_ extra: [Item]) async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: F.items + extra, catalogue: F.catalogue)))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    @Test func aLinkToAnItemTheLibraryDoesNotHoldIsMissingAndKeepsItsID() async throws {
        let stray = ItemID("not-held")
        let holder = F.item(ItemID("holder"), F.note, "Holder", age: 50, edges: [
            Edge(id: EdgeID("stray"), type: "about", from: ItemID("holder"), to: .item(stray), origin: .property("about"))
        ])
        let (library, _) = try await Self.loaded([holder])
        let group = try #require(library.relationships(for: holder.id).first { $0.field == "about" })
        let target = try #require(group.targets.first)
        #expect(target.itemID == stray)
        #expect(target.resolution == .missing)
        #expect(!target.isOpenable)
        #expect(!target.isDeleted)
    }

}
