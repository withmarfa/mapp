import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MarfaMac

/// An item a person's connector keeps, which the server marks read only: `Item.obstacle(to:)` refuses what the
/// connector's next run puts back, everywhere, and leaves the rest open.
@MainActor
@Suite(.hangLimit) struct ReadOnlyItemTests {
    typealias F = LibraryFixture

    static let holiday = MarfaCollectionsTests.holiday

    /// The collections fixture with Feed note, Beta and Old note held read only; Old album is in the bin.
    private static var items: [Item] {
        MarfaCollectionsTests.items.map { item in
            var item = item
            if [F.n2, F.p2, F.n3].contains(item.id) { item.readOnly = true }
            if item.id == F.p2 { item.tags.insert("work") }
            return item
        }
    }

    private func loaded() async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        for item in Self.items { source.setBody("Text of \(item.id.rawValue)", of: item.id) }
        let library = MarfaLibrary(source: source, notices: Notices())
        library.handOverEdits = { $0(true) }
        source.send(.loaded(SourceSnapshot(items: Self.items, catalogue: F.catalogue)))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    private func skips(_ reasons: BatchSkips.Reason...) -> String? {
        var skips = BatchSkips()
        for reason in reasons { skips.skip(reason) }
        return skips.message
    }

    // MARK: The seam

    @Test func oneRuleSaysWhatAnItemAllows() {
        let plain = F.item(F.n1, F.note, "Plain", age: 1)
        #expect(ItemChange.allCases.allSatisfy(plain.allows))

        var kept = plain
        kept.readOnly = true
        #expect(ItemChange.allCases.filter { !kept.allows($0) } == [.title, .text, .fields, .type])
        #expect(kept.obstacle(to: .fields) == .readOnly)

        var archived = kept
        archived.state = .archived
        #expect(ItemChange.allCases.filter { !archived.allows($0) } == [.title, .text, .fields, .type], "archived adds nothing")

        let file = F.item(F.f1, F.image, "Photo", age: 1, content: .file(.png, byteCount: 1))
        #expect(ItemChange.allCases.filter { !file.allows($0) } == [.text, .type])
        #expect(file.obstacle(to: .text) == .file)

        var binned = kept
        binned.state = .trashed
        #expect(ItemChange.allCases.allSatisfy { binned.obstacle(to: $0) == .inBin })
    }

    // MARK: Writes through the library

    @Test func aValueOfAReadOnlyItemIsNotWritten() async throws {
        let (library, source) = try await loaded()
        #expect(!library.setItemProperty(F.n2, key: "title", value: .string("Renamed"), undoManager: nil))
        #expect(source.writes.isEmpty)
        #expect(library.setItemProperty(F.n1, key: "title", value: .string("Renamed"), undoManager: nil), "its neighbours still take edits")
    }

    @Test func theBodyOfAReadOnlyItemIsNotWrittenAndTheTextIsGivenBack() async throws {
        let (library, source) = try await loaded()
        let read = try #require(library.item(F.n2)).version
        library.updateBody(of: F.n2, to: "Typed over it", readAt: read)
        #expect(source.writes.isEmpty)
        #expect(library.notices.told == 1, "the text is returned to the person, never dropped")
    }

    @Test func aReadOnlyItemTakesTagsFavoriteCollectionsLinksAndDelete() async throws {
        let (library, source) = try await loaded()
        library.addTag("later", to: [F.n2], undoManager: nil)
        library.setFavorite([F.n2], true, undoManager: nil)
        #expect(library.addToCollection([F.n2], Self.holiday, undoManager: nil))
        #expect(await library.changeItemRelationship(F.n2, field: "about", adding: [F.p1], removing: [], undoManager: nil))
        library.delete([F.n2], undoManager: nil)
        #expect(source.writes.count == 5, "sent \(source.writes)")
        #expect(source.writes.last == .transition(F.n2, .trashed))
        #expect(library.notices.waiting.isEmpty)
    }

    @Test func aReadOnlyItemDoesNotChangeType() async throws {
        let (library, source) = try await loaded()
        #expect(!library.changeType([F.n2], to: F.ticket, filling: [:], undoManager: nil))
        #expect(source.writes.isEmpty)
        #expect(library.notices.waiting.last?.message == skips(.readOnly))
    }

    @Test func aReadOnlyItemInTheBinCanStillBeRecovered() async throws {
        let (library, source) = try await loaded()
        library.recover([F.n3], undoManager: nil)
        #expect(source.writes == [.transition(F.n3, .active)])
        #expect(library.notices.told == 0)
    }
}
