import Foundation
import Testing
@testable import MarfaMac

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
            // Linked From is on the inspector unless the person puts it on the page; these tests are about the page's list.
            var placements = PagePlacements()
            placements.setLinkedFrom(.page, of: try #require(library.item(id)).type, in: library.catalogue)
            page.editor.showHeader { [unowned page] in
                page.builds += 1
                return ItemPageHeader.header(of: id, in: library, drafts: drafts, placements: placements)
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
}

/// The pictures the header's pins use, drawn once and kept.
@MainActor
@Suite(.hangLimit) struct PageHeaderIconsTests {
    // A picture drawn again has the same bytes, so only the tally of drawings can show one was kept. Each test runs
    // on the main actor without a suspension, so no other drawing reaches the tally meanwhile.
    @Test func theSamePicturesComeBackWithoutBeingDrawnAgain() throws {
        let first = try #require(PageHeaderIcons(textSize: 13, typeIcons: ["lucide:folder"]))
        #if DEBUG
        Cost.resetTallies()
        #endif
        let again = try #require(PageHeaderIcons(textSize: 13, typeIcons: ["lucide:folder"]))
        #if DEBUG
        #expect(Cost.tallies[.iconDraw] == nil)
        #endif
        #expect(first.indicator.url == again.indicator.url)
        #expect(first.symbols.mapValues(\.url) == again.symbols.mapValues(\.url))
    }

    @Test func aTypeIconThatAppearsLaterJoinsTheOnesAlreadyDrawn() throws {
        let one = try #require(PageHeaderIcons(textSize: 13, typeIcons: ["lucide:folder"]))
        #if DEBUG
        Cost.resetTallies()
        #endif
        let both = try #require(PageHeaderIcons(textSize: 13, typeIcons: ["lucide:folder", "lucide:bug"]))
        #if DEBUG
        #expect(Cost.tallies[.iconDraw]?.count == 1)
        #endif
        #expect(both.symbols.count == one.symbols.count + 1)
        for (key, icon) in one.symbols { #expect(both.symbols[key]?.url == icon.url) }
    }
}
