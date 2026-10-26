import Foundation
import Testing
@testable import MAPP

/// Collections as Marfa keeps them: items whose type plays the `container` role, holding members through
/// `in-collection` edges from each member.
@MainActor
@Suite struct MarfaCollectionsTests {
    typealias F = LibraryFixture

    static let holiday = ItemID("al1"), archive = ItemID("al2"), oldAlbum = ItemID("al3")

    static func member(_ edge: String, _ member: ItemID, of collection: ItemID, at position: Double? = nil) -> Edge {
        Edge(
            id: EdgeID(edge), type: "in-collection", source: member, target: .item(collection),
            origin: .property("in-collection"), position: position)
    }

    /// The fixture with three albums: Holiday holds Plain note at 2, Alpha at 1 and Bug one with no position;
    /// Archive holds Beta and Ada with none; a third album is in the bin.
    static var items: [Item] {
        F.items.map { item in
            var item = item
            switch item.id {
            case F.n1: item.edgesOut.append(member("m1", F.n1, of: holiday, at: 2))
            case F.p1: item.edgesOut.append(member("m2", F.p1, of: holiday, at: 1))
            case F.t1: item.edgesOut.append(member("m3", F.t1, of: holiday))
            case F.p2: item.edgesOut.append(member("m4", F.p2, of: archive))
            case F.en1: item.edgesOut.append(member("m5", F.en1, of: archive))
            default: break
            }
            return item
        } + [
            F.item(holiday, F.album, "Holiday", age: 0),
            F.item(archive, F.album, "Archive", age: 0),
            F.item(oldAlbum, F.album, "Old album", age: 0, state: .trashed),
        ]
    }

    func loaded() async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: Self.items, catalogue: F.catalogue)))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    @Test func theIndexListsActiveItemsOfContainerTypesByTitle() async throws {
        let (library, _) = try await loaded()
        #expect(library.collections.map(\.id) == [Self.archive, Self.holiday])
        #expect(library.catalogue.collectionTypes == [F.album])
    }

    @Test func itemsWithChildrenAreNoCollections() async throws {
        let (library, _) = try await loaded()
        // Alpha holds Epic task through `child-of`, which once made it a collection.
        #expect(!library.collections.contains { $0.id == F.p1 })
        #expect(library.items(in: .collection(F.p1)).isEmpty)
    }

    @Test func membersFollowTheirPositionsThenTitle() async throws {
        let (library, _) = try await loaded()
        #expect(library.items(in: .collection(Self.holiday)).map(\.id) == [F.p1, F.n1, F.t1])
        #expect(library.items(in: .collection(Self.archive)).map(\.id) == [F.en1, F.p2])
        #expect(library.count(in: .collection(Self.holiday)) == 3)
        #expect(library.name(of: .collection(Self.holiday)) == "Holiday")
    }

    @Test func aMemberInTheBinLeavesTheCollection() async throws {
        let (library, source) = try await loaded()
        var gone = try #require(library.item(F.n1))
        gone.state = .trashed
        source.send(.upserted([gone]))
        #expect(await eventually { library.items(in: .collection(Self.holiday)).map(\.id) == [F.p1, F.t1] })
    }

    @Test func addingWritesOneEdgeAfterTheLastPosition() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        #expect(library.addToCollection([F.e1, F.n2, F.n1], Self.holiday, undoManager: undo))
        undo.endUndoGrouping()
        // Plain note is in Holiday already. The others follow position 2, by title.
        #expect(source.writes == [
            .link(EdgeDraft(type: "in-collection", source: F.e1, target: Self.holiday, position: 3), undoing: nil),
            .link(EdgeDraft(type: "in-collection", source: F.n2, target: Self.holiday, position: 4), undoing: nil),
        ])
        #expect(library.notices.waiting.isEmpty)
    }

    @Test func addingToACollectionWithNoPositionsSetsNone() async throws {
        let (library, source) = try await loaded()
        #expect(library.addToCollection([F.e1], Self.archive, undoManager: nil))
        #expect(source.writes == [.link(EdgeDraft(type: "in-collection", source: F.e1, target: Self.archive), undoing: nil)])
    }

    @Test func removingUnlinksAndAnUndoPutsThePositionBack() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        #expect(library.removeFromCollection([F.n1, F.e1], Self.holiday, undoManager: undo))
        undo.endUndoGrouping()
        #expect(source.writes == [.unlink(EdgeID("m1"))])
        source.clearWrites()
        undo.undo()
        #expect(source.writes == [
            .link(EdgeDraft(type: "in-collection", source: F.n1, target: Self.holiday, position: 2), undoing: nil),
        ])
        // An item in no collection has nothing to remove.
        source.clearWrites()
        #expect(!library.removeFromCollection([F.e1], Self.holiday, undoManager: nil))
        #expect(source.writes.isEmpty)
    }

    @Test func aCollectionCantBeAMember() async throws {
        let (library, source) = try await loaded()
        #expect(!library.canJoinCollection(try #require(library.item(Self.archive))))
        #expect(library.canJoinCollection(try #require(library.item(F.e1))))
        #expect(library.canJoinCollection(try #require(library.item(F.f1))))
        #expect(!library.addToCollection([F.e1, Self.archive], Self.holiday, undoManager: nil))
        #expect(source.writes.isEmpty)
        #expect(library.notices.waiting.last?.title == String(localized: "Can’t Add to Collection"))
        #expect(library.notices.waiting.last?.message == String(localized: "A collection can’t be in another collection."))
        // Nor is one offered as a collection for another, or written through the item's own relationship.
        #expect(library.relationshipCandidates(for: Self.archive, field: "in-collection").isEmpty)
        #expect(!library.relationships(for: Self.archive).contains { $0.field == "in-collection" && $0.isEditable })
        #expect(!library.setItemRelationship(Self.archive, field: "in-collection", targetIDs: [Self.holiday], undoManager: nil))
        #expect(source.writes.isEmpty)
    }

    @Test func onlyACollectionInTheLibraryTakesMembers() async throws {
        let (library, source) = try await loaded()
        #expect(!library.addToCollection([F.e1], F.p1, undoManager: nil))
        #expect(!library.addToCollection([F.e1], Self.oldAlbum, undoManager: nil))
        #expect(source.writes.isEmpty)
        #expect(library.notices.waiting.last?.message == String(localized: "This collection isn’t in the library."))
    }

    @Test func theCollectionsHoldingTheItemsAreNamed() async throws {
        let (library, _) = try await loaded()
        #expect(library.collections(holding: [F.n1]).map(\.id) == [Self.holiday])
        #expect(library.collections(holding: [F.p2, F.en1]).map(\.id) == [Self.archive])
        #expect(library.collections(holding: [F.e1]).isEmpty)
    }

    /// The collection commands take the whole selection, files too, never only its notes, and leave out what
    /// can't be a member.
    @Test func theCollectionCommandsTakeFilesAndLeaveOutCollections() async throws {
        let (library, source) = try await loaded()
        #expect(library.collectionMembers([F.f1]) == [F.f1])
        #expect(library.collectionMembers([F.n1, F.f1]) == [F.n1, F.f1])
        #expect(library.collectionMembers([F.n1, Self.holiday]) == [F.n1])
        #expect(library.collectionMembers([Self.archive, Self.oldAlbum]).isEmpty)
        #expect(library.addToCollection(library.collectionMembers([F.f1, Self.archive]), Self.holiday, undoManager: nil))
        #expect(source.writes == [.link(EdgeDraft(type: "in-collection", source: F.f1, target: Self.holiday, position: 3), undoing: nil)])
    }

    @Test func noCatalogueContainerMeansNoCollections() async throws {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        let catalogue = Catalogue(itemTypes: Array(F.catalogue.itemTypes.values.filter { $0.id != F.album }), edgeTypes: [])
        source.send(.loaded(SourceSnapshot(items: F.items, catalogue: catalogue)))
        try #require(await eventually { library.isLoaded })
        #expect(library.collections.isEmpty)
        #expect(!library.canJoinCollection(try #require(library.item(F.n1))))
    }
}
