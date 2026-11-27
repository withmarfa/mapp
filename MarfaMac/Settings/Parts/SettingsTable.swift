import SwiftUI

/// A column of a Settings table. A column with no `width` takes what the others leave.
struct SettingsTableColumn<Row> {
    let title: LocalizedStringKey
    var width: CGFloat?
    let alignment: Alignment
    /// How many lines a cell may take; a cell that needs more is cut, and `truncation` says where.
    var lines = 1
    var truncation: Text.TruncationMode = .tail
    let cell: (Row) -> AnyView

    init(
        _ title: LocalizedStringKey, width: CGFloat? = nil, numeric: Bool = false, lines: Int = 1, truncation: Text.TruncationMode = .tail,
        @ViewBuilder cell: @escaping (Row) -> some View
    ) {
        self.title = title
        self.width = width
        self.alignment = numeric ? .trailing : .leading
        self.lines = lines
        self.truncation = truncation
        self.cell = { AnyView(cell($0)) }
    }
}

/// What every row of a table offers, shown on every row and never only on the one under the pointer.
struct SettingsRowAction<Row> {
    let title: LocalizedStringKey
    var isEnabled: (Row) -> Bool = { _ in true }
    let perform: (Row) -> Void
}

/// A table's search field, 28 points, at the trailing edge of a section's name or of the page's count.
struct SettingsTableSearch: View {
    @Binding var text: String

    var body: some View {
        SettingsSearchField(prompt: String(localized: "Search"), text: $text)
    }
}

/// A table's filter and search together, which sit at the trailing edge of a section's name, or of the page's count.
struct SettingsTableFilter<Value: Hashable, Choices: View>: View {
    @Binding var choice: Value
    @Binding var search: String
    @ViewBuilder let choices: Choices

    var body: some View {
        HStack(spacing: SettingsTokens.Metric.searchSpacing) {
            SettingsHeaderPopUp("Filter", selection: $choice) { choices }
            SettingsTableSearch(text: $search)
        }
    }
}

/// A section or list header choice that fits its title and only shows its shape under the pointer.
struct SettingsHeaderPopUp<Value: Hashable, Choices: View>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    @ViewBuilder let choices: Choices
    @State private var isHovered = false

    init(_ title: LocalizedStringKey, selection: Binding<Value>, @ViewBuilder choices: () -> Choices) {
        self.title = title
        _selection = selection
        self.choices = choices()
    }

    var body: some View {
        Picker(title, selection: $selection) { choices }
            .labelsHidden()
            .pickerStyle(.menu)
            .buttonStyle(.borderless)
            .controlSize(.large)
            .fontWeight(.regular)
            .fixedSize()
            .frame(minHeight: SettingsTokens.Metric.controlHeight)
            .padding(.horizontal, SettingsTokens.Metric.headerChoicePadding)
            .background(isHovered ? SettingsTokens.buttonFill : .clear, in: .capsule)
            .onHover { isHovered = $0 }
    }
}

/// Which column a log is ordered by, and which way. The column is its index in the table.
struct SettingsColumnSort: Equatable {
    var column: Int
    var ascending: Bool
}

/// A bar above a list, with a count or tabs leading and search or choices trailing.
struct SettingsListHeader<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: SettingsTokens.Metric.searchSpacing) {
            leading
            Spacer(minLength: 0)
            trailing
        }
    }
}

private struct TableHeader<Row>: View {
    let columns: [SettingsTableColumn<Row>]
    let hasAction: Bool
    var inset = SettingsTokens.Metric.sectionTableInset
    var height = SettingsTokens.Metric.tableHeader
    var hasCheck = false
    /// Set together: a log's headings then order the rows, and say which way.
    var sort: SettingsColumnSort?
    var onColumnSort: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: SettingsTokens.Metric.sectionTableColumnGap) {
            if hasCheck { Color.clear.frame(width: CheckWidth.value) }
            ForEach(columns.indices, id: \.self) { index in
                heading(columns[index], index: index)
            }
            if hasAction { Color.clear.frame(width: ActionWidth.value) }
        }
        .padding(.horizontal, inset)
        .frame(minHeight: height)
        .accessibilityHidden(onColumnSort == nil)
    }

    /// A heading is a label, or a button where the table orders by it. The mark is only on the column in force.
    private func heading(_ column: SettingsTableColumn<Row>, index: Int) -> some View {
        let title = HStack(spacing: SettingsTokens.Metric.dotGap) {
            Text(column.title)
            if sort?.column == index {
                Image(systemName: sort?.ascending == true ? "chevron.up" : "chevron.down")
                    .accessibilityHidden(true)
            }
        }
        .settingsFont(.tableHeader)
        .foregroundStyle(SettingsTokens.secondaryText)
        .frame(width: column.width, alignment: column.alignment)
        .frame(maxWidth: column.width == nil ? .infinity : nil, alignment: column.alignment)
        return Group {
            if let onColumnSort {
                Button { onColumnSort(index) } label: { title }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(sort?.column == index ? .isSelected : [])
            } else {
                title
            }
        }
    }
}

private enum ActionWidth { static let value: CGFloat = SettingsTokens.Metric.Column.action }
private enum CheckWidth { static let value: CGFloat = SettingsTokens.Metric.Column.check }

private struct TableRow<Row>: View {
    let row: Row
    let columns: [SettingsTableColumn<Row>]
    let action: SettingsRowAction<Row>?
    let isSelected: Bool
    var inset = SettingsTokens.Metric.sectionTableInset
    var height = SettingsTokens.Metric.tableRow
    /// Where the table is a page with a checkbox column: whether this row is ticked.
    var check: Binding<Bool>?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: SettingsTokens.Metric.sectionTableColumnGap) {
            if let check {
                Toggle(isOn: check) { EmptyView() }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .frame(width: CheckWidth.value)
            }
            ForEach(columns.indices, id: \.self) { index in
                cell(columns[index])
            }
            if let action {
                SettingsButton(action.title, small: true) { action.perform(row) }
                    .disabled(!action.isEnabled(row))
                    .frame(width: ActionWidth.value, alignment: .trailing)
            }
        }
        .padding(.horizontal, inset)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
        .background(isSelected ? SettingsTokens.selection : (isHovered ? SettingsTokens.hover : Color.clear))
        .contentShape(.rect)
        .onHover { isHovered = $0 }
    }

    private func cell(_ column: SettingsTableColumn<Row>) -> some View {
        column.cell(row)
            .settingsFont(.title)
            .lineLimit(column.lines)
            .truncationMode(column.truncation)
            // A cell that wraps grows its row rather than being cut, keeping the row's padding; a row of one line stays at its height.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, SettingsTokens.Metric.tableCellPadding)
            .frame(width: column.width, alignment: column.alignment)
            .frame(maxWidth: column.width == nil ? .infinity : nil, alignment: column.alignment)
    }
}

/// A section table shows a preview of longer lists. Show All expands the table or opens a dedicated page.
struct SettingsSectionTable<Row: Identifiable>: View {
    let rows: [Row]
    let columns: [SettingsTableColumn<Row>]
    var action: SettingsRowAction<Row>?
    var showAll: (() -> Void)?
    @State private var expanded = false

    private var preview: SettingsTablePreview { SettingsTablePreview(total: rows.count, expanded: expanded) }

    var body: some View {
        SettingsCard {
            VStack(spacing: 0) {
                TableHeader(columns: columns, hasAction: action != nil, height: SettingsTokens.Metric.tableRow)
                Rectangle().fill(SettingsTokens.rule).frame(height: SettingsTokens.Metric.ruleThickness)
                ForEach(rows.prefix(preview.visibleCount)) { row in
                    TableRow(row: row, columns: columns, action: action, isSelected: false)
                }
                if let count = preview.countLabel {
                    Rectangle().fill(SettingsTokens.rule).frame(height: SettingsTokens.Metric.ruleThickness)
                    HStack {
                        Text(verbatim: count).settingsFont(.line).foregroundStyle(SettingsTokens.secondaryText)
                        Spacer(minLength: 0)
                        SettingsShowAllButton { if let showAll { showAll() } else { expanded = true } }
                    }
                    .padding(.horizontal, SettingsTokens.Metric.sectionTableInset)
                    .frame(minHeight: SettingsTokens.Metric.tableFooterHeight)
                }
            }
        }
    }
}

struct SettingsTablePreview {
    let total: Int
    var expanded = false

    var visibleCount: Int {
        !expanded && total > SettingsTokens.Metric.tablePreviewThreshold ? SettingsTokens.Metric.tablePreviewCount : total
    }

    var countLabel: String? {
        visibleCount < total ? String(localized: "\(visibleCount.formatted()) of \(total.formatted())") : nil
    }
}

/// A table that is a page of its own: it fills the pane edge to edge, with its count on the left and its filter and search
/// together on the right under the toolbar, then a checkbox column and the columns, and at the foot how many are
/// selected of how many, with the actions for the selection. The rows scroll between the header and the foot.
struct SettingsPageTable<Row: Identifiable, Filter: View, Foot: View>: View {
    let rows: [Row]
    let columns: [SettingsTableColumn<Row>]
    let count: Text
    @Binding var selection: Set<Row.ID>
    @ViewBuilder let filter: Filter
    @ViewBuilder let foot: Foot

    private var inset: CGFloat { SettingsTokens.Metric.pageTableInset }

    var body: some View {
        VStack(spacing: 0) {
            SettingsListHeader {
                count.settingsFont(.small).foregroundStyle(SettingsTokens.secondaryText)
            } trailing: {
                filter
            }
            .padding(.horizontal, inset)
            .frame(minHeight: SettingsTokens.Metric.pageTableBar)
            Rectangle().fill(SettingsTokens.rule).frame(height: 1)
            TableHeader(columns: columns, hasAction: false, inset: inset, hasCheck: true)
            Rectangle().fill(SettingsTokens.rule).frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        TableRow(
                            row: row, columns: columns, action: nil, isSelected: selection.contains(row.id),
                            inset: inset, height: SettingsTokens.Metric.pageTableRow, check: checked(row.id))
                            .onTapGesture { checked(row.id).wrappedValue.toggle() }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            Rectangle().fill(SettingsTokens.rule).frame(height: 1)
            HStack(spacing: 8) {
                Text(selected)
                    .settingsFont(.line)
                    .foregroundStyle(SettingsTokens.secondaryText)
                Spacer(minLength: 12)
                foot
            }
            .padding(.horizontal, inset)
            .frame(maxWidth: .infinity, minHeight: SettingsTokens.Metric.pageTableBar, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SettingsTokens.page)
    }

    private var selected: String { Self.selectedText(selection.count, of: rows.count) }

    /// "2 of 1,204 selected", or "None selected".
    static func selectedText(_ selected: Int, of total: Int) -> String {
        selected == 0
            ? String(localized: "None selected")
            : String(localized: "\(selected.formatted()) of \(total.formatted()) selected")
    }

    private func checked(_ id: Row.ID) -> Binding<Bool> {
        Binding {
            selection.contains(id)
        } set: { on in
            if on { selection.insert(id) } else { selection.remove(id) }
        }
    }
}

/// A read-only table that is a page of its own, as a log is: it fills the pane edge to edge, with its count on the left and its
/// filter and search together on the right under the toolbar, then the columns, and at the foot where the page stands with its
/// way to the next. The rows scroll between the header and the foot. `empty` stands in the rows' place where there are none.
struct SettingsLogTable<Row: Identifiable, Filter: View, Foot: View, Empty: View>: View {
    let rows: [Row]
    let columns: [SettingsTableColumn<Row>]
    let count: Text
    @ViewBuilder let filter: Filter
    @ViewBuilder let foot: Foot
    @ViewBuilder let empty: Empty
    /// Where the headings order the rows. Nil leaves them as labels, as every table but a log does.
    var sort: SettingsColumnSort?
    var onColumnSort: ((Int) -> Void)?

    private var inset: CGFloat { SettingsTokens.Metric.pageTableInset }

    var body: some View {
        VStack(spacing: 0) {
            SettingsListHeader {
                count.settingsFont(.small).foregroundStyle(SettingsTokens.secondaryText)
            } trailing: {
                filter
            }
            .padding(.horizontal, inset)
            .frame(minHeight: SettingsTokens.Metric.logTableBar)
            Rectangle().fill(SettingsTokens.rule).frame(height: 1)
            TableHeader(columns: columns, hasAction: false, inset: inset, sort: sort, onColumnSort: onColumnSort)
            Rectangle().fill(SettingsTokens.rule).frame(height: 1)
            if rows.isEmpty {
                empty.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            TableRow(
                                row: row, columns: columns, action: nil, isSelected: false, inset: inset,
                                height: SettingsTokens.Metric.pageTableRow)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            Rectangle().fill(SettingsTokens.rule).frame(height: 1)
            HStack(spacing: 8) { foot }
                .padding(.horizontal, inset)
                .frame(maxWidth: .infinity, minHeight: SettingsTokens.Metric.logTableFoot, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SettingsTokens.page)
    }
}
