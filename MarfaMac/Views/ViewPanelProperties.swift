import SwiftUI

/// The panel's Properties (boards N3 and N6): what shows after the title in every layout but the calendar. A table's
/// are its columns, the name locked first; any other layout lists what a chip can say. Each row has its symbol, name, a
/// handle to drag it into order and an eye. Until the list is changed it reads "As in Layouts", each item showing its own
/// type's look; once changed it reads "This Mac", and Use Layouts at the foot puts the fallback back. The Secondary line and
/// the date stay the type's. Edit Layouts… opens Settings > Layouts at a type's page.
struct ViewPanelProperties: View {
    @CurrentLibrary private var library
    let browser: Browser
    @State private var showsHidden = false

    var body: some View {
        let properties = browser.properties
        let listed = properties.arranged(browser.offeredProperties(in: library))
        let shown = listed.filter { properties.isShown($0) }
        let hidden = listed.filter { !properties.isShown($0) }
        let all = browser.tableContent(in: library).columns
        ViewPanelSection(title: "Properties", note: properties.isChanged ? "This Mac" : "As in Layouts") {
            InspectorBox {
                ForEach(shown) { column in
                    PropertyRowView(browser: browser, columns: all, column: column, isShown: true)
                }
                if !hidden.isEmpty {
                    Button {
                        showsHidden.toggle()
                    } label: {
                        Label(showsHidden ? "Hide \(hidden.count) Hidden" : "Show \(hidden.count) More", systemImage: showsHidden ? "chevron.up" : "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ViewPanelShowMoreProperties")
                    if showsHidden {
                        ForEach(hidden) { column in
                            PropertyRowView(browser: browser, columns: all, column: column, isShown: false)
                        }
                    }
                }
                if properties.isChanged {
                    Button { browser.useLayouts() } label: {
                        Label("Use Layouts", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ViewPanelUseLayouts")
                }
                EditLayoutsCommand(types: browser.layoutTypes(in: library)) { browser.showLayouts(of: $0) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
            }
        }
        .accessibilityIdentifier("ViewPanelProperties")
    }
}

private struct PropertyRowView: View {
    @Environment(\.interfaceTextSize) private var textSize
    let browser: Browser
    /// Every column of the place, which a move is spliced into.
    let columns: [ItemTableColumn]
    let column: ItemTableColumn
    let isShown: Bool

    private static let prefix = "column:"

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        let isName = column.content == .title
        HStack(spacing: InspectorMetrics.gap) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11 * scale))
                .foregroundStyle(.tertiary)
                .opacity(isName ? 0 : 1)
                .accessibilityHidden(true)
            Image(systemName: column.symbol)
                .foregroundStyle(.secondary)
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
                    browser.setColumn(column, shown: !isShown)
                } label: {
                    Image(systemName: isShown ? "eye" : "eye.slash")
                        .foregroundStyle(isShown ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                        .frame(width: InspectorMetrics.trailingColumn, height: InspectorMetrics.trailingColumn)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(isShown ? "Hide Property" : "Show Property")
                .accessibilityLabel(isShown ? "Hide Property" : "Show Property")
                .accessibilityIdentifier("ViewPanelPropertyEye.\(column.id)")
            }
        }
        .interfaceFont(.body)
        .contentShape(.rect)
        .modifier(Arrangeable(isOn: !isName, id: Self.prefix + column.id, move: move))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ViewPanelProperty.\(column.id)")
    }

    private func move(_ dragged: String) -> Bool {
        guard dragged.hasPrefix(Self.prefix) else { return false }
        let moved = String(dragged.dropFirst(Self.prefix.count))
        guard moved != column.id else { return false }
        browser.changeProperties { properties in
            let order = properties.arranged(columns).map(\.id)
            properties.move(moved, before: Reordering.anchor(dropping: moved, onto: column.id, in: order), in: columns)
        }
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
