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
        let (library, _) = try await BigLibrary.loaded()
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
        let host = Hosted(window: window, browser: browser, library: library, details: details)
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

    /// What was typed in a row for a new item is kept while the layout, or the place, changes under it, and the table
    /// brings the row back with its text when it appears again.
    @Test func aChangeOfLayoutOrPlaceKeepsATypedNewRow() async throws {
        try await hosted { host in
            let browser = host.browser
            let typed = "Half typed"
            // A draft is kept for one instance, which this library has not yet read.
            host.library.serverKey = "test-instance"
            browser.viewMode = .table
            try await host.settle()
            try #require(browser.beginInPlace(.table(group: nil), in: host.library), "the table has a row to type in")
            browser.inPlace.change { $0.title = typed }
            let place = browser.shown
            let slot = InPlaceRow.slot(.table(group: nil), in: place)
            for mode in [ItemViewMode.board, .list, .table] {
                browser.viewMode = mode
                try await host.settle()
                #expect(browser.inPlace.drafts.holdsDraft(slot, in: host.library.serverKey) || browser.inPlace.draft?.title == typed, "\(mode.rawValue): the typed text is kept")
            }
            #expect(await eventually { browser.inPlace.draft?.title == typed }, "the table brings the row back with its text")
            browser.showing = .library
            try await host.settle()
            #expect(browser.inPlace.drafts.holdsDraft(slot, in: host.library.serverKey), "another place keeps the draft")
            browser.showing = place
            #expect(await eventually { browser.inPlace.draft?.title == typed }, "the place brings the row back with its text")
        }
    }
}
