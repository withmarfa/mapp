import AppKit
import SwiftUI
import Testing
@testable import MAPP

/// A wide board asks for the counts of the cards in the lanes in view, and lets them go when a lane scrolls out.
@MainActor
@Suite(.hangLimit) struct ItemBoardCountsTests {
    private static let lanes = 40
    private static let perLane = 5

    private actor Asked {
        private(set) var ids: Set<ItemID> = []
        func add(_ more: [ItemID]) { ids.formUnion(more) }
        func clear() { ids = [] }
    }

    private struct Host: View {
        let browser: Browser
        @FocusState private var pane: Browser.Pane?
        var body: some View { ItemBoard(browser: browser, pane: $pane) }
    }

    /// Card `n` is in lane `n % lanes`.
    private static func lane(of id: ItemID) -> Int { Int(id.rawValue.dropFirst("card-".count))! % lanes }

    private func scrollView(in view: NSView) -> NSScrollView? {
        if let found = view as? NSScrollView, let document = found.documentView, document.frame.width > found.frame.width { return found }
        for child in view.subviews { if let found = scrollView(in: child) { return found } }
        return nil
    }

    private func withBoard(_ body: (_ window: NSWindow, _ counts: ItemCounts, _ asked: Asked) async throws -> Void) async throws {
        let words = (0..<Self.lanes).map { StatusWord(value: "stage-\($0)", group: .notStarted) }
        let spec = LookFixture.Spec(id: "test.card", fields: [LookFixture.field("stage", .status(words))])
        let catalogue = LookFixture.catalogue([spec], edgeTypes: LookFixture.relationEdges)
        let now = Date(timeIntervalSince1970: 1_794_000_000)
        let items = (0..<Self.lanes * Self.perLane).map { index in
            var item = Item(
                id: ItemID("card-\(index)"), type: TypeID("test.card"), title: "Card \(index)", name: "Card \(index)",
                titleRule: .firstLine, state: .active, version: ItemVersion(1), created: now, modified: now)
            item.properties.append(Property(key: "stage", value: .string("stage-\(index % Self.lanes)")))
            return item
        }
        let library = FakeItemLibrary(items: items, now: now)
        library.catalogue = catalogue
        let asked = Asked()
        library.counts = ItemCounts { ids, _ in
            await asked.add(ids)
            return [:]
        }
        let browser = Browser()
        browser.sidebarItem = .allItems
        browser.viewMode = .board
        browser.lookChoices[TypeID("test.card")] = TypeLookChoice(date: .off, secondary: [], facts: [.count(.children)])

        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Host(browser: browser).environment(\.library, library))
        window.makeKeyAndOrderFront(nil)
        defer { window.performClose(nil); window.contentView = nil }
        try await body(window, library.counts, asked)
    }

    @Test func aBoardAsksOnlyForTheCardsOfTheLanesInView() async throws {
        try await withBoard { _, _, asked in
            try #require(await eventuallyAsking { await asked.ids.count > 0 })
            // Allow requests from the initial layout to arrive before checking the bound.
            try await Task.sleep(for: .milliseconds(500))
            let ids = await asked.ids
            let lanes = Set(ids.map(Self.lane(of:)))
            #expect(lanes.allSatisfy { $0 < 4 }, "asked for lanes \(lanes.sorted())")
            #expect(ids.count <= 4 * Self.perLane, "asked for \(ids.count) of \(Self.lanes * Self.perLane) cards")
        }
    }

    @Test func aLaneScrolledIntoViewAsksAndOneScrolledOutLetsGo() async throws {
        try await withBoard { window, counts, asked in
            try #require(await eventuallyAsking { await asked.ids.count > 0 })
            let root = try #require(window.contentView)
            let scroll = try #require(scrollView(in: root))
            let clip = scroll.contentView
            let end = (scroll.documentView?.frame.width ?? 0) - clip.bounds.width
            clip.scroll(to: NSPoint(x: end, y: 0))
            scroll.reflectScrolledClipView(clip)
            let last = ItemID("card-\(Self.lanes * Self.perLane - 1)")
            #expect(try await eventuallyAsking { await asked.ids.contains(last) }, "the last lane never asked")

            // Asking again asks only for what is still wanted, so a lane that let go is absent.
            try await Task.sleep(for: .milliseconds(500))
            await asked.clear()
            counts.refresh()
            try #require(await eventuallyAsking { await asked.ids.count > 0 })
            try await Task.sleep(for: .milliseconds(500))
            let lanes = Set(await asked.ids.map(Self.lane(of:)))
            #expect(lanes.contains(Self.lanes - 1), "the lane in view stopped asking")
            #expect(lanes.allSatisfy { $0 >= Self.lanes - 4 }, "lanes still asking after scrolling away: \(lanes.sorted())")
        }
    }
}
