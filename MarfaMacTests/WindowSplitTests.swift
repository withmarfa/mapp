import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MarfaMac

/// What the window's split view keeps when the layout changes, read from a hosted window.
@MainActor
@Suite(.hangLimit)
struct WindowSplitTests {
    private static func splits(in view: NSView) -> [NSSplitView] {
        (view as? NSSplitView).map { [$0] + view.subviews.flatMap { splits(in: $0) } } ?? view.subviews.flatMap { splits(in: $0) }
    }

    /// The window's outermost split view, which holds the sidebar.
    private static func mainSplit(in window: NSWindow) -> NSSplitView? {
        window.contentView.flatMap { splits(in: $0).first }
    }

    private static func widths(of split: NSSplitView?) -> [Int] {
        split?.arrangedSubviews.map { Int($0.frame.width) } ?? []
    }

    private struct Hosted {
        let window: NSWindow
        let browser: Browser
        let library: MarfaLibrary
        let source: FakeItemSource
        let details: DetailsPresentation

        func turn() {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.002))
            window.contentView?.layoutSubtreeIfNeeded()
        }

        /// Lets the window lay itself out after a change: no state says when it has, so the wait is fixed.
        func settle() async throws {
            try await Task.sleep(for: .milliseconds(700))
            for _ in 0..<5 { turn() }
        }
    }

    private func hosted(_ script: (Hosted) async throws -> Void) async throws {
        #if DEBUG
        let (library, source) = try await BigLibrary.loaded()
        let browser = Browser()
        browser.inPlace.drafts = NewItemDrafts(file: nil)
        browser.quickAdd.drafts = browser.inPlace.drafts
        browser.adopt(library)
        browser.showing = .type(BigLibrary.project)
        let details = DetailsPresentation()
        let libraries = ItemPreviewFixtures.libraries(named: "MarfaMac.WindowSplit")
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 1280, height: 800), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MainView(browser: browser, details: details, restoresWindow: false)
            .environment(\.library, library)
            .environment(libraries))
        window.makeKeyAndOrderFront(nil)
        defer { window.performClose(nil); window.contentView = nil }
        let host = Hosted(window: window, browser: browser, library: library, source: source, details: details)
        try await host.settle()
        try await script(host)
        #endif
    }

    /// Between the layouts that fill the content column the window keeps its split view, so the open panel keeps its
    /// width and the sidebar its place, and only a layout with a list column of its own, which changes the column count,
    /// makes the split view again.
    @Test func aChangeBetweenCollectionLayoutsKeepsTheSplitView() async throws {
        try await hosted { host in
            host.browser.viewMode = .table
            host.details.isPresented = true
            try await host.settle()
            let split = try #require(Self.mainSplit(in: host.window))
            let widths = Self.widths(of: split)
            for mode in [ItemViewMode.board, .timeline, .gallery, .digest, .table] {
                host.browser.viewMode = mode
                try await host.settle()
                #expect(Self.mainSplit(in: host.window) === split, "\(mode.rawValue): the split view stands")
                #expect(Self.widths(of: Self.mainSplit(in: host.window)) == widths, "\(mode.rawValue): the columns keep their widths")
            }
            host.browser.viewMode = .list
            try await host.settle()
            #expect(Self.mainSplit(in: host.window) !== split, "the list's three columns are another split view")
        }
    }

    /// A New row typed in the table belongs to the table's slot alone: it stays the table's through a board, a list and
    /// another place, the board never makes a row of it, and it adds one item, never two.
    @Test func aTypedTableRowStaysTheTablesThroughALayoutAndPlaceChangeAndAddsOneItem() async throws {
        try await hosted { host in
            let browser = host.browser
            let library = host.library
            let typed = "Half typed"
            // A draft is kept for one instance, which this library has not yet read.
            library.serverKey = "test-instance"
            browser.viewMode = .table
            try await host.settle()
            try #require(browser.beginInPlace(.table(group: nil), in: library), "the table has a row to type in")
            browser.inPlace.change { $0.title = typed }
            let place = browser.shown
            let slot = InPlaceRow.slot(.table(group: nil), in: place)
            #expect(browser.inPlace.slot == slot)
            #expect(slot != InPlaceRow.slot(.lane(.option("todo")), in: place), "the board's row has a slot of its own")
            for mode in [ItemViewMode.board, .list] {
                browser.viewMode = mode
                try await host.settle()
                #expect(browser.inPlace.draft == nil, "\(mode.rawValue): no row of that layout takes the table's draft")
                #expect(browser.inPlace.drafts.holdsDraft(slot, in: library.serverKey), "\(mode.rawValue): the table's slot keeps the typed text")
            }
            browser.viewMode = .table
            try await host.settle()
            #expect(await eventually { browser.inPlace.slot == slot && browser.inPlace.draft?.title == typed }, "the table's row comes back with its text")
            browser.showing = .library
            try await host.settle()
            #expect(browser.inPlace.drafts.holdsDraft(slot, in: library.serverKey), "another place keeps the draft")
            browser.showing = place
            #expect(await eventually { browser.inPlace.draft?.title == typed }, "the place brings the row back with its text")

            func creates() -> [ItemDraft] {
                host.source.writes.compactMap { write in if case .create(_, let draft) = write { draft } else { nil } }
            }
            #expect(creates().isEmpty)
            #expect(await browser.addInPlace(in: library, undoManager: nil, next: false) != nil, "the row adds its item")
            #expect(creates().map(\.title) == [typed], "one create, with the typed title")
            #expect(await browser.addInPlace(in: library, undoManager: nil, next: false) == nil, "a second add makes nothing")
            #expect(creates().count == 1, "never two")
        }
    }
}
