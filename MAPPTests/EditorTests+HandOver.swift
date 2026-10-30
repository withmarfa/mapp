import Foundation
import Testing
import WebKit
@testable import MAPP

/// Closing a window, quitting or changing library while a selection hands the last note over, or while the page
/// leaves its note: the flush that asks for it waits for the hand-over, then hands over whatever is on the page.
extension EditorTests {
    /// A page holding `typed` as the unreported edit of the note on it now, which only a flush brings in. While
    /// `window.held` is true it answers no flush, as a page in the middle of a composition does.
    private static func holdingAnEdit(_ typed: String, in page: Page) async throws -> Int {
        let leaving = page.editor.generation
        try await page.run("""
            window.held = false
            window.asked = []
            const flush = window.editor.flush.bind(window.editor)
            window.editor.flush = generation => {
                if (window.held) throw new Error('composition')
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
        try await page.run("window.held = true")
        page.editor.select(try #require(library.item(second.id)))
        var kept: Bool?
        page.editor.flush { kept = $0 }
        // Time for the held page to be asked again more than once, well inside `flushLimit`.
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
        try await page.run("window.held = true")
        page.editor.select(try #require(library.item(second.id)))
        let kept = await withCheckedContinuation { continuation in page.editor.flush { continuation.resume(returning: $0) } }
        #expect(!kept)
        #expect(library.notices.told == 1)
        #expect(page.editor.noteID == first.id, "the first note stays on the page")
    }
}
