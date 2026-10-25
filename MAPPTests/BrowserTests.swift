import Foundation
import Testing
@testable import MAPP

struct BrowserTests {
    @Test(arguments: [ItemViewMode.board, .agenda])
    func collectionStudiesOpenAndReturnWithoutLosingSelection(_ mode: ItemViewMode) {
        let (library, _, newer, _) = makeFakeLibrary()
        let browser = Browser()
        browser.adopt(library)
        browser.selection = [newer.id]
        browser.viewMode = mode
        browser.openCollectionSelection()
        #expect(browser.isCollectionItemPresented)
        browser.returnToCollection()
        #expect(browser.showsCollection)
        #expect(browser.selection == [newer.id])
        #expect(browser.viewMode == mode)
    }

    @Test func collectionOptionsAreClearedWhenTheLibraryChanges() {
        let (first, _, _, _) = makeFakeLibrary()
        let (second, _, _, _) = makeFakeLibrary()
        let browser = Browser()
        browser.adopt(first)
        browser.boardFields[.allNotes] = "status"
        browser.agendaFields[.allNotes] = "starts_at"
        browser.compactBoards[.allNotes] = true
        browser.adopt(second)
        #expect(browser.boardFields.isEmpty)
        #expect(browser.agendaFields.isEmpty)
        #expect(browser.compactBoards.isEmpty)
    }

    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    /// The same three notes in a library held in memory, for what the browser asks of any library.
    func makeFakeLibrary() -> (FakeItemLibrary, older: Item, newer: Item, favorite: Item) {
        let older = FakeItemLibrary.note("Older", modified: start - 120, tier: .feed)
        let newer = FakeItemLibrary.note("Newer", modified: start - 60, tier: .feed)
        let favorite = FakeItemLibrary.note("Favorite", modified: start - 3600, isFavorite: true)
        let library = FakeItemLibrary(items: [older, newer, favorite], now: start)
        return (library, older, newer, favorite)
    }

    @Test func settingsIsAPlaceThatKeepsTheListAndSelectionBehindIt() {
        let (library, _, newer, _) = makeFakeLibrary()
        let browser = Browser()
        browser.show(.inbox, in: library, order: NoteOrder())
        browser.selection = [newer.id]
        browser.showSettings(.library)
        #expect(browser.showsSettings)
        #expect(browser.settingsPage == .library)
        #expect(browser.sidebarItem == .inbox)
        #expect(browser.selection == [newer.id])
        browser.showSettings()
        #expect(browser.settingsPage == .library, "opening Settings again keeps the page it was on")
    }

    @Test func choosingAPlaceOrAnItemLeavesSettings() throws {
        let (library, older, _, _) = makeFakeLibrary()
        let item = try #require(library.item(older.id))
        let browser = Browser()
        browser.showSettings()
        browser.show(.allNotes, in: library, order: NoteOrder())
        #expect(!browser.showsSettings)
        browser.showSettings()
        browser.reveal(item, in: library, order: NoteOrder())
        #expect(!browser.showsSettings)
        browser.showSettings()
        browser.startNewItem(in: library, undoManager: nil)
        #expect(!browser.showsSettings)
    }

    @Test func everySettingsPageIsListedOnceAndNamed() {
        #expect(SettingsPage.groups.flatMap { $0 } == SettingsPage.allCases)
        #expect(Set(SettingsPage.allCases.map(\.title)).count == SettingsPage.allCases.count)
        #expect(SettingsPage.allCases.allSatisfy { !$0.summary.isEmpty && !$0.symbol.isEmpty })
    }

    @Test func revealingExistingItemsKeepsReadingFocusInListAndGallery() throws {
        let (library, older, _, _) = makeFakeLibrary()
        let item = try #require(library.item(older.id))
        let browser = Browser()
        browser.focusRequest = .page
        browser.reveal(item, in: library, order: NoteOrder())
        #expect(browser.selection == [item.id])
        #expect(browser.focusRequest == .list)
        browser.viewMode = .gallery
        browser.focusRequest = .page
        browser.reveal(item, in: library, order: NoteOrder())
        #expect(browser.isCollectionItemPresented)
        #expect(browser.focusRequest == nil)
    }

    @Test func backAndForwardMoveThroughTheItemsOpenedAndForgetWhatLiesAheadOnANewChoice() {
        let (library, older, newer, favorite) = makeFakeLibrary()
        let browser = Browser()
        #expect(!browser.canGoBack(in: library))
        browser.selection = [older.id]
        browser.selection = [newer.id]
        browser.selection = [favorite.id]
        #expect(browser.canGoBack(in: library))
        #expect(!browser.canGoForward(in: library))
        browser.go(.back, in: library)
        #expect(browser.selection == [newer.id])
        #expect(browser.canGoForward(in: library))
        browser.go(.back, in: library)
        #expect(browser.selection == [older.id])
        #expect(!browser.canGoBack(in: library))
        browser.go(.forward, in: library)
        #expect(browser.selection == [newer.id])
        browser.selection = [favorite.id]
        #expect(!browser.canGoForward(in: library), "a new choice drops what lay ahead")
        browser.go(.back, in: library)
        #expect(browser.selection == [newer.id], "going back did not add the entry again")
    }

    @Test func historyIgnoresSeveralItemsAndTheSameItemAgain() {
        let (library, older, newer, _) = makeFakeLibrary()
        let browser = Browser()
        browser.selection = [older.id]
        browser.selection = [older.id]
        browser.selection = [older.id, newer.id]
        browser.selection = []
        #expect(!browser.canGoBack(in: library), "one item alone was shown")
    }

    @Test func historySkipsDeletedItemsAndShowsAnItemInItsPlaceOrAllItems() {
        let (library, older, newer, favorite) = makeFakeLibrary()
        let browser = Browser()
        browser.sidebarItem = .favorites
        browser.selection = [favorite.id]
        browser.sidebarItem = .allNotes
        browser.selection = [older.id]
        browser.selection = [newer.id]
        library.delete([older.id], undoManager: nil)
        browser.go(.back, in: library)
        #expect(browser.selection == [favorite.id], "the deleted item is skipped")
        #expect(browser.sidebarItem == .favorites, "the place it was seen in comes back")
        #expect(browser.canGoForward(in: library))
        browser.go(.forward, in: library)
        #expect(browser.selection == [newer.id])
    }

    @Test func jumpingToANoteInAnotherPlaceLeavesNothingBetweenItAndTheNoteLeft() {
        let (library, older, newer, _) = makeFakeLibrary()
        let planning = FakeItemLibrary.note("Planning", modified: start - 7200)
        library.items.append(planning)
        let browser = Browser()
        browser.show(.inbox, in: library, order: NoteOrder())
        browser.selection = [older.id]
        browser.reveal(planning, in: library, order: NoteOrder())
        #expect(browser.selection == [planning.id])
        #expect(browser.history.entries.map(\.id) == [newer.id, older.id, planning.id], "the first note All Items showed on the way was not recorded")
        browser.go(.back, in: library)
        #expect(browser.selection == [older.id])
        #expect(browser.sidebarItem == .inbox)
    }

    @Test func theNoteAWindowOpensOnIsWhereBackCanReturnTo() {
        let (library, older, newer, _) = makeFakeLibrary()
        let browser = Browser()
        browser.show(.inbox, in: library, order: NoteOrder())
        #expect(browser.selection == [newer.id])
        browser.selection = [older.id]
        #expect(browser.history.entries.map(\.id) == [newer.id, older.id])
        browser.go(.back, in: library)
        #expect(browser.selection == [newer.id])
    }

    @Test func showingAPlaceOrSearchingMovesTheSelectionWithoutMakingHistory() {
        let (library, older, newer, favorite) = makeFakeLibrary()
        let browser = Browser()
        browser.show(.inbox, in: library, order: NoteOrder())
        browser.selection = [older.id]
        browser.show(.favorites, in: library, order: NoteOrder())
        #expect(browser.selection == [favorite.id])
        browser.show(.inbox, in: library, order: NoteOrder())
        browser.selection = [older.id]
        browser.searchText = "Newer"
        browser.keepSelection(from: [newer.id, older.id], to: browser.items(in: library).map(\.id))
        #expect(browser.selection == [newer.id], "the search moved the selection to a result")
        #expect(browser.history.entries.map(\.id) == [newer.id, older.id])
        #expect(!browser.canGoBack(in: library), "the only earlier note is the one the search moved to")
    }

    // MARK: Making a new item

    @Test func newMakesTheItemAtOnceAndAsksForItsTitle() throws {
        let (library, _, _, _) = makeFakeLibrary()
        let browser = Browser()
        browser.show(.allNotes, in: library, order: NoteOrder())
        browser.searchText = "Favorite"
        let count = library.items.count
        let id = try #require(browser.startNewItem(in: library, undoManager: nil))
        #expect(library.items.count == count + 1)
        let item = try #require(library.item(id))
        #expect(item.title == "Untitled")
        #expect(library.bodies[id] == "")
        #expect(library.item(id)?.type.rawValue == "core.note")
        #expect(browser.selection == [id])
        #expect(browser.focusRequest == .title)
        #expect(!browser.isSearching)
        #expect(browser.items(in: library).contains { $0.id == id })
        #expect(!browser.isAwaitingNewItem)
        #expect(library.notices.waiting.last == nil)
    }

    @Test func newFromAPlaceThatDoesNotListNotesRevealsTheNewItemInItsType() throws {
        let (library, _, _, _) = makeFakeLibrary()
        let browser = Browser()
        browser.show(.files, in: library, order: NoteOrder())
        let id = try #require(browser.startNewItem(in: library, undoManager: nil))
        #expect(browser.item == .itemType("core.note"))
        #expect(browser.selection == [id])
    }

    @Test func newMakesTheTypeChosenInTheMenu() throws {
        let (library, _, _, _) = makeFakeLibrary()
        let browser = Browser()
        let id = try #require(browser.startNewItem(typeID: "test.project", in: library, undoManager: nil))
        #expect(library.item(id)?.type.rawValue == "test.project")
        #expect(browser.selection == [id])
    }

    @Test func newWithoutATypeMakesTheTypeOfThePlaceBeingShown() throws {
        let (library, _, _, _) = makeFakeLibrary()
        let browser = Browser()
        browser.sidebarItem = .itemType("core.task")
        let id = try #require(browser.startNewItem(in: library, undoManager: nil))
        #expect(library.item(id)?.type.rawValue == "core.task")
    }

    @Test(arguments: ["test.project", "core.task"])
    func newInsideAnItemTakesItAsParentOnlyWhereTheTypeAllowsIt(typeID: String) throws {
        let project = Item(
            id: .mint(), type: TypeID("test.project"), title: "Launch", titleRule: .property("title"),
            version: ItemVersion(1), created: start, modified: start)
        let library = FakeItemLibrary(items: [project], now: start)
        library.parentCandidates["core.task"] = [project.id]
        let browser = Browser()
        browser.sidebarItem = .collection(project.id)
        let id = try #require(browser.startNewItem(typeID: typeID, in: library, undoManager: nil))
        let created = try #require(library.item(id))
        #expect(created.type.rawValue == typeID)
        #expect(created.parentID == (typeID == "core.task" ? project.id : nil))
        #expect(browser.selection == [id])
    }

    @Test func newMakesNothingWhileTheLibraryIsStillLoading() {
        let library = FakeItemLibrary(now: start)
        library.isLoaded = false
        let browser = Browser()
        #expect(browser.startNewItem(in: library, undoManager: nil) == nil)
        #expect(library.created.isEmpty && library.items.isEmpty)
    }

    @Test func newLeavesSettings() {
        let (library, _, _, _) = makeFakeLibrary()
        let browser = Browser()
        browser.showSettings()
        browser.startNewItem(in: library, undoManager: nil)
        #expect(!browser.showsSettings)
    }

    @Test func aSecondNewWhileTheFirstIsAwaitedMakesNothingMore() throws {
        let library = FakeItemLibrary(now: start)
        library.holdsCreations = true
        let browser = Browser()
        let first = try #require(browser.startNewItem(in: library, undoManager: nil))
        #expect(browser.isAwaitingNewItem)
        #expect(browser.selection.isEmpty, "the page opens once the library holds the item")
        #expect(browser.startNewItem(in: library, undoManager: nil) == first)
        #expect(library.created.count == 1)

        #expect(!browser.isNewItemSettled(in: library))
        library.deliverCreated()
        #expect(browser.isNewItemSettled(in: library))
        browser.finishNewItem(in: library)
        #expect(!browser.isAwaitingNewItem)
        #expect(browser.selection == [first])
        #expect(browser.focusRequest == .title)
    }

    @Test func aCreateTheLibraryRefusedIsGivenUpAndOpensNothing() throws {
        let library = FakeItemLibrary(now: start)
        library.holdsCreations = true
        let browser = Browser()
        let id = try #require(browser.startNewItem(in: library, undoManager: nil))
        library.refusedCreations.insert(id)
        #expect(browser.isNewItemSettled(in: library))
        browser.finishNewItem(in: library)
        #expect(!browser.isAwaitingNewItem)
        #expect(browser.selection.isEmpty)
        #expect(browser.newItems.isEmpty)
        #expect(browser.startNewItem(in: library, undoManager: nil) != nil, "New works again once the refusal is dealt with")
    }

    // MARK: Leaving a new item

    @Test func anItemLeftCompletelyEmptyIsMovedToRecentlyDeletedWhenAnotherIsChosen() throws {
        let (library, older, _, _) = makeFakeLibrary()
        let browser = Browser()
        let id = try #require(browser.startNewItem(in: library, undoManager: nil))
        browser.selection = [older.id]
        #expect(browser.leaveNewItem(id, closing: false, undoManager: nil))
        #expect(library.item(id)?.state == .trashed)
        #expect(library.notesToPurge.isEmpty, "an empty item is binned, never erased")
        #expect(browser.newItems.isEmpty)
        #expect(library.item(older.id)?.state == .active)
    }

    @Test func anEmptyItemIsDecidedWhenTheWindowOrAppClosesEvenWhileShown() throws {
        let (library, _, _, _) = makeFakeLibrary()
        let browser = Browser()
        let id = try #require(browser.startNewItem(in: library, undoManager: nil))
        #expect(!browser.leaveNewItem(id, closing: false, undoManager: nil), "it is still shown, as when Settings covers it")
        #expect(library.item(id)?.state == .active)
        #expect(browser.newItems[id] != nil)
        #expect(browser.leaveNewItem(id, closing: true, undoManager: nil))
        #expect(library.item(id)?.state == .trashed)
        #expect(library.notesToPurge.isEmpty)
    }

    @Test func anItemWithAnythingInItIsKept() throws {
        let (library, older, _, _) = makeFakeLibrary()
        let browser = Browser()

        let typedInto = try #require(browser.startNewItem(in: library, undoManager: nil))
        library.updateBody(of: typedInto, to: "Some text", readAt: try #require(library.item(typedInto)).version)
        browser.selection = [older.id]
        #expect(!browser.leaveNewItem(typedInto, closing: false, undoManager: nil))
        #expect(library.item(typedInto)?.state == .active)

        let favorited = try #require(browser.startNewItem(in: library, undoManager: nil))
        library.setFavorite([favorited], true, undoManager: nil)
        browser.selection = [older.id]
        #expect(!browser.leaveNewItem(favorited, closing: false, undoManager: nil))
        #expect(library.item(favorited)?.state == .active)

        let titled = try #require(browser.startNewItem(in: library, undoManager: nil))
        browser.selection = [older.id]
        #expect(!browser.leaveNewItem(titled, closing: false, hasUnsavedTitle: true, undoManager: nil))
        #expect(library.item(titled)?.state == .active)
        #expect(browser.newItems.isEmpty, "once left, it is an item like any other")
    }

    @Test func aBodyOfOnlyWhitespaceCountsAsEmpty() throws {
        let (library, older, _, _) = makeFakeLibrary()
        let browser = Browser()
        let id = try #require(browser.startNewItem(in: library, undoManager: nil))
        library.updateBody(of: id, to: " \n\n", readAt: try #require(library.item(id)).version)
        browser.selection = [older.id]
        #expect(browser.leaveNewItem(id, closing: false, undoManager: nil))
    }

    @Test func anEmptyItemTheLibrarySaysWasTouchedIsKept() throws {
        let (library, older, _, _) = makeFakeLibrary()
        let browser = Browser()
        let id = try #require(browser.startNewItem(in: library, undoManager: nil))
        library.touched.insert(id)
        browser.selection = [older.id]
        #expect(!browser.leaveNewItem(id, closing: false, undoManager: nil))
        #expect(library.item(id)?.state == .active)
    }

    // MARK: Keeping the selection in the list

    let a = ItemID.mint(), b = ItemID.mint(), c = ItemID.mint(), d = ItemID.mint()

    @Test func selectedNotesStillListedStaySelected() {
        #expect(Browser.selection([a, b], keptFrom: [a, b, c], in: [b, c]) == [b])
    }

    @Test func aSelectionThatLeavesTheListMovesToTheNoteAfterIt() {
        #expect(Browser.selection([b], keptFrom: [a, b, c], in: [a, c]) == [c])
        #expect(Browser.selection([b, c], keptFrom: [a, b, c, d], in: [a, d]) == [d])
    }

    @Test func withNothingAfterItTheSelectionMovesToTheNoteBefore() {
        #expect(Browser.selection([c], keptFrom: [a, b, c], in: [a, b]) == [b])
    }

    @Test func anEmptiedListLeavesNothingSelected() {
        #expect(Browser.selection([a], keptFrom: [a], in: []).isEmpty)
        #expect(Browser.selection([], keptFrom: [a], in: [a]).isEmpty)
    }

    // MARK: Showing and making

    @Test func showingAnItemClearsTheSearchAndSelectsItsTopRow() {
        let (library, _, newer, favorite) = makeFakeLibrary()
        let browser = Browser()
        browser.searchText = "Older"
        browser.show(.allNotes, in: library, order: NoteOrder())
        #expect(browser.searchText.isEmpty)
        #expect(browser.selection == [favorite.id])
        browser.show(.inbox, in: library, order: NoteOrder())
        #expect(browser.selection == [newer.id])
    }

    @Test(arguments: [SidebarItem.sources, .collections, .inbox, .source("test"), .collection(ItemID("parent"))])
    func listSearchIsAvailableOnlyWhereAnItemListExists(place: SidebarItem) {
        let browser = Browser()
        browser.sidebarItem = place
        let hasList = place != .sources && place != .collections
        #expect(browser.canSearchList == hasList)
        browser.showSettings()
        #expect(!browser.canSearchList)
        browser.leaveSettings()
        #expect(browser.canSearchList == hasList)
    }

    @Test func aWhitespaceSearchIsNoSearch() {
        let browser = Browser()
        browser.searchText = "  \n"
        #expect(!browser.isSearching)
    }

    @Test func favoritesLeadOnlyWhereTheyMeanSomething() {
        let (library, _, newer, _) = makeFakeLibrary()
        let browser = Browser()
        browser.show(.allNotes, in: library, order: NoteOrder())
        #expect(browser.sections(in: library, order: NoteOrder(), now: start).first?.group == .favorites)
        browser.searchText = "e"
        #expect(browser.sections(in: library, order: NoteOrder(), now: start).first?.items.first?.id == newer.id)
    }

    @Test func aLibraryThatCannotPurgeIsNeverAskedToEraseWhatIsDeleted() {
        let (library, older, newer, _) = makeFakeLibrary()
        library.canPurge = false
        library.delete([older.id], undoManager: nil)
        Browser.delete([older.id, newer.id], in: library, undoManager: nil)
        #expect(library.item(newer.id)?.state == .trashed, "what is live still goes to Recently Deleted")
        #expect(library.item(older.id)?.state == .trashed)
        #expect(library.notesToPurge.isEmpty)
        library.canPurge = true
        Browser.delete([older.id], in: library, undoManager: nil)
        #expect(library.notesToPurge == [older.id])
    }

    // MARK: Restoring

    @Test func aRestoredWindowShowsWhatItShowedBefore() {
        let (library, older, _, _) = makeFakeLibrary()
        let saved = Browser()
        saved.show(.inbox, in: library, order: NoteOrder())
        saved.selection = [older.id]
        let restored = Browser()
        restored.restore(saved.snapshot(), in: library, order: NoteOrder())
        #expect(restored.item == .inbox)
        #expect(restored.selection == [older.id])
    }

    @Test func aRestoredWindowShowsATypeTheLibraryHoldsAndLeavesOneItDoesNot() {
        let (library, _, _, _) = makeFakeLibrary()
        let held = library.itemTypeCounts.first.map(\.id.rawValue) ?? ""
        #expect(!held.isEmpty)
        let browser = Browser()
        browser.restore(Browser.Snapshot(place: .itemType(held), selection: []), in: library, order: NoteOrder())
        #expect(browser.item == .itemType(held))
        browser.restore(Browser.Snapshot(place: .itemType("aic.nothing"), selection: []), in: library, order: NoteOrder())
        #expect(browser.item == .allNotes)
    }

    @Test func aRestoredWindowDropsWhatNoLongerExists() {
        let (library, _, _, favorite) = makeFakeLibrary()
        let snapshot = Browser.Snapshot(place: .collection(.mint()), selection: [.mint()])
        let browser = Browser()
        browser.restore(snapshot, in: library, order: NoteOrder())
        #expect(browser.item == .allNotes)
        #expect(browser.selection == [favorite.id])
    }

    @Test func snapshotsSurviveEncodingAsIdentifiers() throws {
        let collection = ItemID("0198f2c4-7d1e-7a00-8000-000000000001")
        let note = ItemID("0198f2c4-7d1e-7a00-8000-000000000002")
        let snapshot = Browser.Snapshot(place: .collection(collection), selection: [note])
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(Browser.Snapshot.self, from: data) == snapshot)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["selection"] as? [String] == [note.rawValue], "an identifier is kept as its own string")
    }

    @Test(arguments: [
        Data(#"{"sidebarItem":{"folder":{"_0":"Work"}},"selection":["Older.md"]}"#.utf8),
        Data("not a snapshot".utf8),
        nil,
    ])
    func aWindowKeptByPathBeforeIdentifiersOrNotAtAllOpensAtItsDefault(saved: Data?) {
        let (library, _, _, favorite) = makeFakeLibrary()
        let browser = Browser()
        browser.restore(from: saved, in: library, order: NoteOrder())
        #expect(browser.item == .allNotes)
        #expect(browser.selection == [favorite.id])
    }

    @Test func aDraggedNoteCarriesItsIdentifierAsAString() throws {
        let id = ItemID("0198f2c4-7d1e-7a00-8000-000000000003")
        let data = try JSONEncoder().encode(NoteReference(id: id, markdown: "# Plan"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["id"] as? String == id.rawValue)
        let decoded = try JSONDecoder().decode(NoteReference.self, from: data)
        #expect(decoded.id == id)
        #expect(decoded.markdown == "# Plan")
    }

    @Test func turningOffDateGroupingListsNotesUnderOneHeadingAfterTheFavorites() {
        let (library, _, _, _) = makeFakeLibrary()
        let browser = Browser()
        browser.show(.allNotes, in: library, order: NoteOrder())
        let sections = browser.sections(in: library, order: NoteOrder(sort: .dateEdited, groupsByDate: false), now: start)
        #expect(sections.map(\.group) == [.favorites, nil])
    }
}
