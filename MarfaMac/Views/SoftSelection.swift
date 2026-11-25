import AppKit
import SwiftUI

extension View {
    /// Selects in a soft grey mark, inset and rounded, the same whether or not the window is active, in place of
    /// the system's accent fill, which reads as too loud across a whole list. Apply it to a `List` or `Table`,
    /// with `rows`, the identifiers it shows, and `selection`, so the marks follow rows that move and every change
    /// of selection, however it is made. The selection is read by the marks alone, so a change of selection does not
    /// run the body of the view that holds the list, which would have the list look at every row again. With
    /// `hovers`, the row under the pointer gets a fainter mark of its own, drawn and followed by the same layer view
    /// from the table's mouse events, so that mark runs no row's body. `inert` names the rows, by their place in the
    /// table, that the pointer passes over without a mark: a heading, which a click does nothing to.
    func softSelection(
        rows: some Hashable, hovers: Bool = false, inert: Set<Int> = [], selection: @escaping () -> some Hashable
    ) -> some View {
        background(SoftSelectionReader(rows: rows.hashValue, hovers: hovers, inert: inert, selection: selection))
    }
}

private struct SoftSelectionReader<Selection: Hashable>: View {
    let rows: Int
    let hovers: Bool
    let inert: Set<Int>
    let selection: () -> Selection

    var body: some View { SoftSelection(rows: rows, hovers: hovers, inert: inert, selection: selection().hashValue) }
}

/// SwiftUI cannot style a list's selection, which the `NSTableView` behind it draws. This finds that table, turns
/// its highlight off, so rows keep their own text colors, and draws the selected rows' marks beneath them.
struct SoftSelection: NSViewRepresentable {
    let rows: Int
    let hovers: Bool
    let inert: Set<Int>
    let selection: Int

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.hovers = hovers
        probe.inert = inert
        return probe
    }
    func updateNSView(_ probe: Probe, context: Context) {
        probe.hovers = hovers
        probe.inert = inert
        probe.refresh(rows: rows, selection: selection)
    }
    static func dismantleNSView(_ probe: Probe, coordinator: ()) { probe.dismantle() }

    final class Probe: NSView {
        private weak var table: NSTableView?
        private weak var marks: Marks?
        private var originalHighlightStyle: NSTableView.SelectionHighlightStyle?
        private var isDismantled = false
        var hovers = false
        /// The rows the pointer leaves unmarked, set on the marks as they come and whenever it changes.
        var inert: Set<Int> = [] {
            didSet { marks?.inert = inert }
        }
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
            let marks = Marks(table: table, hovers: hovers)
            marks.inert = inert
            // One set of marks to a table: a second would draw the chosen gray twice over.
            table.subviews.compactMap { $0 as? Marks }.forEach { $0.detach(); $0.removeFromSuperview() }
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
        /// The mark under the pointer, when rows have one, and whether the pointer is over the table.
        private let hoverMark: CALayer?
        private var pointerIsOver = false
        private var placedHover: (frame: NSRect?, color: CGColor)?
        /// The rows the pointer gets no mark on. SwiftUI's table answers nothing to `shouldSelectRow` for a row it will
        /// not select, so the lists name their headings themselves.
        var inert: Set<Int> = [] {
            didSet { if inert != oldValue { updateHover(forced: true) } }
        }
        /// The row the pointer was last over and the appearance the mark was colored for, so a move inside one row
        /// asks nothing further.
        private var lastHover: (row: Int, appearance: NSAppearance.Name)?
        /// How many rows beyond the visible ones are marked.
        private static let overscan = 10

        final class Weak<Object: AnyObject> {
            weak var object: Object?
            init(_ object: Object) { self.object = object }
        }

        init(table: NSTableView, hovers: Bool) {
            self.table = table
            hoverMark = hovers ? CALayer() : nil
            super.init(frame: table.bounds)
            autoresizingMask = [.width, .height]
            wantsLayer = true
            if let hoverMark {
                hoverMark.cornerRadius = 8
                hoverMark.cornerCurve = .continuous
                hoverMark.isHidden = true
                layer?.addSublayer(hoverMark)
                addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
            }
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
            // A window that is no longer key, as when a sheet or another window takes over, sends no event to say
            // the pointer has gone, and its mark would stay on the last row.
            if let window = table.window {
                observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.pointerIsOver = false
                        self?.updateHover()
                    }
                })
            }
            // Rows scrolled into view get row views of their own, which the marks are placed by.
            if let clip = table.enclosingScrollView?.contentView {
                clip.postsBoundsChangedNotifications = true
                observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.setNeedsUpdate()
                        self?.updateHover()
                    }
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

        override func mouseEntered(with event: NSEvent) {
            pointerIsOver = true
            updateHover()
        }

        override func mouseMoved(with event: NSEvent) {
            pointerIsOver = true
            updateHover()
        }

        override func mouseExited(with event: NSEvent) {
            pointerIsOver = false
            updateHover()
        }

        /// Puts the faint mark on the row under the pointer: not on a row that is chosen, which has its own, nor on
        /// one that is `inert`, such as a heading. Nothing is asked or placed while the pointer stays on the
        /// same row, since a move inside a row is most of the events; a change of selection asks again, with `forced`.
        /// The pointer counts only where the table is what shows there: an overlay above it, such as the command
        /// palette, leaves the table's rows unhovered.
        private func updateHover(forced: Bool = false) {
            guard let hoverMark, let table else { return }
            var row = -1
            if pointerIsOver, let window, isTableShown(at: window.mouseLocationOutsideOfEventStream, in: window) {
                row = table.row(at: table.convert(window.mouseLocationOutsideOfEventStream, from: nil))
            }
            let appearance = effectiveAppearance.name
            if !forced, let lastHover, lastHover.row == row, lastHover.appearance == appearance { return }
            lastHover = (row, appearance)
            if row >= 0, table.isRowSelected(row) || table.rowView(atRow: row, makeIfNecessary: false)?.isSelected == true { row = -1 }
            if inert.contains(row) { row = -1 }
            let frame = row >= 0 ? Self.rect(ofRow: row, in: table) : nil
            let color = SelectionLooks.layerColor(SelectionLooks.hoverOpacity, in: effectiveAppearance)
            if let placedHover, placedHover.frame == frame, placedHover.color == color { return }
            placedHover = (frame, color)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hoverMark.isHidden = frame == nil
            if let frame {
                hoverMark.frame = frame
                hoverMark.backgroundColor = color
            }
            CATransaction.commit()
        }

        /// Whether the view at a point in the window, as a click there would find it, is the table or inside it.
        private func isTableShown(at point: NSPoint, in window: NSWindow) -> Bool {
            guard let table, let content = window.contentView, let frameView = content.superview,
                  let hit = content.hitTest(frameView.convert(point, from: nil)) else { return false }
            return hit.isDescendant(of: table)
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            update()
        }

        /// The layers that mark chosen rows, not the one under the pointer.
        var selectionLayers: [CALayer] { layer?.sublayers?.filter { $0 !== hoverMark } ?? [] }

        func update() {
            guard let table, let layer else { return }
            let color = SelectionLooks.layerColor(SelectionLooks.chosenOpacity, in: effectiveAppearance)
            // The table's selection, and any row view it marks as selected, since SwiftUI can set either first.
            updateHover(forced: true)
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
                selectionLayers.forEach { $0.removeFromSuperlayer() }
                for frame in frames {
                    let mark = CALayer()
                    mark.frame = frame
                    mark.backgroundColor = color
                    mark.cornerRadius = 8
                    mark.cornerCurve = .continuous
                    layer.insertSublayer(mark, at: 0)
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
