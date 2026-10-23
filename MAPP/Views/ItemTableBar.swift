import SwiftUI

/// The bar above a table: its filters as tokens a click removes, then Filter, Sort, Group and Properties, and how
/// many items show. Each choice is the place's, kept for the window.
struct ItemTableBar: View {
    @Binding var options: ItemTableOptions
    let columns: [ItemTableColumn]
    /// Every row before the filters, so a filter can offer values it is hiding.
    let rows: [ItemTableRow]
    let shownCount: Int
    let sort: [ItemTableComparator]
    let grouping: ItemTableColumn?
    @Binding var customization: TableColumnCustomization<ItemTableRow>

    /// The columns a table can be filtered and grouped by: those with a few values to pick from, where some row
    /// holds one.
    private var categorical: [ItemTableColumn] {
        columns.filter { column in column.isCategorical && rows.contains { column.category(of: $0) != nil } }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                filterMenu
                sortMenu
                groupMenu
                ForEach(activeFilters, id: \.column.id) { filter in
                    FilterToken(text: tokenText(filter.column, filter.kept)) {
                        options.filters[filter.column.id] = nil
                    }
                }
                Spacer(minLength: 12)
                countText
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityIdentifier("ItemTableCount")
                propertiesMenu
            }
            .controlSize(.small)
            .menuStyle(.button)
            .buttonStyle(.accessoryBar)
            .menuIndicator(.hidden)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            Divider()
        }
        .background(.windowBackground)
        .interfaceFont(.callout)
    }

    private var countText: Text {
        shownCount == rows.count ? Text("^[\(rows.count) item](inflect: true)") : Text("\(shownCount) of \(rows.count)")
    }

    // MARK: Filter

    private var activeFilters: [(column: ItemTableColumn, kept: Set<String>)] {
        columns.compactMap { column in options.filters[column.id].map { (column, $0) } }
    }

    private var filterMenu: some View {
        Menu {
            ForEach(categorical) { column in
                Menu(column.label) {
                    ForEach(categories(of: column), id: \.value) { category in
                        Toggle(isOn: filterBinding(column, category.value)) {
                            ItemTableMenuLabel(column: column, value: category.value.isEmpty ? nil : category.value,
                                               title: "\(category.title)  \(category.count)")
                        }
                    }
                }
            }
            if !options.filters.isEmpty {
                Divider()
                Button("Clear Filters") { options.filters = [:] }
            }
        } label: {
            Label("Filter", systemImage: options.filters.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
        }
        .help("Show only some items")
        .accessibilityIdentifier("ItemTableFilter")
    }

    /// A column's values with how many rows hold each, in its groups' order, then the empty cells.
    private func categories(of column: ItemTableColumn) -> [(value: String, title: String, count: Int)] {
        ItemTableLayout.groups(of: rows, by: column).map { ($0.id, $0.title, $0.rows.count) }
    }

    private func filterBinding(_ column: ItemTableColumn, _ value: String) -> Binding<Bool> {
        Binding {
            options.filters[column.id]?.contains(value) ?? false
        } set: { isOn in
            var kept = options.filters[column.id] ?? []
            if isOn { kept.insert(value) } else { kept.remove(value) }
            options.filters[column.id] = kept.isEmpty ? nil : kept
        }
    }

    private func tokenText(_ column: ItemTableColumn, _ kept: Set<String>) -> String {
        let titles = categories(of: column).filter { kept.contains($0.value) }.map(\.title)
        let shown = titles.count > 2 ? titles.prefix(2).joined(separator: ", ") + " +\(titles.count - 2)" : titles.joined(separator: ", ")
        return "\(column.label): \(shown)"
    }

    // MARK: Sort

    private var sortMenu: some View {
        let first = sort.first
        return Menu {
            Picker("Sort By", selection: Binding { first?.column.id ?? "" } set: { id in
                guard let column = columns.first(where: { $0.id == id }) else { return }
                options.sort = [ItemTableComparator(column: column, order: column.firstOrder)]
            }) {
                ForEach(shownColumns) { Text($0.label).tag($0.id) }
            }
            .pickerStyle(.inline)
            Divider()
            Picker("Order", selection: Binding { first?.order ?? .forward } set: { order in
                guard let first else { return }
                options.sort = [ItemTableComparator(column: first.column, order: order)] + sort.dropFirst()
            }) {
                Text(first.map(ascendingTitle) ?? String(localized: "Ascending")).tag(SortOrder.forward)
                Text(first.map(descendingTitle) ?? String(localized: "Descending")).tag(SortOrder.reverse)
            }
            .pickerStyle(.inline)
        } label: {
            Label(first.map { String(localized: "Sort: \($0.column.label)") } ?? String(localized: "Sort"),
                  systemImage: first?.order == .reverse ? "arrow.down" : "arrow.up")
        }
        .help("Choose the order of the rows")
        .accessibilityIdentifier("ItemTableSort")
    }

    private func ascendingTitle(_ comparator: ItemTableComparator) -> String {
        switch comparator.column.style {
        case .date: String(localized: "Oldest First")
        case .number, .duration, .priority: String(localized: "Lowest First")
        case .status: String(localized: "In Progress First")
        default: String(localized: "A to Z")
        }
    }

    private func descendingTitle(_ comparator: ItemTableComparator) -> String {
        switch comparator.column.style {
        case .date: String(localized: "Newest First")
        case .number, .duration, .priority: String(localized: "Highest First")
        case .status: String(localized: "Finished First")
        default: String(localized: "Z to A")
        }
    }

    // MARK: Group

    private var groupMenu: some View {
        Menu {
            Picker("Group By", selection: Binding { grouping?.id ?? "" } set: { id in
                options.grouping = id.isEmpty ? .none : .column(id)
                options.collapsed = nil
            }) {
                Text("None").tag("")
                Divider()
                ForEach(categorical) { Text($0.label).tag($0.id) }
            }
            .pickerStyle(.inline)
        } label: {
            Label(grouping.map { String(localized: "Group: \($0.label)") } ?? String(localized: "Group"), systemImage: "rectangle.grid.1x2")
        }
        .help("Put the rows into groups")
        .accessibilityIdentifier("ItemTableGroup")
    }

    // MARK: Properties

    private var shownColumns: [ItemTableColumn] { columns.filter(isShown) }

    private func isShown(_ column: ItemTableColumn) -> Bool {
        switch customization[visibility: column.id] {
        case .visible: true
        case .hidden: false
        default: column.isShownByDefault
        }
    }

    private var propertiesMenu: some View {
        Menu {
            Section("Shown in Table") {
                ForEach(columns.filter { $0.content != .title }) { column in
                    Toggle(column.label, isOn: Binding { isShown(column) } set: {
                        customization[visibility: column.id] = $0 ? .visible : .hidden
                    })
                }
            }
            Divider()
            Button("Reset Columns") { customization = TableColumnCustomization() }
        } label: {
            Label("Properties", systemImage: "slider.horizontal.3")
        }
        .help("Choose which properties show as columns")
        .accessibilityIdentifier("ItemTableProperties")
    }
}

/// A filter in use, which a click removes.
private struct FilterToken: View {
    let text: String
    let remove: () -> Void

    var body: some View {
        Button(action: remove) {
            HStack(spacing: 4) {
                Text(text).lineLimit(1)
                Image(systemName: "xmark").font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(.tint)
            .background(.tint.opacity(0.12), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help("Remove this filter")
        .accessibilityLabel(Text("Remove filter \(text)"))
    }
}
