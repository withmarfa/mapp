import AppKit
import SwiftUI

extension View {
    /// Draws a `Table`'s column headings the same whether or not the window is the key one, without the lines AppKit
    /// puts between them and with one line under them, from where the first column's cells start to where the last
    /// one's end, which is where the rows' separators run. The columns still resize by their edges, reorder by dragging
    /// and sort by a click. SwiftUI cannot style the header the `NSTableView` behind a `Table` draws, so this gives the
    /// table a header view that draws every column's heading itself. The headings are drawn over the table's own
    /// background, or over `backdrop` where the table has none, so rows that scroll under them do not show through. The
    /// same view fits the table to its page, respecting any widths the person set (`Probe.fit`).
    func quietTableHeader(backdrop: NSColor = .windowBackgroundColor, resizing: ColumnResizing? = nil) -> some View {
        background(QuietTableHeader(backdrop: backdrop, resizing: resizing))
    }
}

/// Whether a person is dragging a column's divider in a table's header. A table that keeps its column widths stores
/// one only then: AppKit also gives columns new widths of its own when the table is first laid out and whenever its
/// size or columns change, and those are not the person's.
///
/// AppKit has also refitted the columns by the time this view can first see the table, so it puts each shown column back
/// to the width it should have (`widths`, in the order of the columns shown) as it stops the table's autoresizing.
@MainActor
final class ColumnResizing {
    fileprivate weak var header: NSTableHeaderView?
    /// The width each shown column starts at: the one the person kept, or the column's ideal.
    var widths: [CGFloat] = [] {
        didSet { if widths != oldValue { widthsChanged?() } }
    }

    /// Which shown column takes what the others leave of the table's width, nil where none does: the name, until a person
    /// drags its divider. It never goes under `flexibleMinimum`, and the table scrolls sideways only past that.
    var flexible: Int?
    var flexibleMinimum: CGFloat = 0

    /// Called when `widths` change, as when the table moves to a place with other widths. Nothing else tells the header
    /// that the same table has another place to start at.
    fileprivate var widthsChanged: (() -> Void)?

    var isDragging: Bool { (header?.resizedColumn ?? -1) >= 0 }

    /// The starting widths and shown columns last applied, so a change of place or of stored widths is applied once, and
    /// the same table moving to a place with other widths never keeps the last place's.
    private var applied: (widths: [CGFloat], columns: [NSUserInterfaceItemIdentifier])?

    /// Gives the flexible column the width the others leave in the table, so the columns fill the table and none is cut off
    /// by it while the name can give way.
    fileprivate func fill(_ table: NSTableView, in scrollView: NSScrollView) {
        guard !isDragging, let flexible else { return }
        let shown = table.tableColumns.filter { !$0.isHidden }
        guard shown.indices.contains(flexible), shown.count == widths.count, let first = table.tableColumns.firstIndex(of: shown[0]) else { return }
        let insets = scrollView.contentInsets
        // The table keeps the inset style's room before its first column and the same after its last.
        let room = 2 * table.rect(ofColumn: first).minX
        let available = scrollView.contentView.bounds.width - insets.left - insets.right - room
        let others = shown.enumerated().reduce(CGFloat(0)) { $0 + ($1.offset == flexible ? 0 : $1.element.width) }
        let target = max(flexibleMinimum, floor(available - others - table.intercellSpacing.width * CGFloat(shown.count)))
        let column = shown[flexible]
        if abs(column.width - target) >= 1 { column.width = target }
    }

    /// Answers false while the table's shown columns are not yet the ones `widths` is for, as when SwiftUI replaces them
    /// after a change of place, so the caller tries again once they are.
    fileprivate func restore(_ table: NSTableView) -> Bool {
        guard !isDragging else { return true }
        let shown = table.tableColumns.filter { !$0.isHidden }
        guard shown.count == widths.count else { return false }
        let columns = shown.map(\.identifier)
        if let applied, applied.widths == widths, applied.columns == columns { return true }
        applied = (widths, columns)
        for (column, width) in zip(shown, widths) where column.width != width { column.width = width }
        return true
    }
}

private struct QuietTableHeader: NSViewRepresentable {
    let backdrop: NSColor
    let resizing: ColumnResizing?

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ probe: Probe, context: Context) {
        probe.backdrop = backdrop
        probe.resizing = resizing
        probe.refresh()
    }

    final class Probe: NSView {
        var backdrop = NSColor.windowBackgroundColor
        var resizing: ColumnResizing?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { stopWatching() }
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
            resizing?.header = table.headerView
            resizing?.widthsChanged = { [weak self] in self?.restoreAfterChange() }
            if let scrollView = table.enclosingScrollView {
                watch(scrollView)
                fit(table, in: scrollView)
            }
            table.headerView?.needsDisplay = true
        }

        private weak var watched: NSScrollView?
        private var watching: (any NSObjectProtocol)?

        /// Fits the columns again when the page the table sits in changes size, which this view's own layout does not always
        /// follow: a window made narrower leaves the flexible column as wide as it was.
        private func watch(_ scrollView: NSScrollView) {
            guard watched !== scrollView else { return }
            if let watching { NotificationCenter.default.removeObserver(watching) }
            watched = scrollView
            scrollView.postsFrameChangedNotifications = true
            watching = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification, object: scrollView, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        }

        private func stopWatching() {
            if let watching { NotificationCenter.default.removeObserver(watching) }
            watching = nil
            watched = nil
        }

        /// The width and columns the table was last fitted to.
        private var fittedTo: String?
        /// How many times the table's columns have been waited for, to match the widths it should start at.
        private var restoreTries = 0

        /// The widths the table starts at changed during a pass of SwiftUI, which has not yet given the table its columns.
        /// The header looks again on the next pass of the run loop, and waits for the columns from there.
        private func restoreAfterChange() {
            restoreTries = 0
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }

        /// Makes the table as wide as the page it sits in, and keeps it so as that width changes. A page whose scroll view
        /// runs under the right-hand inspector gets the inspector's width as a safe area that SwiftUI does not carry into
        /// the scroll view's insets, so the table would keep the width it had before the inspector opened or closed. And
        /// a table starts at its columns' ideal widths, which can add up to more than the page. Fitting the columns to the
        /// available width gives the last the remainder, within every column's minimum and maximum, so the table scrolls
        /// sideways only where the minimums do not fit. A fit waits for the mouse to be up, so it does not undo a column
        /// a person is dragging, and happens again only when the width or the columns change.
        ///
        /// An item table restores fixed widths and fits the unset Name column to the space left (`ColumnResizing`).
        private func fit(_ table: NSTableView, in scrollView: NSScrollView) {
            let safeRight = scrollView.safeAreaInsets.right
            if abs(scrollView.contentInsets.right - safeRight) > 0.5 { scrollView.contentInsets.right = safeRight }
            if let resizing {
                if table.columnAutoresizingStyle != .noColumnAutoresizing { table.columnAutoresizingStyle = .noColumnAutoresizing }
                if resizing.restore(table) {
                    restoreTries = 0
                    resizing.fill(table, in: scrollView)
                } else if restoreTries < 50 {
                    restoreTries += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) { [weak self] in self?.refresh() }
                }
                return
            }
            let insets = scrollView.contentInsets
            let width = scrollView.contentView.bounds.width - insets.left - insets.right
            let key = "\(Int(width))|" + table.tableColumns.map(\.identifier.rawValue).joined(separator: ",")
            guard key != fittedTo, NSEvent.pressedMouseButtons == 0 else { return }
            fittedTo = key
            table.sizeToFit()
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

/// A column heading's cell, drawn without the separators and the bottom line AppKit draws with it, in the callout font,
/// medium, and the secondary color, whether or not its column is the sorted one. The sort
/// indicator follows the title, wherever the column aligns it, so every table's reads the same.
private final class QuietHeaderCell: NSTableHeaderCell {
    static let headingFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let bottomLine: CGFloat = 3
    /// The room a column keeps between its edge and its content, which a heading shares with its cells.
    private static let edge: CGFloat = 6
    /// The room a right-aligned heading keeps after its title, which is the room its column's numbers keep after theirs
    /// (`PlaceIndexMetrics.countRoom`) on top of the column's own.
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
