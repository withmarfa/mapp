import Foundation
import Testing
import WebKit
@testable import MarfaMac

/// The page lost what the person typed last, or reported an edit the app cannot place: the person is told, and an edit
/// the app holds goes back to them. Real WebKit cannot be made to crash or fail a file load here, so these call the
/// controller's own navigation delegate methods, as WebKit does.
extension EditorTests {
    private static func flushed(_ page: Page) async -> Bool {
        await withCheckedContinuation { continuation in page.editor.flush { continuation.resume(returning: $0) } }
    }

    private static func post(_ message: String, to page: Page) async throws {
        try await page.run("window.webkit.messageHandlers.host.postMessage(\(message))")
    }

    @Test func aPageWhoseProcessEndsTellsThePersonAndHoldsLeavingUntilItIsBack() async throws {
        let page = try await Page()
        try await page.load("Original\n")
        page.editor.webViewWebContentProcessDidTerminate(page.editor.webView)
        #expect(page.library.notices.waiting.count == 1)
        #expect(await Self.flushed(page) == false)
        #expect(page.library.notices.waiting.count == 1, "told once")
        try await page.wait { page.editor.isReady }
        #expect(await Self.flushed(page), "the item is back on the page, so the person can check it and go")
    }

    @Test func aFlushUnderWayWhenThePageProcessEndsFails() async throws {
        let page = try await Page()
        try await page.load("Original\n")
        page.editor.flushLimit = waitLimit
        try await page.run("window.editor.flush = () => ({ commandError: 'composition', message: 'Composing' })")
        var kept: Bool?
        page.editor.flush { kept = $0 }
        page.editor.webViewWebContentProcessDidTerminate(page.editor.webView)
        try await page.wait { kept != nil }
        #expect(kept == false)
        #expect(page.library.notices.waiting.count == 1)
    }

    /// A page that ends again on its way back cannot come back, so it holds leaving only until the person has answered.
    @Test func aPageThatCannotComeBackHoldsLeavingUntilThePersonAnswers() async throws {
        let page = try await Page()
        try await page.load("Original\n")
        let notices = page.library.notices
        page.editor.webViewWebContentProcessDidTerminate(page.editor.webView)
        page.editor.webViewWebContentProcessDidTerminate(page.editor.webView)
        var kept: [Bool] = []
        page.editor.flush { kept.append($0) }
        while let first = notices.waiting.first { notices.answered(first.id) }
        page.editor.flush { kept.append($0) }
        #expect(kept == [false, true])
    }

    @Test func aPageThatFailsToLoadAfterItWasReadyTellsThePersonAndHoldsLeaving() async throws {
        let page = try await Page()
        try await page.load("Original\n")
        page.editor.webView(page.editor.webView, didFailProvisionalNavigation: page.editor.pageNavigation, withError: URLError(.cannotOpenFile))
        #expect(page.library.notices.waiting.count == 1)
        #expect(await Self.flushed(page) == false)
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
