import AppKit
import SwiftUI

/// The window a view is in, for a step SwiftUI has no way to take: bringing that window forward, as an item link does.
@MainActor final class WindowHandle {
    fileprivate(set) weak var window: NSWindow?

    /// Shows the window in front of the app's others and makes it key, bringing it back from the Dock first.
    func bringForward() {
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }
}

extension View {
    /// Keeps `handle` naming the window this view is in.
    func windowHandle(_ handle: WindowHandle) -> some View {
        background(WindowHandleProbe(handle: handle))
    }
}

private struct WindowHandleProbe: NSViewRepresentable {
    let handle: WindowHandle

    func makeNSView(context: Context) -> Probe { Probe(handle: handle) }
    func updateNSView(_ probe: Probe, context: Context) {}

    final class Probe: NSView {
        private let handle: WindowHandle

        init(handle: WindowHandle) {
            self.handle = handle
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            handle.window = window
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
