import AppKit
import Foundation
import Testing
import WebKit
@testable import MAPP

/// Closing a window, quitting or changing library while a selection hands the last note over, or while the page
/// leaves its note: the flush that asks for it waits for the hand-over, then hands over whatever is on the page.
extension EditorTests {
    /// A page holding `typed` as the unreported edit of the note on it now, which only a flush brings in. While
    /// `window.held` is true it refuses every flush as a page in the middle of a composition does.
    private static func holdingAnEdit(_ typed: String, in page: Page) async throws -> Int {
        let leaving = page.editor.generation
        try await page.run("""
            window.held = false
            window.asked = []
            const flush = window.editor.flush.bind(window.editor)
            window.editor.flush = generation => {
                if (window.held) return { commandError: 'composition', message: 'Text composition is in progress' }
                window.asked.push(generation)
                return generation === \(leaving) ? \(String(reflecting: typed)) : flush(generation)
            }
            """)
        return leaving
    }

    private static func savingEdits(of page: Page) {
        page.editor.onChange = { [library = page.library] id, text, read in library.updateBody(of: id, to: text, readAt: read) }
    }

    @Test func closingAsASelectionHandsTheLastNoteOverSavesItAndGoesAhead() async throws {
        let library = FakeItemLibrary()
        let first = library.add("First\n")
        let second = library.add("Second\n")
        let page = try await Page(library: library)
        Self.savingEdits(of: page)
        try await page.show(first.id)
        _ = try await Self.holdingAnEdit("First, typed\n", in: page)
        let kept = await withCheckedContinuation { continuation in
            page.editor.select(library.item(second.id)!)
            // The page answers in order, so the hand-over's answer, and the next note put on the page, come first.
            page.editor.flush { continuation.resume(returning: $0) }
        }
        #expect(kept)
        #expect(library.notices.waiting.isEmpty, "the first note's text was kept, so nothing is told")
        #expect(page.editor.noteID == second.id)
        #expect(library.body(of: first.id)?.text == "First, typed\n")
    }

    @Test func quittingWhileAHandOverIsHeldWaitsForItThenHandsOverTheNoteOnThePage() async throws {
        let library = FakeItemLibrary()
        let first = library.add("First\n")
        let second = library.add("Second\n")
        let page = try await Page(library: library)
        Self.savingEdits(of: page)
        try await page.show(first.id)
        let leaving = try await Self.holdingAnEdit("First, typed\n", in: page)
        // So the page is never given up on while it is held, however slowly the machine runs.
        page.editor.flushLimit = waitLimit
        try await page.run("window.held = true")
        page.editor.select(try #require(library.item(second.id)))
        var kept: Bool?
        page.editor.flush { kept = $0 }
        // Time for the held page to be asked again more than once.
        try await Task.sleep(for: .milliseconds(300))
        #expect(kept == nil, "the flush waits while the hand-over is held")
        #expect(page.editor.noteID == first.id)

        try await page.run("window.held = false")
        try await page.wait { kept != nil }
        #expect(kept == true)
        #expect(library.notices.waiting.isEmpty)
        #expect(page.editor.noteID == second.id)
        #expect(library.body(of: first.id)?.text == "First, typed\n")
        let asked = try #require(try await page.editor.webView.evaluateJavaScript("window.asked") as? [Int])
        #expect(asked == [leaving, page.editor.generation], "the hand-over asks for the first note, then the flush for the second")
    }

    @Test func closingAsTheNoteIsLeftWaitsForItAndGoesAhead() async throws {
        let library = FakeItemLibrary()
        let note = library.add("Note\n")
        let page = try await Page(library: library)
        Self.savingEdits(of: page)
        try await page.show(note.id)
        _ = try await Self.holdingAnEdit("Note, typed\n", in: page)
        let kept = await withCheckedContinuation { continuation in
            page.editor.close()
            page.editor.flush { continuation.resume(returning: $0) }
        }
        #expect(kept)
        #expect(library.notices.waiting.isEmpty)
        #expect(page.editor.noteID == nil)
        #expect(library.body(of: note.id)?.text == "Note, typed\n")
    }

    /// The hand-over could not take the first note's last edit, so neither can the flush waiting for it: the close or
    /// quit is refused, and the person is told once.
    @Test func closingAsAHandOverIsGivenUpOnRefusesAndTellsOnce() async throws {
        let library = FakeItemLibrary()
        let first = library.add("First\n")
        let second = library.add("Second\n")
        let page = try await Page(library: library)
        try await page.show(first.id)
        _ = try await Self.holdingAnEdit("First, typed\n", in: page)
        page.editor.flushLimit = .milliseconds(250)
        try await page.run("window.held = true")
        page.editor.select(try #require(library.item(second.id)))
        let kept = await withCheckedContinuation { continuation in page.editor.flush { continuation.resume(returning: $0) } }
        #expect(!kept)
        #expect(library.notices.told == 1)
        #expect(page.editor.noteID == first.id, "the first note stays on the page")
    }

    /// A window that goes as the app's windows do: its editor leaves the open ones as it closes.
    private final class ClosingWindow: NSObject, NSWindowDelegate {
        let window = TestWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        weak var editor: EditorController?
        private var proxy: EditorCloseDelegate?

        init(_ editor: EditorController) {
            self.editor = editor
            super.init()
            window.isReleasedWhenClosed = false
            window.delegate = self
            proxy = EditorCloseDelegate(editor: editor, window: window)
            window.orderFront(nil)
        }

        func windowWillClose(_ notification: Notification) { editor?.windowWent() }

        func tearDown() {
            proxy?.detach()
            window.delegate = nil
            window.close()
        }
    }

    private static func quit() -> () -> Bool? {
        var kept: Bool?
        EditorController.flushAll { kept = $0 }
        return { kept }
    }

    /// Nothing is selected while the page is composing, then the window is closed and the app quits: the close and the
    /// quit both wait for the note being left to hand over its typing, which reaches the library before either goes.
    @Test func closingTheWindowAndQuittingWhileTheNoteIsLeftWaitForItsTyping() async throws {
        let library = FakeItemLibrary()
        let note = library.add("Note\n")
        let page = try await Page(library: library)
        Self.savingEdits(of: page)
        try await page.show(note.id)
        _ = try await Self.holdingAnEdit("Note, typed\n", in: page)
        // So the page is never given up on while it is held, however slowly the machine runs.
        page.editor.flushLimit = waitLimit
        try await page.run("window.held = true")
        let closing = ClosingWindow(page.editor)
        defer { closing.tearDown() }

        page.editor.close()
        closing.window.performClose(nil)
        let kept = Self.quit()
        // Time for the held page to be asked again more than once.
        try await Task.sleep(for: .milliseconds(300))
        #expect(closing.window.isVisible, "the window waits for the hand-over")
        #expect(kept() == nil, "the quit waits for the hand-over")

        try await page.run("window.held = false")
        try await page.wait { kept() != nil }
        #expect(kept() == true)
        #expect(library.body(of: note.id)?.text == "Note, typed\n", "the typing is in the library before the quit goes ahead")
        try await page.wait { !closing.window.isVisible }
        #expect(page.editor.windowIsGone)
        #expect(library.notices.waiting.isEmpty)
    }

    /// The same, with a page that never finishes composing: it is given up on once, and the close and the quit are
    /// both refused under that one notice.
    @Test func closingTheWindowAndQuittingWhileTheNoteIsLeftAndGivenUpOnRefusesBothAndTellsOnce() async throws {
        let library = FakeItemLibrary()
        let note = library.add("Note\n")
        let page = try await Page(library: library)
        try await page.show(note.id)
        _ = try await Self.holdingAnEdit("Note, typed\n", in: page)
        page.editor.flushLimit = .milliseconds(250)
        try await page.run("window.held = true")
        let closing = ClosingWindow(page.editor)
        defer { closing.tearDown() }

        page.editor.close()
        closing.window.performClose(nil)
        let kept = Self.quit()
        try await page.wait { kept() != nil }
        #expect(kept() == false)
        #expect(library.notices.told == 1)
        #expect(closing.window.isVisible, "the window stays with the note whose typing was not handed over")
        #expect(!page.editor.windowIsGone)
    }

    /// A page that puts off a reload while the person composes refuses a flush for the reload's generation as stale until
    /// the reload applies, then hands over what it holds.
    @Test func aFlushRefusedAsStaleWhileTheReloadWaitsIsAskedAgainAndKept() async throws {
        let library = FakeItemLibrary()
        let note = library.add("Note\n")
        let page = try await Page(library: library)
        try await page.show(note.id)
        page.editor.flushLimit = waitLimit
        try await page.run("""
            window.asked = 0
            window.editor.flush = () => {
              window.asked++
              return window.asked === 1 ? { commandError: 'stale-document', message: 'Document changed' } : null
            }
            """)
        let kept = await withCheckedContinuation { continuation in page.editor.flush { continuation.resume(returning: $0) } }
        #expect(kept)
        #expect(try await page.editor.webView.evaluateJavaScript("window.asked") as? Int == 2)
        #expect(library.notices.waiting.isEmpty)
    }

    /// A page whose flush fails for any reason but a composition, an import or a reload held back by either is not
    /// asked again for the flush's limit:
    /// the person is told once, at once and with the page's own message, and trying again goes ahead without the page.
    @Test(arguments: [
        "throw new TypeError('the flush broke')",
        "return { commandError: 'internal', message: 'the flush broke' }",
    ])
    func aFlushThatFailsInThePageIsToldWithItsOwnMessageNotAskedAgain(failure: String) async throws {
        let library = FakeItemLibrary()
        let note = library.add("Note\n")
        let page = try await Page(library: library)
        try await page.show(note.id)
        page.editor.flushLimit = waitLimit
        try await page.run("window.asked = 0; window.editor.flush = () => { window.asked++; \(failure) }")
        let kept = await withCheckedContinuation { continuation in page.editor.flush { continuation.resume(returning: $0) } }
        #expect(!kept)
        #expect(try await page.editor.webView.evaluateJavaScript("window.asked") as? Int == 1)
        let messages = library.notices.waiting.map(\.message)
        #expect(messages.count == 1 && messages[0].contains("the flush broke"), "\(messages)")
        #expect(library.notices.waiting.first?.title == "Couldn’t Save “Note”")
        // Time for anything the page's error listener posts to arrive, which nothing signals when it does not.
        try await Task.sleep(for: .milliseconds(200))
        #expect(library.notices.told == 1)
        let keptAgain = await withCheckedContinuation { continuation in page.editor.flush { continuation.resume(returning: $0) } }
        #expect(keptAgain)
    }
}
