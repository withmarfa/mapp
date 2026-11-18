import AppKit
import SwiftUI
import Testing
@testable import MAPP

/// A wide board requests counts for a subset of its cards on first display.
@MainActor
@Suite(.hangLimit) struct ItemBoardCountsTests {
    private static let lanes = 40
    private static let perLane = 5

    private actor Asked {
        var ids: Set<ItemID> = []
        func add(_ more: [ItemID]) { ids.formUnion(more) }
    }

    private struct Host: View {
        let browser: Browser
        @FocusState private var pane: Browser.Pane?
        var body: some View { ItemBoard(browser: browser, pane: $pane) }
    }

    @Test func aBoardOfFortyLanesRequestsCountsForASubsetOfItsCards() async throws {
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
        browser.sidebarItem = .allNotes
        browser.viewMode = .board
        browser.lookChoices[TypeID("test.card")] = TypeLookChoice(date: .off, secondary: [], facts: [.count(.children)])

        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 700, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Host(browser: browser).environment(\.library, library))
        window.makeKeyAndOrderFront(nil)
        defer { window.performClose(nil); window.contentView = nil }

        try #require(await eventuallyAsking { await asked.ids.count > 0 })
        // Allow requests from the initial layout to arrive before checking the upper bound.
        try await Task.sleep(for: .milliseconds(500))
        let count = await asked.ids.count
        #expect(count > 0 && count <= 15 * Self.perLane, "asked for \(count) of \(items.count) cards")
    }
}
