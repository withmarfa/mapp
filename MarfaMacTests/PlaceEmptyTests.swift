import Testing
@testable import MarfaMac

struct PlaceEmptyTests {
    private let catalogue = FakeItemLibrary.testCatalogue

    @Test func theCollectionsIndexOffersNewCollectionWhereACollectionCanBeMade() {
        let empty = PlaceEmpty.of(PlaceView(.collections), in: catalogue, offered: ["core.note", FakeItemLibrary.collectionType.rawValue])
        #expect(empty.title == "No Collections")
        #expect(empty.makes == FakeItemLibrary.collectionType.rawValue)
        #expect(empty.buttonTitle == "New Collection")
    }

    @Test func theCollectionsIndexHasNoButtonWhereNothingCanBeMade() {
        let empty = PlaceEmpty.of(PlaceView(.collections), in: catalogue, offered: [])
        #expect(empty.makes == nil && empty.buttonTitle == nil)
        #expect(PlaceEmpty.of(PlaceView(.collections), in: catalogue, offered: ["core.note"]).makes == nil)
    }

    @Test func otherIndexesKeepNoButton() {
        #expect(PlaceEmpty.of(PlaceView(.sources), in: catalogue, offered: ["core.note"]).makes == nil)
        #expect(PlaceEmpty.of(PlaceView(.types), in: catalogue, offered: ["core.note"]).makes == nil)
    }
}
