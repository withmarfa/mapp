import AppKit
import SwiftUI
import Testing
@testable import MAPP

struct ItemTableColumnsTests {
    private static let catalogue = BigLibrary.catalogue

    /// The columns of a place that mixes types: the name, type, fields, parent and the dates, where Created starts hidden.
    private static var columns: [ItemTableColumn] {
        let rows = BigLibrary.items().prefix(300).map {
            ItemTableRow(item: $0, typeLabel: $0.type.rawValue, typeIcon: nil, parent: nil)
        }
        return ItemTableLayout.columns(for: rows, catalogue: catalogue, hidden: [])
    }

    private static func ids(_ columns: [ItemTableColumn]) -> [String] { columns.map(\.id) }

    // MARK: Which columns the table is given

    @Test func theTableIsGivenOnlyTheColumnsThatAreShownByDefault() {
        let columns = Self.columns
        let shown = ItemTableColumnLayouts.shown(columns, in: .init())
        #expect(Self.ids(shown) == Self.ids(columns.filter(\.isShownByDefault)))
        #expect(columns.contains { !$0.isShownByDefault })
        #expect(!Self.ids(shown).contains("created"))
        #expect(shown.count < columns.count)
    }

    @Test func aHiddenColumnComesBackWhenShownAndLeavesAgainWhenHidden() {
        let columns = Self.columns
        var layout = TableColumnCustomization<ItemTableRow>()
        layout[visibility: "created"] = .visible
        #expect(Self.ids(ItemTableColumnLayouts.shown(columns, in: layout)).contains("created"))
        layout[visibility: "created"] = .hidden
        #expect(!Self.ids(ItemTableColumnLayouts.shown(columns, in: layout)).contains("created"))
    }

    @Test func aColumnShownByDefaultLeavesWhenHiddenAndKeepsItsPlaceInTheOrder() throws {
        let columns = Self.columns
        let victim = try #require(columns.first { $0.isShownByDefault && $0.content != .title })
        var layout = TableColumnCustomization<ItemTableRow>()
        layout[visibility: victim.id] = .hidden
        let shown = ItemTableColumnLayouts.shown(columns, in: layout)
        #expect(!Self.ids(shown).contains(victim.id))
        #expect(Self.ids(shown) == Self.ids(columns.filter { $0.id != victim.id && $0.isShownByDefault }))
    }

    @Test func resetReturnsEveryColumnToItsDefault() {
        let columns = Self.columns
        var layout = TableColumnCustomization<ItemTableRow>()
        layout[visibility: "created"] = .visible
        layout[visibility: "edited"] = .hidden
        layout = TableColumnCustomization()
        #expect(Self.ids(ItemTableColumnLayouts.shown(columns, in: layout)) == Self.ids(columns.filter(\.isShownByDefault)))
    }

    @Test func theNameStaysEvenIfTheStoredLayoutHidesIt() {
        var layout = TableColumnCustomization<ItemTableRow>()
        layout[visibility: "title"] = .hidden
        #expect(Self.ids(ItemTableColumnLayouts.shown(Self.columns, in: layout)).first == "title")
    }

    @Test func aStoredLayoutSurvivesTheRoundTripPerPlace() {
        var layout = TableColumnCustomization<ItemTableRow>()
        layout[visibility: "created"] = .visible
        let stored = ItemTableColumnLayouts.storing(layout, for: .allNotes, in: Data())
        #expect(ItemTableColumnLayouts.layout(for: .allNotes, in: stored)[visibility: "created"] == .visible)
        #expect(ItemTableColumnLayouts.layout(for: .itemType("aic.decision"), in: stored)[visibility: "created"] == .automatic)
    }

    // MARK: In a window

    private struct Host: View {
        let browser: Browser
        @FocusState private var pane: Browser.Pane?
        var body: some View {
            ItemTable(browser: browser, order: NoteOrder(), pane: $pane)
        }
    }

    private static func tableView(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for sub in view.subviews { if let found = tableView(in: sub) { return found } }
        return nil
    }

    private func columnIDs(_ table: NSTableView) -> [String] {
        table.tableColumns.filter { !$0.isHidden }.map(\.identifier.rawValue)
    }

    @MainActor
    @Test func theWindowsTableHoldsOnlyShownColumnsAndKeepsAHiddenOnesWidth() async throws {
        let (library, _) = try await BigLibrary.loaded()
        let browser = Browser()
        browser.sidebarItem = .allNotes
        browser.viewMode = .table
        let suite = "MAPP.ItemTableColumnsTests"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 1400, height: 800), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Host(browser: browser).environment(\.library, library).defaultAppStorage(defaults))
        window.makeKeyAndOrderFront(nil)
        defer { window.performClose(nil); window.contentView = nil }

        func table() async throws -> NSTableView {
            try #require(await eventually { window.contentView.flatMap { Self.tableView(in: $0) }.map { !$0.tableColumns.isEmpty } ?? false })
            return try #require(window.contentView.flatMap { Self.tableView(in: $0) })
        }
        func layout() -> TableColumnCustomization<ItemTableRow> {
            ItemTableColumnLayouts.layout(for: .allNotes, in: defaults.data(forKey: ItemTableColumnLayouts.key) ?? Data())
        }
        func store(_ change: (inout TableColumnCustomization<ItemTableRow>) -> Void) {
            var next = layout()
            change(&next)
            defaults.set(ItemTableColumnLayouts.storing(next, for: .allNotes, in: defaults.data(forKey: ItemTableColumnLayouts.key) ?? Data()), forKey: ItemTableColumnLayouts.key)
        }

        let first = try await table()
        let expected = ItemTableColumnLayouts.shown(browser.tableContent(in: library).columns, in: .init()).map(\.id)
        let initial = first.tableColumns.map(\.identifier)
        // SwiftUI names the table's columns itself, so a column is told by its place: the name first, Created last.
        #expect(initial.count == expected.count)
        let titleColumn = try #require(first.tableColumns.first)

        store { $0[visibility: "created"] = .visible }
        try #require(await eventually { first.tableColumns.count == expected.count + 1 })
        let created = try #require(first.tableColumns.last)
        #expect(!initial.contains(created.identifier))
        created.width = 160
        try #require(await eventually { layout() != .init() })

        store { $0[visibility: "created"] = .hidden }
        try #require(await eventually { first.tableColumns.count == expected.count })
        titleColumn.width += 40
        // Nothing to wait for: this gives the table's write-back time to have happened, if it is going to.
        try await Task.sleep(for: .milliseconds(300))

        store { $0[visibility: "created"] = .visible }
        try #require(await eventually { first.tableColumns.count == expected.count + 1 })
        let back = try #require(first.tableColumns.last)
        #expect(back.width == 160)
        #expect(first.tableColumns.first?.width == titleColumn.width)
    }
}
