import AppKit
import SwiftUI

/// Search in a toolbar, as Mail keeps its own beside the list's buttons: a magnifying glass until it is clicked,
/// then a glass search field. Escape, or clearing the field and leaving it, puts the glass back. SwiftUI's own
/// `searchable` cannot do this on macOS: it always goes to the window's end, never in a column, and has no
/// minimized form there.
///
/// One toolbar item whichever it shows. In a list column the field takes most of the column's toolbar, ending before the
/// view's controls (`ColumnSearchMetrics.share`), and the top row, which measures the toolbar, gives the field the room.
/// Elsewhere it grows leftwards from the glass.
struct ColumnSearch: ToolbarContent {
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
    /// The window whose list the search narrows, which gives the field its tokens and offers. Nil for a field that is only
    /// text.
    var browser: Browser?
    /// Asks, each time it changes, for an open field to take the keyboard again.
    var focusRequests = 0
    var onSubmit: () -> Void = {}
    /// Down Arrow in the field, which hands the keyboard to the list.
    var onDown: () -> Void = {}

    /// - Parameter trailing: The space after the clear button. In a column the options sit in the same glass
    ///   just past the field, so the field keeps less there.
    @ViewBuilder
    private func field(trailing: CGFloat, width: CGFloat) -> some View {
        if let browser {
            BrowserSearchField(browser: browser, prompt: prompt, trailingPadding: trailing, width: width)
        } else {
            ColumnSearchField(
                text: $text, prompt: prompt, focusRequests: focusRequests, trailingPadding: trailing, width: width,
                onSubmit: onSubmit, onDown: onDown
            ) {
                text = ""
                isExpanded = false
            }
        }
    }

    private var button: some View {
        Button("Search", systemImage: "magnifyingglass") { isExpanded = true }
            .help("Search")
    }

    var body: some ToolbarContent {
        ToolbarItem {
            if isExpanded {
                switch layout {
                case .column(let width):
                    let fieldWidth = ColumnSearchMetrics.fieldWidth(inColumn: width)
                    field(trailing: 2, width: fieldWidth).frame(width: fieldWidth)
                case .item:
                    field(trailing: 8, width: ColumnSearchMetrics.itemFieldWidth).frame(width: ColumnSearchMetrics.itemFieldWidth)
                }
            } else {
                button
            }
        }
        .sharedBackgroundVisibility(isExpanded ? .visible : .automatic)
    }
}

enum ColumnSearchMetrics {
    /// What a column's toolbar keeps beside an open field: the toolbar's margin on each side, so the glass sits as
    /// far from what precedes it as from the column's end, and the View button in the same glass.
    static let columnChrome: CGFloat = 89
    /// The room the sidebar button takes at the start of the list column's toolbar while the sidebar is hidden.
    static let sidebarButtonRoom: CGFloat = 46
    /// What a field of its own takes of the room it could fill.
    static let share: CGFloat = 0.85
    /// The room a field could fill as an item of its own, before `share` narrows it.
    private static let itemRoom: CGFloat = 420
    private static let minimum: CGFloat = 120

    /// In a list column, the field fills the column but for the toolbar's margins and the options beside it.
    static func fieldWidth(inColumn width: CGFloat) -> CGFloat {
        max(minimum, (width - columnChrome).rounded())
    }

    static var itemFieldWidth: CGFloat { (itemRoom * share).rounded() }

    /// The field's height at the default text size, which the focus ring follows.
    static let fieldHeight: CGFloat = 24
    /// The most of the field its tokens take before they scroll, so the text always has room.
    static let chipShare: CGFloat = 0.6
}

/// A token the field holds: the clause, and how the filter model words it.
struct SearchChip: Identifiable, Hashable {
    let clause: FilterClause
    let parts: FilterWording.Parts
    var id: FilterClause { clause }
}

/// The list's search field: its tokens and text, and the offers that hang from it. Reads the window's search and writes
/// back to it, so nothing here is kept anywhere else.
private struct BrowserSearchField: View {
    @Bindable var browser: Browser
    @CurrentLibrary private var library
    let prompt: String
    let trailingPadding: CGFloat
    let width: CGFloat

    var body: some View {
        ColumnSearchField(
            text: $browser.searchText, prompt: prompt, focusRequests: browser.searchFocusRequests, trailingPadding: trailingPadding,
            width: width, chips: chips, offers: browser.searchOffers(in: library),
            onSubmit: { browser.focusRequest = .list },
            onDown: { browser.focusRequest = .list },
            onPick: pick,
            onRemove: { browser.removeSearchToken($0.clause) },
            onDeleteAtStart: { browser.removeLastSearchToken() },
            onClear: { browser.searchTokens = [] },
            onEnd: { browser.clearSearch() }
        )
    }

    private var chips: [SearchChip] {
        browser.searchTokens.compactMap { clause in
            browser.tokenParts(of: clause, in: library).map { SearchChip(clause: clause, parts: $0) }
        }
    }

    /// A token is made and the text it came from is taken away, leaving the field ready for the next; the words
    /// themselves are already the search, so choosing them only hands the keyboard to the list.
    private func pick(_ offer: SearchOffer) {
        if let clause = offer.clause {
            browser.addSearchToken(clause)
            browser.searchText = ""
        } else {
            browser.focusRequest = .list
        }
    }
}

/// A rounded search field for a toolbar's glass: a magnifier, the tokens, the prompt, and a clear button once there is
/// something to clear. It takes the keyboard each time it opens, and draws the app's own focus ring and no accent selection.
///
/// One AppKit text field with the tokens drawn beside it, rather than `NSTokenField`: the tokens are the filter row's chips,
/// not the system's token style, and the field keeps the close-on-blur handling and the quiet caret below.
struct ColumnSearchField: View {
    @Binding var text: String
    let prompt: String
    let focusRequests: Int
    let trailingPadding: CGFloat
    var width: CGFloat = ColumnSearchMetrics.itemFieldWidth
    var chips: [SearchChip] = []
    var offers: [SearchOffer] = []
    var onSubmit: () -> Void = {}
    var onDown: () -> Void = {}
    var onPick: (SearchOffer) -> Void = { _ in }
    var onRemove: (SearchChip) -> Void = { _ in }
    /// Delete at the start of the field: whether it took a token away.
    var onDeleteAtStart: () -> Bool = { false }
    var onClear: () -> Void = {}
    let onEnd: () -> Void
    @State private var clears = 0
    @State private var isFocused = false
    /// The token a click chose, which Delete takes away.
    @State private var selected: FilterClause?
    @State private var controller = SearchOffersController()
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if !chips.isEmpty {
                SearchChipRow(
                    chips: chips, width: width * ColumnSearchMetrics.chipShare, selected: Binding { selected } set: { choose($0) },
                    onRemove: remove)
            }
            ToolbarSearchText(
                text: $text, prompt: chips.isEmpty ? prompt : "", label: prompt, focusRequests: focusRequests + clears, keepsOpen: !chips.isEmpty,
                controller: controller, offers: offers, onSubmit: onSubmit, onDown: onDown, onPick: onPick,
                onDelete: delete, onFocus: { isFocused = $0 }, onEnd: onEnd
            )
            .frame(minWidth: 60 * scale)
            if !text.isEmpty || !chips.isEmpty {
                Button("Clear Search", systemImage: "xmark.circle.fill") {
                    text = ""
                    onClear()
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
        .frame(height: ColumnSearchMetrics.fieldHeight * scale)
        .appFocusRing(Capsule(), isFocused: isFocused)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ColumnSearchField")
        // Typing, or a token that has gone, leaves nothing chosen.
        .onChange(of: text) { selected = nil }
        .onChange(of: chips) { if let selected, !chips.contains(where: { $0.clause == selected }) { self.selected = nil } }
    }

    /// Chooses a token, with the keyboard back in the field so Delete reaches it.
    private func choose(_ clause: FilterClause?) {
        selected = clause
        if clause != nil { clears += 1 }
    }

    private func remove(_ chip: SearchChip) {
        selected = nil
        onRemove(chip)
        // With the last token gone, no text and no keyboard in the field, nothing is left to stay open for.
        if !isFocused, text.isEmpty, chips.allSatisfy({ $0 == chip }) { onEnd() }
    }

    /// Delete: takes the chosen token away, or at the start of the field the last one. Whether it did either.
    private func delete(atStart: Bool) -> Bool {
        if let selected, let chip = chips.first(where: { $0.clause == selected }) {
            remove(chip)
            return true
        }
        return atStart && onDeleteAtStart()
    }
}

/// The tokens in a row that scrolls once it is wider than the room it is given, and follows the newest.
struct SearchChipRow: View {
    let chips: [SearchChip]
    let width: CGFloat
    /// The token a click chose, which Delete takes away.
    @Binding var selected: FilterClause?
    let onRemove: (SearchChip) -> Void

    private var row: some View {
        HStack(spacing: 4) {
            ForEach(chips) { chip in
                SearchChipView(
                    chip: chip, isSelected: selected == chip.clause, select: { selected = chip.clause }, remove: { onRemove(chip) })
            }
        }
        .fixedSize()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row
            ScrollView(.horizontal, showsIndicators: false) { row }
                .defaultScrollAnchor(.trailing)
        }
        .frame(maxWidth: width)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search Filters")
    }
}

/// A token: the field in the secondary color and its value in the primary. It has no button; a click chooses it, Delete
/// takes it away, and VoiceOver has Remove.
private struct SearchChipView: View {
    let chip: SearchChip
    let isSelected: Bool
    let select: () -> Void
    let remove: () -> Void
    @Environment(\.interfaceTextSize) private var textSize

    /// The field in the secondary color, then the relation and the values.
    private var styled: AttributedString {
        var head = AttributedString(chip.parts.field)
        head.foregroundColor = .secondary
        let rest = [chip.parts.relation, chip.parts.values].filter { !$0.isEmpty }.joined(separator: " ")
        return head + AttributedString(" " + rest)
    }

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        let looks = ChipLooks.defaults
        HStack(spacing: looks.gap * scale / 1.25) {
            Text(styled)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: looks.textSize * scale))
        .padding(.horizontal, looks.padding * scale)
        .frame(height: looks.height * scale)
        .frame(maxWidth: FilterChipMetrics.widest * scale)
        .background(
            isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.3)) : AnyShapeStyle(.quaternary.opacity(0.6)),
            in: .rect(cornerRadius: looks.cornerRadius * scale, style: .continuous))
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(.rect)
        .onTapGesture(perform: select)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chip.parts.sentence)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Remove", remove)
        .accessibilityIdentifier("SearchToken")
    }
}

/// The field's text, in AppKit: a SwiftUI text field in a toolbar item takes the keyboard only by chance when asked
/// as it appears, and its field editor handles Escape and Down Arrow before SwiftUI sees them. Here the field asks
/// for the keyboard once it is in the window, and its delegate gets those keys as the field editor's commands.
private struct ToolbarSearchText: NSViewRepresentable {
    @Environment(\.interfaceTextSize) private var textSize
    @Binding var text: String
    let prompt: String
    /// What VoiceOver calls the field, the search prompt even where the field shows no placeholder.
    let label: String
    let focusRequests: Int
    /// Whether the search holds tokens, which keep the field open while it is empty and loses the keyboard.
    let keepsOpen: Bool
    let controller: SearchOffersController
    let offers: [SearchOffer]
    let onSubmit: () -> Void
    let onDown: () -> Void
    let onPick: (SearchOffer) -> Void
    /// Delete, and whether it was at the start of the field: whether it took a token away.
    let onDelete: (Bool) -> Bool
    let onFocus: (Bool) -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> ToolbarSearchTextField {
        let field = ToolbarSearchTextField()
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier("ColumnSearch")
        field.onClickElsewhere = { [weak coordinator = context.coordinator] in coordinator?.parent.onEnd() }
        field.onFocus = { [weak coordinator = context.coordinator] in coordinator?.focusChanged($0) }
        controller.field = field
        update(field)
        return field
    }

    func updateNSView(_ field: ToolbarSearchTextField, context: Context) {
        context.coordinator.parent = self
        update(field)
        controller.pick = onPick
        controller.setOffers(offers)
        if context.coordinator.focusRequests != focusRequests {
            context.coordinator.focusRequests = focusRequests
            field.takeKeyboard()
        }
    }

    static func dismantleNSView(_ field: ToolbarSearchTextField, coordinator: Coordinator) {
        coordinator.parent.controller.hide()
    }

    private func update(_ field: ToolbarSearchTextField) {
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = prompt
        field.setAccessibilityLabel(label)
        field.keepsOpen = keepsOpen
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

        func focusChanged(_ isFocused: Bool) {
            parent.onFocus(isFocused)
            parent.controller.setFocused(isFocused)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let controller = parent.controller
            switch selector {
            case #selector(NSResponder.moveDown(_:)):
                if !controller.move(by: 1) { parent.onDown() }
            case #selector(NSResponder.moveUp(_:)):
                return controller.move(by: -1)
            case #selector(NSResponder.cancelOperation(_:)):
                // With tokens, the first Escape takes the words away and the next the tokens, with the field.
                if parent.keepsOpen, !parent.text.isEmpty {
                    textView.string = ""
                    parent.text = ""
                } else {
                    parent.onEnd()
                }
            case #selector(NSResponder.insertNewline(_:)):
                if let offer = controller.chosen { parent.onPick(offer) } else { parent.onSubmit() }
            case #selector(NSResponder.deleteBackward(_:)):
                // A chosen token goes; otherwise at the start of the field Delete takes the last, as it does in Mail.
                guard parent.onDelete(textView.selectedRange == NSRange(location: 0, length: 0)) else { return false }
            default: return false
            }
            return true
        }

        // Left empty, and with no token to keep it, the field goes back to being a button.
        func controlTextDidEndEditing(_ notification: Notification) {
            focusChanged(false)
            if parent.text.isEmpty, !parent.keepsOpen { parent.onEnd() }
        }
    }
}

private final class ToolbarSearchTextField: NSTextField {
    /// Set until the field has had the keyboard once. The toolbar moves its items between windows (full screen,
    /// overflow), and an open field should not take the keyboard from the page each time.
    private var isAwaitingKeyboard = true
    /// Called once a click has finished that landed outside the field and the toolbar items beside it while the
    /// field was open and empty.
    var onClickElsewhere: () -> Void = {}
    /// Called as the field gains the keyboard.
    var onFocus: (Bool) -> Void = { _ in }
    /// Whether tokens keep the field open while it holds no text.
    var keepsOpen = false
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

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus(true) }
        return accepted
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

    /// Whether the field has the keyboard, holds no text and has no token to stay for. A field that has handed the keyboard on has already
    /// closed itself (`controlTextDidEndEditing`).
    private var isOpenAndEmpty: Bool {
        guard !keepsOpen, let editor = currentEditor() as? NSTextView else { return false }
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
