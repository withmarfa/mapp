import AppKit
import SwiftUI
import Testing
@testable import MAPP

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
    @Test(arguments: [1400.0, 900.0, 700.0, 500.0]) func theWindowsTableHoldsOnlyShownColumnsAndKeepsAHiddenOnesWidth(windowWidth: Double) async throws {
        let (library, _) = try await BigLibrary.loaded()
        let browser = Browser()
        browser.sidebarItem = .allNotes
        browser.viewMode = .table
        let suite = "MAPP.ItemTableColumnsTests"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: windowWidth, height: 800), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
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
        /// The width the table has written for a column. A layout offers no way to read one, so this reads the form it encodes to.
        func storedWidth(of id: String) -> Double? {
            guard let data = try? JSONEncoder().encode(layout()),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let states = root["perColumnState"] as? [[String: Any]],
                  let index = states.firstIndex(where: { ($0["base"] as? [String: Any])?["explicit"] as? [String: String] == ["_0": id] }),
                  states.indices.contains(index + 1) else { return nil }
            return states[index + 1]["currentWidth"] as? Double
        }
        func store(_ change: (inout TableColumnCustomization<ItemTableRow>) -> Void) {
            var next = layout()
            change(&next)
            defaults.set(ItemTableColumnLayouts.storing(next, for: .allNotes, in: defaults.data(forKey: ItemTableColumnLayouts.key) ?? Data()), forKey: ItemTableColumnLayouts.key)
        }

        func dump(_ label: String, _ t: NSTableView) {
            let cols = t.tableColumns.map { "\($0.identifier.rawValue)=\($0.width)[\($0.minWidth),\($0.maxWidth)]hidden:\($0.isHidden)" }.joined(separator: " ")
            let stored = (try? JSONEncoder().encode(layout())).flatMap { String(data: $0, encoding: .utf8) } ?? "nil"
            Issue.record(Comment(rawValue: "DIAG w=\(Int(windowWidth)) sum=\(t.tableColumns.filter { !$0.isHidden }.map(\.width).reduce(0, +)) \(label) table=\(t.frame.width) clip=\(t.enclosingScrollView?.contentView.bounds.width ?? -1) style=\(t.columnAutoresizingStyle.rawValue) cols: \(cols)"))
            Issue.record(Comment(rawValue: "DIAG w=\(Int(windowWidth)) sum=\(t.tableColumns.filter { !$0.isHidden }.map(\.width).reduce(0, +)) \(label) stored: \(stored)"))
        }
        let first = try await table()
        dump("0 initial", first)
        let expected = ItemTableColumnLayouts.shown(browser.tableContent(in: library).columns, in: .init()).map(\.id)
        let initial = first.tableColumns.map(\.identifier)
        // SwiftUI names the table's columns itself, so a column is told by its place: the name first, Created last.
        #expect(initial.count == expected.count)
        let titleColumn = try #require(first.tableColumns.first)

        store { $0[visibility: "created"] = .visible }
        try #require(await eventually { first.tableColumns.count == expected.count + 1 })
        dump("1 created shown", first)
        let created = try #require(first.tableColumns.last)
        #expect(!initial.contains(created.identifier))
        // The table also writes the other columns' widths when Created arrives, so wait for Created's own.
        created.width = 160
        try #require(await eventually { storedWidth(of: "created") == 160 })
        dump("2 created set to 160", first)

        store { $0[visibility: "created"] = .hidden }
        try #require(await eventually { first.tableColumns.count == expected.count })
        dump("3 created hidden", first)
        titleColumn.width += 40
        // Nothing to wait for: this gives the table's write-back time to have happened, if it is going to.
        try await Task.sleep(for: .milliseconds(300))
        dump("4 title widened", first)
        #expect(storedWidth(of: "created") == 160)

        store { $0[visibility: "created"] = .visible }
        try #require(await eventually { first.tableColumns.count == expected.count + 1 })
        dump("5 created back", first)
        try await Task.sleep(for: .milliseconds(500))
        dump("6 created back +500ms", first)
        let back = try #require(first.tableColumns.last)
        #expect(back.width == 160)
        #expect(first.tableColumns.first?.width == titleColumn.width)
    }
}
