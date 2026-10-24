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

    private func pump() async {
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(50))
        }
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
        await pump()

        let table = try #require(table(in: window.contentView!))
        let before = marks(of: table)
        #expect(before.marks.count == 1)
        let short = try #require(before.row)
        #expect(before.marks.first?.height == short.height)

        model.tallRow = true
        await pump()
        let grown = marks(of: table)
        let tall = try #require(grown.row)
        #expect(tall.height > short.height)
        #expect(grown.marks.first?.height == tall.height)

        model.tallRow = false
        await pump()
        let shrunk = marks(of: table)
        #expect(shrunk.marks.first?.height == shrunk.row?.height)
        #expect(shrunk.row?.height == short.height)
    }

    @Test func theMarkFollowsTheListWhenItsWidthChanges() async throws {
        let model = Model()
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 420), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Harness(model: model))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        await pump()

        let table = try #require(table(in: window.contentView!))
        model.width = 480
        await pump()
        let widened = marks(of: table)
        let row = try #require(widened.row)
        let expectedWidth = row.width - 20
        #expect(abs((widened.marks.first?.width ?? 0) - expectedWidth) < 0.5)
    }
}
