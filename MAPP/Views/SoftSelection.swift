import AppKit
import SwiftUI

extension View {
    /// Selects in a soft grey mark, inset and rounded, the same whether or not the window is active, in place of
    /// the system's accent fill, which reads as too loud across a whole list. Apply it to a `List` or `Table`,
    /// with `rows`, the identifiers it shows, and `selection`, so the marks follow rows that move and every change
    /// of selection, however it is made.
    func softSelection(rows: some Hashable, selection: some Hashable) -> some View {
        background(SoftSelection(rows: rows.hashValue, selection: selection.hashValue))
    }
}

/// SwiftUI cannot style a list's selection, which the `NSTableView` behind it draws. This finds that table, turns
/// its highlight off, so rows keep their own text colors, and draws the selected rows' marks beneath them.
private struct SoftSelection: NSViewRepresentable {
    let rows: Int
    let selection: Int

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ probe: Probe, context: Context) { probe.refresh() }
    static func dismantleNSView(_ probe: Probe, coordinator: ()) { probe.dismantle() }

    final class Probe: NSView {
        private weak var table: NSTableView?
        private weak var marks: Marks?
        private var originalHighlightStyle: NSTableView.SelectionHighlightStyle?
        private var isDismantled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // The list's table joins the window in the same pass, so it is looked for once the pass is done.
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func refresh() {
            guard !isDismantled, window != nil else { return }
            if table == nil || table?.window !== window { attach() }
            // SwiftUI may set the highlight again as it updates the table.
            if let table, table.selectionHighlightStyle != .none { table.selectionHighlightStyle = .none }
            marks?.update()
            // SwiftUI hands the table its new selection after this update, so the marks look again once it has.
            DispatchQueue.main.async { [weak self] in self?.marks?.update() }
        }

        private func attach() {
            guard window != nil, let table = nearestTable() else { return }
            detach(restoringHighlight: true)
            self.table = table
            originalHighlightStyle = table.selectionHighlightStyle
            table.selectionHighlightStyle = .none
            let marks = Marks(table: table)
            table.addSubview(marks, positioned: .below, relativeTo: nil)
            self.marks = marks
        }

        func dismantle() {
            isDismantled = true
            // Restoring an outline's highlight reloads its rows. SwiftUI's row tree is already being removed.
            detach(restoringHighlight: false)
        }

        private func detach(restoringHighlight: Bool) {
            marks?.detach()
            marks?.removeFromSuperview()
            if restoringHighlight, let table, table.window != nil, let originalHighlightStyle {
                table.selectionHighlightStyle = originalHighlightStyle
            }
            table = nil
            marks = nil
            originalHighlightStyle = nil
        }

        /// The table this probe sits behind: the first, going outwards, whose scroll view covers the probe's centre.
        private func nearestTable() -> NSTableView? {
            let centre = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
            var ancestor = superview
            while let view = ancestor {
                if let table = Self.tables(in: view).first(where: { table in
                    let area = table.enclosingScrollView ?? table
                    return area.convert(area.bounds, to: nil).contains(centre)
                }) {
                    return table
                }
                ancestor = view.superview
            }
            return nil
        }

        private static func tables(in view: NSView) -> [NSTableView] {
            view.subviews.flatMap { subview in
                (subview as? NSTableView).map { [$0] } ?? tables(in: subview)
            }
        }
    }

    /// One rounded layer for each selected row, beneath the row views, kept in step with the table's selection.
    final class Marks: NSView {
        private weak var table: NSTableView?
        private var observers: [NSObjectProtocol] = []

        init(table: NSTableView) {
            self.table = table
            super.init(frame: table.bounds)
            autoresizingMask = [.width, .height]
            wantsLayer = true
            let center = NotificationCenter.default
            var changes = [NSTableView.selectionDidChangeNotification, NSView.frameDidChangeNotification]
            if table is NSOutlineView {
                changes += [NSOutlineView.selectionDidChangeNotification,
                            NSOutlineView.itemDidExpandNotification, NSOutlineView.itemDidCollapseNotification]
            }
            for name in Set(changes) {
                observers.append(center.addObserver(forName: name, object: table, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.update()
                        // Outline disclosure can finish moving its row views after the notification.
                        DispatchQueue.main.async { [weak self] in self?.update() }
                    }
                })
            }
            table.postsFrameChangedNotifications = true
            // Rows scrolled into view get row views of their own, which the marks are placed by.
            if let clip = table.enclosingScrollView?.contentView {
                clip.postsBoundsChangedNotifications = true
                observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.update() }
                })
            }
        }

        required init?(coder: NSCoder) { nil }

        isolated deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func detach() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            table = nil
        }

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            update()
        }

        func update() {
            guard let table, let layer else { return }
            var color = CGColor.clear
            effectiveAppearance.performAsCurrentDrawingAppearance {
                color = NSColor.labelColor.withAlphaComponent(0.08).cgColor
            }
            // The table's selection, and any row view it marks as selected, since SwiftUI can set either first.
            var rows = table.selectedRowIndexes
            table.enumerateAvailableRowViews { view, row in
                if view.isSelected { rows.insert(row) }
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.sublayers?.forEach { $0.removeFromSuperlayer() }
            for row in rows where row < table.numberOfRows {
                let mark = CALayer()
                mark.frame = Self.rect(ofRow: row, in: table)
                mark.backgroundColor = color
                mark.cornerRadius = 6
                mark.cornerCurve = .continuous
                layer.addSublayer(mark)
            }
            CATransaction.commit()
        }

        /// Where the system would have drawn the row's selection: the row view's frame where one is made, which an
        /// inset table already insets, otherwise the row inset as the inset style insets it.
        private static func rect(ofRow row: Int, in table: NSTableView) -> NSRect {
            if let view = table.rowView(atRow: row, makeIfNecessary: false) {
                return view.frame.insetBy(dx: table.style == .inset ? 10 : 0, dy: 0)
            }
            return table.rect(ofRow: row).insetBy(dx: table.style == .inset ? 10 : 0, dy: 0)
        }
    }
}
