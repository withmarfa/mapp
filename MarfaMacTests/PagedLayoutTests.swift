import AppKit
import SwiftUI
import Testing
@testable import MarfaMac

/// The list, the gallery and the timeline draw a long place a page at a time (`Browser.listDrawn`). These host the
/// real window, in one nobody sees, and check that Select All chooses every item, not only those drawn, and that a chosen
/// item far past the page is drawn with a page around it, not every item up to it.
@MainActor
@Suite(.hangLimit, .serialized) struct PagedLayoutTests {
    /// Hosts the window on the Library of `BigLibrary` (650 items), in `mode`.
    private func hosted(
        _ mode: ItemViewMode, options: ItemTableOptions? = nil,
        _ script: @MainActor (Browser, MarfaLibrary, FakeItemSource, NSWindow) async throws -> Void
    ) async throws {
        let (library, source) = try await BigLibrary.loaded()
        #expect(library.items(in: .library).count > 2 * Browser.listPage)
        let browser = Browser()
        browser.adopt(library)
        browser.showing = .library
        let libraries = ItemPreviewFixtures.libraries(named: "MarfaMac.PagedLayout")
        let window = TestWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1280, height: 800), styleMask: [.titled, .closable, .resizable], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MainView(browser: browser, details: DetailsPresentation(), restoresWindow: false)
            .environment(\.library, library)
            .environment(libraries))
        window.makeKeyAndOrderFront(nil)
        defer { window.performClose(nil); window.contentView = nil }
        // The window opens on the Library's own layout, then shows the one asked for.
        try #require(await eventually { browser.holdsTableContent || browser.sectionsWork.held != nil })
        browser.viewMode = mode
        try #require(await eventually { browser.sectionsWork.held != nil || browser.timelineWork.held != nil })
        if let options {
            // Through the window's funnel, so the place's default keeps it.
            browser.tableOptions[.library] = options
            browser.choicesChanged()
        }
        try await script(browser, library, source, window)
    }

    /// The window's longest table: its own, since other suites' windows may be open beside it.
    private static func longestTable(in window: NSWindow) -> NSTableView? {
        func tables(in view: NSView) -> [NSTableView] {
            (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap { tables(in: $0) }
        }
        guard let content = window.contentView else { return nil }
        return tables(in: content).max(by: { $0.numberOfRows < $1.numberOfRows })
    }

    @Test func selectAllInTheTimelineChoosesEveryItem() async throws {
        try await hosted(.timeline) { browser, _, _, window in
            try #require(await eventually { Self.longestTable(in: window)?.numberOfRows ?? 0 > 100 })
            let all = try #require(browser.timelineWork.held?.value.positions.keys).map { $0 }
            #expect(all.count > Browser.listPage, "more items than are drawn")
            // As the Edit menu sends it.
            #expect(NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: Self.longestTable(in: window), from: nil))
            #expect(browser.selection == Set(all))
        }
    }

    /// The gallery's Command-A chooses the arrangement's ids, which hold every item, not only the page drawn.
    @Test func theGallerysSelectAllReadsEveryItem() async throws {
        try await hosted(.gallery) { browser, library, _, _ in
            let all = try #require(browser.sectionsWork.held?.value.ids)
            #expect(all.count > Browser.listPage, "more items than are drawn")
            let arrangement = browser.arrangement(in: library, order: ItemOrder(), now: library.now())
            #expect(arrangement.ids == all)
            #expect(Self.drawnCount(in: browser, of: all.count) < all.count, "only a page is drawn")
        }
    }

    /// The chosen item, renamed to the end of a sort by name, is drawn there.
    @Test(arguments: [ItemViewMode.list, .gallery])
    func aChosenItemAChangeMovesPastThePageIsDrawn(mode: ItemViewMode) async throws {
        try await hosted(mode, options: ItemTableOptions(sort: [ItemTableComparator(column: .title)])) { browser, library, source, _ in
            // Sorted by name, as asked.
            @MainActor func sortedByName() -> Bool {
                guard let held = browser.sectionsWork.held, held.value.ids.count > 2 * Browser.listPage else { return false }
                return held.key.choices.shape?.options.sort?.map(\.column.id) == [ItemTableColumn.title.id]
            }
            let sorted = await eventually(sortedByName)
            try #require(sorted)
            let held = try #require(browser.sectionsWork.held?.value)
            let chosen = held.ids[100]
            browser.selection = [chosen]
            let item = try #require(library.item(chosen))
            var renamed = item
            renamed.title = "Zzz last"
            renamed.name = renamed.title
            renamed.version = ItemVersion(99)
            source.send(.upserted([renamed]))
            @MainActor func position() -> Int? { browser.sectionsWork.held?.value.positions[chosen] }
            let moved = await eventually { position() != 100 }
            try #require(moved)
            let now = try #require(position())
            #expect(now > Browser.listPage, "moved to \(now) of \(held.ids.count)")
            let drawn = await eventually { Self.draws(now, in: browser, of: held.ids.count) }
            #expect(drawn, "the page follows the chosen item to \(now)")
            #expect(Self.drawnCount(in: browser, of: held.ids.count) < held.ids.count, "a page around it, not everything up to it")
        }
    }

    /// The gallery's keyboard cursor gives way to a single choice made elsewhere, as a link makes.
    @Test func aChoiceMadeElsewhereEndsTheGallerysCursor() {
        let cursor = ItemID("cursor"), far = ItemID("far")
        #expect(ChosenItemDrawn.shown(cursor: cursor, single: far) == far, "the new choice is drawn, not the cursor's card")
        #expect(ChosenItemDrawn.endsCursor(cursor, single: far))
        #expect(ChosenItemDrawn.shown(cursor: cursor, single: cursor) == cursor)
        #expect(!ChosenItemDrawn.endsCursor(cursor, single: cursor))
        #expect(ChosenItemDrawn.shown(cursor: cursor, single: nil) == cursor, "several chosen: the cursor stays drawn")
        #expect(!ChosenItemDrawn.endsCursor(cursor, single: nil))
    }

    /// A single card chosen far past the page is drawn with a page around it, not every card up to it.
    @Test func aCardChosenFarPastThePageIsDrawn() async throws {
        try await hosted(.gallery) { browser, _, _, _ in
            let ids = try #require(browser.sectionsWork.held?.value.ids)
            let far = ids.count - 1
            #expect(far >= 2 * Browser.listPage, "far enough to need a page of its own")
            browser.selection = [ids[far]]
            let drawn = await eventually { Self.draws(far, in: browser, of: ids.count) }
            #expect(drawn, "the card chosen at \(far) is drawn")
            #expect(Self.drawnCount(in: browser, of: ids.count) < ids.count, "a page around it, not everything up to it")
        }
    }

    /// Whether the layout draws the item at `position` of `count`.
    private static func draws(_ position: Int, in browser: Browser, of count: Int) -> Bool {
        browser.listDrawn.runs(of: count).contains { $0.contains(position) }
    }

    /// How many items of `count` the layout draws.
    private static func drawnCount(in browser: Browser, of count: Int) -> Int {
        browser.listDrawn.runs(of: count).reduce(0) { $0 + $1.count }
    }
}
