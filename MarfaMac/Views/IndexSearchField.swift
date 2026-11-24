import AppKit
import SwiftUI

/// The system's search field for an index page's header: white, a hairline edge, a capsule at 28 points, with the
/// magnifier and the clear button drawn by AppKit. SwiftUI's `searchable` places a field only in a toolbar or a sidebar,
/// so a field inside a page is an `NSSearchField`. It takes the keyboard each time it opens, Escape or an empty field
/// that has lost the keyboard closes it, and Down Arrow hands the keyboard to the list.
struct IndexSearchField: NSViewRepresentable {
    @Environment(\.interfaceTextSize) private var textSize
    @Binding var text: String
    let prompt: String
    /// Asks, each time it changes, for the field to take the keyboard again.
    let focusRequests: Int
    let onDown: () -> Void
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.controlSize = .large
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier("ColumnSearch")
        field.onClickElsewhere = { [weak coordinator = context.coordinator] in coordinator?.parent.onEnd() }
        update(field)
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        update(field)
        if context.coordinator.focusRequests != focusRequests {
            context.coordinator.focusRequests = focusRequests
            field.takeKeyboard()
        }
    }

    private func update(_ field: Field) {
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = prompt
        field.font = InterfaceStyle.font(.body, textSize: textSize)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: Field, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 240, height: field.intrinsicContentSize.height)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: IndexSearchField
        var focusRequests: Int

        init(parent: IndexSearchField) {
            self.parent = parent
            focusRequests = parent.focusRequests
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField, parent.text != field.stringValue else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)): parent.onDown()
            case #selector(NSResponder.cancelOperation(_:)): parent.onEnd()
            default: return false
            }
            return true
        }

        // Left empty, the field goes back to being a button.
        func controlTextDidEndEditing(_ notification: Notification) {
            if parent.text.isEmpty { parent.onEnd() }
        }
    }

    final class Field: NSSearchField {
        /// Set until the field has had the keyboard once.
        private var isAwaitingKeyboard = true
        /// Called once a click has landed outside the field while it was open and empty: the field editor keeps the
        /// keyboard through a click on a background that cannot take it, so the field never hears that the person moved on.
        var onClickElsewhere: () -> Void = {}
        private var monitor: Any?

        isolated deinit { removeMonitor() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                MainActor.assumeIsolated { self?.watch(event) }
                return event
            }
            if isAwaitingKeyboard { takeKeyboard() }
        }

        func takeKeyboard() {
            isAwaitingKeyboard = true
            // The page finishes placing the field after this returns; asked any sooner, the window keeps the keyboard.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window, self.isAwaitingKeyboard else { return }
                if window.makeFirstResponder(self) { self.isAwaitingKeyboard = false }
            }
        }

        private func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func watch(_ event: NSEvent) {
            guard event.window != nil, event.window === window, let editor = currentEditor() as? NSTextView, editor.string.isEmpty,
                  let content = window?.contentView else { return }
            let point = content.convert(event.locationInWindow, from: nil)
            guard let hit = content.hitTest(point), !hit.isDescendant(of: self) else { return }
            DispatchQueue.main.async { [weak self] in
                if let self, (self.currentEditor() as? NSTextView)?.string.isEmpty == true { self.onClickElsewhere() }
            }
        }
    }
}
