import Foundation
import Testing
@testable import MAPP

/// The Format menu's commands that reach the page: the deeper headings, Highlight and Link.
extension EditorTests {
    /// Selects the first occurrence of `text` and gives the page the keyboard, as a person selecting it would.
    private func select(_ text: String, in page: Page) async throws {
        try await page.run("""
            const snapshot = window.editor.readableSnapshot()
            const at = snapshot.text.indexOf('\(text)')
            window.editor.findSelect(at, at + \(text.count), snapshot.generation, snapshot.snapshotId)
            window.editor.focus()
            """)
        page.editor.focus()
    }

    @Test(arguments: [(Format.heading4, "#### Plan\n", 4), (.heading5, "##### Plan\n", 5), (.heading6, "###### Plan\n", 6)])
    func theDeeperHeadingsAreWrittenAndChecked(format: Format, markdown: String, level: Int) async throws {
        let page = try await Page()
        try await page.load("Plan\n")
        try await select("Plan", in: page)
        try await page.wait { page.editor.canApply(format) }
        page.editor.format(format)
        try await page.wait { page.changes.last == markdown }
        try await page.wait { page.editor.caret.block == .heading(level) }
        #expect(format.isActive(in: page.editor.caret))
    }

    @Test func highlightMarksTheSelectionAndCanBeTakenOff() async throws {
        let page = try await Page()
        try await page.load("Mind the gap\n")
        try await select("gap", in: page)
        try await page.wait { page.editor.canApply(.highlight) }
        page.editor.format(.highlight)
        try await page.wait { page.changes.last == "Mind the ==gap==\n" }
        try await page.wait { Format.highlight.isActive(in: page.editor.caret) }
        page.editor.format(.highlight)
        try await page.wait { page.changes.last == "Mind the gap\n" }
    }

    @Test func linkAsksForAnAddressAndSetsItOnTheSelection() async throws {
        let page = try await Page()
        try await page.load("Read the docs\n")
        try await select("docs", in: page)
        try await page.wait { page.editor.canApply(.link) }
        page.editor.format(.link)
        let request = try #require(page.editor.webLinkRequest)
        #expect(!request.removable)
        #expect(!page.editor.finishWebLink("not an address"), "an address Inkkit would refuse keeps the request open")
        #expect(page.editor.webLinkRequest != nil)
        #expect(page.editor.finishWebLink("example.com/docs"))
        #expect(page.editor.webLinkRequest == nil)
        try await page.wait { page.changes.last == "Read the [docs](https://example.com/docs)\n" }
    }

    @Test func linkOnALinkOffersToRemoveIt() async throws {
        let page = try await Page()
        try await page.load("Read the [docs](https://example.com)\n")
        try await select("docs", in: page)
        try await page.wait { Format.link.isActive(in: page.editor.caret) }
        page.editor.format(.link)
        #expect(try #require(page.editor.webLinkRequest).removable)
        #expect(page.editor.finishWebLink(nil))
        try await page.wait { page.changes.last == "Read the docs\n" }
    }

    @Test func cancellingLinkChangesNothing() async throws {
        let page = try await Page()
        try await page.load("Read the docs\n")
        try await select("docs", in: page)
        try await page.wait { page.editor.canApply(.link) }
        page.editor.format(.link)
        page.editor.cancelWebLink()
        #expect(page.editor.webLinkRequest == nil)
        #expect(page.changes.isEmpty)
    }
}

struct WebLinkAddressTests {
    @Test(arguments: [
        ("https://example.com/a?b=1", "https://example.com/a?b=1"),
        ("http://example.com", "http://example.com"),
        ("  example.com  ", "https://example.com"),
        ("www.example.com/path", "https://www.example.com/path"),
        ("me@example.com", "mailto:me@example.com"),
        ("mailto:me@example.com", "mailto:me@example.com"),
        ("tel:+441234567890", "tel:+441234567890"),
    ])
    func anAddressIsKeptOrGivenItsScheme(typed: String, written: String) {
        #expect(WebLinkAddress.normalized(typed) == written)
    }

    @Test(arguments: ["", "   ", "two words", "javascript:alert(1)", "file:///etc/passwd", "https://", "mailto:", "ftp://example.com"])
    func anythingElseIsRefused(typed: String) {
        #expect(WebLinkAddress.normalized(typed) == nil)
    }
}
