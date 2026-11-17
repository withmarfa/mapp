import AppKit
import SwiftUI

extension View {
    /// Draws a `Table`'s column headings without the lines AppKit puts between them. The columns still resize by
    /// their edges and reorder by dragging, and the heading's bottom line stays. SwiftUI cannot style the header the
    /// `NSTableView` behind a `Table` draws, so this gives each column a header cell that leaves out the separator.
    func quietTableHeader() -> some View {
        background(QuietTableHeader())
    }
}

private struct QuietTableHeader: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ probe: Probe, context: Context) { probe.refresh() }

    final class Probe: NSView {
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
            for column in table.tableColumns where !(column.headerCell is QuietHeaderCell) {
                let old = column.headerCell
                let cell = QuietHeaderCell(textCell: old.stringValue)
                cell.font = old.font
                cell.alignment = old.alignment
                cell.lineBreakMode = old.lineBreakMode
                cell.truncatesLastVisibleLine = old.truncatesLastVisibleLine
                column.headerCell = cell
            }
            table.headerView?.needsDisplay = true
        }
    }
}

/// A column heading's cell, drawn without the separators AppKit puts at its edges. The heading's bottom line stays.
private final class QuietHeaderCell: NSTableHeaderCell {
    private static let bottomLine: CGFloat = 3

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let height = cellFrame.height - Self.bottomLine
        let top = controlView.isFlipped ? cellFrame.minY : cellFrame.minY + Self.bottomLine
        let clip = NSBezierPath(rect: cellFrame.insetBy(dx: -8, dy: -8))
        clip.append(NSBezierPath(rect: NSRect(x: cellFrame.minX - 3, y: top, width: 5, height: height)))
        clip.append(NSBezierPath(rect: NSRect(x: cellFrame.maxX - 3, y: top, width: 6, height: height)))
        clip.windingRule = .evenOdd
        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        super.draw(withFrame: cellFrame, in: controlView)
        NSGraphicsContext.restoreGraphicsState()
    }
}
