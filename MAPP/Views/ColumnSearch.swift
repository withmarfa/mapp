import AppKit
import SwiftUI

/// Search in a toolbar, as Mail keeps its own beside the list's buttons: a magnifying glass until it is clicked,
/// then a glass search field. Escape, or clearing the field and leaving it, puts the glass back. SwiftUI's own
/// `searchable` cannot do this on macOS: it always goes to the window's end, never in a column, and has no
/// minimized form there.
///
/// The view's own controls (`controls`) follow it, in the same glass while it is a glass. In a list column the field
/// spans the column's toolbar in place of its title, up to those controls. Elsewhere it is an item of its own, with
/// the controls as an item after it, and it grows leftwards from the glass.
struct ColumnSearch<Controls: View>: ToolbarContent {
    enum Layout {
        /// Across a list column, whose width a toolbar item cannot tell, so the caller passes it.
        case column(width: CGFloat)
        /// An item of its own, at the trailing side of a full-width toolbar.
        case item
    }

    @Binding var isExpanded: Bool
    @Binding var text: String
    let prompt: String
    let layout: Layout
    /// Asks, each time it changes, for an open field to take the keyboard again.
    var focusRequests = 0
    var onSubmit: () -> Void = {}
    /// Down Arrow in the field, which hands the keyboard to the list.
    var onDown: () -> Void = {}
    @ViewBuilder let controls: () -> Controls

    /// - Parameter trailing: The space after the clear button. In a column the options sit in the same glass
    ///   just past the field, so the field keeps less there.
    private func field(trailing: CGFloat) -> some View {
        ColumnSearchField(
            text: $text, prompt: prompt, focusRequests: focusRequests, trailingPadding: trailing,
            onSubmit: onSubmit, onDown: onDown
        ) {
            text = ""
            isExpanded = false
        }
    }

    private var button: some View {
        Button("Search", systemImage: "magnifyingglass") { isExpanded = true }
            .help("Search")
    }

    var body: some ToolbarContent {
        switch layout {
        case .column(let width):
            if isExpanded {
                ToolbarItem(id: "listSearchField") { field(trailing: 2).frame(width: ColumnSearchMetrics.fieldWidth(inColumn: width)) }
                    .sharedBackgroundVisibility(.visible)
                ToolbarItem(id: "listOptions") { controls() }
            } else {
                ToolbarItemGroup {
                    button
                    controls()
                }
            }
        case .item:
            if isExpanded {
                ToolbarItem(id: "collectionSearchField") { field(trailing: 8).frame(width: ColumnSearchMetrics.itemFieldWidth) }
                    .sharedBackgroundVisibility(.visible)
                ToolbarItem(id: "collectionOptions") { controls() }
            } else {
                ToolbarItemGroup {
                    button
                    controls()
                }
            }
        }
    }
}

enum ColumnSearchMetrics {
    /// What a column's toolbar keeps beside an open field: its margins, the options item and the gap before it.
    static let columnChrome: CGFloat = 54
    /// What the field takes of the room it could fill. One factor for every layout, so they narrow together.
    static let share: CGFloat = 0.85
    /// The room a field could fill as an item of its own, before `share` narrows it.
    private static let itemRoom: CGFloat = 260
    private static let minimum: CGFloat = 120

    /// In a list column, the field ends before the options item, with the rest of the column's room left over.
    static func fieldWidth(inColumn width: CGFloat) -> CGFloat {
        max(minimum, ((width - columnChrome) * share).rounded())
    }

    static var itemFieldWidth: CGFloat { (itemRoom * share).rounded() }
}

/// A rounded search field for a toolbar's glass: a magnifier, the prompt, and a clear button once there is text.
/// It takes the keyboard each time it opens, and draws neither a focus ring nor an accent selection.
struct ColumnSearchField: View {
    @Binding var text: String
    let prompt: String
    let focusRequests: Int
    let trailingPadding: CGFloat
    let onSubmit: () -> Void
    let onDown: () -> Void
    let onEnd: () -> Void
    @State private var clears = 0

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            ToolbarSearchText(
                text: $text, prompt: prompt, focusRequests: focusRequests + clears,
                onSubmit: onSubmit, onDown: onDown, onEnd: onEnd
            )
            if !text.isEmpty {
                Button("Clear Search", systemImage: "xmark.circle.fill") {
                    text = ""
                    // Back in the field, so that leaving it empty still closes it.
                    clears += 1
                }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ClearColumnSearch")
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, trailingPadding)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ColumnSearchField")
    }
}

/// The field's text, in AppKit: a SwiftUI text field in a toolbar item takes the keyboard only by chance when asked
/// as it appears, and its field editor handles Escape and Down Arrow before SwiftUI sees them. Here the field asks
/// for the keyboard once it is in the window, and its delegate gets those keys as the field editor's commands.
private struct ToolbarSearchText: NSViewRepresentable {
    @Environment(\.interfaceTextSize) private var textSize
    @Binding var text: String
    let prompt: String
    let focusRequests: Int
    let onSubmit: () -> Void
    let onDown: () -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> ToolbarSearchTextField {
        let field = ToolbarSearchTextField()
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier("ColumnSearch")
        field.onClickElsewhere = { [weak coordinator = context.coordinator] in coordinator?.parent.onEnd() }
        update(field)
        return field
    }

    func updateNSView(_ field: ToolbarSearchTextField, context: Context) {
        context.coordinator.parent = self
        update(field)
        if context.coordinator.focusRequests != focusRequests {
            context.coordinator.focusRequests = focusRequests
            field.takeKeyboard()
        }
    }

    private func update(_ field: ToolbarSearchTextField) {
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = prompt
        field.font = InterfaceStyle.font(.body, textSize: textSize)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ToolbarSearchText
        var focusRequests: Int

        init(parent: ToolbarSearchText) {
            self.parent = parent
            focusRequests = parent.focusRequests
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)): parent.onDown()
            case #selector(NSResponder.cancelOperation(_:)): parent.onEnd()
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit()
            default: return false
            }
            return true
        }

        // Left empty, the field goes back to being a button.
        func controlTextDidEndEditing(_ notification: Notification) {
            if parent.text.isEmpty { parent.onEnd() }
        }
    }
}

private final class ToolbarSearchTextField: NSTextField {
    /// Set until the field has had the keyboard once. The toolbar moves its items between windows (full screen,
    /// Customize Toolbar, overflow), and an open field should not take the keyboard from the page each time.
    private var isAwaitingKeyboard = true
    /// Called once a click has finished that landed outside the field and the toolbar items beside it while the
    /// field was open and empty.
    var onClickElsewhere: () -> Void = {}
    private var monitor: Any?
    private var isClickElsewhere = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = ToolbarSearchTextCell(textCell: "")
        isEditable = true
        isSelectable = true
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        usesSingleLineMode = true
        lineBreakMode = .byTruncatingTail
        cell?.isScrollable = true
        cell?.wraps = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    isolated deinit { removeMonitor() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        addMonitor()
        if isAwaitingKeyboard { takeKeyboard() }
    }

    func takeKeyboard() {
        isAwaitingKeyboard = true
        // The toolbar finishes placing its items after this returns; asked any sooner, the window keeps the
        // keyboard where it was.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, self.isAwaitingKeyboard else { return }
            if window.makeFirstResponder(self) { self.isAwaitingKeyboard = false }
        }
    }

    // MARK: Clicks elsewhere

    // The field editor keeps the keyboard through a click on anything that cannot take it, such as the page's
    // background, the toolbar or the title bar, so the field never hears that the person has moved on. The click
    // is left alone and acts as it would, and the field closes once the mouse button is up, since the items
    // beside it move when it does.

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
            isClickElsewhere = isOpenAndEmpty && !isOverOwnItems(event)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            guard isClickElsewhere else { return }
            isClickElsewhere = false
            // After the click's own action, which may run as the event is delivered.
            DispatchQueue.main.async { [weak self] in
                if let self, self.isOpenAndEmpty { self.onClickElsewhere() }
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

    /// Whether a click is on the field, its clear button, or the item after it in the toolbar, which holds the
    /// view's own controls: a click there is the person using the search, not leaving it.
    private func isOverOwnItems(_ event: NSEvent) -> Bool {
        guard let frame = window?.contentView?.superview else { return false }
        guard let hit = frame.hitTest(frame.convert(event.locationInWindow, from: nil)) else { return false }
        if hit.isDescendant(of: self) { return true }
        let items = window?.toolbar?.items ?? []
        guard let own = items.firstIndex(where: { $0.view.map(isDescendant(of:)) ?? false }) else { return false }
        return items[own...].prefix(2).contains { $0.view.map(hit.isDescendant(of:)) ?? false }
    }
}

/// Edits with a field editor of its own, so the caret and the selection can be quiet without changing the
/// window's shared editor.
private final class ToolbarSearchTextCell: NSTextFieldCell {
    private lazy var editor: NSTextView = {
        let editor = NSTextView()
        editor.isFieldEditor = true
        editor.insertionPointColor = .secondaryLabelColor
        editor.selectedTextAttributes = [.backgroundColor: NSColor.unemphasizedSelectedTextBackgroundColor]
        return editor
    }()

    override func fieldEditor(for controlView: NSView) -> NSTextView? { editor }
}
