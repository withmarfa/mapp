import Foundation
import Testing
import WebKit
@testable import MAPP

/// The editor's page running in real WebKit, driven through the same bridge the app uses.
@Suite(.serialized)
struct EditorTests {
    /// An editor whose page has loaded, reporting each change it makes.
    final class Harness {
        let editor = EditorController()
        var changes: [String] = []

        init() async throws {
            editor.onChange = { [unowned self] _, markdown in changes.append(markdown) }
            try await wait { self.editor.isReady }
        }

        func load(_ body: String, deleted: Bool = false) async throws {
            editor.load(Note(body: body, created: .now, deleted: deleted ? .now : nil))
            // The page answers every load with its caret; a round trip through it means the load has landed.
            _ = try await editor.webView.evaluateJavaScript("1")
        }

        /// What the page would save, or nil while the note is as it was loaded.
        func markdown() async throws -> String? {
            try await editor.webView.evaluateJavaScript("window.editor.markdown()") as? String
        }

        func run(_ script: String) async throws {
            _ = try await editor.webView.evaluateJavaScript("\(script); 0")
        }

        /// Waits for something the page does in its own time, such as reporting an edit after a pause.
        func wait(_ condition: () -> Bool) async throws {
            for _ in 0..<100 where !condition() {
                try await Task.sleep(for: .milliseconds(50))
            }
            try #require(condition())
        }
    }

    let kitchen = """
    # Kitchen quotes

    | Supplier | Quote |
    | --- | ---: |
    | Oak & Iron | £11,850 |

    - [x] Measure the alcove
    - [ ] Book a site visit

    """

    @Test func aNoteOpenedAndLeftAloneIsNotRewritten() async throws {
        let page = try await Harness()
        try await page.load(kitchen)
        #expect(try await page.markdown() == nil)
        // Longer than the pause after which the page reports an edit.
        try await Task.sleep(for: .milliseconds(400))
        #expect(page.changes.isEmpty)
    }

    @Test func formattingReportsTheNoteAsMarkdown() async throws {
        let page = try await Harness()
        try await page.load("Milk\n")
        page.editor.format(.checklist)
        try await page.wait { !page.changes.isEmpty }
        #expect(page.changes.last == "- [ ] Milk\n")
    }

    @Test func aTableMadeInThePageIsWrittenWithoutAlignment() async throws {
        let page = try await Harness()
        try await page.load("Quotes\n")
        page.editor.format(.table)
        try await page.wait { !page.changes.isEmpty }
        let markdown = try #require(page.changes.last)
        #expect(markdown.contains("| --- | --- | --- |"))
        #expect(!markdown.contains(":-"))
    }

    @Test func undoAndRedoGoThroughThePagesOwnHistory() async throws {
        let page = try await Harness()
        try await page.load("Milk\n")
        page.editor.format(.checklist)
        try await page.wait { page.editor.caret.canUndo }
        page.editor.undo()
        try await page.wait { page.editor.caret.canRedo }
        #expect(try await page.markdown() == nil)
    }

    @Test func aDeletedNoteCannotBeEdited() async throws {
        let page = try await Harness()
        try await page.load("Old list\n", deleted: true)
        #expect(!page.editor.isEditable)
        try await page.run("document.querySelector('.ProseMirror').focus(); document.execCommand('insertText', false, 'x')")
        page.editor.format(.checklist)
        page.editor.format(.table)
        #expect(try await page.markdown() == nil)
    }

    @Test func anEditNotYetReportedIsHandedOverOnFlush() async throws {
        let page = try await Harness()
        try await page.load("Draft\n")
        page.editor.format(.title)
        page.editor.flush()
        try await page.wait { !page.changes.isEmpty }
        #expect(page.changes == ["# Draft\n"])
    }
}
