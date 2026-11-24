import Foundation
import Testing
import WebKit
@testable import MarfaMac

/// The page lost what the person typed last, or reported an edit the app cannot place: the person is told, and an edit
/// the app holds goes back to them. Real WebKit cannot be made to crash or fail a file load here, so these call the
/// controller's own navigation delegate methods, as WebKit does. A page with no window draws no frames, so a page
/// that comes back never reports that it showed the item unless a test posts `painted` for it.
extension EditorTests {
    /// Whether a flush goes ahead: one `leaving` is a quit, a window close or a library change.
    private static func flushed(_ page: Page, leaving: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            page.editor.flush(leaving: leaving) { continuation.resume(returning: $0) }
        }
    }

    private static func post(_ message: String, to page: Page) async throws {
        try await page.run("window.webkit.messageHandlers.host.postMessage(\(message))")
    }

    private static func answerAll(_ notices: Notices) {
        while let first = notices.waiting.first { notices.answered(first.id) }
    }

    @Test func aPageWhoseProcessEndsTellsThePersonAndHoldsLeavingUntilItIsBack() async throws {
        let page = try await Page()
        try await page.load("Original\n")
        page.editor.webViewWebContentProcessDidTerminate(page.editor.webView)
        #expect(page.library.notices.waiting.count == 1)
        #expect(await Self.flushed(page, leaving: true) == false)
        #expect(page.library.notices.waiting.count == 1, "told once")
        try await page.wait { page.editor.isReady }
        #expect(await Self.flushed(page, leaving: true), "the item is back on the page, so the person can check it and go")
    }

    @Test func aFlushUnderWayWhenThePageProcessEndsFails() async throws {
        let page = try await Page()
        try await page.load("Original\n")
        page.editor.flushLimit = waitLimit
        try await page.run("window.editor.flush = () => ({ commandError: 'composition', message: 'Composing' })")
        var kept: Bool?
        page.editor.flush(leaving: true) { kept = $0 }
        page.editor.webViewWebContentProcessDidTerminate(page.editor.webView)
        try await page.wait { kept != nil }
        #expect(kept == false)
        #expect(page.library.notices.waiting.count == 1)
    }

    /// A page that ends again on its way back cannot come back, so it holds leaving only until the person has answered.
    @Test func aPageThatCannotComeBackHoldsLeavingUntilThePersonAnswers() async throws {
        let page = try await Page()
        try await page.load("Original\n")
        page.editor.webViewWebContentProcessDidTerminate(page.editor.webView)
        page.editor.webViewWebContentProcessDidTerminate(page.editor.webView)
        #expect(await Self.flushed(page, leaving: true) == false)
        Self.answerAll(page.library.notices)
        #expect(await Self.flushed(page, leaving: true))
    }

    /// A page that ends every time it shows the item would otherwise reload, and tell the person, for ever.
    @Test func aPageThatEndsAgainBeforeItShowsTheItemIsNotLoadedAgain() async throws {
        let page = try await Page()
        try await page.load("Original\n")
        let notices = page.library.notices
        page.editor.webViewWebContentProcessDidTerminate(page.editor.webView)
        try await page.wait { page.editor.isReady }
        let reload = page.editor.pageNavigation
        page.editor.webViewWebContentProcessDidTerminate(page.editor.webView)
        page.editor.webViewWebContentProcessDidTerminate(page.editor.webView)
        #expect(page.editor.pageNavigation === reload, "not loaded again")
        #expect(notices.waiting.count == 2, "told it is coming back, then that it cannot")
        Self.answerAll(notices)
        #expect(await Self.flushed(page, leaving: true))
    }

    @Test func aPageThatShowedTheItemAgainComesBackFromAnotherEnd() async throws {
        let page = try await Page()
        try await page.load("Original\n")
        page.editor.webViewWebContentProcessDidTerminate(page.editor.webView)
        try await page.wait { page.editor.isReady }
        try await Self.post("{ type: 'painted', generation: \(page.editor.generation) }", to: page)
        try await page.wait { page.editor.pageLoss == nil }
        let reload = page.editor.pageNavigation
        page.editor.webViewWebContentProcessDidTerminate(page.editor.webView)
        #expect(page.editor.pageNavigation !== reload)
        #expect(page.editor.pageLoss?.comingBack == true)
        try await page.wait { page.editor.isReady }
    }

    @Test func aReloadThatIsNotReadyInTimeCountsAsUnableToComeBack() async throws {
        let page = try await Page()
        try await page.load("Original\n")
        let notices = page.library.notices
        page.editor.reloadLimit = .milliseconds(10)
        page.editor.webViewWebContentProcessDidTerminate(page.editor.webView)
        try await page.wait { notices.waiting.count == 2 }
        #expect(page.editor.pageLoss?.comingBack == false, "the person is told to close the window and open the item again")
        Self.answerAll(notices)
        #expect(await Self.flushed(page, leaving: true))
    }

    /// Choosing another item stays in the window, so it waits for no answer: what was lost is already told.
    @Test func anItemChosenWhileThePageComesBackShowsOnceItIsBack() async throws {
        let library = FakeItemLibrary()
        let first = library.add("First\n")
        let second = library.add("Second\n")
        let page = try await Page(library: library)
        try await page.show(first.id)
        page.editor.webViewWebContentProcessDidTerminate(page.editor.webView)
        page.editor.select(try #require(library.item(second.id)))
        try await page.wait { page.editor.isReady }
        #expect(page.editor.pageItemID == second.id)
        #expect(try await page.shownText(until: "Second") == "Second")
    }

    @Test func anItemChosenWhileAHandOverWaitsWhenThePageEndsShowsOnceItIsBack() async throws {
        let library = FakeItemLibrary()
        let first = library.add("First\n")
        let second = library.add("Second\n")
        let page = try await Page(library: library)
        try await page.show(first.id)
        page.editor.flushLimit = waitLimit
        try await page.run("window.editor.flush = () => ({ commandError: 'composition', message: 'Composing' })")
        page.editor.select(try #require(library.item(second.id)))
        page.editor.webViewWebContentProcessDidTerminate(page.editor.webView)
        try await page.wait { page.editor.pageItemID == second.id && page.editor.isReady }
        #expect(try await page.shownText(until: "Second") == "Second")
    }

    @Test func anItemLeftWhileThePageComesBackIsLeft() async throws {
        let page = try await Page()
        try await page.load("Original\n")
        page.editor.webViewWebContentProcessDidTerminate(page.editor.webView)
        page.editor.close()
        try await page.wait { page.editor.isReady }
        #expect(page.editor.pageItemID == nil)
    }

    /// The notice keeps the words it was told with, so it is still found when its item is renamed or goes.
    @Test func aWaitingLossNoticeIsFoundAfterItsItemGoes() async throws {
        let page = try await Page()
        try await page.load("Original\n")
        let id = try #require(page.editor.pageItemID)
        page.editor.webViewWebContentProcessDidTerminate(page.editor.webView)
        page.library.items.removeAll { $0.id == id }
        #expect(await Self.flushed(page, leaving: true) == false)
        #expect(page.library.notices.waiting.count == 1, "told once")
    }

    @Test func aPageThatFailsToLoadAfterItWasReadyTellsThePersonAndHoldsLeaving() async throws {
        let page = try await Page()
        try await page.load("Original\n")
        page.editor.webView(page.editor.webView, didFailProvisionalNavigation: page.editor.pageNavigation, withError: URLError(.cannotOpenFile))
        #expect(page.library.notices.waiting.count == 1)
        #expect(await Self.flushed(page, leaving: true) == false)
    }

    /// WebKit can fail the page's own load for its process ending before it says the process ended.
    @Test func aLoadFailureFromTheProcessEndingIsLeftToTheProcessEnding() async throws {
        let page = try await Page()
        try await page.load("Original\n")
        let ended = NSError(domain: WKError.errorDomain, code: WKError.webContentProcessTerminated.rawValue)
        page.editor.webView(page.editor.webView, didFail: page.editor.pageNavigation, withError: ended)
        #expect(page.library.notices.waiting.isEmpty)
        page.editor.webViewWebContentProcessDidTerminate(page.editor.webView)
        try await page.wait { page.editor.isReady }
    }

    @Test func anEditForALoadNoLongerKeptIsHandedBack() async throws {
        let library = FakeItemLibrary()
        let note = library.add("Original\n")
        let page = try await Page(library: library)
        try await page.show(note.id)
        let typedIn = page.editor.generation
        for change in 1...9 {
            library.updateBody(of: note.id, to: "Elsewhere \(change)\n")
            page.editor.itemChanged(try #require(library.item(note.id)))
        }
        try await Self.post("{ type: 'changed', markdown: 'Typed\\n', generation: \(typedIn) }", to: page)
        try await page.wait { !library.notices.waiting.isEmpty }
        #expect(library.notices.waiting.map(\.text) == ["Typed\n"])
        #expect(!page.changes.contains("Typed\n"))
    }

    @Test func anEditThatDoesNotDecodeIsHandedBackWhereItsTextIsReadable() async throws {
        let page = try await Page()
        try await page.load("Original\n")
        try await Self.post("{ type: 'changed', generation: \(page.editor.generation) }", to: page)
        try await Self.post("{ type: 'changed', markdown: 'Typed\\n', generation: 'one' }", to: page)
        try await page.wait { !page.library.notices.waiting.isEmpty }
        #expect(page.library.notices.waiting.map(\.text) == ["Typed\n"], "the message with no text tells nothing")
    }
}
