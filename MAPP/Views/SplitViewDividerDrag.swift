import AppKit
import SwiftUI

extension View {
    /// Calls `action` with the widths of the split view's columns, from the first, each time the person drags one of its
    /// dividers. Apply it to the sidebar column, which every split view has. A width the layout itself produces never
    /// reaches `action`: SwiftUI gives a column only its ideal width when the split view is built, so a width is worth
    /// remembering only when the person chose it.
    ///
    /// `placing` gives the widths the columns before the detail should have; the split view is set to them once, after
    /// its first layout. SwiftUI applies a column's ideal width only to the first split view a window builds, so one
    /// rebuilt when the workspace changes would otherwise open its columns at their minimum.
    func onSplitViewDividerDrag(placing widths: @escaping () -> [CGFloat], perform action: @escaping ([CGFloat]) -> Void) -> some View {
        background(SplitViewDividerDrag(widths: widths, action: action))
    }
}

private struct SplitViewDividerDrag: NSViewRepresentable {
    let widths: () -> [CGFloat]
    let action: ([CGFloat]) -> Void

    func makeNSView(context: Context) -> DividerDragView { DividerDragView(widths: widths, action: action) }
    func updateNSView(_ view: DividerDragView, context: Context) {
        view.widths = widths
        view.action = action
    }
}

final class DividerDragView: NSView {
    var action: ([CGFloat]) -> Void
    var widths: () -> [CGFloat]
    private var observation: NSObjectProtocol?
    private var isPlacementPending = false

    /// Whether a divider is being dragged at this moment: the left button is down and the event being handled is its drag.
    /// A resize that layout causes happens with the button up.
    var isDragging: () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 && NSApp.currentEvent?.type == .leftMouseDragged }

    init(widths: @escaping () -> [CGFloat], action: @escaping ([CGFloat]) -> Void) {
        self.widths = widths
        self.action = action
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observation = nil
        guard window != nil, let split = enclosingSplitView else { return }
        isPlacementPending = true
        // Next turn of the run loop: the split view has had its first layout by then.
        DispatchQueue.main.async { [weak self, weak split] in
            guard let self, let split else { return }
            self.placeColumns(in: split)
        }
        observation = NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification, object: split, queue: .main
        ) { [weak self, weak split] _ in
            MainActor.assumeIsolated {
                guard let self, let split else { return }
                self.placeColumns(in: split)
                guard self.isDragging() else { return }
                self.action(ColumnWidthTracker.columnWidths(rightEdges: split.arrangedSubviews.map(\.frame.maxX)))
            }
        }
    }

    /// Sets the dividers to the wanted widths, once per split view. It waits for a layout with room to place them in,
    /// and never moves a divider the person is dragging.
    private func placeColumns(in split: NSSplitView) {
        guard isPlacementPending, split.bounds.width > 0, !isDragging() else { return }
        let items = split.arrangedSubviews
        let hidden = items.map { split.isSubviewCollapsed($0) || $0.isHidden || $0.frame.width == 0 }
        isPlacementPending = false
        for (index, position) in Self.dividerPositions(widths: widths(), hidden: hidden) where index < items.count - 1 {
            split.setPosition(position, ofDividerAt: index)
        }
    }

    /// The divider to set and where, for each visible column that has a wanted width, from the first. `hidden` holds one
    /// entry per item of the split view, the detail included. A hidden column takes no room and has no divider to set;
    /// the divider beside it is not touched.
    static func dividerPositions(widths: [CGFloat], hidden: [Bool]) -> [(index: Int, position: CGFloat)] {
        var edge: CGFloat = 0
        var positions: [(index: Int, position: CGFloat)] = []
        for (index, width) in widths.enumerated() where index < hidden.count - 1 && !hidden[index] {
            edge += width
            positions.append((index, edge))
        }
        return positions
    }

    private var enclosingSplitView: NSSplitView? {
        var view = superview
        while let current = view, !(current is NSSplitView) { view = current.superview }
        return view as? NSSplitView
    }
}
