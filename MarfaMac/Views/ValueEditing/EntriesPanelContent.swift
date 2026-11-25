import SwiftUI

/// The value panel of a list of entries: one block for each entry with its members in rows, and a row to add one. It
/// scrolls past the room the window has, as a list of options does.
struct EntriesPanelContent: View {
    let model: ValueEditModel
    @Environment(\.interfaceTextSize) private var textSize

    private var scale: CGFloat { InterfaceStyle.scale(for: textSize) }

    var body: some View {
        if case .entries(let field, let shape) = model.kind {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    EntriesEditor(
                        shape: shape, label: field.label, key: field.key, value: model.value, isEditable: model.isEditable,
                        editing: model.entries, isWriting: model.request.item.map { model.library.isWritingProperties(of: $0) } ?? false,
                        onChange: model.writeEntries)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.measure(.rows, $0) }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: shownHeight)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.measure(.list, $0) }
                doneRow
            }
            .padding(ValueEditMetrics.padding * scale)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.measure(.total, $0) }
            .accessibilityIdentifier("EntriesPanel")
        }
    }

    /// Done ends the panel, which writes what was typed or gives it back, as a click outside does.
    private var doneRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.vertical, 4 * scale)
            HStack {
                Spacer(minLength: 0)
                Button("Done") { model.close() }
                    .appButton(.primary, size: .small)
                    .accessibilityIdentifier("EntriesDone")
            }
            .padding(.horizontal, 8 * scale)
            .padding(.bottom, 2 * scale)
        }
    }

    /// The blocks' own height until the room runs out, with a row's worth shown at the very least.
    private var shownHeight: CGFloat {
        let wanted = model.rowsHeight > 0 ? model.rowsHeight : 4 * ValueEditMetrics.rowHeight * scale
        let chrome = max(0, model.totalHeight - model.listHeight)
        return min(wanted, max(model.maxHeight - chrome, ValueEditMetrics.rowHeight * scale))
    }
}
