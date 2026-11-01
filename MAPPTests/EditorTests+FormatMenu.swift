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
        #expect(request.address.isEmpty)
        #expect(await !page.editor.setWebLink("not an address"), "an address Inkkit would refuse keeps the request open")
        #expect(page.editor.webLinkRequest != nil)
        #expect(await page.editor.setWebLink("example.com/docs"))
        #expect(page.editor.webLinkRequest == nil)
        try await page.wait { page.changes.last == "Read the [docs](https://example.com/docs)\n" }
    }

    @Test func linkOnALinkOffersToRemoveIt() async throws {
        let page = try await Page()
        try await page.load("Read the [docs](https://example.com)\n")
        try await select("docs", in: page)
        try await page.wait { Format.link.isActive(in: page.editor.caret) }
        page.editor.format(.link)
        try await page.wait { page.editor.webLinkRequest != nil }
        let request = try #require(page.editor.webLinkRequest)
        #expect(request.removable)
        #expect(request.address == "https://example.com", "the sheet starts from the link's own address")
        page.editor.removeWebLink()
        try await page.wait { page.changes.last == "Read the docs\n" }
    }

    @Test func changingALinkReplacesItsAddressOnTheWholeLink() async throws {
        let page = try await Page()
        try await page.load("Read the [docs](https://example.com)\n")
        try await select("docs", in: page)
        try await page.wait { Format.link.isActive(in: page.editor.caret) }
        page.editor.format(.link)
        try await page.wait { page.editor.webLinkRequest != nil }
        #expect(await page.editor.setWebLink("example.org:8080/docs"))
        try await page.wait { page.changes.last == "Read the [docs](https://example.org:8080/docs)\n" }
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

    /// Opens the Link sheet on "docs", then has the note changed elsewhere so the page reloads under a new generation.
    private func reload(_ page: Page, whileAsking ask: (() async -> Bool)? = nil) async throws -> Bool? {
        let note = page.library.add("Read the docs\n")
        try await page.show(note.id)
        try await select("docs", in: page)
        try await page.wait { page.editor.canApply(.link) }
        page.editor.format(.link)
        try #require(page.editor.webLinkRequest != nil)
        let asking = ask.map { ask in Task { await ask() } }
        // The task runs as far as the page's question; the page answers only after the reload below.
        await Task.yield()
        page.library.updateBody(of: note.id, to: "Read the docs, changed elsewhere\n")
        page.editor.noteChanged(try #require(page.library.item(note.id)))
        return await asking?.value
    }

    @Test func aReloadClosesTheLinkSheetBeforeAnAddressIsAdded() async throws {
        let page = try await Page()
        _ = try await reload(page)
        #expect(page.editor.webLinkRequest == nil, "the selection the sheet was opened for is gone")
        #expect(await !page.editor.setWebLink("example.com"), "nothing is open to add to")
        #expect(page.changes.isEmpty)
    }

    @Test func aReloadWhileTheAddressIsReadClosesTheSheetAndWritesNoLink() async throws {
        let page = try await Page()
        let answered = try await reload(page) { await page.editor.setWebLink("example.com") }
        #expect(answered == true, "the sheet is not told the address was refused")
        #expect(page.editor.webLinkRequest == nil)
        _ = try await page.shownText(until: "Read the docs, changed elsewhere")
        #expect(page.changes.isEmpty, "no link was written on the reloaded page")
    }
}
