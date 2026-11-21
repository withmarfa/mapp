import AppKit
import OSLog
import SwiftUI

extension View {
    /// Draws a `Table`'s column headings the same whether or not the window is the key one, without the lines AppKit
    /// puts between them and with one line under them, from where the first column's cells start to where the last
    /// one's end, which is where the rows' separators run. The columns still resize by their edges, reorder by dragging
    /// and sort by a click. SwiftUI cannot style the header the `NSTableView` behind a `Table` draws, so this gives the
    /// table a header view that draws every column's heading itself. The headings are drawn over the table's own
    /// background, or over `backdrop` where the table has none, so rows that scroll under them do not show through.
    ///
    /// A table that sits directly under the toolbar passes `isUnderToolbar` to be told when its rows have scrolled past the
    /// headings, which stay pinned, and so under the toolbar, where the caller draws a `ToolbarBand`. A table in an index
    /// page leaves that to the page (`indexScrollsAway`).
    func quietTableHeader(backdrop: NSColor = .windowBackgroundColor, isUnderToolbar: Binding<Bool>? = nil) -> some View {
        background(QuietTableHeader(backdrop: backdrop, isUnderToolbar: isUnderToolbar))
    }
}

private struct QuietTableHeader: NSViewRepresentable {
    let backdrop: NSColor
    let isUnderToolbar: Binding<Bool>?

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ probe: Probe, context: Context) {
        probe.backdrop = backdrop
        probe.isUnderToolbar = isUnderToolbar
        probe.refresh()
    }

    static func dismantleNSView(_ probe: Probe, coordinator: ()) {
        probe.stop()
    }

    final class Probe: NSView {
        var backdrop = NSColor.windowBackgroundColor
        var isUnderToolbar: Binding<Bool>?
        private weak var followed: NSClipView?
        private var observer: (any NSObjectProtocol)?

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
            if let sv = table.enclosingScrollView {
                let cols = table.tableColumns.map { "\(Int($0.width))[\(Int($0.minWidth))-\(Int(min($0.maxWidth, 9999)))]" }.joined(separator: ",")
                Logger(subsystem: "tbldebug", category: "t").notice("DBG id=\(table.accessibilityIdentifier(), privacy: .public) scroll=\(Int(sv.frame.width)) clip=\(Int(sv.contentView.bounds.width)) table=\(Int(table.frame.width)) auto=\(table.columnAutoresizingStyle.rawValue) hs=\(sv.hasHorizontalScroller) cols=\(cols, privacy: .public)")
            }
            table.headerView?.needsDisplay = true
            follow(table)
            report(table)
        }

        func stop() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            followed = nil
        }

        private func follow(_ table: NSTableView) {
            guard isUnderToolbar != nil, let clip = table.enclosingScrollView?.contentView, clip !== followed else { return }
            stop()
            followed = clip
            clip.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let table = self?.nearestTable() { self?.report(table) }
                }
            }
        }

        /// The headings stay pinned under the toolbar, so the rows reach the toolbar only once they have scrolled by the
        /// headings' height as well.
        private func report(_ table: NSTableView) {
            guard let isUnderToolbar, let clip = table.enclosingScrollView?.contentView else { return }
            let scrolled = clip.bounds.origin.y + clip.contentInsets.top
            let isUnder = scrolled > (table.headerView?.frame.height ?? 0) + 0.5
            if isUnderToolbar.wrappedValue != isUnder { isUnderToolbar.wrappedValue = isUnder }
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
    /// The cell this view draws each column's heading with. The view makes them as it draws, because SwiftUI adds and
    /// replaces a table's columns (and their own cells) after the view is installed, and a column that kept its own
    /// cell would have no heading.
    private let cells = NSMapTable<NSTableColumn, QuietHeaderCell>(keyOptions: .weakMemory, valueOptions: .strongMemory)

    private func cell(for column: NSTableColumn) -> QuietHeaderCell {
        let cell = cells.object(forKey: column) ?? QuietHeaderCell(textCell: "")
        let source = column.headerCell
        cell.stringValue = source.stringValue
        cell.font = QuietHeaderCell.headingFont
        cell.alignment = source.alignment
        cell.lineBreakMode = source.lineBreakMode
        cell.truncatesLastVisibleLine = source.truncatesLastVisibleLine
        cells.setObject(cell, forKey: column)
        return cell
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let table = tableView else { return }
        let ground = table.backgroundColor
        (ground.alphaComponent >= 1 ? ground : backdrop).setFill()
        dirtyRect.fill()
        let sorted = table.sortDescriptors.first
        for (index, column) in table.tableColumns.enumerated() {
            let frame = headerRect(ofColumn: index)
            guard frame.intersects(dirtyRect) else { continue }
            let cell = cell(for: column)
            let isSorted = sorted != nil && sorted?.key == column.sortDescriptorPrototype?.key
            cell.isSorted = isSorted
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

    /// Whether the table is sorted by this column, which keeps its arrow clear of the title.
    var isSorted = false

    /// AppKit draws a header cell's title in its own white whatever `textColor` and `attributedStringValue` say, so the cell draws
    /// the title itself, in its font and the secondary color, level with where AppKit puts it.
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        let title = NSAttributedString(
            string: stringValue,
            attributes: [.font: Self.headingFont, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style])
        let area = titleRect(forBounds: cellFrame)
        let height = title.size().height
        // The 6 points a column keeps between its edge and its content, so a heading starts where its cells' content does.
        let left = cellFrame.minX + 6
        let right = isSorted ? sortIndicatorRect(forBounds: cellFrame).minX : cellFrame.maxX - 6
        title.draw(in: NSRect(x: left, y: area.midY - height / 2, width: max(0, right - left), height: height))
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let height = cellFrame.height - Self.bottomLine
        let top = controlView.isFlipped ? cellFrame.minY : cellFrame.minY + Self.bottomLine
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: cellFrame.minX + 2, y: top, width: cellFrame.width - 5, height: height)).addClip()
        super.draw(withFrame: cellFrame, in: controlView)
        NSGraphicsContext.restoreGraphicsState()
    }
}
