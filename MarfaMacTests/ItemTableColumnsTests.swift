import AppKit
import SwiftUI
import Testing
@testable import MarfaMac

@Suite(.hangLimit)
struct ItemTableColumnsTests {
    private static let catalogue = BigLibrary.catalogue

    /// The columns of a place that mixes types, with no look to show any: the name, type and status, then the rest hidden, Created among them.
    private static var columns: [ItemTableColumn] {
        let rows = BigLibrary.items().prefix(300).map {
            ItemTableRow(item: $0, typeLabel: $0.type.rawValue, typeIcon: nil, parent: nil)
        }
        return ItemTableLayout.columns(for: rows, catalogue: catalogue, hidden: [], looks: [:])
    }

    private static func ids(_ columns: [ItemTableColumn]) -> [String] { columns.map(\.id) }

    // MARK: Which columns the table is given

    @Test func theTableIsGivenOnlyTheColumnsThatAreShownByDefault() {
        let columns = Self.columns
        let shown = ViewProperties().shownColumns(columns)
        #expect(Self.ids(shown) == Self.ids(columns.filter(\.isShownByDefault)))
        #expect(columns.contains { !$0.isShownByDefault })
        #expect(!Self.ids(shown).contains("created"))
        #expect(shown.count < columns.count)
    }

    @Test func aColumnShownByDefaultLeavesWhenHiddenAndKeepsItsPlaceInTheOrder() throws {
        let columns = Self.columns
        let victim = try #require(columns.first { $0.isShownByDefault && $0.content != .title })
        var properties = ViewProperties()
        properties.setShown(victim, false)
        let shown = properties.shownColumns(columns)
        #expect(!Self.ids(shown).contains(victim.id))
        #expect(Self.ids(shown) == Self.ids(columns.filter { $0.id != victim.id && $0.isShownByDefault }))
    }

    @Test func resetReturnsEveryColumnToItsDefault() {
        let columns = Self.columns
        var properties = ViewProperties()
        properties.setShown(.created, true)
        properties.setShown(.edited, false)
        properties.reset()
        #expect(Self.ids(properties.shownColumns(columns)) == Self.ids(columns.filter(\.isShownByDefault)))
    }

    @Test func aStoredLayoutSurvivesTheRoundTripPerPlace() {
        var layout = TableColumnCustomization<ItemTableRow>()
        layout[visibility: "created"] = .hidden
        let stored = ItemTableColumnLayouts.storing(layout, for: .allItems, in: Data())
        #expect(ItemTableColumnLayouts.layout(for: .allItems, in: stored) == layout)
        #expect(ItemTableColumnLayouts.layout(for: .itemType("aic.decision"), in: stored) == .init())
    }

    // MARK: In a window

    private struct Host: View {
        let browser: Browser
        @FocusState private var pane: Browser.Pane?
        var body: some View {
            ItemTable(browser: browser, order: ItemOrder(), pane: $pane)
        }
    }

    private static func tableView(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for sub in view.subviews { if let found = tableView(in: sub) { return found } }
        return nil
    }

    @MainActor
    @Test(arguments: [false, true]) func aWideWindowsTableHoldsEveryShownColumn(inSavedView: Bool) async throws {
        let (library, _) = try await BigLibrary.loaded()
        let browser = Browser()
        browser.sidebarItem = inSavedView ? .view(ItemID("view-1")) : .allItems
        browser.viewMode = .table
        let suite = "MarfaMac.ItemTableColumnsTests.wide.\(inSavedView ? "view" : "all")"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 2600, height: 800), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Host(browser: browser).environment(\.library, library).defaultAppStorage(defaults))
        window.makeKeyAndOrderFront(nil)
        defer { window.performClose(nil); window.contentView = nil }
        let expected = browser.shownColumns(browser.tableContent(in: library).columns).map(\.id)
        try #require(await eventually { window.contentView.flatMap { Self.tableView(in: $0) }.map { !$0.tableColumns.isEmpty } ?? false })
        // Nothing to wait for: this gives the table time to add or hide columns after its first layout, if it is going to.
        try await Task.sleep(for: .milliseconds(500))
        let table = try #require(window.contentView.flatMap { Self.tableView(in: $0) })
        #expect(table.tableColumns.filter { !$0.isHidden }.count == expected.count)
    }
}
