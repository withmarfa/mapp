import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MarfaMac

struct BrowserTests {
    @Test func collectionOptionsAreClearedWhenTheLibraryChanges() {
        let (first, _, _, _) = makeFakeLibrary()
        let (second, _, _, _) = makeFakeLibrary()
        let browser = Browser()
        browser.adopt(first)
        browser.timelineFields[.allItems] = "starts_at"
        browser.compactBoards[.allItems] = true
        browser.adopt(second)
        #expect(browser.timelineFields.isEmpty)
        #expect(browser.compactBoards.isEmpty)
    }

    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    /// The same three items in a library held in memory, for what the browser asks of any library.
    func makeFakeLibrary() -> (FakeItemLibrary, older: Item, newer: Item, favorite: Item) {
        let older = FakeItemLibrary.note("Older", modified: start - 120, tier: .feed)
        let newer = FakeItemLibrary.note("Newer", modified: start - 60, tier: .feed)
        let favorite = FakeItemLibrary.note("Favorite", modified: start - 3600, isFavorite: true)
        let library = FakeItemLibrary(items: [older, newer, favorite], now: start)
        return (library, older, newer, favorite)
    }

    // MARK: Showing and making

    @Test func aLibraryThatCannotPurgeIsNeverAskedToEraseWhatIsDeleted() {
        let (library, older, newer, _) = makeFakeLibrary()
        library.reachesServer = false
        library.delete([older.id], undoManager: nil)
        Browser.delete([older.id, newer.id], in: library, undoManager: nil)
        #expect(library.item(newer.id)?.state == .trashed, "what is live still goes to Recently Deleted")
        #expect(library.item(older.id)?.state == .trashed)
        #expect(library.itemsToPurge.isEmpty)
        library.reachesServer = true
        Browser.delete([older.id], in: library, undoManager: nil)
        #expect(library.itemsToPurge == [older.id])
    }

    // MARK: Restoring

    @Test func snapshotsSurviveEncodingAsIdentifiers() throws {
        let collection = ItemID("0198f2c4-7d1e-7a00-8000-000000000001")
        let note = ItemID("0198f2c4-7d1e-7a00-8000-000000000002")
        let snapshot = Browser.Snapshot(place: .collection(collection), selection: [note])
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(Browser.Snapshot.self, from: data) == snapshot)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["selection"] as? [String] == [note.rawValue], "an identifier is kept as its own string")
    }

    @Test func aDraggedItemCarriesOnlyItsIdentifierAsAString() throws {
        let id = ItemID("0198f2c4-7d1e-7a00-8000-000000000003")
        let data = try JSONEncoder().encode(ItemReference(id: id, title: "Plan", type: .markdown, content: .text("# Plan")))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["id"] as? String == id.rawValue)
        #expect(json.count == 1)
        let decoded = try JSONDecoder().decode(ItemReference.self, from: data)
        #expect(decoded.id == id)
        #expect(decoded.content == nil)
    }
}
