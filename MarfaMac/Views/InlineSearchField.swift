import AppKit
import SwiftUI

/// An `NSSearchField` for a page or sheet, where SwiftUI's `searchable` would place it in a toolbar or sidebar.
struct InlineSearchField: NSViewRepresentable {
    @Environment(\.interfaceTextSize) private var textSize
    @Binding var text: String
    let prompt: String
    let identifier: String
    /// Names the field's clear button for accessibility, where a page needs to reach it.
    var clearIdentifier: String?
    /// Asks, each time it changes, for the field to take the keyboard again.
    var focusRequests = 0
    let onDown: () -> Void
    var onUp: (() -> Void)?
    var onSubmit: (() -> Void)?
    let onCancel: () -> Void
    /// Closes a search that only stays open while it has focus or text.
    var onEnd: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.controlSize = .large
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier(identifier)
        field.setAccessibilityLabel(prompt)
        if let clearIdentifier { (field.cell as? NSSearchFieldCell)?.cancelButtonCell?.setAccessibilityIdentifier(clearIdentifier) }
        if onEnd != nil {
            field.onClickElsewhere = { [weak coordinator = context.coordinator] in coordinator?.parent.onEnd?() }
        }
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
        var parent: InlineSearchField
        var focusRequests: Int

        init(parent: InlineSearchField) {
            self.parent = parent
            focusRequests = parent.focusRequests
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField, parent.text != field.stringValue else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let action: (() -> Void)? = switch selector {
            case #selector(NSResponder.moveDown(_:)): parent.onDown
            case #selector(NSResponder.moveUp(_:)): parent.onUp
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel
            default: nil
            }
            guard let action else { return false }
            action()
            return true
        }

        // Left empty, the field goes back to being a button.
        func controlTextDidEndEditing(_ notification: Notification) {
            if parent.text.isEmpty { parent.onEnd?() }
        }
    }

    final class Field: NSSearchField {
        /// Set until the field has had the keyboard once.
        private var isAwaitingKeyboard = true
        /// Called once a click has finished that landed outside the field while it was open and empty: the field editor
        /// keeps the keyboard through a click on a background that cannot take it, so the field never hears that the
        /// person moved on.
        var onClickElsewhere: (() -> Void)?
        private var monitor: Any?
        private var isClickElsewhere = false

        isolated deinit { removeMonitor() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            if onClickElsewhere != nil { addMonitor() }
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

        // The click is left alone and acts as it would. The field closes once the mouse button is up, since the buttons
        // beside it move when it does, and a button that moved on mouse down would never be clicked.

        private func addMonitor() {
            let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp, .rightMouseUp, .otherMouseUp]
            monitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
                MainActor.assumeIsolated { self?.watch(event) }
                return event
            }
        }

        private func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            isClickElsewhere = false
        }

        private func watch(_ event: NSEvent) {
            guard event.window != nil, event.window === window else { return }
            switch event.type {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                isClickElsewhere = isOpenAndEmpty && !isOverField(event)
            case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                guard isClickElsewhere else { return }
                isClickElsewhere = false
                // After the click's own action, which may run as the event is delivered.
                DispatchQueue.main.async { [weak self] in
                    if let self, self.isOpenAndEmpty { self.onClickElsewhere?() }
                }
            default: break
            }
        }

        /// Whether the field has the keyboard and holds no text. A field that has handed the keyboard on has already
        /// closed itself (`controlTextDidEndEditing`).
        private var isOpenAndEmpty: Bool {
            guard let editor = currentEditor() as? NSTextView else { return false }
            return editor.string.isEmpty
        }

        /// Whether a click is on the field or its clear button. The window's frame view is hit, not its content view,
        /// so a click in the title bar counts as elsewhere.
        private func isOverField(_ event: NSEvent) -> Bool {
            guard let frame = window?.contentView?.superview,
                  let hit = frame.hitTest(frame.convert(event.locationInWindow, from: nil)) else { return false }
            return hit.isDescendant(of: self)
        }
    }
}
