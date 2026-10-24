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
    let work = Folder(name: "Work")

    func makeLibrary() -> (NoteLibrary, older: Note, newer: Note, favorite: Note) {
        let older = Note(body: "# Older", created: start - 120)
        let newer = Note(body: "# Newer", created: start - 60)
        let favorite = Note(body: "# Favorite", created: start - 3600, folderID: work.id, isFavorite: true)
        let library = NoteLibrary(notes: [older, newer, favorite], folders: [work], now: { start })
        return (library, older, newer, favorite)
    }

    /// The same three notes in a library held in memory, for what the browser asks of any library.
    func makeFakeLibrary() -> (FakeItemLibrary, older: Item, newer: Item, favorite: Item) {
        let older = FakeItemLibrary.note("Older", modified: start - 120)
        let newer = FakeItemLibrary.note("Newer", modified: start - 60)
        let favorite = FakeItemLibrary.note("Favorite", modified: start - 3600, in: work, isFavorite: true)
        let library = FakeItemLibrary(items: [older, newer, favorite], folders: [work], now: start)
        return (library, older, newer, favorite)
    }

    @Test func settingsIsAPlaceThatKeepsTheListAndSelectionBehindIt() {
        let (library, _, newer, _) = makeLibrary()
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
        let (library, older, _, _) = makeLibrary()
        let item = try #require(library.item(older.id))
        let browser = Browser()
        browser.showSettings()
        browser.show(.allNotes, in: library, order: NoteOrder())
        #expect(!browser.showsSettings)
        browser.showSettings()
        browser.reveal(item, in: library, order: NoteOrder())
        #expect(!browser.showsSettings)
        browser.showSettings()
        browser.startItemDraft()
        #expect(!browser.showsSettings)
    }

    @Test func everySettingsPageIsListedOnceAndNamed() {
        #expect(SettingsPage.groups.flatMap { $0 } == SettingsPage.allCases)
        #expect(Set(SettingsPage.allCases.map(\.title)).count == SettingsPage.allCases.count)
        #expect(SettingsPage.allCases.allSatisfy { !$0.summary.isEmpty && !$0.symbol.isEmpty })
    }

    @Test func revealingExistingItemsKeepsReadingFocusInListAndGallery() throws {
        let (library, older, _, _) = makeLibrary()
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
        let planning = FakeItemLibrary.note("Planning", modified: start - 7200, in: work)
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
        browser.show(.folder(work.id), in: library, order: NoteOrder())
        #expect(browser.selection == [favorite.id])
        browser.show(.inbox, in: library, order: NoteOrder())
        browser.selection = [older.id]
        browser.searchText = "Newer"
        browser.keepSelection(from: [newer.id, older.id], to: browser.items(in: library).map(\.id))
        #expect(browser.selection == [newer.id], "the search moved the selection to a result")
        #expect(browser.history.entries.map(\.id) == [newer.id, older.id])
        #expect(!browser.canGoBack(in: library), "the only earlier note is the one the search moved to")
    }

    @Test func draftDoesNotExposePreviouslySelectedNoteToCommands() {
        let (library, _, newer, _) = makeFakeLibrary()
        let browser = Browser()
        browser.selection = [newer.id]
        #expect(browser.selectedItems(in: library).count == 1)
        browser.startItemDraft()
        #expect(browser.selectedItems(in: library).isEmpty)
        browser.isCreatingItem = false
        #expect(browser.selectedItems(in: library).count == 1)
    }

    @Test func creationOutsideOriginalProjectRevealsTheNewItem() throws {
        let library = NoteLibrary(notes: [])
        let project = try #require(library.createItem(typeID: "aic.project", title: "Project", in: .allNotes).flatMap { library.note($0) })
        let browser = Browser()
        browser.sidebarItem = .collection(project.id)
        browser.startItemDraft()
        browser.itemDraft?.typeID = "aic.ticket.task"
        browser.itemDraft?.title = "Unparented task"
        browser.itemDraft?.parentID = nil
        let id = try #require(browser.createDraft(in: library, undoManager: nil))
        #expect(browser.items(in: library).contains { $0.id == id })
        #expect(browser.selection == [id])
        #expect(browser.focusRequest == .page)
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

    @Test(arguments: [SidebarItem.files])
    func aNewItemFromAPlaceWithoutNotesOpensADraftThenRevealsTheCreatedItem(from item: SidebarItem) {
        let (library, _, _, _) = makeLibrary()
        let browser = Browser()
        browser.show(item, in: library, order: NoteOrder())
        browser.searchText = "Favorite"
        let count = library.notes.count
        browser.startItemDraft()
        #expect(browser.isCreatingItem)
        #expect(browser.item == item)
        #expect(library.notes.count == count)
        let created = browser.createDraft(in: library, undoManager: nil)
        #expect(created != nil)
        #expect(browser.item == .itemType("core.note"))
        #expect(!browser.isSearching)
        #expect(browser.selectedItems(in: library).map { library.body(of: $0.id)?.text } == [""])
        #expect(browser.selection == Set(created.map { [$0] } ?? []))
    }

    @Test func choosingAnotherTypeDoesNotSilentlyDiscardDraftText() {
        let browser = Browser()
        browser.startItemDraft(typeID: "aic.ticket.task")
        #expect(browser.itemDraft?.typeID == "aic.ticket.task")
        browser.itemDraft?.title = "Keep my title"
        browser.itemDraft?.body = "Keep my text"
        browser.isCreatingItem = false
        browser.startItemDraft(typeID: "core.note")
        #expect(browser.itemDraft?.typeID == "aic.ticket.task")
        #expect(browser.itemDraft?.title == "Keep my title")
        #expect(browser.itemDraft?.body == "Keep my text")
        #expect(browser.isCreatingItem)
    }

    @Test func choosingATypeReplacesAnUntouchedDraftInTheCurrentPlace() throws {
        let browser = Browser()
        browser.startItemDraft(typeID: "aic.ticket.task")
        let previous = try #require(browser.itemDraft)
        browser.sidebarItem = .collection(ItemID("parent"))
        browser.isCreatingItem = false

        browser.startItemDraft(typeID: "core.note")

        let current = try #require(browser.itemDraft)
        #expect(current !== previous)
        #expect(current.typeID == "core.note")
        #expect(current.parentID == ItemID("parent"))
        #expect(browser.isCreatingItem)
    }

    @Test(arguments: ["A title", " ", "\n"])
    func titleContentRequiresExplicitDiscard(text: String) throws {
        let browser = Browser()
        browser.startItemDraft(typeID: "aic.ticket.task")
        let previous = try #require(browser.itemDraft)
        previous.title = text

        browser.startItemDraft(typeID: "core.note")

        #expect(browser.itemDraft === previous)
        #expect(previous.title == text)
        #expect(previous.typeID == "aic.ticket.task")
        #expect(previous.hasText)
        #expect(browser.replaceItemDraft(previous, typeID: "core.note"))
        #expect(browser.itemDraft !== previous)
        #expect(browser.itemDraft?.typeID == "core.note")
        #expect(browser.itemDraft?.hasText == false)
    }

    @Test(arguments: ["Body text", " ", "\r\n"])
    func bodyContentRequiresExplicitDiscard(text: String) throws {
        let browser = Browser()
        browser.startItemDraft(typeID: "aic.ticket.task")
        let previous = try #require(browser.itemDraft)
        previous.body = text

        browser.startItemDraft(typeID: "core.note")

        #expect(browser.itemDraft === previous)
        #expect(previous.body == text)
        #expect(previous.typeID == "aic.ticket.task")
        #expect(previous.hasText)
    }

    @Test func anOldDiscardConfirmationCannotReplaceANewerDraft() throws {
        let browser = Browser()
        browser.startItemDraft(typeID: "aic.ticket.task")
        let previous = try #require(browser.itemDraft)
        #expect(browser.replaceItemDraft(previous, typeID: "core.note"))
        browser.itemDraft?.title = "Newer text"

        #expect(!browser.replaceItemDraft(previous, typeID: "aic.project"))
        #expect(browser.itemDraft?.title == "Newer text")
        #expect(browser.itemDraft?.typeID == "core.note")
    }

    @Test func submittedDraftCannotBeReplacedEvenWhenItHasNoText() throws {
        let (library, _, _, _) = makeFakeLibrary()
        library.holdsCreations = true
        let browser = Browser()
        browser.startItemDraft(typeID: "core.note")
        let previous = try #require(browser.itemDraft)
        let created = try #require(browser.createDraft(in: library, undoManager: nil))
        #expect(browser.isAwaitingCreation)

        browser.startItemDraft(typeID: "aic.ticket.task")

        #expect(browser.itemDraft === previous)
        #expect(previous.typeID == "core.note")
        #expect(!browser.replaceItemDraft(previous, typeID: "aic.ticket.task"))
        #expect(browser.creation?.id == created)
    }

    @Test(arguments: ["aic.project", "aic.ticket.task"])
    func preselectedDraftTypeValidatesItsInheritedParent(typeID: String) throws {
        let epic = Note(path: "Epics/Launch.md", text: "---\ntype: aic.epic\ntitle: Launch\n---\n", created: start)
        let library = NoteLibrary(notes: [epic])
        let browser = Browser()
        browser.sidebarItem = .collection(epic.id)
        browser.startItemDraft(typeID: typeID)
        let draft = try #require(browser.itemDraft)
        draft.title = "New work"
        draft.body = "Keep this text."
        draft.validateParent(in: library)
        let expectedParent = typeID == "aic.project" ? nil : epic.id
        #expect(draft.parentID == expectedParent)
        let createdID = try #require(browser.createDraft(in: library, undoManager: nil))
        let created = try #require(library.item(createdID))
        #expect(created.type.rawValue == typeID)
        #expect(created.parentID == expectedParent)
        #expect(library.body(of: createdID)?.text == "Keep this text.")
    }

    @Test func parentValidationWaitsForTheLibraryBeforeFittingARetainedDraft() throws {
        let parentID = ItemID.mint()
        let library = FakeItemLibrary(now: start)
        library.isLoaded = false
        let draft = NewItemDraft(place: .collection(parentID))
        draft.title = "Keep the title"
        draft.body = "Keep the text"

        draft.validateParent(in: library)
        #expect(draft.parentID == parentID)
        #expect(draft.fit(to: library) == nil)

        library.isLoaded = true
        let change = try #require(draft.fit(to: library))
        #expect(change.message.contains("parent"))
        #expect(draft.parentID == nil)
        #expect(draft.title == "Keep the title")
        #expect(draft.body == "Keep the text")
    }

    @Test(arguments: [SidebarItem.sources, .collections, .inbox, .source("test"), .collection(ItemID("parent"))])
    func listSearchIsAvailableOnlyWhereAnItemListExists(place: SidebarItem) {
        let browser = Browser()
        browser.sidebarItem = place
        let hasList = place != .sources && place != .collections
        #expect(browser.canSearchList == hasList)
        browser.startItemDraft()
        #expect(browser.canSearchList == hasList)
        browser.showSettings()
        #expect(!browser.canSearchList)
        browser.leaveSettings()
        #expect(browser.canSearchList == hasList)
    }

    @Test func newItemDraftRespectsTypeAndSurvivesNavigation() {
        let (library, _, _, _) = makeLibrary()
        let browser = Browser()
        browser.sidebarItem = .itemType("aic.ticket.feature")
        browser.startItemDraft()
        #expect(browser.itemDraft?.typeID == "aic.ticket.feature")
        browser.itemDraft?.title = "Draft feature"
        browser.itemDraft?.body = "Keep this content"
        browser.show(.inbox, in: library, order: NoteOrder())
        #expect(!browser.isCreatingItem)
        browser.startItemDraft()
        #expect(browser.itemDraft?.title == "Draft feature")
        #expect(browser.itemDraft?.body == "Keep this content")
        #expect(browser.itemDraft?.typeID == "aic.ticket.feature")
    }

    @Test func rejectedCreationKeepsDraftAndSuccessfulCreationIncludesContent() {
        let (library, _, _, _) = makeLibrary()
        let browser = Browser()
        browser.startItemDraft()
        browser.itemDraft?.title = "Not/a/title"
        browser.itemDraft?.body = "A draft body.\n"
        #expect(browser.createDraft(in: library, undoManager: nil) == nil)
        #expect(browser.isCreatingItem)
        #expect(browser.itemDraft?.body == "A draft body.\n")
        browser.itemDraft?.title = "A valid title"
        let note = browser.createDraft(in: library, undoManager: nil).flatMap { library.note($0) }
        #expect(note?.body == "A draft body.\n")
        #expect(note?.file.property("title") == "A valid title")
        #expect(browser.itemDraft == nil)
        #expect(!browser.isCreatingItem)
    }

    @Test func aTitleOnlyDraftStillCreatesAnEmptyFileNote() throws {
        let (library, _, _, _) = makeLibrary()
        let browser = Browser()
        browser.startItemDraft()
        browser.itemDraft?.title = "A title without text"

        let id = try #require(browser.createDraft(in: library, undoManager: nil))
        let note = try #require(library.note(id))
        #expect(note.title == "A title without text")
        #expect(note.body.isEmpty)
        #expect(library.failure == nil)
        #expect(browser.itemDraft == nil)
        #expect(!browser.isCreatingItem)
        #expect(browser.selection == [id])
    }

    @Test func untitledDraftNamesAreUniqueAndProjectsSupplyParents() {
        let existing = Note(path: "Notes/Untitled.md", text: "---\ntype: core.note\ntitle: Untitled\n---\n", created: start)
        let project = Note(path: "Projects/Area.md", text: "---\ntype: aic.project\ntitle: Area\n---\n", created: start)
        let library = NoteLibrary(notes: [existing, project])
        let browser = Browser()
        browser.sidebarItem = .collection(project.id)
        browser.startItemDraft()
        #expect(browser.itemDraft?.parentID == project.id)
        let created = browser.createDraft(in: library, undoManager: nil).flatMap { library.note($0) }
        #expect(created?.title == "Untitled 2")
        #expect(created?.file.property("child-of") == "[[Area]]")
    }

    @Test func aWhitespaceSearchIsNoSearch() {
        let browser = Browser()
        browser.searchText = "  \n"
        #expect(!browser.isSearching)
    }

    @Test func aRemovedFolderGivesWayToAllNotes() {
        let (library, _, _, favorite) = makeLibrary()
        let browser = Browser()
        browser.newFolder(in: library, order: NoteOrder(), undoManager: nil)
        guard case .folder(let id) = browser.item else { return #expect(Bool(false)) }
        #expect(browser.renamingFolder == id)
        library.deleteFolder(id)
        browser.folderRemoved(in: library, order: NoteOrder())
        #expect(browser.item == .allNotes)
        #expect(browser.renamingFolder == nil)
        #expect(browser.selection == [favorite.id])
    }

    @Test func favoritesLeadOnlyWhereTheyMeanSomething() {
        let (library, _, newer, _) = makeLibrary()
        let browser = Browser()
        browser.show(.allNotes, in: library, order: NoteOrder())
        #expect(browser.sections(in: library, order: NoteOrder(), now: start).first?.group == .favorites)
        browser.searchText = "e"
        #expect(browser.sections(in: library, order: NoteOrder(), now: start).first?.items.first?.id == newer.id)
    }

    @Test func aLibraryThatCannotPurgeIsNeverAskedToEraseWhatIsDeleted() {
        let (library, older, newer, _) = makeFakeLibrary()
        library.capabilities = []
        library.delete([older.id], undoManager: nil)
        Browser.delete([older.id, newer.id], in: library, undoManager: nil)
        #expect(library.item(newer.id)?.state == .trashed, "what is live still goes to Recently Deleted")
        #expect(library.item(older.id)?.state == .trashed)
        #expect(library.notesToPurge.isEmpty)
        library.capabilities = .purge
        Browser.delete([older.id], in: library, undoManager: nil)
        #expect(library.notesToPurge == [older.id])
    }

    @Test func dropsOnTheInboxAndFoldersNeedALibraryThatMoves() {
        let (library, _, _, _) = makeFakeLibrary()
        library.capabilities = []
        #expect(!Browser.canDrop(on: .inbox, in: library))
        #expect(!Browser.canDrop(on: .folder(work.id), in: library))
        #expect(!Browser.canDrop(on: .recentlyDeleted, in: library), "Recently Deleted is no longer a place to drop on")
        library.capabilities = .move
        #expect(Browser.canDrop(on: .inbox, in: library))
        #expect(Browser.canDrop(on: .folder(work.id), in: library))
        for place: SidebarItem in [.allNotes, .favorites, .files, .itemType("core.note")] {
            #expect(!Browser.canDrop(on: place, in: library))
        }
    }

    @Test func aNewFolderIsMadeOnlyWhereTheLibraryEditsFolders() {
        let (library, _, _, _) = makeFakeLibrary()
        library.capabilities = []
        let browser = Browser()
        browser.newFolder(in: library, order: NoteOrder(), undoManager: nil)
        #expect(library.folders.count == 1)
        #expect(browser.renamingFolder == nil)
        library.capabilities = .folders
        browser.newFolder(in: library, order: NoteOrder(), undoManager: nil)
        #expect(library.folders.count == 2)
        #expect(browser.renamingFolder == library.folders.last?.id)
    }

    @Test func deletingMovesLiveNotesAwayAndAsksBeforeErasingDeletedOnes() {
        let (library, older, _, _) = makeLibrary()
        Browser.delete([older.id], in: library, undoManager: nil)
        #expect(library.note(older.id)?.isDeleted == true)
        Browser.delete([older.id], in: library, undoManager: nil)
        #expect(library.note(older.id) != nil)
        #expect(library.notesToPurge == [older.id])
    }

    @Test func aNewItemDraftAsksForThePage() {
        let browser = Browser()
        browser.startItemDraft()
        #expect(browser.isCreatingItem)
        #expect(browser.itemDraft != nil)
        #expect(browser.focusRequest == .page)
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
        let (library, _, _, _) = makeLibrary()
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
        let snapshot = Browser.Snapshot(place: .folder(.mint()), selection: [.mint()])
        let browser = Browser()
        browser.restore(snapshot, in: library, order: NoteOrder())
        #expect(browser.item == .allNotes)
        #expect(browser.selection == [favorite.id])
    }

    @Test func snapshotsSurviveEncodingAsIdentifiers() throws {
        let folder = ItemID("0198f2c4-7d1e-7a00-8000-000000000001")
        let note = ItemID("0198f2c4-7d1e-7a00-8000-000000000002")
        let snapshot = Browser.Snapshot(place: .folder(folder), selection: [note])
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(Browser.Snapshot.self, from: data) == snapshot)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["selection"] as? [String] == [note.rawValue], "an identifier is kept as its own string")
    }

    @Test func aRestoredWindowFindsItsFolderAndNotesByIdentifierAfterTheyAreRenamed() {
        let (library, older, _, _) = makeLibrary()
        let work = library.folders[0]
        let saved = Browser()
        saved.show(.folder(work.id), in: library, order: NoteOrder())
        saved.selection = [older.id]
        let snapshot = saved.snapshot()
        library.rename(work.id, to: "Office")
        library.move([older.id], to: work.id)
        let restored = Browser()
        restored.restore(snapshot, in: library, order: NoteOrder())
        #expect(restored.item == .folder(work.id))
        #expect(restored.selection == [older.id])
    }

    @Test(arguments: [
        Data(#"{"sidebarItem":{"folder":{"_0":"Work"}},"selection":["Older.md"]}"#.utf8),
        Data("not a snapshot".utf8),
        nil,
    ])
    func aWindowKeptByPathBeforeIdentifiersOrNotAtAllOpensAtItsDefault(saved: Data?) {
        let (library, _, _, favorite) = makeLibrary()
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
        let (library, _, _, _) = makeLibrary()
        let browser = Browser()
        browser.show(.allNotes, in: library, order: NoteOrder())
        let sections = browser.sections(in: library, order: NoteOrder(sort: .dateEdited, groupsByDate: false), now: start)
        #expect(sections.map(\.group) == [.favorites, nil])
    }
}
