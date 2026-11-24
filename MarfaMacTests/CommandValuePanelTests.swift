import Foundation
import Testing
@testable import MarfaMac

/// The Add to Collection and Add Tag panels, which a command opens for the whole selection and the page's own rows open
/// for the one item, under the value instead of in a sheet.
@MainActor
struct CommandValuePanelTests {
    private func note(_ title: String) -> Item { FakeItemLibrary.note(title, modified: .now) }

    private func model(
        _ kind: ValueEditKind, over ids: [ItemID], in library: FakeItemLibrary
    ) -> ValueEditModel {
        var request = ValueEditRequest(kind: kind, library: library, item: ids.count == 1 ? ids.first : nil)
        request.items = Set(ids)
        request.isCentered = true
        return ValueEditModel(request)
    }

    private func world() -> (library: FakeItemLibrary, first: Item, second: Item, reading: Item, work: Item) {
        let first = note("First"), second = note("Second")
        let reading = FakeItemLibrary.collection("Reading"), work = FakeItemLibrary.collection("Work")
        let library = FakeItemLibrary(items: [first, second, reading, work])
        library.catalogue = FakeItemLibrary.testCatalogue
        return (library, first, second, reading, work)
    }

    // MARK: Collections

    @Test func choosingACollectionFilesEveryItemThePanelIsForAndKeepsThePanelOpen() {
        let world = world()
        let model = model(.collections, over: [world.first.id, world.second.id], in: world.library)
        var closed = false
        model.close = { closed = true }
        model.activate(ValueEditModel.collectionPrefix + world.reading.id.rawValue)
        #expect(world.library.item(world.first.id)?.collectionIDs == [world.reading.id])
        #expect(world.library.item(world.second.id)?.collectionIDs == [world.reading.id])
        #expect(!closed, "the person may add the item to another collection")
        #expect(model.chips.map(\.title) == ["Reading"])
        #expect(model.rows.map(\.title) == ["Work"], "a collection every item is in is not offered again")
    }

    @Test func aCollectionOnlySomeOfTheItemsAreInIsNotShownAsHeldAndCanBeChosenForTheRest() {
        let world = world()
        #expect(world.library.addToCollection([world.first.id], world.reading.id, undoManager: nil))
        let model = model(.collections, over: [world.first.id, world.second.id], in: world.library)
        #expect(model.chips.isEmpty)
        #expect(model.rows.map(\.title) == ["Reading", "Work"])
        model.activate(ValueEditModel.collectionPrefix + world.reading.id.rawValue)
        #expect(world.library.item(world.second.id)?.collectionIDs == [world.reading.id])
        #expect(model.chips.map(\.title) == ["Reading"])
    }

    @Test func takingAChipAwayRemovesTheItemsFromThatCollectionOnly() throws {
        let world = world()
        try #require(world.library.addToCollection([world.first.id], world.reading.id, undoManager: nil))
        try #require(world.library.addToCollection([world.first.id], world.work.id, undoManager: nil))
        let model = model(.collections, over: [world.first.id], in: world.library)
        let chip = try #require(model.chips.first { $0.title == "Reading" })
        model.remove(chip)
        #expect(world.library.item(world.first.id)?.collectionIDs == [world.work.id])
    }

    @Test func aPanelForItemsNoneCanJoinIsNotEditableAndSavesNothing() {
        let world = world()
        let model = model(.collections, over: [world.reading.id], in: world.library)
        #expect(!model.isEditable, "a collection is no member of a collection here")
        model.activate(ValueEditModel.collectionPrefix + world.work.id.rawValue)
        #expect(world.library.item(world.reading.id)?.collectionIDs.isEmpty == true)
    }

    @Test func theCollectionRowIsTheMembershipEdge() {
        #expect(ValueEditKind.collections.rowID == MarfaMapping.collectionEdge)
        #expect(!ValueEditKind.collections.closesOnChoice)
    }

    // MARK: Tags

    @Test func aTagIsAddedToEveryItemThePanelIsFor() {
        let world = world()
        let model = model(.tags, over: [world.first.id, world.second.id], in: world.library)
        model.query = "idea"
        model.activate("create")
        #expect(world.library.item(world.first.id)?.tags.contains("idea") == true)
        #expect(world.library.item(world.second.id)?.tags.contains("idea") == true)
        #expect(model.chips.map(\.title) == ["idea"])
    }

    @Test func onlyTheTagsEveryItemHoldsShowAsChipsAndRemovingOneTakesItFromAll() {
        let world = world()
        world.library.addTag("shared", to: [world.first.id, world.second.id], undoManager: nil)
        world.library.addTag("mine", to: [world.first.id], undoManager: nil)
        let model = model(.tags, over: [world.first.id, world.second.id], in: world.library)
        #expect(model.heldTokens == ["shared"])
        model.removeToken("shared")
        #expect(world.library.item(world.first.id)?.tags.contains("shared") == false)
        #expect(world.library.item(world.second.id)?.tags.contains("shared") == false)
        #expect(world.library.item(world.first.id)?.tags.contains("mine") == true)
    }

    @Test func anItemThatCannotTakeTagsDoesNotEmptyTheTagsTheOthersHold() {
        let world = world()
        var kept = note("Kept by a connector")
        kept.readOnly = true
        world.library.items.append(kept)
        world.library.addTag("shared", to: [world.first.id, world.second.id], undoManager: nil)
        let model = model(.tags, over: [world.first.id, world.second.id, kept.id], in: world.library)
        #expect(model.heldTokens == ["shared"], "the item the panel cannot change is left out of what every item must hold")
    }

    @Test func aTagRefusedForTheTextTypedKeepsItAndTellsWhy() {
        let world = world()
        let model = model(.tags, over: [world.first.id], in: world.library)
        model.query = "   "
        model.activate("create")
        #expect(model.notice != nil)
        #expect(model.query == "   ", "what was typed is kept")
    }
}
