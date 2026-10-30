import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MAPP

/// What the sidebar is like on the turns of the run loop after the window changes shape, which is when the window
/// mounts its split view afresh (`MainView`). For each move it prints `FRAME|<window>|<move>|<ms>|...` at every turn
/// in which something a person would see changed, up to three seconds after: whether the sidebar's list exists, its
/// selection highlight (1 is the system's, -1 none, the soft marks draw instead), how many marks are drawn, which
/// rows are selected and how far it is scrolled. The numbers are for a person to read, never a gate.
@MainActor
@Suite(.tags(.measure), .enabled(if: ProcessInfo.processInfo.environment["MAPP_MEASURE"] != nil), .serialized)
struct SidebarFramesTests {
    @Test func theSidebarAcrossTheWindowChangingShape() async throws {
        try await frames(height: 800, scrolledBy: 0, tag: "tall")
    }

    /// A window short enough that the sidebar scrolls, scrolled down before each move, so a rebuilt list that starts
    /// again at the top shows.
    @Test func aScrolledSidebarAcrossTheWindowChangingShape() async throws {
        try await frames(height: 430, scrolledBy: 90, tag: "scrolled")
    }

    private func frames(height: CGFloat, scrolledBy offset: CGFloat, tag: String) async throws {
        #if DEBUG
        let (library, _) = try await BigLibrary.loaded()
        let browser = Browser()
        let libraries = ItemPreviewFixtures.libraries(named: "MAPP.SidebarFrames.\(tag)")
        let window = TestWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1280, height: height), styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MainView(browser: browser, details: DetailsPresentation(), restoresWindow: false)
            .environment(\.library, library)
            .environment(libraries))
        window.makeKeyAndOrderFront(nil)
        defer { window.performClose(nil); window.contentView = nil }
        /// One turn of the run loop, then whatever the window draws from it.
        func turn() {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.002))
            CATransaction.flush()
            window.contentView?.layoutSubtreeIfNeeded()
        }
        func settle() async throws {
            try await Task.sleep(for: .milliseconds(600))
            for _ in 0..<5 { turn() }
        }
        func scrollSidebar() throws {
            guard offset > 0, let scroll = Self.sidebar(in: window)?.enclosingScrollView else { return }
            scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scroll.reflectScrolledClipView(scroll.contentView)
            for _ in 0..<3 { turn() }
        }
        func move(_ name: String, _ change: () -> Void) async throws {
            try await settle()
            try scrollSidebar()
            var last = Self.facts(of: window)
            print("FRAME|\(tag)|\(name)|before|\(last)")
            let start = ContinuousClock.now
            change()
            var turns = 0
            while ContinuousClock.now - start < .seconds(3) {
                // Yielding, not spinning the run loop, lets the window's display cycle run as it does for a person.
                try await Task.sleep(for: .milliseconds(4))
                turn()
                turns += 1
                let now = Self.facts(of: window)
                let elapsed = ContinuousClock.now - start
                let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
                // The first turns always, then only a turn that changed something.
                if turns <= 2 || now != last { print("FRAME|\(tag)|\(name)|\(String(format: "%.0f", ms)) ms (turn \(turns))|\(now)") }
                last = now
            }
        }

        try await move("list place") { browser.sidebarItem = .itemType("aic.decision") }
        try await move("list to gallery") { browser.viewMode = .gallery }
        try await move("gallery to index") { browser.sidebarItem = .sources }
        try await move("index to gallery") { browser.sidebarItem = .allNotes }
        try await move("gallery to list") { browser.viewMode = .list }
        try await move("list to settings") { browser.showSettings() }
        try await move("settings to list") { browser.leaveSettings() }
        #endif
    }

    /// The sidebar's list: the left-most table in the window, since SwiftUI sets its identifier on the accessibility
    /// element and not on the view.
    private static func sidebar(in window: NSWindow) -> NSTableView? {
        func tables(_ view: NSView) -> [NSTableView] {
            (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap(tables)
        }
        return window.contentView.flatMap(tables)?
            .min { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
    }

    private static func facts(of window: NSWindow) -> String {
        guard let outline = sidebar(in: window), let scroll = outline.enclosingScrollView else { return "no sidebar" }
        let marks = outline.subviews.first { $0 is SoftSelection.Marks }
        let markCount = marks?.layer?.sublayers?.count ?? -1
        let selected = outline.selectedRowIndexes.map(String.init).joined(separator: ",")
        return "highlight=\(outline.selectionHighlightStyle.rawValue) marks=\(markCount) selected=[\(selected)] "
            + "rows=\(outline.numberOfRows) scrollY=\(Int(scroll.contentView.bounds.origin.y))"
    }
}
