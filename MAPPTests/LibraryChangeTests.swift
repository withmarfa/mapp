import Foundation
import Testing
@testable import MAPP

/// A new item that a server's library shows only when its source says so, a window carried to another library,
/// and a file fetched rather than at hand.
struct LibraryChangeTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func aLibraryThatHoldsTheItemAtOnceOpensItAtOnce() throws {
        let library = FakeItemLibrary(now: start)
        let browser = Browser()
        let id = try #require(browser.startNewItem(in: library, undoManager: nil))
        #expect(browser.selection == [id])
        #expect(!browser.isAwaitingNewItem)
        #expect(browser.focusRequest == .title)
        #expect(library.item(id)?.title == String(localized: "Untitled"))
        #expect(library.bodies[id] == "", "a note that needs a body is sent an empty one")
    }

    @Test func aLibraryThatShowsTheItemLaterOpensItWhenItArrives() throws {
        let library = FakeItemLibrary(now: start)
        library.holdsCreations = true
        let browser = Browser()
        let id = try #require(browser.startNewItem(in: library, undoManager: nil))

        #expect(browser.isAwaitingNewItem)
        #expect(browser.selection.isEmpty)
        #expect(library.item(id) == nil)

        library.deliverCreated()
        browser.finishNewItem(in: library)
        #expect(browser.selection == [id])
        #expect(!browser.isAwaitingNewItem)
        #expect(browser.focusRequest == .title)
    }

    @Test func handingOverBeforeTheItemArrivesChangesNothing() throws {
        let library = FakeItemLibrary(now: start)
        library.holdsCreations = true
        let browser = Browser()
        _ = try #require(browser.startNewItem(in: library, undoManager: nil))
        browser.finishNewItem(in: library)
        #expect(browser.isAwaitingNewItem)
        #expect(browser.selection.isEmpty)
    }

    @Test func anItemStillAwaitedIsNotEmptiedAwayBeforeItIsShown() throws {
        let library = FakeItemLibrary(now: start)
        library.holdsCreations = true
        let browser = Browser()
        let id = try #require(browser.startNewItem(in: library, undoManager: nil))
        #expect(!browser.leaveNewItem(id, closing: true, undoManager: nil), "nothing is known of it yet")
        #expect(browser.isAwaitingNewItem)
    }

    @Test func aRefusedItemEndsTheWaitAndOpensNothing() throws {
        let library = FakeItemLibrary(now: start)
        library.holdsCreations = true
        let browser = Browser()
        let id = try #require(browser.startNewItem(in: library, undoManager: nil))
        library.syncReport = SyncReport(
            problems: [
                SyncProblemEntry(
                    id: .write("w"), itemID: id, kind: .refused, change: .create, reason: SyncProblem(code: "refused"),
                    content: SyncContent(title: "Untitled"), actions: [.discard])
            ], queueRead: true)

        browser.finishNewItem(in: library)
        #expect(!browser.isAwaitingNewItem)
        #expect(browser.selection.isEmpty)
    }

    // MARK: Carrying a window to another library

    @Test func aWindowCarriedToAnotherLibraryStartsAfresh() throws {
        let old = FakeItemLibrary(items: [FakeItemLibrary.note("Old", modified: start)], now: start)
        let new = FakeItemLibrary(now: start)
        let browser = Browser()
        browser.adopt(old)
        browser.selection = [old.items[0].id]
        browser.sidebarItem = .favorites
        browser.searchText = "hotel"
        browser.renamingNote = old.items[0].id

        browser.adopt(new)
        #expect(browser.selection.isEmpty, "the new library has none of the old selection's items")
        #expect(browser.sidebarItem == .allNotes)
        #expect(browser.searchText == "")
        #expect(browser.renamingNote == nil)
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

    /// A new item is followed only in the library it was made in, which the window leaves with the page's last
    /// hand-over, so the next library is never asked about it.
    @Test func aNewItemIsNotFollowedIntoTheNextLibrary() throws {
        let old = FakeItemLibrary(now: start)
        let browser = Browser()
        browser.adopt(old)
        let id = try #require(browser.startNewItem(in: old, undoManager: nil))
        #expect(browser.newItems[id] != nil)

        browser.adopt(FakeItemLibrary(now: start))
        #expect(browser.newItems.isEmpty)
        #expect(!browser.isAwaitingNewItem)
    }

    /// The window's undo acts on the library it was registered with, so it goes when the window shows another.
    @Test func aWindowCarriedToAnotherLibraryForgetsItsUndo() {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        let browser = Browser()
        let old = FakeItemLibrary(now: start)
        browser.adopt(old, undoManager: undoManager)
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: old) { _ in }
        undoManager.endUndoGrouping()
        browser.adopt(old, undoManager: undoManager)
        #expect(undoManager.canUndo, "the same library keeps its undo")

        browser.adopt(FakeItemLibrary(now: start), undoManager: undoManager)
        #expect(!undoManager.canUndo)
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

    /// A fetch still running for one item, as from Try Again, never shows its file under the next item.
    @Test func aLateFileForAnEarlierItemIsNeverShownUnderTheNext() async {
        let library = FakeItemLibrary(now: start)
        let a = ItemID.mint(), b = ItemID.mint()
        let urlA = URL(filePath: "/tmp/a.pdf"), urlB = URL(filePath: "/tmp/b.pdf")
        library.fetchable = [a: urlA, b: urlB]
        library.fetchDelay[a] = .milliseconds(300)
        let loader = ItemFileLoader()

        let late = Task { await loader.load(a, in: library) }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await loader.load(b, in: library) == .ready(urlB))
        #expect(await late.value == nil, "the earlier load gave way to the later one")
        #expect(loader.resolution(of: b) == .ready(urlB))
        #expect(loader.resolution(of: a) == nil)
        #expect(loader.shown?.id == b)
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
