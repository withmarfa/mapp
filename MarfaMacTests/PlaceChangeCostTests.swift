import AppKit
import Darwin
import Foundation
import SwiftUI
import Testing
@testable import MarfaMac

/// Measures a hosted window with 48,750 items in each layout. Run with the Measure test plan.
/// Each `BUSY` line gives main-thread CPU time and share, the longest sampled stall including the action,
/// and elapsed time. For a change, `landed` is when what the layout draws (`drawn`) first matches what a window opened on
/// a copy with the change draws; a change that draws nothing new, or never matches, fails the run.
@MainActor
@Suite(.tags(.measure), .enabled(if: ProcessInfo.processInfo.environment["MARFA_MAC_MEASURE"] != nil), .serialized)
struct PlaceChangeCostTests {
    /// How long after a move the main thread is watched, as the issue's Time Profiler run watched a sync.
    private static let watched = Duration.seconds(5)
    private static let changed = 2_000

    @Test func aSyncOfTwoThousandItemsInEachLayout() async throws {
        // `MARFA_MAC_MEASURE_LAYOUTS` names the layouts to run, by name and comma-separated; unset runs them all.
        let named = ProcessInfo.processInfo.environment["MARFA_MAC_MEASURE_LAYOUTS"].map { Set($0.split(separator: ",").map(String.init)) }
        for (layout, setUp) in Self.layouts where named?.contains(layout.name) ?? true {
            try await hosted(layout) { browser, library, source, step in
                setUp(browser)
                try await step("idle", nil) {}
                try await step("open (\(library.items(in: .library).count))", nil) { browser.viewMode = layout.mode }
                for (round, name) in [(1, "2000 edited"), (2, "2000 edited again")] {
                    let edited = Self.edited(library, round: round)
                    let expected = try await Self.drawn(after: Self.upserting(edited, in: library), like: browser, mode: layout.mode)
                    try await step(name, expected) { source.send(.upserted(edited)) }
                }
                let first = try #require(Self.drawn(in: browser, mode: layout.mode, library: library)?.first.flatMap { library.item($0.id) })
                let added = Self.added(round: 1, like: first)
                let joined = try await Self.drawn(after: Self.upserting(added, in: library), like: browser, mode: layout.mode)
                try await step("2000 new", joined) { source.send(.upserted(added)) }
                // The copy read whole again, with a sync's edits in it, as a rehydration brings them.
                let reread = Self.upserting(Self.edited(library, round: 3), in: library)
                let snapshot = SourceSnapshot(items: reread, catalogue: BigLibrary.catalogue)
                let expected = try await Self.drawn(after: reread, like: browser, mode: layout.mode)
                try await step("whole copy read again", expected) { source.send(.loaded(snapshot)) }
            }
        }
    }

    /// Opening the Library's table and list, sorting each by name, and scrolling the list.
    @Test func openingSortingAndScrolling() async throws {
        for layout in [Layout(name: "table", mode: .table), Layout(name: "list", mode: .list)] {
            try await hosted(layout) { browser, _, _, step in
                try await step("open", nil) { browser.viewMode = layout.mode }
                try await step("sort by name", nil) {
                    Self.sortByName(browser)
                }
                for index in 1...3 { try await step("scroll \(index)", nil) { Self.scroll(by: 2_000) } }
            }
        }
    }

    struct Layout {
        let name: String
        let mode: ItemViewMode
    }

    private static let layouts: [(Layout, (Browser) -> Void)] = [
        (Layout(name: "table", mode: .table), { _ in }),
        (Layout(name: "table by name", mode: .table), { sortByName($0) }),
        (Layout(name: "table grouped by status", mode: .table), {
            $0.tableOptions[.library, default: ItemTableOptions()].grouping = .column("field.status")
        }),
        (Layout(name: "list", mode: .list), { _ in }),
        (Layout(name: "list by name", mode: .list), { sortByName($0) }),
        (Layout(name: "gallery", mode: .gallery), { _ in }),
        (Layout(name: "board", mode: .board), { _ in }),
        // On the month the sample's dates fall in, so the calendar draws items.
        (Layout(name: "calendar", mode: .calendar), { $0.calendarDay = Date(timeIntervalSince1970: 1_780_000_000) }),
        (Layout(name: "timeline", mode: .timeline), { _ in }),
    ]

    private static func sortByName(_ browser: Browser) {
        browser.tableOptions[.library, default: ItemTableOptions()].sort = [ItemTableComparator(column: .title)]
    }

    /// The Library's `changed` newest items with a new title and edit date, each round's ahead of every earlier round's and
    /// of the new items in a sort by name or by Edited, so the first page drawn shows them in any order.
    private static func edited(_ library: any ItemLibrary, round: Int) -> [Item] {
        library.items(in: .library).prefix(changed).enumerated().map { index, item in
            var item = item
            item.title = String(format: "0 %d Round %d %04d", 4 - round, round, index)
            item.name = item.title
            item.modified = Date(timeIntervalSince1970: 1_790_000_000 + Double(round * 100_000 + index))
            return item
        }
    }

    /// `changed` new items like `template`, the first item the layout draws, of its type, values, tier and tags, made and
    /// edited after the first two rounds, so the first page drawn in any order, grouping or date shows them. Their dates are
    /// the template's, spread over the four weeks up to it, as a sync's are.
    private static func added(round: Int, like template: Item) -> [Item] {
        (0..<changed).map { index in
            let title = String(format: "0 1 Added %04d", index)
            let properties = template.properties.filter { $0.key != "title" }.map { property in
                Property(key: property.key, value: property.value.string.flatMap { earlier($0, by: index % 28) }.map { .string($0) } ?? property.value)
            }
            var item = LibraryFixture.item(
                ItemID("added-\(round)-\(index)"), template.type, title, age: index, tier: template.tier, tags: template.tags,
                properties: properties + [Property(key: "title", value: .string(title))])
            item.occurred = template.occurred
            item.source = template.source
            item.created = Date(timeIntervalSince1970: 1_000_000 + Double(changed - index))
            item.modified = Date(timeIntervalSince1970: 1_790_250_000 - Double(index))
            return item
        }
    }

    /// A day or a moment written as Marfa writes it, `days` earlier, or nil for any other text.
    private static func earlier(_ text: String, by days: Int) -> String? {
        let shift = -Double(days) * 86_400
        if let date = try? Date(text, strategy: .iso8601) { return date.addingTimeInterval(shift).formatted(.iso8601) }
        if let day = try? Date(text, strategy: .iso8601.year().month().day()) {
            return day.addingTimeInterval(shift).formatted(.iso8601.year().month().day())
        }
        return nil
    }

    /// Every item of `library` with `items` in place of those of the same id, and those it lacks added.
    private static func upserting(_ items: [Item], in library: MarfaLibrary) -> [Item] {
        let ids = Set(items.map(\.id))
        return library.records.values.map(\.item).filter { !ids.contains($0.id) } + items
    }

    /// An item as a layout draws it.
    struct DrawnItem: Equatable {
        let id: ItemID
        let title: String
    }

    /// What a window opened on a copy holding `items` draws in `mode`, with `browser`'s choices: what the hosted window is
    /// to draw once it takes the change.
    private static func drawn(after items: [Item], like browser: Browser, mode: ItemViewMode) async throws -> [DrawnItem] {
        let source = FakeItemSource()
        let copy = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: items, catalogue: BigLibrary.catalogue)))
        try #require(await eventually(within: .seconds(60)) { copy.isLoaded })
        let fresh = Browser()
        fresh.adopt(copy)
        fresh.showing = browser.shown
        fresh.tableOptions = browser.tableOptions
        fresh.calendarDay = browser.calendarDay
        fresh.viewMode = mode
        // Asked as the layout asks, so the fresh window holds what it would draw.
        switch mode {
        case .table: _ = fresh.tableContent(in: copy)
        case .list, .gallery:
            let order = try #require(browser.sectionsWork.held?.key.choices.order)
            _ = fresh.arrangement(in: copy, order: order, now: copy.now())
        case .timeline:
            let field = try #require(browser.timelineWork.held?.key.choice).field
            _ = fresh.timelinePlacing(in: copy, field: field, now: copy.now())
        case .board: _ = fresh.boardLanes(in: copy)
        case .calendar: _ = fresh.calendarPlacing(in: copy, calendar: Calendar.chosenWeekStart)
        }
        return try #require(drawn(in: fresh, mode: mode, library: copy))
    }

    /// What the layout draws now, read from what the window holds without asking the layout to update: the table's loaded
    /// pages, the list's, the gallery's and the timeline's drawn runs (`Browser.listDrawn`), the board's shown lanes and
    /// the calendar's drawn days.
    private static func drawn(in browser: Browser, mode: ItemViewMode, library: any ItemLibrary) -> [DrawnItem]? {
        func items(_ items: some Sequence<Item>) -> [DrawnItem] { items.map { DrawnItem(id: $0.id, title: $0.title) } }
        switch mode {
        case .table:
            guard let content = browser.tableMemo?.content else { return nil }
            let (paging, size) = (browser.tablePaging, browser.tablePageSize)
            let rows = content.grouping == nil
                ? paging.slice(content.rows, size: size).rows
                : paging.slice(groups: content.groups, collapsed: content.collapsed, size: size).groups.flatMap(\.rows)
            return items(rows.map(\.item))
        case .list, .gallery:
            guard let held = browser.sectionsWork.held?.value else { return nil }
            return items(held.drawn(browser.listDrawn, countsFolded: mode == .gallery).flatMap(\.section.items))
        case .timeline:
            guard let held = browser.timelineWork.held?.value else { return nil }
            return items(held.drawn(browser.listDrawn).flatMap { $0.group.rows.map(\.item) })
        case .board:
            guard let held = browser.boardWork.held?.value else { return nil }
            return items(browser.shownBoardLanes(held).flatMap(\.items))
        case .calendar:
            guard let held = browser.calendarWork.held?.value else { return nil }
            let calendar = Calendar.chosenWeekStart
            let now = library.now()
            let first = CalendarLayout.firstDayShown(browser.calendarDay, now: now, calendar: calendar)
            let days = CalendarLayout.drawn(browser.calendarScale, firstShown: first, anchor: browser.calendarDay ?? now, calendar: calendar)
            let ids = CalendarLayout.ids(in: held.entries, within: days)
            return held.entries.filter { ids.contains($0.id) }.map { DrawnItem(id: $0.id, title: $0.title) }
        }
    }

    private static func scroll(by points: CGFloat) {
        func tables(in view: NSView) -> [NSTableView] {
            (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap { tables(in: $0) }
        }
        guard let content = NSApp.windows.first(where: { $0 is TestWindow })?.contentView,
              let table = tables(in: content).max(by: { $0.numberOfRows < $1.numberOfRows }), let scroll = table.enclosingScrollView
        else { return }
        let clip = scroll.contentView
        clip.scroll(to: NSPoint(x: 0, y: clip.bounds.origin.y + points))
        scroll.reflectScrolledClipView(clip)
    }

    /// The CPU time the calling thread has used, in milliseconds.
    private static func threadMilliseconds() -> Double {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
        let port = mach_thread_self()
        defer { mach_port_deallocate(mach_task_self_, port) }
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), $0, &count) }
        }
        guard result == KERN_SUCCESS else { return 0 }
        func ms(_ time: time_value_t) -> Double { Double(time.seconds) * 1000 + Double(time.microseconds) / 1000 }
        return ms(info.user_time) + ms(info.system_time)
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    /// Hosts the real window on the Library, in `layout`, and hands `script` the browser, the library, the source and `step`.
    private func hosted(
        _ layout: Layout,
        _ script: (Browser, MarfaLibrary, FakeItemSource, (String, [DrawnItem]?, () -> Void) async throws -> Void) async throws -> Void
    ) async throws {
        #if DEBUG
        let (library, source) = try await BigLibrary.loaded(scale: 75)
        let browser = Browser()
        browser.adopt(library)
        browser.showing = .library
        let libraries = ItemPreviewFixtures.libraries(named: "MarfaMac.PlaceChangeCost")
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 1280, height: 800), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MainView(browser: browser, details: DetailsPresentation(), restoresWindow: false)
            .environment(\.library, library)
            .environment(libraries))
        window.makeKeyAndOrderFront(nil)
        defer { window.performClose(nil); window.contentView = nil }
        // Lets the window draw the Library first, so the first move is measured on its own.
        try await Task.sleep(for: .seconds(3))

        /// Runs `move` and watches the main thread; `expected` is what the layout is to draw after it, nil for a move that
        /// changes no item.
        func step(_ name: String, _ expected: [DrawnItem]?, _ move: () -> Void) async throws {
            // Lets earlier work finish, so it is not counted in the measure.
            try await Task.sleep(for: .seconds(1))
            func took() -> Bool { expected.map { Self.drawn(in: browser, mode: layout.mode, library: library) == $0 } ?? true }
            if let expected {
                #expect(Self.drawn(in: browser, mode: layout.mode, library: library) != expected, "\(layout.name), \(name): the change draws something new")
                #expect(!expected.isEmpty, "\(layout.name), \(name): the layout draws items")
            }
            Cost.resetTallies()
            let cpu = Self.threadMilliseconds()
            let start = ContinuousClock.now
            move()
            // The move itself holds the main actor too.
            var stall = Self.milliseconds(ContinuousClock.now - start)
            var landed: Duration? = expected == nil ? .zero : nil
            var checked = start
            while ContinuousClock.now - start < Self.watched {
                let before = ContinuousClock.now
                try await Task.sleep(for: .milliseconds(5))
                stall = max(stall, Self.milliseconds(ContinuousClock.now - before - .milliseconds(5)))
                // Checked four times a second, so reading what the layout draws costs the main thread little.
                if landed == nil, ContinuousClock.now - checked >= .milliseconds(250) {
                    checked = ContinuousClock.now
                    if took() { landed = checked - start }
                }
            }
            let window = Self.milliseconds(ContinuousClock.now - start)
            let main = Self.threadMilliseconds() - cpu
            if landed == nil, await eventually(within: .seconds(60), took) { landed = ContinuousClock.now - start }
            let costs = Cost.tallies.sorted { $0.value.milliseconds > $1.value.milliseconds }.prefix(6)
                .map { "\($0.key.rawValue)=\($0.value.count)x\(String(format: "%.1f", $0.value.milliseconds))ms" }.joined(separator: " ")
            print(String(
                format: "BUSY|%@|%@|main=%.0fms|busy=%.1f%%|stall=%.0fms|window=%.0fms|landed=%@|%@", layout.name, name, main,
                main / window * 100, stall, window, landed.map { String(format: "%.0fms", Self.milliseconds($0)) } ?? "never", costs))
            #expect(landed != nil, "\(layout.name), \(name): the layout drew the change")
        }

        try await script(browser, library, source, step)
        #endif
    }
}
