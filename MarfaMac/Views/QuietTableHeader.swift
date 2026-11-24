import AppKit
import SwiftUI

extension View {
    /// Draws a `Table`'s column headings the same whether or not the window is the key one, without the lines AppKit
    /// puts between them and with one line under them, from where the first column's cells start to where the last
    /// one's end, which is where the rows' separators run. The columns still resize by their edges, reorder by dragging
    /// and sort by a click. SwiftUI cannot style the header the `NSTableView` behind a `Table` draws, so this gives the
    /// table a header view that draws every column's heading itself. The headings are drawn over the table's own
    /// background, or over `backdrop` where the table has none, so rows that scroll under them do not show through. The
    /// same view keeps the table as wide as its page (see `Probe.fit`), or, for a table whose column widths a person
    /// sets and keeps, leaves every width to the person's drags (`keepsWidths`).
    ///
    /// A table that sits directly under the toolbar passes `isUnderToolbar` to be told when its rows have scrolled past the
    /// headings, which stay pinned, and so under the toolbar, where the caller draws a `ToolbarBand`. A table in an index
    /// page leaves that to the page (`indexScrollsAway`).
    func quietTableHeader(
        backdrop: NSColor = .windowBackgroundColor, isUnderToolbar: Binding<Bool>? = nil, keepsWidths: Bool = false
    ) -> some View {
        background(QuietTableHeader(backdrop: backdrop, isUnderToolbar: isUnderToolbar, keepsWidths: keepsWidths))
    }
}

private struct QuietTableHeader: NSViewRepresentable {
    let backdrop: NSColor
    let isUnderToolbar: Binding<Bool>?
    let keepsWidths: Bool

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ probe: Probe, context: Context) {
        probe.backdrop = backdrop
        probe.isUnderToolbar = isUnderToolbar
        probe.keepsWidths = keepsWidths
        probe.refresh()
    }

    static func dismantleNSView(_ probe: Probe, coordinator: ()) {
        probe.stop()
    }

    final class Probe: NSView {
        var backdrop = NSColor.windowBackgroundColor
        var isUnderToolbar: Binding<Bool>?
        var keepsWidths = false
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
            if let scrollView = table.enclosingScrollView { fit(table, in: scrollView) }
            table.headerView?.needsDisplay = true
            follow(table)
            report(table)
        }

        /// The width and columns the table was last fitted to.
        private var fittedTo: String?

        /// Makes the table as wide as the page it sits in, and keeps it so as that width changes. A page whose scroll view
        /// runs under the right-hand inspector gets the inspector's width as a safe area that SwiftUI does not carry into
        /// the scroll view's insets, so the table would keep the width it had before the inspector opened or closed. And
        /// a table starts at its columns' ideal widths, which can add up to more than the page. Fitting the columns to the
        /// available width gives the last the remainder, within every column's minimum and maximum, so the table scrolls
        /// sideways only where the minimums do not fit. A fit waits for the mouse to be up, so it does not undo a column
        /// a person is dragging, and happens again only when the width or the columns change.
        ///
        /// A table that keeps its widths is never fitted: AppKit would give every column a new width when a column is
        /// shown or hidden or the page changes, and the table writes each one to the stored layout, over the widths the
        /// person set. It gets no column autoresizing at all, so a width changes only by a drag of a divider.
        private func fit(_ table: NSTableView, in scrollView: NSScrollView) {
            let safeRight = scrollView.safeAreaInsets.right
            if abs(scrollView.contentInsets.right - safeRight) > 0.5 { scrollView.contentInsets.right = safeRight }
            if keepsWidths {
                if table.columnAutoresizingStyle != .noColumnAutoresizing { table.columnAutoresizingStyle = .noColumnAutoresizing }
                return
            }
            let insets = scrollView.contentInsets
            let width = scrollView.contentView.bounds.width - insets.left - insets.right
            let key = "\(Int(width))|" + table.tableColumns.map(\.identifier.rawValue).joined(separator: ",")
            guard key != fittedTo, NSEvent.pressedMouseButtons == 0 else { return }
            fittedTo = key
            table.sizeToFit()
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
/// looks the same whichever window is key and hides the rows that scroll under it. It draws each column's title and,
/// after it, the sort mark of the column the table is sorted by, through `QuietHeaderCell`, and one line under the
/// columns, from where the first column starts to where the rows' separators end.
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
            cell.sortDirection = isSorted ? sorted.map { $0.ascending ? .ascending : .descending } : nil
            cell.draw(withFrame: frame, in: self)
        }
        guard let first = table.tableColumns.indices.first, let last = table.tableColumns.indices.last else { return }
        // A row's separator runs the row's width less the table's inset and 6 points at each end, which is neither
        // where the first column starts nor where the last one ends: a last column that has reached its widest, or any
        // column of a table that keeps its widths, stops short of the row, and one fitted to the page can run past it.
        // So the line ends where the rows' separators do,
        // and at the last column's edge only while no row shows.
        let tableInset = headerRect(ofColumn: first).minX
        let start = tableInset + 6
        var end = headerRect(ofColumn: last).maxX - 6
        let visible = table.rows(in: table.visibleRect)
        if visible.length > 0, let row = table.rowView(atRow: visible.location, makeIfNecessary: false) {
            end = row.frame.maxX - (tableInset - row.frame.minX) - 6
        }
        let thickness = 1 / (window?.backingScaleFactor ?? 2)
        NSColor.separatorColor.setFill()
        NSRect(x: start, y: isFlipped ? bounds.maxY - thickness : bounds.minY, width: end - start, height: thickness).fill()
    }
}

/// A column heading's cell, drawn without the separators and the bottom line AppKit draws with it, in the font of the
/// New row's label (callout, medium) and the secondary color, whether or not its column is the sorted one. The sort
/// indicator follows the title, wherever the column aligns it, so every table's reads the same.
private final class QuietHeaderCell: NSTableHeaderCell {
    static let headingFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let bottomLine: CGFloat = 3
    /// The room a column keeps between its edge and its content, which a heading shares with its cells.
    private static let edge: CGFloat = 6
    /// The room a right-aligned heading keeps after its title, which is the room its column's numbers keep after theirs
    /// (`IndexMetrics.countRoom`) on top of the column's own.
    static let trailingRoom: CGFloat = 20
    private static let indicatorGap: CGFloat = 3
    private static let indicatorFont = NSFont.systemFont(ofSize: 9, weight: .semibold)

    enum Direction { case ascending, descending }

    /// Which way the table is sorted by this column, if it is.
    var sortDirection: Direction?

    /// The mark after the title, which AppKit draws at the cell's far edge instead.
    private func indicator() -> NSImage? {
        guard let sortDirection else { return nil }
        let name = sortDirection == .ascending ? "chevron.up" : "chevron.down"
        let configuration = NSImage.SymbolConfiguration(pointSize: Self.indicatorFont.pointSize, weight: .semibold)
            .applying(.init(paletteColors: [.secondaryLabelColor]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }

    /// AppKit draws a header cell's title in its own white whatever `textColor` and `attributedStringValue` say, so the
    /// cell draws the title itself, in its font and the secondary color, level with where AppKit puts it.
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let title = NSAttributedString(
            string: stringValue,
            attributes: [.font: Self.headingFont, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style])
        let area = titleRect(forBounds: cellFrame)
        let size = title.size()
        let mark = indicator()
        let markWidth = mark.map { $0.size.width + Self.indicatorGap } ?? 0
        let available = max(0, cellFrame.width - Self.edge - (alignment == .right ? Self.trailingRoom : Self.edge))
        let titleWidth = min(ceil(size.width), max(0, available - markWidth))
        let total = titleWidth + markWidth
        let left = alignment == .right ? cellFrame.maxX - Self.trailingRoom - total : cellFrame.minX + Self.edge
        title.draw(in: NSRect(x: left, y: area.midY - size.height / 2, width: titleWidth, height: size.height))
        if let mark {
            let origin = NSPoint(x: left + titleWidth + Self.indicatorGap, y: area.midY - mark.size.height / 2)
            mark.draw(in: NSRect(origin: origin, size: mark.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
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
