import Foundation
import Testing
@testable import MAPP

/// A new item that a server's library shows only when its source says so, a window carried to another library,
/// and a file fetched rather than at hand.
struct DraftHandoverTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func browser(typing title: String, in library: FakeItemLibrary, parent: ItemID? = nil) -> Browser {
        let browser = Browser()
        browser.startItemDraft()
        browser.itemDraft?.title = title
        browser.itemDraft?.body = "Book the hotel"
        browser.itemDraft?.parentID = parent
        return browser
    }

    @Test func aLibraryThatHoldsTheItemAtOnceHandsOverAtOnce() throws {
        let library = FakeItemLibrary(now: start)
        let browser = browser(typing: "Trip", in: library)
        let id = try #require(browser.createDraft(in: library, undoManager: nil))
        #expect(browser.selection == [id])
        #expect(browser.itemDraft == nil)
        #expect(!browser.isCreatingItem)
        #expect(!browser.isAwaitingCreation)
        #expect(browser.focusRequest == .page)
    }

    @Test func aLibraryThatShowsTheItemLaterKeepsTheDraftOnThePageUntilThen() throws {
        let library = FakeItemLibrary(now: start)
        library.holdsCreations = true
        let browser = browser(typing: "Trip", in: library)
        let id = try #require(browser.createDraft(in: library, undoManager: nil))

        #expect(browser.isAwaitingCreation)
        #expect(browser.isCreatingItem, "the page shows what was typed until the item can be shown")
        #expect(browser.itemDraft?.title == "Trip")
        #expect(browser.itemDraft?.body == "Book the hotel")
        #expect(browser.selection.isEmpty)
        #expect(library.item(id) == nil)

        library.deliverCreated()
        browser.finishCreation(in: library)
        #expect(browser.selection == [id])
        #expect(browser.itemDraft == nil)
        #expect(!browser.isCreatingItem)
        #expect(!browser.isAwaitingCreation)
        #expect(browser.focusRequest == .page)
        #expect(library.item(id)?.title == "Trip")
    }

    @Test func startingWritingAgainWhileWaitingMakesNothingMore() throws {
        let library = FakeItemLibrary(now: start)
        library.holdsCreations = true
        let browser = browser(typing: "Trip", in: library)
        let first = try #require(browser.createDraft(in: library, undoManager: nil))
        let second = try #require(browser.createDraft(in: library, undoManager: nil))
        #expect(first == second)
        library.deliverCreated()
        #expect(library.items.count == 1, "a second Return made no second item")
    }

    @Test func handingOverBeforeTheItemArrivesChangesNothing() throws {
        let library = FakeItemLibrary(now: start)
        library.holdsCreations = true
        let browser = browser(typing: "Trip", in: library)
        _ = try #require(browser.createDraft(in: library, undoManager: nil))
        browser.finishCreation(in: library)
        #expect(browser.isAwaitingCreation)
        #expect(browser.isCreatingItem)
    }

    @Test func aRefusedItemEndsTheWaitAndKeepsTheDraftToEdit() throws {
        let library = FakeItemLibrary(now: start)
        library.holdsCreations = true
        let browser = browser(typing: "Trip", in: library)
        let id = try #require(browser.createDraft(in: library, undoManager: nil))
        library.syncReport = SyncReport(
            problems: [
                SyncProblemEntry(
                    id: .write("w"), itemID: id, kind: .refused, change: .create, reason: SyncProblem(code: "refused"),
                    content: SyncContent(title: "Trip"), actions: [.discard])
            ], queueRead: true)

        browser.finishCreation(in: library)
        #expect(!browser.isAwaitingCreation)
        #expect(browser.isCreatingItem)
        #expect(browser.itemDraft?.title == "Trip", "the text is still on the page, and in the refused change")
        #expect(browser.selection.isEmpty)
    }

    @Test func aCreateTheLibraryRefusesAtOnceKeepsTheDraftToEdit() {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("Trip", modified: start)], now: start)
        let browser = browser(typing: "Trip", in: library)
        #expect(browser.createDraft(in: library, undoManager: nil) == nil, "the title is taken")
        #expect(browser.isCreatingItem)
        #expect(browser.itemDraft?.title == "Trip")
        #expect(!browser.isAwaitingCreation)
    }

    // MARK: Carrying a window to another library

    @Test func aWindowCarriedToAnotherLibraryStartsAfreshAndKeepsOnlyTheDraft() throws {
        let old = FakeItemLibrary(items: [FakeItemLibrary.note("Old", modified: start)], now: start)
        let new = FakeItemLibrary(now: start)
        let parent = old.items[0].id
        let browser = browser(typing: "Trip", in: old, parent: parent)
        browser.adopt(old)
        browser.selection = [parent]
        browser.sidebarItem = .favorites
        browser.searchText = "hotel"
        browser.renamingNote = parent

        browser.adopt(new)
        #expect(browser.selection.isEmpty, "the new library has none of the old selection's items")
        #expect(browser.sidebarItem == .allNotes)
        #expect(browser.searchText == "")
        #expect(browser.renamingNote == nil)
        #expect(browser.isCreatingItem)
        #expect(browser.itemDraft?.title == "Trip")
        #expect(browser.itemDraft?.body == "Book the hotel")
        #expect(browser.itemDraft?.parentID == nil, "a parent the new library does not have is dropped, not kept dangling")
    }

    @Test func theFirstLibraryAWindowIsShownLeavesItAsItWas() {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("A", modified: start)], now: start)
        let browser = Browser()
        browser.selection = [library.items[0].id]
        browser.sidebarItem = .favorites
        browser.adopt(library)
        browser.adopt(library)
        #expect(browser.selection == [library.items[0].id])
        #expect(browser.sidebarItem == .favorites)
    }

    @Test func aDraftAlreadySentIsNotCarriedBecauseItsTextIsInTheLibrarysOwnQueue() throws {
        let old = FakeItemLibrary(now: start)
        old.holdsCreations = true
        let browser = browser(typing: "Trip", in: old)
        browser.adopt(old)
        _ = try #require(browser.createDraft(in: old, undoManager: nil))

        browser.adopt(FakeItemLibrary(now: start))
        #expect(!browser.isAwaitingCreation)
        #expect(browser.itemDraft == nil, "carrying it would make the item twice")
        #expect(!browser.isCreatingItem)
    }

    @Test func aDraftOfAKindTheNewLibraryLacksBecomesANote() {
        let old = FakeItemLibrary(now: start)
        let new = FakeItemLibrary(now: start)
        new.catalogue = Catalogue()
        let browser = browser(typing: "Trip", in: old)
        browser.itemDraft?.typeID = "aic.task"
        browser.adopt(old)
        browser.adopt(new)
        #expect(browser.itemDraft?.typeID == "core.note")
    }

    // MARK: Files

    @Test func aFileAtHandIsShownAtOnce() throws {
        let library = FakeItemLibrary(now: start)
        let id = ItemID.mint()
        let url = URL(filePath: "/tmp/at-hand.pdf")
        library.files[id] = url
        #expect(ItemFileResolution.atHand(id, in: library) == .ready(url))
    }

    @Test func aFileFetchedLaterIsAskedForWhereItIsNotAtHand() async {
        let library = FakeItemLibrary(now: start)
        let id = ItemID.mint()
        let url = URL(filePath: "/tmp/fetched.pdf")
        library.fetchable[id] = url
        #expect(ItemFileResolution.atHand(id, in: library) == nil)
        #expect(await ItemFileResolution.fetch(id, in: library) == .ready(url))
    }

    @Test func aLibraryWithoutFilesSaysSoWithoutBreakingAnything() async {
        let library = FakeItemLibrary(now: start)
        let id = ItemID.mint()
        #expect(ItemFileResolution.atHand(id, in: library) == nil)
        #expect(await ItemFileResolution.fetch(id, in: library) == .unavailable)
        #expect(library.folderURL == nil)
        #expect(library.path(of: id) == nil)
    }

    @Test func aFileThatCannotBeFetchedIsAFailureNotAnAbsence() async {
        let library = FakeItemLibrary(now: start)
        library.fetchFails = true
        #expect(await ItemFileResolution.fetch(.mint(), in: library) == .failed)
    }

    @Test func sharingUsesTheFileAtHandOrTheOneFetchedToShow() {
        let library = FakeItemLibrary(now: start)
        let browser = Browser()
        let id = ItemID.mint()
        let fetched = URL(filePath: "/tmp/fetched.pdf")
        #expect(browser.fileURL(of: id, in: library) == nil)

        browser.fileFetched(id, at: fetched)
        #expect(browser.fileURL(of: id, in: library) == fetched)
        #expect(browser.fileURL(of: .mint(), in: library) == nil, "another item's file is not this one's")

        let atHand = URL(filePath: "/tmp/at-hand.pdf")
        library.files[id] = atHand
        #expect(browser.fileURL(of: id, in: library) == atHand)

        browser.fileFetched(id, at: nil)
        library.files = [:]
        #expect(browser.fileURL(of: id, in: library) == nil)
    }
}
