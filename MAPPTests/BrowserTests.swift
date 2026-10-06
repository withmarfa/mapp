import Foundation
import Testing
@testable import MAPP

struct BrowserTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let work = Folder(name: "Work")

    func makeLibrary() -> (NoteLibrary, older: Note, newer: Note, favorite: Note) {
        let older = Note(body: "# Older", created: start - 120)
        let newer = Note(body: "# Newer", created: start - 60)
        let favorite = Note(body: "# Favorite", created: start - 3600, folderID: work.id, isFavorite: true)
        let library = NoteLibrary(notes: [older, newer, favorite], folders: [work], now: { start })
        return (library, older, newer, favorite)
    }

    @Test func draftDoesNotExposePreviouslySelectedNoteToCommands() {
        let (library, _, newer, _) = makeLibrary()
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
        let project = try #require(library.createItem(typeID: "aic.project", title: "Project", in: .allNotes))
        let browser = Browser()
        browser.sidebarItem = .project(project.id)
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
        let (library, _, newer, favorite) = makeLibrary()
        let browser = Browser()
        browser.searchText = "Older"
        browser.show(.allNotes, in: library, order: NoteOrder())
        #expect(browser.searchText.isEmpty)
        #expect(browser.selection == [favorite.id])
        browser.show(.inbox, in: library, order: NoteOrder())
        #expect(browser.selection == [newer.id])
    }

    @Test(arguments: [SidebarItem.recentlyDeleted, .marfaTypes])
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

    @Test func untitledDraftNamesAreUniqueAndProjectsSupplyParents() {
        let existing = Note(path: "Notes/Untitled.md", text: "---\ntype: core.note\ntitle: Untitled\n---\n", created: start)
        let project = Note(path: "Projects/Area.md", text: "---\ntype: aic.project\ntitle: Area\n---\n", created: start)
        let library = NoteLibrary(notes: [existing, project])
        let browser = Browser()
        browser.sidebarItem = .project(project.id)
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
        let (library, older, _, _) = makeLibrary()
        let saved = Browser()
        saved.show(.inbox, in: library, order: NoteOrder())
        saved.selection = [older.id]
        let restored = Browser()
        restored.restore(saved.snapshot(), in: library, order: NoteOrder())
        #expect(restored.item == .inbox)
        #expect(restored.selection == [older.id])
    }

    @Test func aRestoredWindowShowsMarfaTypesAgain() {
        let (library, _, _, _) = makeLibrary()
        let saved = Browser()
        saved.show(.marfaTypes, in: library, order: NoteOrder())
        let restored = Browser()
        restored.restore(saved.snapshot(), in: library, order: NoteOrder())
        #expect(restored.showsTypes)
    }

    @Test func aRestoredWindowDropsWhatNoLongerExists() {
        let (library, _, _, favorite) = makeLibrary()
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
