import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MAPP

struct BrowserTests {
    @Test(arguments: [ItemViewMode.board, .timeline])
    func collectionStudiesOpenAndReturnWithoutLosingSelection(_ mode: ItemViewMode) {
        let (library, _, newer, _) = makeFakeLibrary()
        let browser = Browser()
        browser.adopt(library)
        browser.sidebarItem = .recents
        browser.selection = [newer.id]
        browser.viewMode = mode
        browser.open(browser.selection, as: .fullPage)
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

    @Test func showingSettingsAsksTheWindowToOpenAtThePageAndChangesNothingHere() {
        let (library, _, newer, _) = makeFakeLibrary()
        let browser = Browser()
        browser.show(.inbox, in: library, order: ItemOrder())
        browser.selection = [newer.id]
        var asked: [SettingsPage?] = []
        browser.openSettings = { asked.append($0) }
        browser.showSettings(.connection)
        browser.showSettings()
        #expect(asked == [.connection, nil], "no page leaves the window where it was")
        #expect(browser.sidebarItem == .inbox)
        #expect(browser.selection == [newer.id])
    }

    @Test func everySettingsPageIsListedOnceAndNamed() {
        #expect(Set(SettingsPage.all).count == SettingsPage.all.count)
        #expect(Set(SettingsPage.all.map(\.title)).count == SettingsPage.all.count)
        #expect(SettingsPage.all.allSatisfy { !$0.symbol.isEmpty })
        #expect(SettingsPage.mappGroups.flatMap { $0 }.allSatisfy { $0.marfaPage == nil })
        #expect(SettingsPage.marfaGroups.flatMap { $0 }.allSatisfy { $0.marfaPage != nil })
    }

    @Test func revealingExistingItemsKeepsReadingFocusInListAndGallery() throws {
        let (library, older, _, _) = makeFakeLibrary()
        let item = try #require(library.item(older.id))
        let browser = Browser()
        browser.sidebarItem = .recents
        browser.focusRequest = .page
        browser.reveal(item, in: library, order: ItemOrder())
        #expect(browser.selection == [item.id])
        #expect(browser.focusRequest == .list)
        browser.viewMode = .gallery
        browser.focusRequest = .page
        browser.reveal(item, in: library, order: ItemOrder())
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
        browser.sidebarItem = .allItems
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

    @Test func jumpingToAnItemInAnotherPlaceLeavesNothingBetweenItAndTheItemLeft() {
        let (library, older, newer, _) = makeFakeLibrary()
        let planning = FakeItemLibrary.note("Planning", modified: start - 7200)
        library.items.append(planning)
        let browser = Browser()
        browser.show(.inbox, in: library, order: ItemOrder())
        browser.selection = [older.id]
        browser.reveal(planning, in: library, order: ItemOrder())
        #expect(browser.selection == [planning.id])
        #expect(browser.history.entries.map(\.id) == [newer.id, older.id, planning.id], "the first item All Items showed on the way was not recorded")
        browser.go(.back, in: library)
        #expect(browser.selection == [older.id])
        #expect(browser.sidebarItem == .inbox)
    }

    @Test func theItemAWindowOpensOnIsWhereBackCanReturnTo() {
        let (library, older, newer, _) = makeFakeLibrary()
        let browser = Browser()
        browser.show(.inbox, in: library, order: ItemOrder())
        #expect(browser.selection == [newer.id])
        browser.selection = [older.id]
        #expect(browser.history.entries.map(\.id) == [newer.id, older.id])
        browser.go(.back, in: library)
        #expect(browser.selection == [newer.id])
    }

    @Test func showingAPlaceOrSearchingMovesTheSelectionWithoutMakingHistory() {
        let (library, older, newer, favorite) = makeFakeLibrary()
        let browser = Browser()
        browser.show(.inbox, in: library, order: ItemOrder())
        browser.selection = [older.id]
        browser.show(.favorites, in: library, order: ItemOrder())
        #expect(browser.selection == [favorite.id])
        browser.show(.inbox, in: library, order: ItemOrder())
        browser.selection = [older.id]
        browser.searchText = "Newer"
        browser.keepSelection(from: [newer.id, older.id], to: browser.items(in: library).map(\.id))
        #expect(browser.selection == [newer.id], "the search moved the selection to a result")
        #expect(browser.history.entries.map(\.id) == [newer.id, older.id])
        #expect(!browser.canGoBack(in: library), "the only earlier item is the one the search moved to")
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

    @Test func selectedItemsStillListedStaySelected() {
        #expect(Browser.selection([a, b], keptFrom: [a, b, c], in: [b, c]) == [b])
    }

    @Test func aSelectionThatLeavesTheListMovesToTheItemAfterIt() {
        #expect(Browser.selection([b], keptFrom: [a, b, c], in: [a, c]) == [c])
        #expect(Browser.selection([b, c], keptFrom: [a, b, c, d], in: [a, d]) == [d])
    }

    @Test func withNothingAfterItTheSelectionMovesToTheItemBefore() {
        #expect(Browser.selection([c], keptFrom: [a, b, c], in: [a, b]) == [b])
    }

    @Test func anEmptiedListLeavesNothingSelected() {
        #expect(Browser.selection([a], keptFrom: [a], in: []).isEmpty)
        #expect(Browser.selection([], keptFrom: [a], in: [a]).isEmpty)
    }

    // MARK: Showing and making

    @Test func showingAnItemClearsTheSearchAndSelectsItsTopRow() {
        let (library, _, newer, _) = makeFakeLibrary()
        let browser = Browser()
        browser.searchText = "Older"
        browser.show(.allItems, in: library, order: ItemOrder())
        #expect(browser.searchText.isEmpty)
        #expect(browser.selection.isEmpty, "Items is an index, which chooses nothing until the person does")
        browser.show(.inbox, in: library, order: ItemOrder())
        #expect(browser.selection == [newer.id])
    }

    @Test func aWhitespaceSearchIsNoSearch() {
        let browser = Browser()
        browser.searchText = "  \n"
        #expect(!browser.isSearching)
    }

    @Test func favoritesLeadOnlyWhereTheyMeanSomething() {
        let (library, _, newer, _) = makeFakeLibrary()
        let browser = Browser()
        browser.show(.allItems, in: library, order: ItemOrder())
        #expect(browser.sections(in: library, order: ItemOrder(), now: start).first?.group == .favorites)
        browser.searchText = "e"
        browser.orderSearch(byRelevance: false)
        let results = browser.sections(in: library, order: ItemOrder(), now: start)
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
        browser.show(.collection(collection.id), in: library, order: ItemOrder())
        #expect(browser.keepsPlaceOrder)
        let sections = browser.sections(in: library, order: ItemOrder(sort: .dateEdited, groupsByDate: true), now: start)
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
        #expect(library.itemsToPurge.isEmpty)
        library.reachesServer = true
        Browser.delete([older.id], in: library, undoManager: nil)
        #expect(library.itemsToPurge == [older.id])
    }

    // MARK: Restoring

    @Test func aRestoredWindowShowsWhatItShowedBefore() {
        let (library, older, _, _) = makeFakeLibrary()
        let saved = Browser()
        saved.show(.inbox, in: library, order: ItemOrder())
        saved.selection = [older.id]
        let restored = Browser()
        restored.restore(saved.snapshot(), in: library, order: ItemOrder())
        #expect(restored.item == .inbox)
        #expect(restored.selection == [older.id])
    }

    @Test func aRestoredWindowShowsATypeTheLibraryHoldsAndLeavesOneItDoesNot() {
        let (library, _, _, _) = makeFakeLibrary()
        let held = library.itemTypeCounts.first.map(\.id.rawValue) ?? ""
        #expect(!held.isEmpty)
        let browser = Browser()
        browser.restore(Browser.Snapshot(place: .itemType(held), selection: []), in: library, order: ItemOrder())
        #expect(browser.item == .itemType(held))
        browser.restore(Browser.Snapshot(place: .itemType("aic.nothing"), selection: []), in: library, order: ItemOrder())
        #expect(browser.item == .allItems)
    }

    @Test func aRestoredWindowDropsWhatNoLongerExists() {
        let (library, _, _, _) = makeFakeLibrary()
        let snapshot = Browser.Snapshot(place: .collection(.mint()), selection: [.mint()])
        let browser = Browser()
        browser.restore(snapshot, in: library, order: ItemOrder())
        #expect(browser.item == .allItems)
        #expect(browser.selection.isEmpty, "Items is an index, which chooses nothing until the person does")
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
        let (library, _, _, _) = makeFakeLibrary()
        let browser = Browser()
        browser.restore(from: saved, in: library, order: ItemOrder())
        #expect(browser.item == .allItems)
        #expect(browser.selection.isEmpty, "Items is an index, which chooses nothing until the person does")
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

    @Test func turningOffDateGroupingListsItemsUnderOneHeadingAfterTheFavorites() {
        let (library, _, _, _) = makeFakeLibrary()
        let browser = Browser()
        browser.show(.allItems, in: library, order: ItemOrder())
        let sections = browser.sections(in: library, order: ItemOrder(sort: .dateEdited, groupsByDate: false), now: start)
        #expect(sections.map(\.group) == [.favorites, nil])
    }
}
