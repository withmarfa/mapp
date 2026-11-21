import AppKit
import SwiftUI

extension View {
    /// Draws a `Table`'s column headings the same whether or not the window is the key one, without the lines AppKit
    /// puts between them and with one line under them, from where the first column's cells start to where the last
    /// one's end, which is where the rows' separators run. The columns still resize by their edges, reorder by dragging
    /// and sort by a click. SwiftUI cannot style the header the `NSTableView` behind a `Table` draws, so this gives the
    /// table a header view and each column a header cell of its own. The headings are drawn over the table's own
    /// background, or over `backdrop` where the table has none, so rows that scroll under them do not show through.
    func quietTableHeader(backdrop: NSColor = .windowBackgroundColor) -> some View {
        background(QuietTableHeader(backdrop: backdrop))
    }
}

private struct QuietTableHeader: NSViewRepresentable {
    let backdrop: NSColor

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ probe: Probe, context: Context) {
        probe.backdrop = backdrop
        probe.refresh()
    }

    final class Probe: NSView {
        var backdrop = NSColor.windowBackgroundColor

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            refresh()
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }

        override func layout() {
            super.layout()
            refresh()
        }

        func refresh() {
            guard window != nil, let table = nearestTable() else { return }
            if !(table.headerView is QuietHeaderView), let old = table.headerView {
                let view = QuietHeaderView(frame: old.frame)
                table.headerView = view
            }
            (table.headerView as? QuietHeaderView)?.backdrop = backdrop
            for column in table.tableColumns where !(column.headerCell is QuietHeaderCell) {
                let old = column.headerCell
                let cell = QuietHeaderCell(textCell: old.stringValue)
                cell.font = QuietHeaderCell.headingFont
                cell.textColor = .secondaryLabelColor
                cell.alignment = old.alignment
                cell.lineBreakMode = old.lineBreakMode
                cell.truncatesLastVisibleLine = old.truncatesLastVisibleLine
                column.headerCell = cell
            }
            table.headerView?.needsDisplay = true
        }
    }
}

/// The header AppKit draws grays out while its window is not the key one, puts a line between the columns and runs its
/// bottom line the width of the table. This one fills with the table's own background and no material, so the heading
/// looks the same whichever window is key and hides the rows that scroll under it. It draws each column's title through `QuietHeaderCell`, the sort arrow of the column the table is sorted by,
/// and one line under the columns, from where the first column starts to where the last ends.
private final class QuietHeaderView: NSTableHeaderView {
    /// What fills the header where the table's own background is clear.
    var backdrop = NSColor.windowBackgroundColor

    override func draw(_ dirtyRect: NSRect) {
        guard let table = tableView else { return }
        let ground = table.backgroundColor
        (ground.alphaComponent >= 1 ? ground : backdrop).setFill()
        dirtyRect.fill()
        let sorted = table.sortDescriptors.first
        for (index, column) in table.tableColumns.enumerated() {
            let frame = headerRect(ofColumn: index)
            guard frame.intersects(dirtyRect), let cell = column.headerCell as? QuietHeaderCell else { continue }
            let isSorted = sorted != nil && sorted?.key == column.sortDescriptorPrototype?.key
            cell.draw(withFrame: frame, in: self)
            if let sorted, isSorted {
                cell.drawSortIndicator(withFrame: frame, in: self, ascending: sorted.ascending, priority: 0)
            }
        }
        guard let first = table.tableColumns.indices.first, let last = table.tableColumns.indices.last else { return }
        // A column keeps 6 points between its edge and its cell's content at the outer edges of the table.
        let start = headerRect(ofColumn: first).minX + 6
        let end = headerRect(ofColumn: last).maxX - 6
        let thickness = 1 / (window?.backingScaleFactor ?? 2)
        NSColor.separatorColor.setFill()
        NSRect(x: start, y: isFlipped ? bounds.maxY - thickness : bounds.minY, width: end - start, height: thickness).fill()
    }
}

/// A column heading's cell, drawn without the separators and the bottom line AppKit draws with it, in the font of the
/// New row's label (callout, medium) and the secondary color, whether or not its column is the sorted one.
private final class QuietHeaderCell: NSTableHeaderCell {
    static let headingFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let bottomLine: CGFloat = 3

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let height = cellFrame.height - Self.bottomLine
        let top = controlView.isFlipped ? cellFrame.minY : cellFrame.minY + Self.bottomLine
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: cellFrame.minX + 2, y: top, width: cellFrame.width - 5, height: height)).addClip()
        super.draw(withFrame: cellFrame, in: controlView)
        NSGraphicsContext.restoreGraphicsState()
    }
}
