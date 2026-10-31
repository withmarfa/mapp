import Foundation
import Testing
@testable import MAPP

struct BrowserTests {
    @Test(arguments: [ItemViewMode.board, .timeline])
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
        browser.timelineFields[.allNotes] = "starts_at"
        browser.compactBoards[.allNotes] = true
        browser.adopt(second)
        #expect(browser.boardFields.isEmpty)
        #expect(browser.timelineFields.isEmpty)
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
        browser.openQuickAdd(in: library)
        #expect(!browser.showsSettings)
    }

    @Test func everySettingsPageIsListedOnceAndNamed() {
        #expect(SettingsPage.groups.flatMap { $0 } == SettingsPage.allCases)
        #expect(Set(SettingsPage.allCases.map(\.title)).count == SettingsPage.allCases.count)
        #expect(SettingsPage.allCases.allSatisfy { !$0.symbol.isEmpty })
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

    // MARK: Keeping the selection in the list

    @Test func aSearchNotYetAnsweredHoldsTheSelectionForTheAnswer() {
        let browser = Browser()
        browser.selection = [b]
        browser.keepSelection(from: [a, b, c], to: [], isPending: true)
        #expect(browser.selection == [b], "an empty list that is only waiting says nothing about the selection")
        browser.keepSelection(from: [], to: [c, d])
        #expect(browser.selection == [c], "the answer is compared with the list before the search")
    }

    @Test func aSearchAnsweredWithNothingClearsTheHeldSelection() {
        let browser = Browser()
        browser.selection = [b]
        browser.keepSelection(from: [a, b, c], to: [], isPending: true)
        browser.keepHeldSelection(in: [])
        #expect(browser.selection.isEmpty, "an answer of nothing leaves nothing to select, though the list did not change")
        browser.selection = [c]
        browser.keepHeldSelection(in: [])
        #expect(browser.selection == [c], "with no search waiting, there is nothing held to resolve")
    }

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
    func searchIsAvailableOnEveryPlaceButSettings(place: SidebarItem) {
        let browser = Browser()
        browser.sidebarItem = place
        #expect(browser.canSearchList)
        browser.showSettings()
        #expect(!browser.canSearchList)
        browser.leaveSettings()
        #expect(browser.canSearchList)
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
        browser.orderSearch(byRelevance: false)
        let results = browser.sections(in: library, order: NoteOrder(), now: start)
        #expect(results.first?.group != .favorites)
        #expect(results.first?.items.first?.id == newer.id)
    }

    @Test func aCollectionKeepsItsOwnOrderUntilASearch() {
        let (library, older, newer, favorite) = makeFakeLibrary()
        let collection = FakeItemLibrary.collection("Reading")
        library.items.append(collection)
        // The fake lists members in the library's order: older before newer, whatever the list's sort.
        #expect(library.addToCollection([older.id, newer.id, favorite.id], collection.id, undoManager: nil))
        let browser = Browser()
        browser.show(.collection(collection.id), in: library, order: NoteOrder())
        #expect(browser.keepsPlaceOrder)
        let sections = browser.sections(in: library, order: NoteOrder(sort: .dateEdited, groupsByDate: true), now: start)
        #expect(sections.count == 1)
        #expect(sections.first?.group == nil)
        #expect(sections.first?.items.map(\.id) == [older.id, newer.id, favorite.id])
        browser.searchText = "e"
        #expect(!browser.keepsPlaceOrder)
    }

    @Test func aLibraryThatCannotPurgeIsNeverAskedToEraseWhatIsDeleted() {
        let (library, older, newer, _) = makeFakeLibrary()
        library.reachesServer = false
        library.delete([older.id], undoManager: nil)
        Browser.delete([older.id, newer.id], in: library, undoManager: nil)
        #expect(library.item(newer.id)?.state == .trashed, "what is live still goes to Recently Deleted")
        #expect(library.item(older.id)?.state == .trashed)
        #expect(library.notesToPurge.isEmpty)
        library.reachesServer = true
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
