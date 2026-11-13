import SwiftUI

/// An item's Location as a row of the inspector: its name beside a small pin, or Map where it has a point and no name,
/// which opens the same panel the page's Location opens (`LocationPanelContent`). An item that cannot be edited still
/// opens it where it has a point, to show it.
struct ItemLocationRow: View {
    let spec: ItemLocation
    let item: Item
    /// Whether the page shows Location too, and what changes it; nil offers no choice.
    var shownOnPage = true
    var onShowOnPage: ((Bool) -> Void)?
    /// A row the person has just added opens its panel at once.
    var startsEditing = false
    @Environment(\.library) private var library
    @Environment(\.undoManager) private var undoManager
    @State private var anchor = ValueEditAnchorBox()

    private var summary: String? { spec.summary(of: item) }
    private var canOpen: Bool { item.isEditable || spec.hasPoint(item) }

    var body: some View {
        InspectorRow(name: "Location") {
            label
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ValueEditAnchor(box: anchor))
        }
        .onNameTap(canOpen ? { openPanel() } : nil)
        .showOnPageMenu(isShown: shownOnPage, onChange: onShowOnPage)
        .task {
            guard startsEditing else { return }
            await Task.yield()
            openPanel()
        }
    }

    @ViewBuilder private var label: some View {
        let content = HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let summary {
                Image(systemName: "mappin").foregroundStyle(.secondary).imageScale(.small)
                Text(verbatim: summary).lineLimit(2).truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
            } else {
                InspectorPlaceholder(text: "Empty")
            }
        }
        if canOpen {
            Button { openPanel() } label: { content.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect) }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .accessibilityLabel("Location")
                .accessibilityValue(summary.map { Text(verbatim: $0) } ?? Text("Empty"))
                .accessibilityHint("Opens a map")
                .accessibilityIdentifier("ItemLocation")
        } else {
            content.accessibilityIdentifier("ItemLocation")
        }
    }

    private func openPanel() {
        guard canOpen, let library, let view = anchor.view else { return }
        let request = ValueEditRequest(kind: .location(spec), library: library, item: item.id, undoManager: undoManager)
        ValueEditPresenter.shared.present(request, anchor: view)
    }
}
