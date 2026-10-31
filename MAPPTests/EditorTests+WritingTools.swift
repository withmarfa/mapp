import AppKit
import Foundation
import Testing
import WebKit
@testable import MAPP

/// While Writing Tools has a session open, the text it shows is not yet the person's, so none of it is saved until
/// the session ends. A real session needs Apple Intelligence; these stand in for it through
/// `EditorController.isWritingToolsActive`.
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
        try await Task.sleep(for: .milliseconds(500))
        #expect(page.changes.count == saved, "the held edit is not saved a second time")
    }

    @Test func typingOutsideASessionIsSavedAtOnce() async throws {
        let page = try await Page()
        try await page.load("Draft\n")
        try await page.run("window.editor.focus(); document.execCommand('insertText', false, ' typed')")
        try await page.wait { page.changes.last?.contains("typed") == true }
    }
}
