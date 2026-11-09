import SwiftUI

/// The panel's Sort: up to `ViewDraft.maxSortKeys` keys, each a property chosen with Add Sort and the direction in its own words
/// (Newest First for a date). A key is dragged to a new place, or moved with its menu, and the first sorts first.
struct ViewPanelSort: View {
    @Environment(\.interfaceTextSize) private var textSize
    let browser: Browser
    let content: ItemTableContent

    var body: some View {
        let sort = content.sort
        let unused = content.columns.filter { column in !sort.contains { $0.column.id == column.id } }
        ViewPanelSection(title: "Sort") {
            InspectorBox {
                ForEach(sort, id: \.column.id) { key in
                    SortRow(browser: browser, content: content, key: key, sort: sort)
                }
                if sort.count < ViewDraft.maxSortKeys, !unused.isEmpty {
                    Menu {
                        ForEach(unused) { column in
                            Button(column.label) { set(sort + [ItemTableComparator(column: column, order: column.firstOrder)]) }
                        }
                    } label: {
                        Label("Add Sort", systemImage: "plus")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .accessibilityIdentifier("ViewPanelAddSort")
                }
            }
        }
    }

    private func set(_ sort: [ItemTableComparator]) {
        browser.orderSearch(byRelevance: false)
        browser.tableOptions[browser.item, default: .init()].sort = sort
    }
}

private struct SortRow: View {
    @Environment(\.interfaceTextSize) private var textSize
    let browser: Browser
    let content: ItemTableContent
    let key: ItemTableComparator
    let sort: [ItemTableComparator]

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        HStack(spacing: InspectorMetrics.gap) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11 * scale))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            // The property is fixed once added, as a filter's is: Add Sort chooses it, and the row only turns it round.
            Text(key.column.label)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("ViewPanelSortColumn")
            Picker("Direction", selection: Binding { key.order } set: { order in
                replace(ItemTableComparator(column: key.column, order: order))
            }) {
                Text(key.column.ascendingTitle).tag(SortOrder.forward)
                Text(key.column.descendingTitle).tag(SortOrder.reverse)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityIdentifier("ViewPanelSortDirection")
            Button("Remove Sort", systemImage: "minus.circle.fill") { write(sort.filter { $0.column.id != key.column.id }) }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .disabled(sort.count <= 1)
                .accessibilityIdentifier("ViewPanelSortRemove")
        }
        .interfaceFont(.body)
        .contentShape(.rect)
        .draggable(LayoutRowDrag(id: dragID(key.column.id)))
        .dropDestination(for: LayoutRowDrag.self) { drops, _ in
            guard let drop = drops.first, let moved = column(in: drop.id), moved != key.column.id else { return false }
            write(Reordering.moving(moved, before: key.column.id, in: sort.map(\.column.id)).compactMap { id in
                sort.first { $0.column.id == id }
            })
            return true
        }
        .contextMenu {
            Button("Move Up") { write(Reordering.moving(key, by: -1, in: sort)) }
                .disabled(sort.first == key)
            Button("Move Down") { write(Reordering.moving(key, by: 1, in: sort)) }
                .disabled(sort.last == key)
            Button("Remove Sort") { write(sort.filter { $0.column.id != key.column.id }) }
                .disabled(sort.count <= 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ViewPanelSortRow.\(key.column.id)")
    }

    private func replace(_ next: ItemTableComparator) {
        write(sort.map { $0.column.id == key.column.id ? next : $0 })
    }

    private func write(_ next: [ItemTableComparator]) {
        browser.orderSearch(byRelevance: false)
        browser.tableOptions[browser.item, default: .init()].sort = next
    }

    private static let prefix = "sort:"

    private func dragID(_ column: String) -> String { Self.prefix + column }

    private func column(in drag: String) -> String? {
        drag.hasPrefix(Self.prefix) ? String(drag.dropFirst(Self.prefix.count)) : nil
    }
}
