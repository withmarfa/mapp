import Foundation
import Testing
@testable import MAPP

/// A new item that a server's library shows only when its source says so, a window carried to another library,
/// and a file fetched rather than at hand.
@Suite(.hangLimit)
struct LibraryChangeTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func aRefusedItemEndsTheWaitAndOpensNothing() async throws {
        let library = FakeItemLibrary(now: start)
        library.holdsCreations = true
        let browser = Browser()
        let id = try #require(await browser.quickAdded("Untitled", in: library))
        library.syncReport = SyncReport(
            problems: [
                SyncProblemEntry(
                    id: .write("w"), itemID: id, kind: .refused, change: .create, reason: SyncProblem(code: "refused"),
                    content: SyncContent(title: "Untitled"), actions: [.discard])
            ], queueRead: true)

        browser.finishNewItem(in: library)
        #expect(browser.newItem == nil)
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

        browser.adopt(new)
        #expect(browser.selection.isEmpty, "the new library has none of the old selection's items")
        #expect(browser.sidebarItem == .allNotes)
        #expect(browser.searchText == "")
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

    @Test func aFileIsFetchedWhenAskedFor() async {
        let library = FakeItemLibrary(now: start)
        let id = ItemID.mint()
        let url = URL(filePath: "/tmp/fetched.pdf")
        library.files[id] = url
        #expect(await ItemFileResolution.fetch(id, in: library) == .ready(url))
    }

    @Test func anItemWithNoFileSaysSo() async {
        let library = FakeItemLibrary(now: start)
        #expect(await ItemFileResolution.fetch(.mint(), in: library) == .unavailable)
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
        library.files = [a: urlA, b: urlB]
        library.fetchDelay[a] = .milliseconds(300)
        let loader = ItemFileLoader()

        let late = Task { await loader.load(a, in: library) }
        #expect(await eventually { library.fetches == 1 }, "the earlier load has asked for its file")
        #expect(await loader.load(b, in: library) == .ready(urlB))
        #expect(await late.value == nil, "the earlier load gave way to the later one")
        #expect(loader.resolution(of: b) == .ready(urlB))
        #expect(loader.resolution(of: a) == nil)
        #expect(loader.shown?.id == b)
    }

    @Test func sharingUsesTheFileFetchedToShow() {
        let browser = Browser()
        let id = ItemID.mint()
        let fetched = URL(filePath: "/tmp/fetched.pdf")
        #expect(browser.fileURL(of: id) == nil)

        browser.fileFetched(id, at: fetched)
        #expect(browser.fileURL(of: id) == fetched)
        #expect(browser.fileURL(of: .mint()) == nil, "another item's file is not this one's")

        browser.fileFetched(id, at: nil)
        #expect(browser.fileURL(of: id) == nil)
    }
}
