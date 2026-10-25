import AppKit
import Foundation
import SwiftUI
import Testing
import WebKit
@testable import MAPP

/// Links to notes in the editor's page, running in real WebKit through the app's bridge.
extension EditorTests {
    private func marks(_ page: Page) async throws -> String {
        try await page.editor.webView.evaluateJavaScript(
            "[...document.querySelectorAll('.inkkit-wiki-link')].map(l => l.dataset.missing === 'true' ? 'missing' : 'live').join()"
        ) as? String ?? ""
    }

    /// The marks of the page's links, once they read `expected` or after a few seconds.
    private func marks(_ page: Page, until expected: String) async throws -> String {
        var shown = ""
        _ = try await eventuallyAsking {
            shown = try await marks(page)
            return shown == expected
        }
        return shown
    }

    /// A command-click on the page's `index`th link, as the person makes it.
    private func commandClick(_ index: Int, in page: Page) async throws {
        try await page.run("""
        document.querySelectorAll('.inkkit-wiki-link')[\(index)].dispatchEvent(
          new MouseEvent('click', { metaKey: true, button: 0, bubbles: true }))
        """)
    }

    /// Gives what the page posted time to arrive. A page in no window draws no frames, so this does not wait for one.
    private func settled(_ page: Page) async throws {
        _ = try await page.editor.webView.evaluateJavaScript("1")
        try await Task.sleep(for: .milliseconds(200))
    }

    @Test func aLinkToNoNoteIsMarkedMissingAndFollowsTheLibrary() async throws {
        let page = try await Page()
        let plan = page.library.add("Plan\n")
        try await page.load("Reader\n\nSee [[Plan]] and [[Later]].\n")
        #expect(try await marks(page, until: "live,missing") == "live,missing")

        let later = page.library.add("Later\n")
        #expect(try await marks(page, until: "live,live") == "live,live", "a note made makes its link live")

        let index = try #require(page.library.items.firstIndex { $0.id == plan.id })
        page.library.items[index].title = "Plan v2"
        #expect(try await marks(page, until: "missing,live") == "missing,live", "a note renamed leaves its old link missing")

        page.library.items.removeAll { $0.id == later.id }
        #expect(try await marks(page, until: "missing,missing") == "missing,missing", "a note deleted makes its link missing")
    }

    @Test func aNoteOpenedWithItsLinksResolvedAndMarkedAndThenClosedIsNotRewritten() async throws {
        let page = try await Page()
        page.library.add("Plan\n")
        let body = "Reader\n\nSee [[Plan]], [[Plan#Soil|soil]], [[Later]] and [[22222222-2222-4222-8222-222222222222|Plan]].\n"
        try await page.load(body)
        let reader = try #require(page.editor.noteID)
        #expect(try await marks(page, until: "live,live,missing,missing") == "live,live,missing,missing")
        page.library.add("Later\n")
        #expect(try await marks(page, until: "live,live,live,missing") == "live,live,live,missing")

        #expect(try await page.markdown() == nil, "the page holds the text it was given")
        page.editor.close()
        try await page.wait { page.editor.noteID == nil }
        #expect(page.changes.isEmpty)
        #expect(page.library.bodyWrites.isEmpty)
        #expect(page.library.bodies[reader] == body)
    }

    @Test func commandClickingALinkOpensTheNoteItNamesAndBeepsForAnyOtherLink() async throws {
        let identity = "33333333-3333-4333-8333-333333333333"
        let page = try await Page()
        let plan = page.library.add("Plan\n", id: ItemID(identity))
        page.library.add("Twin\n")
        page.library.add("Twin\n")
        try await page.load("Reader\n\n[[Plan]] [[Plan|alias]] [[\(identity)]] [[\(identity)|Plan]] [[Gone]] [[Twin]] [[Plan#Soil]]\n")
        var opened: [ItemID] = []
        var beeps = 0
        page.editor.onOpenNote = { opened.append($0) }
        page.editor.onUnopenableLink = { beeps += 1 }
        _ = try await marks(page, until: "live,live,live,live,missing,live,live")

        for index in 0..<4 {
            try await commandClick(index, in: page)
            try await page.wait { opened.count == index + 1 }
        }
        #expect(opened == Array(repeating: plan.id, count: 4))
        #expect(beeps == 0)

        try await commandClick(4, in: page)
        try await page.wait { beeps == 1 }
        try await commandClick(5, in: page)
        try await page.wait { beeps == 2 }
        #expect(opened.count == 4, "a link to no note and one to two notes open nothing")
        #expect(page.library.items.count == 4, "no note is made for a link")

        // A plain click only places the caret.
        try await page.run("document.querySelectorAll('.inkkit-wiki-link')[0].dispatchEvent(new MouseEvent('click', { button: 0, bubbles: true }))")
        try await settled(page)
        #expect(opened.count == 4)
    }

    @Test func aClickInANoteThePageHasLeftOpensNothing() async throws {
        let page = try await Page()
        page.library.add("Plan\n")
        try await page.load("Reader\n\nSee [[Plan]].\n")
        var opened = 0, beeps = 0
        page.editor.onOpenNote = { _ in opened += 1 }
        page.editor.onUnopenableLink = { beeps += 1 }
        page.editor.openNote(NoteLink(name: "Plan"), from: ItemID("another"))
        #expect(opened == 0 && beeps == 0)
        page.editor.windowWent()
        page.editor.openNote(NoteLink(name: "Plan"), from: try #require(page.editor.noteID))
        #expect(opened == 0 && beeps == 0)
    }

    @Test func aLinkWithAHeadingScrollsToItOnceTheNoteIsShown() async throws {
        let page = try await Page()
        let plan = page.library.add("Plan\n\n# Soil\n\nLoam.\n\n## Light and Water\n\nSun.\n")
        try await page.load("Reader\n\nSee [[Plan#light and water]] and [[Plan#Nowhere]].\n")
        let library = page.library
        let editor = page.editor
        editor.onOpenNote = { id in
            if let item = library.item(id) { editor.load(item) }
        }
        _ = try await marks(page, until: "live,live")
        try await commandClick(0, in: page)
        try await page.wait { editor.noteID == plan.id }
        var heading = ""
        _ = try await eventuallyAsking {
            heading = try await editor.webView.evaluateJavaScript(
                "(window.getSelection().anchorNode?.parentElement?.closest('h1,h2,h3')?.textContent) ?? ''") as? String ?? ""
            return !heading.isEmpty
        }
        #expect(heading == "Light and Water", "the page moved to the heading, ignoring case")
    }

    @Test func aHeadingThatIsNotThereStillOpensTheNote() async throws {
        let page = try await Page()
        let plan = page.library.add("Plan\n\n# Soil\n")
        try await page.load("Reader\n\nSee [[Plan#Nowhere]].\n")
        var opened: [ItemID] = []
        page.editor.onOpenNote = { opened.append($0) }
        _ = try await marks(page, until: "live")
        try await commandClick(0, in: page)
        try await page.wait { !opened.isEmpty }
        #expect(opened == [plan.id])
    }

    @Test func aLinkToAHeadingOfItsOwnNoteMovesThePageWithoutOpeningAnything() async throws {
        let page = try await Page()
        try await page.load("Reader\n\n# Soil\n\nSee [[#soil]].\n")
        var opened = 0, beeps = 0
        page.editor.onOpenNote = { _ in opened += 1 }
        page.editor.onUnopenableLink = { beeps += 1 }
        _ = try await marks(page, until: "live")
        try await commandClick(0, in: page)
        var heading = ""
        _ = try await eventuallyAsking {
            heading = try await page.editor.webView.evaluateJavaScript(
                "(window.getSelection().anchorNode?.parentElement?.closest('h1,h2,h3')?.textContent) ?? ''") as? String ?? ""
            return !heading.isEmpty
        }
        #expect(heading == "Soil")
        #expect(opened == 0 && beeps == 0)
    }

    private final class ShownItem {
        var id: ItemID?
    }

    @Test func aLinkFollowedInANoteWindowShowsTheLinkedNoteInThatWindow() async throws {
        let library = FakeItemLibrary()
        let plan = library.add("Plan\n")
        let reader = library.add("Reader\n\nSee [[Plan]] and [[Gone]].\n")
        let shown = ShownItem()
        shown.id = reader.id
        let editor = NoteWindow.makeEditor(
            library: library, details: DetailsPresentation(), showing: Binding { shown.id } set: { shown.id = $0 })
        try #require(await eventually { editor.isReady })
        editor.load(try #require(library.item(reader.id)))
        try #require(await eventually { editor.noteID == reader.id })
        let window = TestWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = editor.container
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        var beeps = 0
        editor.onUnopenableLink = { beeps += 1 }

        editor.openNote(NoteLink(name: "Gone"), from: reader.id)
        #expect(shown.id == reader.id && beeps == 1, "a link to no note leaves the window as it is")
        window.makeFirstResponder(nil)
        editor.openNote(NoteLink(name: "Plan"), from: reader.id)
        #expect(shown.id == plan.id, "the window now shows the linked note, which it will find again at the next launch")
        // The window's page loads the note it now shows, and the keyboard goes there with it.
        editor.load(try #require(library.item(plan.id)))
        func typing() async throws -> Bool {
            try await editor.webView.evaluateJavaScript("document.activeElement?.matches('.ProseMirror') === true") as? Bool ?? false
        }
        let focused = try await eventuallyAsking(typing)
        #expect(focused && window.firstResponder === editor.webView, "the caret is in the linked note, so typing goes on there")
        editor.windowWent()
    }
}
