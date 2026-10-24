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
            ToolbarItem(placement: .principal) {
                ColumnSearchField(text: $text, prompt: prompt, focusRequests: focusRequests, onSubmit: onSubmit, onDown: onDown) {
                    text = ""
                    isExpanded = false
                }
                .frame(width: max(160, columnWidth - 24))
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItemGroup {
                Button("Search", systemImage: "magnifyingglass") { isExpanded = true }
                    .help("Search")
                leading()
            }
        }
    }
}

/// The system search field, which takes the keyboard as it appears.
struct ColumnSearchField: NSViewRepresentable {
    @Environment(\.interfaceTextSize) private var textSize
    @Binding var text: String
    let prompt: String
    let focusRequests: Int
    let onSubmit: () -> Void
    let onDown: () -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> ClosableSearchField {
        let view = ClosableSearchField()
        let field = view.field
        field.placeholderString = prompt
        field.font = InterfaceStyle.font(.body, textSize: textSize)
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier("ColumnSearch")
        view.onClose = onEnd
        return view
    }

    func updateNSView(_ view: ClosableSearchField, context: Context) {
        let field = view.field
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = prompt
        view.onClose = onEnd
        field.font = InterfaceStyle.font(.body, textSize: textSize)
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

/// The search field with a close button over its trailing edge. The button is the field's sibling rather than its
/// subview: NSSearchField does not report subviews to accessibility, and adding the button to the field's
/// accessibility children crashed the app whenever its accessibility tree was read.
final class ClosableSearchField: NSView {
    let field = FocusingSearchField()
    var onClose: () -> Void = {}
    private let closeButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: String(localized: "Close Search"))
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.bezelStyle = .inline
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeSearch)
        closeButton.setAccessibilityLabel(String(localized: "Close Search"))
        closeButton.setAccessibilityIdentifier("CloseColumnSearch")
        addSubview(field)
        addSubview(closeButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: field.intrinsicContentSize.height)
    }

    override func layout() {
        super.layout()
        field.frame = bounds
        closeButton.frame = NSRect(x: bounds.maxX - 28, y: (bounds.height - 20) / 2, width: 20, height: 20)
    }

    @objc private func closeSearch() { onClose() }
}

final class FocusingSearchField: NSSearchField {
    private var hasAppeared = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = ClosingSearchFieldCell(textCell: "")
        isEditable = true
        isSelectable = true
        isBezeled = true
        bezelStyle = .roundedBezel
        controlSize = .large
        // NSSearchField hides its cancel button when empty; an expanded column still needs a way to close, which
        // the close button over the field's trailing edge gives. AppKit draws and edits the search field itself.
        (cell as? NSSearchFieldCell)?.cancelButtonCell = nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

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

private final class ClosingSearchFieldCell: NSSearchFieldCell {
    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        var textRect = super.searchTextRect(forBounds: rect)
        textRect.size.width = max(0, min(textRect.maxX, rect.maxX - 32) - textRect.minX)
        return textRect
    }
}
