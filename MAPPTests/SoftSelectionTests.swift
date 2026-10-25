import AppKit
import SwiftUI
import Testing
@testable import MAPP

/// The selection mark under a list row, which a table draws no longer once `softSelection` turns its highlight off.
@MainActor
struct SoftSelectionTests {
    @Observable
    final class Model {
        var selection: Int? = 1
        var tallRow = false
        var width: CGFloat = 320
    }

    struct Harness: View {
        @Bindable var model: Model

        var body: some View {
            List(selection: $model.selection) {
                ForEach(0..<4, id: \.self) { index in
                    VStack(alignment: .leading) {
                        Text("Row \(index)")
                        if index == 1, model.tallRow {
                            Text("A preview line")
                            Text("Another line")
                        }
                    }
                    .tag(index)
                }
            }
            .listStyle(.inset)
            .softSelection(rows: Array(0..<4), selection: model.selection)
            .frame(width: model.width, height: 400)
        }
    }

    private func table(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for subview in view.subviews { if let found = table(in: subview) { return found } }
        return nil
    }

    /// The window's table, once it shows a selected row and its mark.
    private func shownTable(in window: NSWindow) async throws -> NSTableView {
        try #require(await eventually {
            guard let table = table(in: window.contentView!) else { return false }
            let shown = marks(of: table)
            return shown.row != nil && !shown.marks.isEmpty
        })
        return try #require(table(in: window.contentView!))
    }

    /// The marks' frames, and the frame the selected row's view has.
    private func marks(of table: NSTableView) -> (marks: [CGRect], row: CGRect?) {
        let layers = table.subviews.compactMap { $0 as? SoftSelection.Marks }.first?.layer?.sublayers ?? []
        let row = table.selectedRow >= 0 ? table.rowView(atRow: table.selectedRow, makeIfNecessary: false)?.frame : nil
        return (layers.map(\.frame), row)
    }

    @Test func theMarkFollowsASelectedRowThatGrowsAndShrinks() async throws {
        let model = Model()
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 420), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Harness(model: model))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        let table = try await shownTable(in: window)
        let before = marks(of: table)
        #expect(before.marks.count == 1)
        let short = try #require(before.row)
        #expect(before.marks.first?.height == short.height)

        model.tallRow = true
        #expect(await eventually {
            let grown = marks(of: table)
            guard let tall = grown.row else { return false }
            return tall.height > short.height && grown.marks.first?.height == tall.height
        }, "the mark grows with its row")

        model.tallRow = false
        #expect(await eventually {
            let shrunk = marks(of: table)
            return shrunk.row?.height == short.height && shrunk.marks.first?.height == short.height
        }, "the mark shrinks with its row")
    }

    @Test func theMarkFollowsTheListWhenItsWidthChanges() async throws {
        let model = Model()
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 420), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Harness(model: model))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        let table = try await shownTable(in: window)
        let wide = try #require(marks(of: table).row?.width)
        model.width = 480
        #expect(await eventually {
            let widened = marks(of: table)
            guard let row = widened.row, row.width > wide, let mark = widened.marks.first else { return false }
            return abs(mark.width - (row.width - 20)) < 0.5
        }, "the mark is as wide as its row, less its insets")
    }
}
