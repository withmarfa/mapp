import AppKit
import Darwin
import Foundation
import SwiftUI
import Testing
@testable import MarfaMac

/// Measures a hosted window with 48,750 items in each layout. Run with the Measure test plan.
/// Each `BUSY` line gives main-thread CPU time and share, the longest sampled stall including the action,
/// and elapsed time. For sampled items, `landed` is when the layout cache first contains the expected titles.
/// The test can wait for those titles after the five-second measurement ends.
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
                try await step("idle", [:]) {}
                try await step("open (\(library.items(in: .library).count))", [:]) { browser.viewMode = layout.mode }
                for (round, name) in [(1, "2000 edited"), (2, "2000 edited again")] {
                    let edited = Self.edited(library, round: round)
                    try await step(name, Self.awaited(edited, in: browser, mode: layout.mode)) { source.send(.upserted(edited)) }
                }
                let added = Self.added(round: 1)
                try await step("2000 new", Self.awaited(added, in: browser, mode: layout.mode, joining: true)) {
                    source.send(.upserted(added))
                }
                // The copy read whole again, with a sync's edits in it, as a rehydration brings them.
                let reread = Self.edited(library, round: 3)
                let rereadIDs = Set(reread.map(\.id))
                let rest = library.records.values.map(\.item).filter { !rereadIDs.contains($0.id) }
                let snapshot = SourceSnapshot(items: reread + rest, catalogue: BigLibrary.catalogue)
                try await step("whole copy read again", Self.awaited(reread, in: browser, mode: layout.mode)) {
                    source.send(.loaded(snapshot))
                }
            }
        }
    }

    /// Opening the Library's table and list, sorting each by name, and scrolling the list.
    @Test func openingSortingAndScrolling() async throws {
        for layout in [Layout(name: "table", mode: .table), Layout(name: "list", mode: .list)] {
            try await hosted(layout) { browser, _, _, step in
                try await step("open", [:]) { browser.viewMode = layout.mode }
                try await step("sort by name", [:]) {
                    Self.sortByName(browser)
                }
                for index in 1...3 { try await step("scroll \(index)", [:]) { Self.scroll(by: 2_000) } }
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
        (Layout(name: "calendar", mode: .calendar), { _ in }),
        (Layout(name: "timeline", mode: .timeline), { _ in }),
    ]

    private static func sortByName(_ browser: Browser) {
        browser.tableOptions[.library, default: ItemTableOptions()].sort = [ItemTableComparator(column: .title)]
    }

    /// `changed` items of the Library with a new title and edit date, which moves them in a sort by name or by Edited.
    private static func edited(_ library: any ItemLibrary, round: Int) -> [Item] {
        library.items(in: .library).prefix(changed).enumerated().map { index, item in
            var item = item
            item.title = "Round \(round) \(index)"
            item.name = item.title
            item.modified = Date(timeIntervalSince1970: 1_790_000_000 + Double(round * 10_000 + index))
            return item
        }
    }

    private static func added(round: Int) -> [Item] {
        (0..<changed).map { index in
            LibraryFixture.item(
                ItemID("added-\(round)-\(index)"), BigLibrary.note, "Added \(index)", age: index,
                properties: [Property(key: "title", value: .string("Added \(index)"))])
        }
    }

    /// Up to five of `items` the layout shows now, spread through them, with the titles it is to show once it takes them;
    /// for items `joining` the place, up to five of them.
    private static func awaited(_ items: [Item], in browser: Browser, mode: ItemViewMode, joining: Bool = false) -> [ItemID: String] {
        let candidates = joining ? items : items.filter { shown($0.id, in: browser, mode: mode) != nil }
        let step = max(1, candidates.count / 5)
        return Dictionary(stride(from: 0, to: candidates.count, by: step).prefix(5).map { (candidates[$0].id, candidates[$0].title) },
            uniquingKeysWith: { first, _ in first })
    }

    /// Reads a cached title without asking the layout to update.
    private static func shown(_ id: ItemID, in browser: Browser, mode: ItemViewMode) -> String? {
        func nth<Group>(_ position: Int?, of groups: [Group], _ items: (Group) -> [Item]) -> String? {
            guard var position else { return nil }
            for group in groups {
                let held = items(group)
                if position < held.count { return held[position].title }
                position -= held.count
            }
            return nil
        }
        switch mode {
        case .table:
            guard let content = browser.tableMemo?.content, let at = content.made.positions[id] else { return nil }
            return content.allRows[at].item.title
        case .list, .gallery:
            guard let held = browser.sectionsWork.held?.value else { return nil }
            return nth(held.positions[id], of: held.sections, \.items)
        case .timeline:
            guard let held = browser.timelineWork.held?.value else { return nil }
            return nth(held.positions[id], of: held.groups) { $0.rows.map(\.item) }
        case .board:
            return browser.boardWork.held?.value.all.lazy.flatMap(\.items).first { $0.id == id }?.title
        case .calendar:
            return browser.calendarWork.held?.value.entries.first { $0.id == id }?.title
        default:
            return nil
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
        _ script: (Browser, MarfaLibrary, FakeItemSource, (String, [ItemID: String], () -> Void) async throws -> Void) async throws -> Void
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

        /// Runs `move` and watches the main thread; `awaited` names the items whose titles the layout is to show after it.
        func step(_ name: String, _ awaited: [ItemID: String], _ move: () -> Void) async throws {
            // Lets earlier work finish, so it is not counted in the measure.
            try await Task.sleep(for: .seconds(1))
            func took() -> Bool { awaited.allSatisfy { Self.shown($0.key, in: browser, mode: layout.mode) == $0.value } }
            Cost.resetTallies()
            let cpu = Self.threadMilliseconds()
            let start = ContinuousClock.now
            move()
            // The move itself holds the main actor too.
            var stall = Self.milliseconds(ContinuousClock.now - start)
            var landed: Duration? = awaited.isEmpty ? .zero : nil
            var checked = start
            while ContinuousClock.now - start < Self.watched {
                let before = ContinuousClock.now
                try await Task.sleep(for: .milliseconds(5))
                stall = max(stall, Self.milliseconds(ContinuousClock.now - before - .milliseconds(5)))
                // Checked a few times a second, so the check costs the main thread next to nothing.
                if landed == nil, ContinuousClock.now - checked >= .milliseconds(50) {
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
            #expect(landed != nil, "\(layout.name), \(name): the layout showed the change")
        }

        try await script(browser, library, source, step)
        #endif
    }
}
