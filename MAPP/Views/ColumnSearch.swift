import AppKit
import SwiftUI

/// Search in a list's column, as Mail keeps its own beside the list's buttons: a magnifying glass among them
/// until it is clicked, then a search field across the column in place of its title. Escape, or leaving the field
/// empty, puts it back. SwiftUI's own search field always goes to the window's end, so this is built here.
struct ColumnSearch<Leading: View>: ToolbarContent {
    @Binding var isExpanded: Bool
    @Binding var text: String
    let prompt: String
    /// The column's width, which the field spans, less the toolbar's margins; a toolbar item cannot tell.
    let columnWidth: CGFloat
    /// Asks, each time it changes, for an open field to take the keyboard again.
    var focusRequests = 0
    var onSubmit: () -> Void = {}
    /// Down Arrow in the field, which hands the keyboard to the list.
    var onDown: () -> Void = {}
    @ViewBuilder let leading: () -> Leading

    var body: some ToolbarContent {
        if isExpanded {
            ToolbarItem {
                ColumnSearchField(text: $text, prompt: prompt, focusRequests: focusRequests, onSubmit: onSubmit, onDown: onDown) {
                    text = ""
                    isExpanded = false
                }
                .frame(width: max(160, columnWidth - 40))
            }
        } else {
            ToolbarItemGroup {
                leading()
                Button("Search", systemImage: "magnifyingglass") { isExpanded = true }
                    .help("Search")
            }
        }
    }
}

/// The system search field, which takes the keyboard as it appears.
struct ColumnSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    let focusRequests: Int
    let onSubmit: () -> Void
    let onDown: () -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> FocusingSearchField {
        let field = FocusingSearchField()
        field.placeholderString = prompt
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier("ColumnSearch")
        return field
    }

    func updateNSView(_ field: FocusingSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = prompt
        if context.coordinator.focusRequests != focusRequests {
            context.coordinator.focusRequests = focusRequests
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: ColumnSearchField
        var focusRequests: Int

        init(parent: ColumnSearchField) {
            self.parent = parent
            focusRequests = parent.focusRequests
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEnd()
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
            case #selector(NSResponder.moveDown(_:)):
                parent.onDown()
            default:
                return false
            }
            return true
        }

        // Left empty, the field goes back to being a button.
        func controlTextDidEndEditing(_ notification: Notification) {
            if parent.text.isEmpty { parent.onEnd() }
        }
    }
}

final class FocusingSearchField: NSSearchField {
    private var hasAppeared = false

    // Once only: the toolbar moves its items between windows (full screen, Customize Toolbar, overflow), and an
    // open field should not take the keyboard from the page each time.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !hasAppeared else { return }
        hasAppeared = true
        // The toolbar places the field once this returns; asked any sooner, the window keeps the keyboard where it was.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }
}
