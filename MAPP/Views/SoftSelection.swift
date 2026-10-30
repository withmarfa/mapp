import AppKit
import SwiftUI

extension View {
    /// Selects in a soft grey mark, inset and rounded, the same whether or not the window is active, in place of
    /// the system's accent fill, which reads as too loud across a whole list. Apply it to a `List` or `Table`,
    /// with `rows`, the identifiers it shows, and `selection`, so the marks follow rows that move and every change
    /// of selection, however it is made. The selection is read by the marks alone, so a change of selection does not
    /// run the body of the view that holds the list, which would have the list look at every row again.
    func softSelection(rows: some Hashable, selection: @escaping () -> some Hashable) -> some View {
        background(SoftSelectionReader(rows: rows.hashValue, selection: selection))
    }
}

private struct SoftSelectionReader<Selection: Hashable>: View {
    let rows: Int
    let selection: () -> Selection

    var body: some View { SoftSelection(rows: rows, selection: selection().hashValue) }
}

/// SwiftUI cannot style a list's selection, which the `NSTableView` behind it draws. This finds that table, turns
/// its highlight off, so rows keep their own text colors, and draws the selected rows' marks beneath them.
struct SoftSelection: NSViewRepresentable {
    let rows: Int
    let selection: Int

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ probe: Probe, context: Context) { probe.refresh(rows: rows, selection: selection) }
    static func dismantleNSView(_ probe: Probe, coordinator: ()) { probe.dismantle() }

    final class Probe: NSView {
        private weak var table: NSTableView?
        private weak var marks: Marks?
        private var originalHighlightStyle: NSTableView.SelectionHighlightStyle?
        private var isDismantled = false
        /// The rows and selection the marks were last asked to follow, so an update SwiftUI makes for any other
        /// reason leaves them alone.
        private var seen: Followed?

        private struct Followed: Equatable {
            let rows: Int
            let selection: Int
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Looked for at once, since turning the highlight off reloads every row the table has made, and a
            // table that is already filled is built twice. The table may not be in the window yet, so it is looked
            // for again once the pass is done.
            refresh()
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            // A list the window has just mounted gets its table in this pass, and its first frame should not show
            // the system's highlight for the turn it takes the soft marks to arrive.
            if !isDismantled, window != nil, table == nil { attach() }
        }

        func refresh(rows: Int? = nil, selection: Int? = nil) {
            guard !isDismantled, window != nil else { return }
            if table == nil || table?.window !== window {
                attach()
                seen = nil
            }
            // SwiftUI may set the highlight again as it updates the table.
            if let table, table.selectionHighlightStyle != .none { table.selectionHighlightStyle = .none }
            if let rows, let selection {
                let followed = Followed(rows: rows, selection: selection)
                guard followed != seen else { return }
                seen = followed
            }
            // SwiftUI hands the table its new selection after this update, and its notification then asks again.
            marks?.setNeedsUpdate()
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
    }

    /// One rounded layer for each selected row, beneath the row views, kept in step with the table's selection.
    final class Marks: NSView {
        private weak var table: NSTableView?
        private var observers: [NSObjectProtocol] = []
        /// The selected rows' views, which post when their own frames change (see `follow`).
        private var followed: [ObjectIdentifier: (view: Weak<NSTableRowView>, observer: NSObjectProtocol)] = [:]
        private var isUpdatePending = false
        /// Where the marks are and in what color, so a pass that finds them already there places nothing.
        private var placed: (frames: [NSRect], color: CGColor)?
        /// How many rows beyond the visible ones are marked.
        private static let overscan = 10

        final class Weak<Object: AnyObject> {
            weak var object: Object?
            init(_ object: Object) { self.object = object }
        }

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
                        // The mark is in place before the next frame; whatever the pass settles after it is caught
                        // by the one deferred look.
                        self?.update()
                        self?.setNeedsUpdate()
                    }
                })
            }
            table.postsFrameChangedNotifications = true
            // Rows scrolled into view get row views of their own, which the marks are placed by.
            if let clip = table.enclosingScrollView?.contentView {
                clip.postsBoundsChangedNotifications = true
                observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.setNeedsUpdate() }
                })
            }
        }

        required init?(coder: NSCoder) { nil }

        isolated deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
            followed.values.forEach { NotificationCenter.default.removeObserver($0.observer) }
        }

        func detach() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            followed.values.forEach { NotificationCenter.default.removeObserver($0.observer) }
            followed.removeAll()
            table = nil
        }

        /// Asks for the marks to be placed once the current pass is done, however many things ask before it: a
        /// click, SwiftUI's update and the table's own notification all land in one pass and make one placing. The
        /// table's selection and its row views settle after the first of them, and an outline's disclosure moves
        /// its row views after its notification.
        func setNeedsUpdate() {
            guard !isUpdatePending else { return }
            isUpdatePending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                isUpdatePending = false
                update()
            }
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
            // Only the rows in view get a mark, with a few either side so a scroll never shows a bare row: Select All
            // on a long list selects every row, and a layer for each would be made again after every scroll, which
            // also updates the marks.
            let shown = table.rows(in: table.visibleRect)
            let last = min(table.numberOfRows, shown.location + shown.length + Self.overscan)
            let nearby = IndexSet(integersIn: min(max(0, shown.location - Self.overscan), last)..<last)
            rows = rows.intersection(nearby)
            var views: [NSTableRowView] = []
            var frames: [NSRect] = []
            for row in rows where row < table.numberOfRows {
                if let view = table.rowView(atRow: row, makeIfNecessary: false) { views.append(view) }
                frames.append(Self.rect(ofRow: row, in: table))
            }
            follow(views)
            if let placed, placed.frames == frames, placed.color == color { return }
            placed = (frames, color)
            Cost.measure(.softSelection) {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.sublayers?.forEach { $0.removeFromSuperlayer() }
                for frame in frames {
                    let mark = CALayer()
                    mark.frame = frame
                    mark.backgroundColor = color
                    mark.cornerRadius = 8
                    mark.cornerCurve = .continuous
                    layer.addSublayer(mark)
                }
                CATransaction.commit()
            }
        }

        /// A selected row that grows or shrinks, or moves under one that does, changes no frame but its own row
        /// view's: the table's frame stays put while it has room, and no selection or row identifier changes. So
        /// the marks listen to the selected rows' views alone, never to every view in the app.
        private func follow(_ views: [NSTableRowView]) {
            let center = NotificationCenter.default
            let ids = Set(views.map(ObjectIdentifier.init))
            for (id, entry) in followed where !ids.contains(id) || entry.view.object == nil {
                center.removeObserver(entry.observer)
                followed[id] = nil
            }
            for view in views {
                let id = ObjectIdentifier(view)
                if let entry = followed[id] {
                    if entry.view.object === view { continue }
                    center.removeObserver(entry.observer)
                }
                view.postsFrameChangedNotifications = true
                let observer = center.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.setNeedsUpdate() }
                }
                followed[id] = (Weak(view), observer)
            }
        }

        /// Where the system draws a selection: a shape inset from both edges, as Finder's sidebar has it. A source
        /// list's row view spans the whole column, so it is inset here as the system inset does.
        private static func rect(ofRow row: Int, in table: NSTableView) -> NSRect {
            let frame = table.rowView(atRow: row, makeIfNecessary: false)?.frame ?? table.rect(ofRow: row)
            switch table.style {
            case .sourceList: return frame.insetBy(dx: 10, dy: 1)
            case .inset: return frame.insetBy(dx: 10, dy: 0)
            default: return frame
            }
        }
    }
}

extension NSView {
    /// The table a background view sits behind: the first, going outwards, whose scroll view covers the view's centre.
    func nearestTable() -> NSTableView? {
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

    static func tables(in view: NSView) -> [NSTableView] {
        view.subviews.flatMap { subview in
            (subview as? NSTableView).map { [$0] } ?? tables(in: subview)
        }
    }
}
