import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MarfaMac

/// What the window's split view keeps when the layout or the place changes, read from a hosted window.
@MainActor
@Suite(.hangLimit)
struct WindowSplitTests {
    private static func splits(in view: NSView) -> [NSSplitView] {
        (view as? NSSplitView).map { [$0] + view.subviews.flatMap { splits(in: $0) } } ?? view.subviews.flatMap { splits(in: $0) }
    }

    private static func widths(in window: NSWindow) -> String {
        guard let content = window.contentView else { return "" }
        return splits(in: content).map { split in
            split.arrangedSubviews.map { "\(Int($0.frame.width))\($0.isHidden ? "h" : "")" }.joined(separator: "/")
        }.joined(separator: " | ")
    }

    private static func note(_ line: String) {
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches/withmarfa/262j-first-open/split.out")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(data); try? handle.close() } else { try? data.write(to: url) }
    }

    @Test func probe() async throws {
        #if DEBUG
        let (library, _) = try await BigLibrary.loaded()
        let browser = Browser()
        browser.adopt(library)
        browser.showing = .library
        let details = DetailsPresentation()
        let libraries = ItemPreviewFixtures.libraries(named: "MarfaMac.WindowSplit")
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 1280, height: 800), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MainView(browser: browser, details: details, restoresWindow: false)
            .environment(\.library, library)
            .environment(libraries))
        window.makeKeyAndOrderFront(nil)
        defer { window.performClose(nil); window.contentView = nil }
        func turn() {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.002))
            window.contentView?.layoutSubtreeIfNeeded()
        }
        func settle() async throws {
            try await Task.sleep(for: .milliseconds(900))
            for _ in 0..<5 { turn() }
        }
        try await settle()
        browser.viewMode = .table
        details.isPresented = true
        try await settle()
        Self.note("SPLIT|table, panel open|\(Self.widths(in: window))")
        for mode in [ItemViewMode.board, .timeline, .gallery, .table] {
            browser.viewMode = mode
            try await settle()
            Self.note("SPLIT|\(mode.rawValue)|\(Self.widths(in: window))")
        }
        #endif
    }
}
