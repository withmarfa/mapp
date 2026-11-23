import SwiftUI

/// Holds the view a value editor opens under, which the row's SwiftUI body cannot reach.
@MainActor
final class ValueEditAnchorBox {
    weak var view: NSView?
}

/// A view laid behind a value, the width of the value column, for its editor to open under. It takes no clicks, and
/// closes the editor when it leaves its window.
struct ValueEditAnchor: NSViewRepresentable {
    let box: ValueEditAnchorBox

    func makeNSView(context: Context) -> NSView {
        let view = AnchorView()
        box.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        box.view = view
    }

    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        ValueEditPresenter.shared.anchorLeft(view)
    }

    private final class AnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { ValueEditPresenter.shared.anchorLeft(self) }
        }
    }
}
