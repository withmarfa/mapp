import AppKit
import SwiftUI
import Testing
@testable import MarfaMac

@MainActor
struct NearestTableTests {
    private func column(frame: NSRect) -> (NSView, NSTableView) {
        let table = NSTableView()
        let scroll = NSScrollView(frame: frame)
        scroll.documentView = table
        let host = NSView(frame: frame)
        host.addSubview(scroll)
        return (host, table)
    }

    @Test func aBackgroundFindsTheTableOfItsOwnHostingView() {
        let split = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let (host, table) = column(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
        let hosting = NSHostingView(rootView: Color.clear)
        hosting.frame = NSRect(x: 0, y: 0, width: 200, height: 400)
        hosting.addSubview(host)
        let probe = NSView(frame: hosting.bounds)
        hosting.addSubview(probe)
        split.addSubview(hosting)
        #expect(probe.nearestTable() === table)
    }

    /// A column whose list is not made yet must not lend the table of one beside it, whose scroll view reaches under it.
    @Test func aBackgroundBesideAnotherColumnsTableFindsNone() {
        let split = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let (neighbour, _) = column(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        split.addSubview(neighbour)
        let hosting = NSHostingView(rootView: Color.clear)
        hosting.frame = NSRect(x: 0, y: 0, width: 200, height: 400)
        let probe = NSView(frame: hosting.bounds)
        hosting.addSubview(probe)
        split.addSubview(hosting)
        #expect(probe.nearestTable() == nil)
    }
}
