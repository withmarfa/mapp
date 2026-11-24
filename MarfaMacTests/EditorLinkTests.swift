import AppKit
import Foundation
import SwiftUI
import Testing
import WebKit
@testable import MarfaMac

/// Links to items in the editor's page, running in real WebKit through the app's bridge.
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

    @Test func anItemOpenedWithItsLinksResolvedAndMarkedAndThenClosedIsNotRewritten() async throws {
        let page = try await Page()
        page.library.add("Plan\n")
        let body = "Reader\n\nSee [[Plan]], [[Plan#Soil|soil]], [[Later]] and [[22222222-2222-4222-8222-222222222222|Plan]].\n"
        try await page.load(body)
        let reader = try #require(page.editor.pageItemID)
        #expect(try await marks(page, until: "live,live,missing,missing") == "live,live,missing,missing")
        page.library.add("Later\n")
        #expect(try await marks(page, until: "live,live,live,missing") == "live,live,live,missing")

        #expect(try await page.markdown() == nil, "the page holds the text it was given")
        page.editor.close()
        try await page.wait { page.editor.pageItemID == nil }
        #expect(page.changes.isEmpty)
        #expect(page.library.bodyWrites.isEmpty)
        #expect(page.library.bodies[reader] == body)
    }

    @Test func commandClickingALinkOpensTheItemItNamesAndBeepsForAnyOtherLink() async throws {
        let identity = "33333333-3333-4333-8333-333333333333"
        let page = try await Page()
        let plan = page.library.add("Plan\n", id: ItemID(identity))
        let twinA = page.library.add("Twin\n")
        let twinB = page.library.add("Twin\n")
        try await page.load("Reader\n\n[[Plan]] [[Plan|alias]] [[\(identity)]] [[\(identity)|Plan]] [[Gone]] [[Twin]] [[Plan#Soil]]\n")
        var opened: [ItemID] = []
        var beeps = 0
        page.editor.onOpenItem = { opened.append($0) }
        page.editor.onUnopenableLink = { beeps += 1 }
        var offered: [[ItemID]] = []
        page.editor.onChooseAmbiguousLink = { ids, pick in
            offered.append(ids)
            pick(ids[1])
        }
        _ = try await marks(page, until: "live,live,live,live,missing,live,live")

        for index in 0..<4 {
            try await commandClick(index, in: page)
            try await page.wait { opened.count == index + 1 }
        }
        #expect(opened == Array(repeating: plan.id, count: 4))
        #expect(beeps == 0)

        try await commandClick(4, in: page)
        try await page.wait { beeps == 1 }
        #expect(opened.count == 4, "a link to no item opens nothing")
        try await commandClick(5, in: page)
        try await page.wait { opened.count == 5 }
        #expect(beeps == 1, "a link to two items offers both and does not beep")
        #expect(offered == [[twinA.id, twinB.id]])
        #expect(opened.last == twinB.id, "the one chosen from the offer is opened")
        #expect(page.library.items.count == 4, "no item is made for a link")

        // A plain click only places the caret.
        try await page.run("document.querySelectorAll('.inkkit-wiki-link')[0].dispatchEvent(new MouseEvent('click', { button: 0, bubbles: true }))")
        try await settled(page)
        #expect(opened.count == 5)
    }

    @Test func aLinkTheCopyHasNotBoundOffersTheItemItsNameAnswersToAndOpensItOnlyWhenChosen() async throws {
        let page = try await Page()
        let plan = page.library.add("Plan\n")
        // The copy holds a slice, so the server may hold another item by this name: the core leaves it unbound.
        page.library.linkAnswerOverrides["Plan"] = LinkAnswer(target: "Plan", state: .unresolved, item: nil, candidates: [plan.id])
        try await page.load("Reader\n\nSee [[Plan]].\n")
        var opened: [ItemID] = [], beeps = 0
        var offered: [[ItemID]] = []
        var choose: ((ItemID) -> Void)?
        page.editor.onOpenItem = { opened.append($0) }
        page.editor.onUnopenableLink = { beeps += 1 }
        page.editor.onChooseAmbiguousLink = { ids, pick in
            offered.append(ids)
            choose = pick
        }
        await page.editor.openItemLink(ItemLink(linkText: "[[Plan]]")!, from: try #require(page.editor.pageItemID))
        #expect(offered == [[plan.id]] && opened.isEmpty && beeps == 0)
        choose?(plan.id)
        #expect(opened == [plan.id])
    }

    @Test func aClickInAnItemThePageHasLeftOpensNothing() async throws {
        let page = try await Page()
        page.library.add("Plan\n")
        try await page.load("Reader\n\nSee [[Plan]].\n")
        var opened = 0, beeps = 0
        page.editor.onOpenItem = { _ in opened += 1 }
        page.editor.onUnopenableLink = { beeps += 1 }
        await page.editor.openItemLink(ItemLink(linkText: "[[Plan]]")!, from: ItemID("another"))
        #expect(opened == 0 && beeps == 0)
        page.editor.windowWent()
        await page.editor.openItemLink(ItemLink(linkText: "[[Plan]]")!, from: try #require(page.editor.pageItemID))
        #expect(opened == 0 && beeps == 0)
    }

    private final class ShownItem {
        var id: ItemID?
    }

    @Test func aLinkFollowedInAnItemWindowShowsTheLinkedItemInThatWindow() async throws {
        let library = FakeItemLibrary()
        let plan = library.add("Plan\n")
        let reader = library.add("Reader\n\nSee [[Plan]] and [[Gone]].\n")
        let shown = ShownItem()
        shown.id = reader.id
        let editor = ItemWindow.makeEditor(
            library: library, details: DetailsPresentation(), showing: Binding { shown.id } set: { shown.id = $0 })
        try #require(await eventually { editor.isReady })
        editor.load(try #require(library.item(reader.id)))
        try #require(await eventually { editor.pageItemID == reader.id })
        let window = TestWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = editor.container
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        var beeps = 0
        editor.onUnopenableLink = { beeps += 1 }

        await editor.openItemLink(ItemLink(linkText: "[[Gone]]")!, from: reader.id)
        #expect(shown.id == reader.id && beeps == 1, "a link to no item leaves the window as it is")
        window.makeFirstResponder(nil)
        await editor.openItemLink(ItemLink(linkText: "[[Plan]]")!, from: reader.id)
        #expect(shown.id == plan.id, "the window now shows the linked item, which it will find again at the next launch")
        // The window's page loads the item it now shows, and the keyboard goes there with it.
        editor.load(try #require(library.item(plan.id)))
        func typing() async throws -> Bool {
            try await editor.webView.evaluateJavaScript("document.activeElement?.matches('.ProseMirror') === true") as? Bool ?? false
        }
        let focused = try await eventuallyAsking(typing)
        #expect(focused && window.firstResponder === editor.webView, "the caret is in the linked item, so typing goes on there")
        editor.windowWent()
    }

    /// A right-click on the page's `index`th link, which Inkkit answers by selecting it and asking the app for its menu.
    private func rightClick(_ selector: String, in page: Page) async throws {
        try await page.run("document.querySelector('\(selector)').dispatchEvent(new MouseEvent('contextmenu', { button: 2, bubbles: true, cancelable: true }))")
    }

    @Test func removeLinkTakesALinkOffAndKeepsItsWordsWhateverKindItIs() async throws {
        let page = try await Page()
        page.library.add("Plan\n")
        let id = page.library.add("Reader\n\nSee [[Plan|the plan]] and [site](https://example.com).\n").id
        try await page.show(id)
        var offered: [[EditorController.LinkChoice]] = []
        var choose: ((EditorController.LinkChoice) -> Void)?
        page.editor.onLinkMenu = { entries, pick in
            offered.append(entries.map(\.choice))
            choose = pick
        }

        try await rightClick(".inkkit-wiki-link", in: page)
        try await page.wait { choose != nil }
        #expect(offered == [[.open, .copy, .remove]], "a link to an item offers no address")
        // A menu answered after the page has moved on from its load changes nothing.
        page.editor.generation += 1
        choose?(.remove)
        try await settled(page)
        #expect(page.changes.isEmpty)
        page.editor.generation -= 1

        choose?(.remove)
        try await page.wait { page.changes.last == "Reader\n\nSee the plan and [site](https://example.com).\n" }

        choose = nil
        try await rightClick("a:not(.inkkit-wiki-link)", in: page)
        try await page.wait { choose != nil }
        #expect(offered.last == [.open, .copy, .edit, .remove])
        choose?(.remove)
        try await page.wait { page.changes.last == "Reader\n\nSee the plan and site.\n" }
    }
}
