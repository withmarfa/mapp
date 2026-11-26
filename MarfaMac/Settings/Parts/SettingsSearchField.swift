import AppKit
import SwiftUI

/// The system's search field, large (28 points, a capsule), for a table's search and the keyboard's. SwiftUI's own `searchable` places a field only in
/// a toolbar or a sidebar, so a field inside a page is `NSSearchField`, which draws the magnifier and the clear button itself.
struct SettingsSearchField: NSViewRepresentable {
    let prompt: String
    @Binding var text: String
    var width: CGFloat = SettingsTokens.Metric.searchWidth
    var identifier: String?
    var onClear: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, onClear: onClear) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.controlSize = .large
        field.font = .systemFont(ofSize: NSFont.systemFontSize(for: .regular))
        field.sendsSearchStringImmediately = true
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        if onClear != nil, let clear = (field.cell as? NSSearchFieldCell)?.cancelButtonCell {
            clear.target = context.coordinator
            clear.action = #selector(Coordinator.clear)
        }
        if let identifier { field.setAccessibilityIdentifier(identifier) }
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onClear = onClear
        field.placeholderString = prompt
        if field.stringValue != text { field.stringValue = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: NSSearchField, context: Context) -> CGSize? {
        CGSize(width: width, height: field.intrinsicContentSize.height)
    }

    final class Coordinator: NSObject {
        var text: Binding<String>
        var onClear: (() -> Void)?

        init(text: Binding<String>, onClear: (() -> Void)?) {
            self.text = text
            self.onClear = onClear
        }

        @objc func clear() { onClear?() }

        @objc func changed(_ field: NSSearchField) {
            if text.wrappedValue != field.stringValue { text.wrappedValue = field.stringValue }
        }
    }
}
