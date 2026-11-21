import AppKit
import SwiftUI

extension View {
    /// Ends editing when the window is clicked anywhere outside the field being edited, as a Mac field does in the system's own
    /// windows: the field gives up focus, so a value typed and left is kept. It is set once for the whole window.
    func settingsClickOutsideEndsEditing() -> some View {
        background(EndEditingWatch())
    }
}

private struct EndEditingWatch: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ probe: Probe, context: Context) {}

    static func dismantleNSView(_ probe: Probe, coordinator: ()) { probe.stop() }

    final class Probe: NSView {
        private var token: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            token = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                MainActor.assumeIsolated { self?.endEditing(for: event) }
                return event
            }
        }

        func stop() {
            if let token { NSEvent.removeMonitor(token) }
            token = nil
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func endEditing(for event: NSEvent) {
            guard let window, event.window === window, let editor = window.firstResponder as? NSTextView, editor.isFieldEditor else { return }
            let owner = editor.delegate as? NSView
            guard let hit = window.contentView?.superview?.hitTest(event.locationInWindow) else { return }
            if hit.isDescendant(of: editor) || owner.map({ hit.isDescendant(of: $0) }) == true { return }
            window.makeFirstResponder(nil)
        }
    }
}
