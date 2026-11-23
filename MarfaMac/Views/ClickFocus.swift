import AppKit
import SwiftUI

extension View {
    /// Gives this list or table the keyboard when a click lands in it, through `take`, unless it already has it.
    /// A click on a SwiftUI list's row selects the row but leaves the keyboard where it was, with the window or the
    /// page, so Select All, Delete, Return and the arrow keys would not reach the list that was clicked.
    func takesKeyboardOnClick(_ take: @escaping () -> Void) -> some View {
        background(ClickFocus(take: take))
    }
}

private struct ClickFocus: NSViewRepresentable {
    let take: () -> Void

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ probe: Probe, context: Context) { probe.take = take }
    static func dismantleNSView(_ probe: Probe, coordinator: ()) { probe.stopWatching() }

    final class Probe: NSView {
        var take: (() -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopWatching()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.clicked(event)
                return event
            }
        }

        func stopWatching() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// Looked for at each click, since SwiftUI may replace the table as the list changes.
        private func clicked(_ event: NSEvent) {
            guard let window, event.window === window, let table = nearestTable(),
                  let area = table.enclosingScrollView, let frame = window.contentView?.superview,
                  frame.hitTest(event.locationInWindow)?.isDescendant(of: area) == true
            else { return }
            // Once the click has been handled, so a click that does give the table the keyboard asks for nothing.
            DispatchQueue.main.async { [weak self, weak table] in
                guard let self, let table, let window = table.window else { return }
                let responder = window.firstResponder as? NSView
                if responder === table || responder?.isDescendant(of: table) == true { return }
                take?()
            }
        }
    }
}
