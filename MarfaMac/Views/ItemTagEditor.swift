import AppKit
import SwiftUI

/// The right sidebar's Tags section: the item's tags as chips in one box, with the text cursor in that box while a tag is
/// being added, and the tags that match what is typed in a list under it. Return adds the highlighted one, or creates
/// what was typed, and the field stays ready for the next. A click in the box, or the heading's plus, starts it; Escape,
/// or a click anywhere else, ends it.
struct InspectorTagsContent: View {
    @Environment(\.interfaceTextSize) private var textSize
    let tags: [String]
    let isEditable: Bool
    let onRemove: (String) -> Void
    /// The editor while a tag is being added, else nil.
    let editor: ValueEditModel?
    let begin: () -> Void
    /// Ends the editing, adding what was typed and not yet added.
    let finish: () -> Void
    /// Ends the editing at Escape, which the person asked for.
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InspectorBox {
                box
            }
            if let editor { TagSuggestions(model: editor) }
        }
        .background { OutsideClick(isActive: editor != nil, action: finish) }
    }

    @ViewBuilder private var box: some View {
        if let editor {
            TagField(model: editor, tags: tags, onRemove: onRemove, cancel: cancel, finish: finish)
        } else {
            Group {
                if tags.isEmpty {
                    Text("No Tags").foregroundStyle(.secondary)
                } else {
                    TagFlowLayout(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            TagChip(tag: tag, onRemove: isEditable ? { onRemove(tag) } : nil)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .onTapGesture { if isEditable { begin() } }
            .accessibilityIdentifier("ItemTags")
        }
    }
}

/// The chips and, after them, the field the person types into.
private struct TagField: View {
    @Environment(\.interfaceTextSize) private var textSize
    @Bindable var model: ValueEditModel
    let tags: [String]
    let onRemove: (String) -> Void
    let cancel: () -> Void
    let finish: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        ChipFieldLayout(spacing: 6 * scale, lineHeight: 24 * scale, queryFloor: (model.query.isEmpty ? 56 : 72) * scale) {
            ForEach(tags, id: \.self) { tag in
                TagChip(tag: tag, onRemove: { onRemove(tag) })
            }
            TextField(tags.isEmpty ? model.searchPrompt : "", text: $model.query)
                .textFieldStyle(.plain)
                .interfaceFont(.body)
                .focused($isFocused)
                .appFocusRing(isFocused: isFocused)
                .onSubmit {
                    model.submitTyped()
                    isFocused = true
                }
                .onKeyPress(.upArrow) { handle { model.move(by: -1) } }
                .onKeyPress(.downArrow) { handle { model.move(by: 1) } }
                .onKeyPress(keys: [.delete]) { press in
                    // Not on a repeat: holding Delete to clear the text must not go on to remove the chips.
                    press.phase == .repeat || !model.query.isEmpty ? .ignored : (model.removeLastChip() ? .handled : .ignored)
                }
                .onExitCommand {
                    if model.query.isEmpty { cancel() } else { model.query = "" }
                }
                .accessibilityLabel(model.searchPrompt)
                .accessibilityIdentifier("ItemTagField")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .onTapGesture { isFocused = true }
        .task {
            await Task.yield()
            isFocused = true
        }
        .onChange(of: isFocused) { _, focused in
            // Tabbing away or leaving the window ends it; a click is the monitor's, so a click on a suggestion does not.
            if !focused, NSEvent.pressedMouseButtons == 0 { finish() }
        }
    }

    /// Takes a key for the field unless the person is composing text, where the arrows belong to the input method.
    private func handle(_ action: () -> Void) -> KeyPress.Result {
        if (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true { return .ignored }
        action()
        return .handled
    }
}

/// The tags that match what is typed, as rows in a box of their own under the field, with Create "<text>" where none is
/// the tag typed.
private struct TagSuggestions: View {
    @Environment(\.interfaceTextSize) private var textSize
    let model: ValueEditModel

    private static let visibleRows = 6

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        let rows = model.rows.filter { $0.role == .option || $0.role == .create }
        VStack(alignment: .leading, spacing: 6) {
            if !rows.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(rows) { row in
                                TagSuggestionRow(row: row, model: model, scale: scale)
                            }
                        }
                        .padding(4 * scale)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: min(CGFloat(rows.count), CGFloat(Self.visibleRows)) * 28 * scale + 8 * scale)
                    .onChange(of: model.activeRow) { _, id in if let id, model.viaKeyboard { proxy.scrollTo(id) } }
                }
                .inspectorSurface(radius: InspectorMetrics.boxRadius)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("ItemTagSuggestions")
            }
            if let notice = model.notice {
                Text(verbatim: notice)
                    .interfaceFont(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, InspectorMetrics.headingInset)
                    .accessibilityIdentifier("ItemTagNotice")
            }
        }
    }
}

private struct TagSuggestionRow: View {
    let row: ValueListRow
    let model: ValueEditModel
    let scale: CGFloat

    private var isActive: Bool { model.activeRow == row.id }

    var body: some View {
        HStack(spacing: 7 * scale) {
            ValueMarkView(mark: row.mark, scale: scale)
            Text(verbatim: row.title).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8 * scale)
            if let detail = row.detail {
                Text(verbatim: detail).foregroundStyle(.secondary).layoutPriority(1)
            }
        }
        .interfaceFont(.body)
        .padding(.horizontal, 8 * scale)
        .frame(height: 28 * scale)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: InspectorMetrics.rowRadius * scale, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            }
        }
        .contentShape(.rect)
        .onHover { model.hover($0 ? row.id : nil) }
        .onTapGesture { model.activate(row.id) }
        .id(row.id)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.activate(row.id) }
        .accessibilityIdentifier("ItemTagSuggestion.\(row.id)")
    }
}

/// Calls `action` for a click anywhere in the window outside the view it is the background of, while `isActive`. The click
/// goes on to whatever it was for.
struct OutsideClick: NSViewRepresentable {
    let isActive: Bool
    let action: () -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.action = action
        view.isActive = isActive
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.isActive = false }

    final class MonitorView: NSView {
        var action: () -> Void = {}
        private var monitor: Any?

        var isActive = false {
            didSet {
                guard isActive != oldValue else { return }
                if isActive { start() } else { stop() }
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func start() {
            let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            monitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
                MainActor.assumeIsolated { self?.see(event) }
                return event
            }
        }

        private func stop() {
            monitor.map(NSEvent.removeMonitor)
            monitor = nil
        }

        private func see(_ event: NSEvent) {
            guard let window, event.window === window, !bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            action()
        }
    }
}
