import Foundation
import Testing
@testable import MAPP

/// An item a person's connector keeps, which the server marks read only: the seam that decides an item takes
/// changes refuses it everywhere, the items around it are changed as before, and what stays open to a person stays open.
@MainActor
@Suite(.hangLimit) struct ReadOnlyItemTests {
    typealias F = LibraryFixture

    static let holiday = MarfaCollectionsTests.holiday

    /// The collections fixture with Feed note, Beta and Old note held read only, Old note in the bin.
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

    @Test func anItemNoConnectorKeepsTakesChangesAsBefore() {
        let item = F.item(F.n1, F.note, "Plain", age: 1)
        #expect(!item.readOnly)
        #expect(item.isEditable && item.isWritable && item.canEditTags)
        #expect(item.writeObstacle == nil)
    }

    @Test func aReadOnlyItemOffersNoValueTextOrTagToChange() {
        var item = F.item(F.n1, F.note, "Plain", age: 1)
        item.readOnly = true
        #expect(!item.isEditable, "the page and the sidebar offer no value to edit")
        #expect(!item.isWritable, "and the body takes no typing")
        #expect(!item.canEditTags)
        #expect(item.writeObstacle == .readOnly)
    }

    @Test func aReadOnlyItemInTheBinIsToldAsInTheBinFirst() {
        var item = F.item(F.n1, F.note, "Plain", age: 1, state: .trashed)
        item.readOnly = true
        #expect(item.writeObstacle == .inBin)
    }

    @Test func theReadOnlySentenceSaysWhyInPlainWords() {
        #expect(skips(.readOnly) == "1 item is managed by a connector, so changes made here would be overwritten.")
        #expect(skips(.readOnly, .inBin)?.contains("Recently Deleted") == true)
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

    @Test func tagsOfAReadOnlyItemAreNotChangedAndTheOthersAre() async throws {
        let (library, source) = try await loaded()
        library.addTag("work", to: [F.n1, F.n2], undoManager: nil)
        #expect(source.writes == [.tag(F.n1, "work", on: true)])
        #expect(library.notices.waiting.last?.message == skips(.readOnly))

        source.clearWrites()
        library.removeTag("work", from: [F.p2], undoManager: nil)
        #expect(source.writes.isEmpty, "a tag a connector keeps is not removed here")
    }

    @Test func aReadOnlyItemDoesNotChangeType() async throws {
        let (library, source) = try await loaded()
        #expect(!library.changeType([F.n2], to: F.ticket, filling: [:], undoManager: nil))
        #expect(source.writes.isEmpty)
        #expect(library.notices.waiting.last?.message == skips(.readOnly))
    }

    @Test func favoriteLeavesAReadOnlyItemAloneAndTellsHowMany() async throws {
        let (library, source) = try await loaded()
        library.setFavorite([F.n1, F.n2], true, undoManager: nil)
        #expect(source.writes.isEmpty, "Plain note is a favorite already, and Feed note is kept by a connector")
        #expect(library.notices.waiting.last?.message == skips(.readOnly))

        library.setFavorite([F.e1, F.n2], true, undoManager: nil)
        #expect(source.writes == [.tag(F.e1, ItemTag.favorite, on: true)])
    }

    @Test func deleteLeavesAReadOnlyItemInPlace() async throws {
        let (library, source) = try await loaded()
        library.delete([F.e1, F.n2], undoManager: nil)
        #expect(source.writes == [.transition(F.e1, .trashed)])
        #expect(library.notices.waiting.last?.title == String(localized: "Some Items Were Skipped"))
        #expect(library.notices.waiting.last?.message == skips(.readOnly))
    }

    @Test func deletingOnlyAReadOnlyItemSaysSoAndAsksNothing() async throws {
        let (library, source) = try await loaded()
        var asked = false
        Browser.delete([F.n2, F.p2], in: library, undoManager: nil, asking: { _ in asked = true })
        #expect(!asked, "nothing is left to confirm")
        #expect(source.writes.isEmpty)
        #expect(library.notices.waiting.last?.title == String(localized: "Can’t Delete"))
        #expect(library.notices.waiting.last?.message == skips(.readOnly, .readOnly))
    }

    @Test func aMixedDeleteAsksAboutOnlyTheItemsItWillMove() async throws {
        let (library, _) = try await loaded()
        var asked: Set<ItemID>?
        Browser.delete([F.e1, F.n1, F.n2], in: library, undoManager: nil, asking: { asked = $0 })
        #expect(asked == [F.e1, F.n1])
    }

    @Test func aReadOnlyItemInTheBinCanStillBeRecovered() async throws {
        let (library, source) = try await loaded()
        library.recover([F.n3], undoManager: nil)
        #expect(source.writes == [.transition(F.n3, .active)])
        #expect(library.notices.told == 0)
    }

    @Test func aReadOnlyItemIsNotFiledInACollection() async throws {
        let (library, source) = try await loaded()
        #expect(!library.canJoinCollection(try #require(library.item(F.n2))))
        #expect(library.addToCollection([F.e1, F.n2], Self.holiday, undoManager: nil))
        let joined = source.writes.compactMap { write -> ItemID? in if case .link(let draft, _) = write { draft.source } else { nil } }
        #expect(joined == [F.e1])
        #expect(library.notices.waiting.last?.message == skips(.readOnly))
    }

    @Test func theRelationshipsOfAReadOnlyItemOfferNoChange() async throws {
        let (library, source) = try await loaded()
        #expect(library.relationships(for: F.n2).allSatisfy { !$0.isEditable })
        let kept = await library.changeItemRelationship(F.n2, field: "about", adding: [F.p1], removing: [], undoManager: nil)
        #expect(!kept)
        #expect(source.writes.isEmpty)
        #expect(library.relationships(for: F.n1).contains { $0.isEditable }, "an item no connector keeps still does")
    }

    // MARK: What stays open

    @Test func aReadOnlyItemCanStillBeReadAndItsLayoutCustomised() async throws {
        let (library, _) = try await loaded()
        let item = try #require(library.item(F.n2))
        #expect(item.displayTitle == "Feed note")
        #expect(library.body(of: F.n2)?.text == "Text of n2")
        #expect(PageCustomization.isAvailable(for: item), "Customize Layout changes no item")
    }
}
