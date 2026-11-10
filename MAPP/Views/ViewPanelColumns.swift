import SwiftUI

/// The panel's Columns, for the table: the name stays and is first, the others are shown or hidden with the eye and
/// dragged into order. A saved view's choices are stored for this Mac as made, and a place's own apply at once and keep their
/// order, which only a view arranges.
struct ViewPanelColumns: View {
    @Environment(\.interfaceTextSize) private var textSize
    let browser: Browser
    let panel: ViewPanel
    let content: ItemTableContent
    @AppStorage(ItemTableColumnLayouts.key) private var stored = Data()
    @State private var showsHidden = false

    private var viewID: ItemID? {
        if case .view(let id) = browser.item { id } else { nil }
    }

    var body: some View {
        let arranged = viewID.map { browser.macSettings(for: $0).columns.arranged(content.columns) } ?? content.columns
        let shown = arranged.filter { browser.showsColumn($0, stored: stored) }
        let hidden = arranged.filter { !browser.showsColumn($0, stored: stored) }
        VStack(alignment: .leading, spacing: InspectorMetrics.headingGap) {
            HStack(spacing: 6) {
                Text("Columns").interfaceFont(.body.weight(.semibold))
                Text(shown.count, format: .number).interfaceFont(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if panel.purpose != .place {
                    Text("This Mac").interfaceFont(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, InspectorMetrics.headingInset)
            .accessibilityAddTraits(.isHeader)
            InspectorBox {
                ForEach(shown) { column in
                    ColumnRow(browser: browser, content: content, column: column, isShown: true, canArrange: viewID != nil, stored: $stored)
                }
                if !hidden.isEmpty {
                    Button {
                        showsHidden.toggle()
                    } label: {
                        Label(showsHidden ? "Hide \(hidden.count) Hidden" : "Show \(hidden.count) More", systemImage: showsHidden ? "chevron.up" : "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ViewPanelShowMoreColumns")
                    if showsHidden {
                        ForEach(hidden) { column in
                            ColumnRow(browser: browser, content: content, column: column, isShown: false, canArrange: viewID != nil, stored: $stored)
                        }
                    }
                }
            }
        }
    }
}

private struct ColumnRow: View {
    @Environment(\.interfaceTextSize) private var textSize
    let browser: Browser
    let content: ItemTableContent
    let column: ItemTableColumn
    let isShown: Bool
    let canArrange: Bool
    @Binding var stored: Data

    private static let prefix = "column:"

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        let isName = column.content == .title
        HStack(spacing: InspectorMetrics.gap) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11 * scale))
                .foregroundStyle(.tertiary)
                .opacity(canArrange && !isName ? 1 : 0)
                .accessibilityHidden(true)
            Text(verbatim: column.label)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isShown ? .primary : .secondary)
            Spacer(minLength: 0)
            if isName {
                Image(systemName: "lock")
                    .foregroundStyle(.tertiary)
                    .help("The name always shows.")
                    .accessibilityLabel("Always shown")
            } else {
                Button {
                    browser.setColumn(column, shown: !isShown, stored: $stored)
                } label: {
                    Image(systemName: isShown ? "eye" : "eye.slash")
                        .foregroundStyle(isShown ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                        .frame(width: InspectorMetrics.trailingColumn, height: InspectorMetrics.trailingColumn)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(isShown ? "Hide Column" : "Show Column")
                .accessibilityLabel(isShown ? "Hide Column" : "Show Column")
                .accessibilityIdentifier("ViewPanelColumnEye.\(column.id)")
            }
        }
        .interfaceFont(.body)
        .contentShape(.rect)
        .modifier(Arrangeable(isOn: canArrange && !isName, id: Self.prefix + column.id, move: move))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ViewPanelColumn.\(column.id)")
    }

    private func move(_ dragged: String) -> Bool {
        guard dragged.hasPrefix(Self.prefix), case .view(let id) = browser.item else { return false }
        let moved = String(dragged.dropFirst(Self.prefix.count))
        guard moved != column.id else { return false }
        browser.changeViewSettings(id) { $0.columns.move(moved, before: column.id, in: content.columns) }
        return true
    }
}

/// Drag to reorder, and the keyboard's way to the same move.
struct Arrangeable: ViewModifier {
    let isOn: Bool
    let id: String
    let move: (String) -> Bool

    func body(content: Content) -> some View {
        if isOn {
            content
                .draggable(LayoutRowDrag(id: id))
                .dropDestination(for: LayoutRowDrag.self) { drops, _ in
                    drops.first.map { move($0.id) } ?? false
                }
        } else {
            content
        }
    }
}
