import AppKit
import SwiftUI
import Testing
@testable import MarfaMac

/// The list, the gallery and the timeline draw a long place a page at a time (`Browser.listItemsDrawn`). These host the
/// real window, in one nobody sees, and check that Select All chooses every item, not only those drawn, and that a chosen
/// item a change moves past the page is drawn.
@MainActor
@Suite(.hangLimit, .serialized) struct PagedLayoutTests {
    /// Hosts the window on the Library of `BigLibrary` (650 items), in `mode`.
    private func hosted(
        _ mode: ItemViewMode, options: ItemTableOptions? = nil,
        _ script: @MainActor (Browser, MarfaLibrary, FakeItemSource) async throws -> Void
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
        try await script(browser, library, source)
    }

    private static func longestTable() -> NSTableView? {
        func tables(in view: NSView) -> [NSTableView] {
            (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap { tables(in: $0) }
        }
        guard let content = NSApp.windows.first(where: { $0 is TestWindow })?.contentView else { return nil }
        return tables(in: content).max(by: { $0.numberOfRows < $1.numberOfRows })
    }

    @Test func selectAllInTheTimelineChoosesEveryItem() async throws {
        try await hosted(.timeline) { browser, _, _ in
            try #require(await eventually { Self.longestTable()?.numberOfRows ?? 0 > 100 })
            let all = try #require(browser.timelineWork.held?.value.positions.keys).map { $0 }
            #expect(all.count > Browser.listPage, "more items than are drawn")
            // As the Edit menu sends it.
            #expect(NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: Self.longestTable(), from: nil))
            #expect(browser.selection == Set(all))
        }
    }

    @Test func commandAInTheGalleryChoosesEveryItem() async throws {
        try await hosted(.gallery) { browser, _, _ in
            let all = try #require(browser.sectionsWork.held?.value.ids)
            #expect(all.count > Browser.listPage, "more items than are drawn")
            browser.focusRequest = .list
            let window = try #require(NSApp.windows.first { $0 is TestWindow && $0.isVisible })
            let press = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber, context: nil,
                characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
            // Sent again until the gallery has the keyboard, which it takes once the window has drawn it.
            let chose = await eventually {
                if browser.selection.isEmpty { NSApp.sendEvent(press) }
                return !browser.selection.isEmpty
            }
            try #require(chose)
            #expect(browser.selection == Set(all))
        }
    }

    /// The chosen item, renamed to the end of a sort by name, is drawn there.
    @Test(arguments: [ItemViewMode.list, .gallery])
    func aChosenItemAChangeMovesPastThePageIsDrawn(mode: ItemViewMode) async throws {
        try await hosted(mode, options: ItemTableOptions(sort: [ItemTableComparator(column: .title)])) { browser, library, source in
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
            let drawn = await eventually { browser.listItemsDrawn > now }
            #expect(drawn, "the page follows the chosen item to \(now)")
        }
    }
}
