import AppKit
import SwiftUI

extension View {
    /// Calls `action` with the widths of the split view's columns, from the first, each time the person drags one of its
    /// dividers. Apply it to the sidebar column, which every split view has. A width the layout itself produces never
    /// reaches `action`: SwiftUI gives a column only its ideal width when the split view is built, so a width is worth
    /// remembering only when the person chose it.
    func onSplitViewDividerDrag(perform action: @escaping ([CGFloat]) -> Void) -> some View {
        background(SplitViewDividerDrag(action: action))
    }
}

private struct SplitViewDividerDrag: NSViewRepresentable {
    let action: ([CGFloat]) -> Void

    func makeNSView(context: Context) -> DividerDragView { DividerDragView(action: action) }
    func updateNSView(_ view: DividerDragView, context: Context) { view.action = action }
}

final class DividerDragView: NSView {
    var action: ([CGFloat]) -> Void
    private var observation: NSObjectProtocol?

    /// Whether a divider is being dragged at this moment: the left button is down and the event being handled is its drag.
    /// A resize that layout causes happens with the button up.
    var isDragging: () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 && NSApp.currentEvent?.type == .leftMouseDragged }

    init(action: @escaping ([CGFloat]) -> Void) {
        self.action = action
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observation = nil
        guard window != nil, let split = enclosingSplitView else { return }
        observation = NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification, object: split, queue: .main
        ) { [weak self, weak split] _ in
            MainActor.assumeIsolated {
                guard let self, let split, self.isDragging() else { return }
                self.action(ColumnWidthTracker.columnWidths(rightEdges: split.arrangedSubviews.map(\.frame.maxX)))
            }
        }
    }

    private var enclosingSplitView: NSSplitView? {
        var view = superview
        while let current = view, !(current is NSSplitView) { view = current.superview }
        return view as? NSSplitView
    }
}
