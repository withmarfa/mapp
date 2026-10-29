import Foundation
import Testing
@testable import MAPP

/// When the open item's page header is built again: for what it shows, and for nothing else.
@MainActor
@Suite(.hangLimit) struct ItemPageHeaderRebuildTests {
    typealias F = LibraryFixture

    /// A library on the fixture's items, an editor following the header of `id` as the item page does, and how often
    /// that header has been built.
    private final class Page {
        let library: MarfaLibrary
        let source: FakeItemSource
        let editor: EditorController
        private(set) var builds = 0

        private init(source: FakeItemSource, library: MarfaLibrary) {
            self.source = source
            self.library = library
            editor = EditorController(library: library)
        }

        static func opening(_ id: ItemID) async throws -> Page {
            let source = FakeItemSource()
            for (item, text) in F.texts { source.setBody(text, of: item) }
            let library = MarfaLibrary(source: source, notices: Notices())
            source.send(.loaded(F.snapshot))
            try #require(await eventually { library.isLoaded })
            let page = Page(source: source, library: library)
            let drafts = DetailsPresentation()
            page.editor.showHeader { [unowned page] in
                page.builds += 1
                return ItemPageHeader.header(of: id, in: library, drafts: drafts)
            }
            return page
        }

        func send(_ item: Item) async throws {
            source.send(.upserted([item]))
            try #require(await eventually { library.item(item.id) == item })
        }

        /// Lets the editor read the header again if anything it read has changed.
        func settle() async throws {
            // Fixed time to give a reading that should not happen a chance to; one that should is awaited by its caller.
            try await Task.sleep(for: .milliseconds(150))
        }
    }

    @Test func anEditToAnUnrelatedItemDoesNotBuildTheHeaderAgain() async throws {
        let page = try await Page.opening(F.p1)
        #expect(page.builds == 1)
        var other = try #require(page.library.item(F.p2))
        other.title = "Renamed elsewhere"
        try await page.send(other)
        var feed = try #require(page.library.item(F.n2))
        feed.title = "Renamed too"
        try await page.send(feed)
        try await page.settle()
        #expect(page.builds == 1)
    }

    @Test func anEditToTheOpenItemBuildsTheHeaderAgain() async throws {
        let page = try await Page.opening(F.p1)
        var open = try #require(page.library.item(F.p1))
        open.title = "Alpha, renamed"
        try await page.send(open)
        #expect(await eventually { page.editor.header?.title == "Alpha, renamed" })
        #expect(page.builds == 2)
    }

    @Test func aNewTitleOfAnItemLinkedFromHereIsShown() async throws {
        let page = try await Page.opening(F.p1)
        // The plain note holds an about link to the project.
        #expect(page.editor.header?.linked.map(\.title).contains("Plain note") == true)
        var linking = try #require(page.library.item(F.n1))
        linking.title = "Plain note, renamed"
        try await page.send(linking)
        #expect(await eventually { page.editor.header?.linked.map(\.title).contains("Plain note, renamed") == true })
        #expect(page.editor.header?.linked.map(\.title).contains("Plain note") == false)
    }

    @Test func aLinkAnotherItemGainsIsShown() async throws {
        let page = try await Page.opening(F.p2)
        #expect(page.editor.header?.linked.isEmpty == true)
        var linking = try #require(page.library.item(F.n2))
        linking.edgesOut = [Edge(id: EdgeID("a2"), type: "about", source: F.n2, target: .item(F.p2), origin: .property("about"))]
        try await page.send(linking)
        #expect(await eventually { page.editor.header?.linked.map(\.title) == ["Feed note"] })
    }

    @Test func aLinkAnotherItemMovesAwayFromHereIsGone() async throws {
        let page = try await Page.opening(F.p1)
        var linking = try #require(page.library.item(F.n1))
        linking.edgesOut = [Edge(id: EdgeID("a1"), type: "about", source: F.n1, target: .item(F.p2), origin: .property("about"))]
        try await page.send(linking)
        #expect(await eventually { page.editor.header?.linked.map(\.title).contains("Plain note") == false })
    }

    @Test func aLinkingItemThatIsRemovedIsGone() async throws {
        let page = try await Page.opening(F.p1)
        #expect(page.editor.header?.linked.map(\.title).contains("Plain note") == true)
        page.source.send(.removed([F.n1]))
        #expect(await eventually { page.editor.header?.linked.map(\.title).contains("Plain note") == false })
    }
}

/// The pictures the header's pins use, drawn once and kept.
@MainActor
@Suite(.hangLimit) struct PageHeaderIconsTests {
    // A picture drawn again has the same bytes, so only the tally of drawings can show one was kept. Each test runs
    // on the main actor without a suspension, so no other drawing reaches the tally meanwhile.
    @Test func theSamePicturesComeBackWithoutBeingDrawnAgain() throws {
        let first = try #require(PageHeaderIcons(textSize: 13, typeIcons: ["folder"]))
        #if DEBUG
        Cost.resetTallies()
        #endif
        let again = try #require(PageHeaderIcons(textSize: 13, typeIcons: ["folder"]))
        #if DEBUG
        #expect(Cost.tallies[.iconDraw] == nil)
        #endif
        #expect(first.parent.url == again.parent.url)
        #expect(first.symbols.mapValues(\.url) == again.symbols.mapValues(\.url))
    }

    @Test func aTypeIconThatAppearsLaterJoinsTheOnesAlreadyDrawn() throws {
        let one = try #require(PageHeaderIcons(textSize: 13, typeIcons: ["folder"]))
        #if DEBUG
        Cost.resetTallies()
        #endif
        let both = try #require(PageHeaderIcons(textSize: 13, typeIcons: ["folder", "bug"]))
        #if DEBUG
        #expect(Cost.tallies[.iconDraw]?.count == 1)
        #endif
        #expect(both.symbols.count == one.symbols.count + 1)
        for (key, icon) in one.symbols { #expect(both.symbols[key]?.url == icon.url) }
    }

    @Test func aNewTextSizeDrawsEverythingAtTheNewSize() throws {
        let small = try #require(PageHeaderIcons(textSize: 11, typeIcons: ["folder"]))
        let large = try #require(PageHeaderIcons(textSize: 24, typeIcons: ["folder"]))
        #expect(small.parent.width < large.parent.width)
        let back = try #require(PageHeaderIcons(textSize: 11, typeIcons: ["folder"]))
        #expect(back.parent.url == small.parent.url)
    }
}
