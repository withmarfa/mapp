import Foundation
import Testing
@testable import MAPP

/// The core names an item (`Item.name`), which is not always what MAPP stores as its title: a note with no title
/// is named by its first line. Wherever MAPP names an item to the person it uses the core's name, and the stored
/// title stays what the page edits.
@MainActor
@Suite(.hangLimit) struct ItemNameTests {
    typealias F = LibraryFixture

    /// "Zeta" is stored as the title and the core names it "Alpha"; "Alpha" is stored and named "Zeta"; an item the
    /// core cannot name has no name at all.
    private static func items() -> [Item] {
        var first = F.item(F.n1, F.note, "Zeta", age: 1, tags: [ItemTag.favorite])
        first.name = "Alpha"
        var second = F.item(F.n2, F.note, "Alpha", age: 2)
        second.name = "Zeta"
        var nameless = F.item(F.p1, F.project, "", age: 3)
        nameless.name = nil
        return [first, second, nameless]
    }

    private func library() async throws -> MarfaLibrary {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: Self.items(), catalogue: F.catalogue)))
        try #require(await eventually { library.isLoaded })
        return library
    }

    @Test func aTitleSortOrdersByTheNameShown() {
        let sorted = NoteSort.title.sorted(Self.items())
        #expect(sorted.map(\.displayTitle) == ["Alpha", "Untitled", "Zeta"].sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        #expect(sorted.first?.id == F.n1)
    }

    @Test func aFavoriteAndACollectionAreNamedByTheCoresName() async throws {
        let library = try await library()
        #expect(library.name(of: .favoriteItem(F.n1)) == "Alpha")
        #expect(library.name(of: .favoriteItem(F.p1)) == "Untitled")
    }

    @Test func aRelationshipTargetIsNamedByTheCoresName() async throws {
        var holder = F.item(F.n3, F.note, "Holder", age: 4, edges: [
            Edge(id: EdgeID("a1"), type: "about", source: F.n3, target: .item(F.n1), origin: .property("about")),
            Edge(id: EdgeID("a2"), type: "about", source: F.n3, target: .item(F.p1), origin: .property("about")),
        ])
        holder.name = "Holder"
        let source = FakeItemSource()
        let linked = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: Self.items() + [holder], catalogue: F.catalogue)))
        try #require(await eventually { linked.isLoaded })
        let about = try #require(linked.relationships(for: F.n3).first { $0.field == "about" })
        #expect(Set(about.targets.map(\.displayTitle)) == ["Alpha", "Untitled"])
        #expect(!about.targets.contains { $0.title == "Zeta" })
    }
}
