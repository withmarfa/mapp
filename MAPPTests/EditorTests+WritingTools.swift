import AppKit
import Foundation
import Testing
import WebKit
@testable import MAPP

/// While Writing Tools has a session open, the text it shows is not yet the person's, so none of it is saved until
/// the session ends. A real session needs Apple Intelligence; these stand in for it through
/// `EditorController.isWritingToolsActive` and `writingToolsActivityChanged()`, which the web view's key-value
/// observation of `isWritingToolsActive` calls.
extension EditorTests {
    @Test func theEditorAsksForTheFullWritingToolsExperience() async throws {
        let page = try await Page()
        #expect(page.editor.webView.configuration.writingToolsBehavior == .complete)
    }

    @Test func nothingIsSavedDuringASessionAndTheLatestTextIsSavedWhenItEnds() async throws {
        let page = try await Page()
        try await page.load("Draft\n")
        var active = true
        page.editor.isWritingToolsActive = { active }
        try await page.run("window.editor.focus(); document.execCommand('insertText', false, ' one')")
        try await page.run("document.execCommand('insertText', false, ' two')")
        // Long enough for the page to have reported both edits and the hold to have kept them.
        try await Task.sleep(for: .milliseconds(500))
        #expect(page.changes.isEmpty, "the rewrite is not saved while it can still be reverted")
        active = false
        page.editor.writingToolsActivityChanged()
        try await page.wait { !page.changes.isEmpty }
        #expect(page.changes.count == 1)
        #expect(page.changes.last?.contains("one two") == true)
    }

    @Test func aFlushDuringASessionSavesWhatThePageShows() async throws {
        let page = try await Page()
        try await page.load("Draft\n")
        page.editor.isWritingToolsActive = { true }
        try await page.run("window.editor.focus(); document.execCommand('insertText', false, ' kept')")
        try await Task.sleep(for: .milliseconds(300))
        #expect(page.changes.isEmpty)
        await withCheckedContinuation { continuation in page.editor.flush { _ in continuation.resume() } }
        #expect(page.changes.last?.contains("kept") == true, "closing or quitting during a session loses nothing")
        let saved = page.changes.count
        page.editor.isWritingToolsActive = { false }
        page.editor.writingToolsActivityChanged()
        try await Task.sleep(for: .milliseconds(500))
        #expect(page.changes.count == saved, "the held edit is not saved a second time")
    }

    @Test func typingOutsideASessionIsSavedAtOnce() async throws {
        let page = try await Page()
        try await page.load("Draft\n")
        try await page.run("window.editor.focus(); document.execCommand('insertText', false, ' typed')")
        try await page.wait { page.changes.last?.contains("typed") == true }
    }

    /// Text from outside reloads the note under a new generation; the rewrite held for the old one is saved first,
    /// against the version it was made on, instead of being replaced by the next edit.
    @Test func aRewriteHeldWhenTheNoteReloadsIsSavedBeforeTheReload() async throws {
        let library = FakeItemLibrary()
        let note = library.add("Draft\n")
        let page = try await Page(library: library)
        try await page.show(note.id)
        var active = true
        page.editor.isWritingToolsActive = { active }
        try await page.run("window.editor.focus(); document.execCommand('insertText', false, ' rewrite')")
        try await page.wait { page.editor.heldEdit != nil }
        library.updateBody(of: note.id, to: "Draft, changed elsewhere\n")
        page.editor.noteChanged(try #require(library.item(note.id)))
        #expect(page.changes.count == 1)
        #expect(page.changes.first?.contains("rewrite") == true, "the held rewrite is saved when the page is replaced")
        #expect(page.editor.heldEdit == nil)
        let reloaded = try await page.shownText(until: "Draft, changed elsewhere")
        #expect(reloaded == "Draft, changed elsewhere")
        try await page.run("window.editor.focus(); document.execCommand('insertText', false, ' more')")
        try await page.wait { page.editor.heldEdit != nil }
        active = false
        page.editor.writingToolsActivityChanged()
        try await page.wait { page.changes.count == 2 }
        #expect(page.changes.last?.contains("more") == true)
        #expect(page.changes.first?.contains("rewrite") == true, "the first save was not replaced")
    }

    @Test func aRewriteHeldWhenThePageProcessEndsIsSavedAndComesBack() async throws {
        let page = try await Page()
        try await page.load("Draft\n")
        page.editor.isWritingToolsActive = { true }
        try await page.run("window.editor.focus(); document.execCommand('insertText', false, ' rewrite')")
        try await page.wait { page.editor.heldEdit != nil }
        page.editor.webViewWebContentProcessDidTerminate(page.editor.webView)
        #expect(page.changes.last?.contains("rewrite") == true)
        try await page.wait { page.editor.isReady }
        let shown = try await page.shownText(until: "Draft rewrite")
        #expect(shown == "Draft rewrite", "the reloaded page holds the rewrite")
    }

    @Test func aRewriteHeldForAnotherGenerationIsSavedNotReplaced() async throws {
        let page = try await Page()
        try await page.load("Draft\n")
        let old = page.editor.generation
        page.editor.heldEdit = ("old", old)
        page.editor.holdEdit("new", of: old + 1)
        #expect(page.changes == ["old"])
        #expect(page.editor.heldEdit?.markdown == "new")
    }
}
