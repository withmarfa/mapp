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
        let stored = ItemTableColumnLayouts.storing(layout, for: .library, in: Data())
        #expect(ItemTableColumnLayouts.layout(for: .library, in: stored) == layout)
        #expect(ItemTableColumnLayouts.layout(for: .type(TypeID("aic.decision")), in: stored) == .init())
    }

    // MARK: In a window

    private struct Host: View {
        let browser: Browser
        @FocusState private var pane: Browser.Pane?
        var body: some View {
            ItemTable(browser: browser, order: ItemOrder(), pane: $pane)
        }
    }

    fileprivate static func tableView(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for sub in view.subviews { if let found = tableView(in: sub) { return found } }
        return nil
    }

    @MainActor
    @Test(arguments: [false, true]) func aWideWindowsTableHoldsEveryShownColumn(inSavedView: Bool) async throws {
        let (library, _) = try await BigLibrary.loaded()
        let browser = Browser()
        browser.showing = inSavedView ? .saved(ItemID("view-1")) : .library
        browser.viewMode = .table
        let defaults = ThrowawayDefaults.make("ItemTableColumnsTests.wide")
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

    /// What a table's first appearance leaves in the stored layout. The widths a person set are theirs: AppKit's own
    /// layout, which fills a wide window with the columns, must never be stored in their place.
    private struct Opened {
        let window: TestWindow
        let browser: Browser
        let defaults: UserDefaults

        var table: NSTableView? { window.contentView.flatMap { ItemTableColumnsTests.tableView(in: $0) } }
        var shownTableColumns: [NSTableColumn] { (table?.tableColumns ?? []).filter { !$0.isHidden } }
        /// The stored widths of the place the table shows, as the defaults hold them.
        var stored: Data {
            guard let id = browser.shown.savedView else { return defaults.data(forKey: ItemTableColumnLayouts.key) ?? Data() }
            return ViewLayouts.stored(in: defaults).settings(for: id)?.widths ?? Data()
        }
    }

    /// A person's drag of the divider after a column, to the right by `distance` (to the left, when negative), as the header
    /// takes it: the header tracks the mouse until it is up, so the drag and the release are queued before the press.
    @MainActor
    private static func drag(dividerAfter column: NSTableColumn, by distance: CGFloat, in opened: Opened) throws {
        let header = try #require(opened.table?.headerView)
        let edge = header.headerRect(ofColumn: try #require(opened.table?.tableColumns.firstIndex(of: column))).maxX
        func event(_ type: NSEvent.EventType, at x: CGFloat) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(
                with: type, location: header.convert(NSPoint(x: x, y: header.bounds.midY), to: nil), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: opened.window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
        }
        let press = try event(.leftMouseDown, at: edge - 1)
        for step in 1...4 {
            opened.window.postEvent(try event(.leftMouseDragged, at: edge - 1 + distance * CGFloat(step) / 4), atStart: false)
        }
        opened.window.postEvent(try event(.leftMouseUp, at: edge - 1 + distance), atStart: false)
        header.mouseDown(with: press)
    }

    @MainActor
    private static func open(width: CGFloat, inSavedView: Bool, suite: String, seeded: Data = Data()) async throws -> Opened {
        let (library, _) = try await BigLibrary.loaded()
        let browser = Browser()
        browser.showing = inSavedView ? .saved(ItemID("view-1")) : .library
        browser.viewMode = .table
        let defaults = try #require(UserDefaults(suiteName: suite))
        browser.defaults = defaults
        if !seeded.isEmpty {
            if inSavedView {
                ViewLayouts.update(in: defaults) { $0.set(ViewMacSettings(widths: seeded), for: ItemID("view-1")) }
            } else {
                defaults.set(seeded, forKey: ItemTableColumnLayouts.key)
            }
        }
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: width, height: 800), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Host(browser: browser).environment(\.library, library).defaultAppStorage(defaults))
        window.makeKeyAndOrderFront(nil)
        let opened = Opened(window: window, browser: browser, defaults: defaults)
        let shown = browser.shownColumns(browser.tableContent(in: library).columns)
        try #require(await eventually { opened.shownTableColumns.count == shown.count })
        // Nothing to wait for: gives the table time to size its columns and to write them, if it is going to.
        try await Task.sleep(for: .milliseconds(500))
        return opened
    }

    @MainActor
    @Test(arguments: [false, true]) func openingATableInAWideWindowStoresNoWidthBeforeADrag(inSavedView: Bool) async throws {
        let suite = "MarfaMac.ItemTableColumnsTests.opening.\(inSavedView ? "view" : "all")"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let opened = try await Self.open(width: 1500, inSavedView: inSavedView, suite: suite)
        defer { opened.window.performClose(nil); opened.window.contentView = nil; opened.defaults.removePersistentDomain(forName: suite) }
        #expect(opened.stored.isEmpty, "the layout AppKit chose was stored as the person's")
        let (library, _) = try await BigLibrary.loaded()
        let ideals = opened.browser.shownColumns(opened.browser.tableContent(in: library).columns).map(\.widths.ideal)
        #expect(opened.shownTableColumns.map { $0.width.rounded() } == ideals.map { $0.rounded() }, "a column with no stored width opens at its ideal")
    }

    @MainActor
    @Test(arguments: [false, true]) func reopeningATableInAWideWindowKeepsTheStoredWidths(inSavedView: Bool) async throws {
        let suite = "MarfaMac.ItemTableColumnsTests.reopening.\(inSavedView ? "view" : "all")"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        // A person drags the name column wider and another narrower, and the table stores them.
        let first = try await Self.open(width: 1500, inSavedView: inSavedView, suite: suite)
        let columns = first.shownTableColumns
        try Self.drag(dividerAfter: columns[0], by: 37, in: first)
        if columns.count > 2 { try Self.drag(dividerAfter: columns[2], by: -21, in: first) }
        try #require(await eventually { !first.stored.isEmpty })
        let kept = first.stored
        let widths = first.shownTableColumns.map { $0.width.rounded() }
        first.window.performClose(nil)
        first.window.contentView = nil

        let second = try await Self.open(width: 1500, inSavedView: inSavedView, suite: suite, seeded: kept)
        defer { second.window.performClose(nil); second.window.contentView = nil }
        #expect(second.stored == kept, "opening the table wrote over the person's widths")
        #expect(second.shownTableColumns.map { $0.width.rounded() } == widths, "the table opened at widths the person did not set")
    }

    @MainActor
    @Test func aPlaceWithNoStoredWidthsOpensAtTheIdealsAfterAnotherPlacesDrag() async throws {
        let suite = "MarfaMac.ItemTableColumnsTests.switching"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let opened = try await Self.open(width: 1500, inSavedView: false, suite: suite)
        defer { opened.window.performClose(nil); opened.window.contentView = nil; opened.defaults.removePersistentDomain(forName: suite) }
        try Self.drag(dividerAfter: opened.shownTableColumns[0], by: 37, in: opened)
        try #require(await eventually { !opened.stored.isEmpty })

        // The same table moves to a saved view that holds no widths of its own.
        opened.browser.showing = .saved(ItemID("view-1"))
        let (library, _) = try await BigLibrary.loaded()
        let ideals = opened.browser.shownColumns(opened.browser.tableContent(in: library).columns).map { $0.widths.ideal.rounded() }
        try #require(await eventually { opened.shownTableColumns.count == ideals.count })
        #expect(await eventually { opened.shownTableColumns.map { $0.width.rounded() } == ideals }, "the saved view kept the last place's widths: \(opened.shownTableColumns.map { $0.width.rounded() }) vs \(ideals)")
        #expect(opened.stored.isEmpty, "showing the saved view stored widths for it")
    }

    /// A person's widths are layout data the table writes to the stored layout. In a window wide enough for the columns
    /// (so the table does not scroll), AppKit used to fit every column again when one was shown or hidden, and the
    /// table stored what it chose over the widths the person had set.
    @MainActor
    @Test func widthsSurviveShowingAndHidingAColumnWhileTheColumnsFitTheWindow() async throws {
        let suite = "MarfaMac.ItemTableColumnsTests.fit"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let opened = try await Self.open(width: 1500, inSavedView: false, suite: suite)
        let (window, browser, defaults) = (opened.window, opened.browser, opened.defaults)
        defer { window.performClose(nil); window.contentView = nil; defaults.removePersistentDomain(forName: suite) }
        let (library, _) = try await BigLibrary.loaded()
        func table() -> NSTableView? { opened.table }
        // SwiftUI gives its columns identifiers of its own, so a column is found by its place among the shown ones.
        func shownTableColumns() -> [NSTableColumn] { opened.shownTableColumns }
        func widths() -> [String: CGFloat] {
            let ids = browser.shownColumns(columns).map(\.id)
            let tableColumns = shownTableColumns()
            guard ids.count == tableColumns.count else { return [:] }
            return Dictionary(uniqueKeysWithValues: zip(ids, tableColumns.map { $0.width.rounded() }))
        }
        let columns = browser.tableContent(in: library).columns
        let shown = browser.shownColumns(columns)
        let tableView = try #require(table())
        let scrollView = try #require(tableView.enclosingScrollView)
        // The state that failed: the columns fit the window, so the table does not scroll.
        try #require(tableView.tableColumns.reduce(0) { $0 + $1.width } <= scrollView.contentView.bounds.width)

        // A person drags the status column wider and the name column narrower.
        let status = try #require(shown.first { $0.id != shown[0].id && $0.widths.max - $0.widths.ideal > 40 })
        let dragged = shownTableColumns()[try #require(shown.firstIndex { $0.id == status.id })]
        let name = try #require(shownTableColumns().first)
        let set = (status: dragged.width + 20, name: name.width - 60)
        try Self.drag(dividerAfter: dragged, by: 20, in: opened)
        try Self.drag(dividerAfter: name, by: -60, in: opened)
        try #require(await eventually { !opened.stored.isEmpty })
        let before = widths()
        #expect(before[status.id] == set.status.rounded())
        #expect(before[shown[0].id] == set.name.rounded())

        let extra = try #require(columns.first { !browser.showsColumn($0) && $0.widths.ideal < 150 })
        browser.setColumn(extra, shown: true)
        try #require(await eventually { widths()[extra.id] != nil })
        try await Task.sleep(for: .milliseconds(300)) // Nothing to wait for: gives AppKit time to refit the columns, if it is going to.
        let withExtra = widths()
        for (id, width) in before { #expect(withExtra[id] == width, "\(id) after showing a column") }

        browser.setColumn(extra, shown: false)
        try #require(await eventually { widths()[extra.id] == nil })
        try await Task.sleep(for: .milliseconds(300)) // As above, after hiding it.
        #expect(widths() == before)

        browser.setColumn(status, shown: false)
        try #require(await eventually { widths()[status.id] == nil })
        browser.setColumn(status, shown: true)
        try #require(await eventually { widths()[status.id] != nil })
        try await Task.sleep(for: .milliseconds(300)) // As above, after showing it again.
        #expect(widths()[status.id] == before[status.id], "a column hidden and shown again keeps its width")
        #expect(widths()[shown[0].id] == before[shown[0].id])
    }
}
