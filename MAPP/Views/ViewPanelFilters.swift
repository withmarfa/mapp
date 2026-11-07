import SwiftUI

/// The panel's Filters: a row for each filtered column with Is or Is Not and its values, Add Filter, and the
/// conditions of the view's filter that the window cannot show, which a save leaves as they are.
struct ViewPanelFilters: View {
    @CurrentLibrary private var library
    @Environment(\.interfaceTextSize) private var textSize
    let browser: Browser
    let panel: ViewPanel
    let content: ItemTableContent

    var body: some View {
        let options = browser.tableOptions[browser.item] ?? ItemTableOptions()
        let filtered = content.columns.filter { options.filters[$0.id]?.isEmpty == false }
        let held = heldConditions
        ViewPanelSection(title: "Filters") {
            InspectorBox {
                ForEach(filtered) { column in
                    FilterRow(browser: browser, column: column, rows: content.allRows)
                }
                Menu {
                    FilterMenuItems(browser: browser)
                } label: {
                    Label("Add Filter", systemImage: "plus")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .disabled(content.categoricalColumns.isEmpty)
                .accessibilityIdentifier("ViewPanelAddFilter")
                ForEach(held, id: \.self) { condition in
                    HStack(spacing: InspectorMetrics.gap) {
                        Image(systemName: "lock").foregroundStyle(.tertiary).accessibilityHidden(true)
                        Text(verbatim: condition).foregroundStyle(.secondary).lineLimit(2)
                    }
                    .help("Marfa keeps this condition. This window can’t show it, and saving leaves it as it is.")
                }
            }
        }
    }

    /// The conditions of the saved view's own filter that no row above stands for.
    private var heldConditions: [String] {
        guard let id = panel.viewID, let view = library.views.first(where: { $0.id == id }) else { return [] }
        return ViewDraft.unshownConditions(of: view.query, catalogue: library.catalogue)
    }
}

/// One filtered column: its name, whether the filter is Is or Is Not, and the values it keeps.
private struct FilterRow: View {
    @Environment(\.interfaceTextSize) private var textSize
    let browser: Browser
    let column: ItemTableColumn
    let rows: [ItemTableRow]

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        let options = browser.tableOptions[browser.item] ?? ItemTableOptions()
        let kept = options.filters[column.id] ?? []
        let categories = ItemTableLayout.categories(of: rows, by: column)
        HStack(spacing: 6) {
            Text(verbatim: column.label)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 56 * scale, alignment: .leading)
                .help(column.label)
            Picker("Condition", selection: Binding { options.isNegated(column.id) } set: { negated in
                browser.tableOptions[browser.item, default: .init()].setFilter(column.id, values: kept, negated: negated)
            }) {
                Text("is").tag(false)
                Text("is not").tag(true)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 70 * scale)
            .accessibilityIdentifier("ViewPanelFilterCondition")
            Menu {
                ForEach(categories, id: \.id) { category in
                    Toggle(isOn: binding(for: category.id, kept: kept)) {
                        ItemTableMenuLabel(
                            column: column, value: category.id.isEmpty ? nil : category.id, title: "\(category.title)  \(category.rows.count)")
                    }
                }
            } label: {
                Text(verbatim: summary(of: kept, in: categories)).lineLimit(1).truncationMode(.tail)
            }
            .menuStyle(.button)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("ViewPanelFilterValues")
            Button("Remove Filter", systemImage: "xmark.circle.fill") {
                browser.tableOptions[browser.item, default: .init()].clearFilter(column.id)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .accessibilityIdentifier("ViewPanelFilterRemove")
        }
        .interfaceFont(.body)
    }

    private func binding(for value: String, kept: Set<String>) -> Binding<Bool> {
        Binding {
            kept.contains(value)
        } set: { isOn in
            var next = kept
            if isOn { next.insert(value) } else { next.remove(value) }
            browser.tableOptions[browser.item, default: .init()].setFilter(column.id, values: next)
        }
    }

    /// The values kept by name, in the menu's order, and a value no row holds any more by what it was kept as.
    private func summary(of kept: Set<String>, in categories: [ItemTableGroup]) -> String {
        let named = categories.filter { kept.contains($0.id) }.map(\.title)
        let known = Set(categories.map(\.id))
        let rest = kept.subtracting(known).sorted().map { $0.isEmpty ? String(localized: "None") : $0 }
        return (named + rest).joined(separator: ", ")
    }
}
