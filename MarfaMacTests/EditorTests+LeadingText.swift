import Foundation
import Testing
import WebKit
@testable import MarfaMac

/// A highlight's passage leads its page: the text is the passage, drawn large with the rows after it. That is a display
/// of the same text, so opening it and leaving it, in either look, writes nothing.
extension EditorTests {
    /// Forms a passage may hold that a rewrite would change: a star bullet, a hard break, a trailing space and a link
    /// definition.
    private static let passage = "A grid is a promise  \nabout where things will be.\n\n* kept on every page\n\n[grid]: https://example.com/grid\n"

    @Test func aPassageOpenedWithItsRowsAfterItAndLeftAloneKeepsEveryByte() async throws {
        let page = try await Page()
        try await page.load(Self.passage)
        let id = try #require(page.editor.pageItemID)
        var header = Self.header("", id: id)
        header.textLeads = true
        header.showsTitle = false
        header.rows.append(PropertyRow(id: "note", label: "Note", value: .text("A note on the passage")))
        page.editor.setHeader(header)
        try #require(await eventuallyAsking {
            try await page.editor.webView.evaluateJavaScript("document.body.dataset.lead") as? String == "on"
        })
        let rowsAfterText = try await page.editor.webView.evaluateJavaScript(
            "document.querySelector('#item-footer > .item-rows [data-row=\"note\"]') !== null") as? Bool
        #expect(rowsAfterText == true, "the rows follow the text, in the footer")
        #expect(try await page.markdown() == nil)

        // The head's other look puts the rows back above the text, and neither look edits the text.
        header.textLeads = false
        page.editor.setHeader(header)
        try #require(await eventuallyAsking {
            try await page.editor.webView.evaluateJavaScript("document.querySelector('#item-header > .item-rows') !== null") as? Bool == true
        })
        page.editor.flush()
        _ = try await page.editor.webView.evaluateJavaScript("1")
        #expect(try await page.markdown() == nil)
        #expect(page.changes.isEmpty, "nothing was saved")
    }
}
