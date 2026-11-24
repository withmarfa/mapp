import SwiftUI

/// A column of a Settings table. A column with no `width` takes what the others leave.
struct SettingsTableColumn<Row> {
    let title: LocalizedStringKey
    var width: CGFloat?
    /// How many lines a cell may take; a cell that needs more is cut, and `truncation` says where.
    var lines = 1
    var truncation: Text.TruncationMode = .tail
    let cell: (Row) -> AnyView

    init(
        _ title: LocalizedStringKey, width: CGFloat? = nil, lines: Int = 1, truncation: Text.TruncationMode = .tail,
        @ViewBuilder cell: @escaping (Row) -> some View
    ) {
        self.title = title
        self.width = width
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
            SettingsFilterPopUp(selection: $choice) { choices }
            SettingsTableSearch(text: $search)
        }
    }
}

/// A table's filter: a pop-up with no fill, as a header row draws every control, which shows its shape only under the pointer.
struct SettingsFilterPopUp<Value: Hashable, Choices: View>: View {
    @Binding var selection: Value
    @ViewBuilder let choices: Choices
    @State private var isHovered = false

    var body: some View {
        Picker("Filter", selection: $selection) { choices }
            .labelsHidden()
            .pickerStyle(.menu)
            .buttonStyle(.borderless)
            .controlSize(.large)
            .fontWeight(.regular)
            .fixedSize()
            .frame(height: SettingsTokens.Metric.controlHeight)
            .padding(.horizontal, 4)
            .background(isHovered ? SettingsTokens.buttonFill : .clear, in: .capsule)
            .onHover { isHovered = $0 }
    }
}

private struct TableHeader<Row>: View {
    let columns: [SettingsTableColumn<Row>]
    let hasAction: Bool
    var inset = SettingsTokens.Metric.inset
    var hasCheck = false

    var body: some View {
        HStack(spacing: 12) {
            if hasCheck { Color.clear.frame(width: CheckWidth.value) }
            ForEach(columns.indices, id: \.self) { index in
                Text(columns[index].title)
                    .settingsFont(.tableHeader)
                    .foregroundStyle(SettingsTokens.secondaryText)
                    .frame(width: columns[index].width, alignment: .leading)
                    .frame(maxWidth: columns[index].width == nil ? .infinity : nil, alignment: .leading)
            }
            if hasAction { Color.clear.frame(width: ActionWidth.value) }
        }
        .padding(.horizontal, inset)
        .frame(height: SettingsTokens.Metric.tableHeader)
        .accessibilityHidden(true)
    }
}

private enum ActionWidth { static let value: CGFloat = SettingsTokens.Metric.Column.action }
private enum CheckWidth { static let value: CGFloat = SettingsTokens.Metric.Column.check }

private struct TableRow<Row>: View {
    let row: Row
    let columns: [SettingsTableColumn<Row>]
    let action: SettingsRowAction<Row>?
    let isSelected: Bool
    var isBanded = false
    var inset = SettingsTokens.Metric.inset
    var height = SettingsTokens.Metric.tableRow
    /// Where the table is a page with a checkbox column: whether this row is ticked.
    var check: Binding<Bool>?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
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
        .background(isSelected ? SettingsTokens.selection : (isHovered ? SettingsTokens.hover : (isBanded ? SettingsTokens.band : Color.clear)))
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
            .frame(width: column.width, alignment: .leading)
            .frame(maxWidth: column.width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// A table in a section: light, with no rules between rows but every other row shaded, a page at a time. Its foot says how many it shows of how many
/// and has Show All, which opens the table as a page.
struct SettingsSectionTable<Row: Identifiable>: View {
    let rows: [Row]
    let columns: [SettingsTableColumn<Row>]
    var action: SettingsRowAction<Row>?
    /// How many rows there are in all, where the table holds only a page of them.
    var total: Int?
    var showAll: (() -> Void)?
    /// Whether the foot says how many; a table that is the whole of a short list has none.
    var showsCount = true

    var body: some View {
        SettingsCard {
            VStack(spacing: 0) {
                TableHeader(columns: columns, hasAction: action != nil)
                Rectangle().fill(SettingsTokens.rule).frame(height: 1)
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    TableRow(row: row, columns: columns, action: action, isSelected: false, isBanded: index.isMultiple(of: 2))
                }
                if showsCount || showAll != nil {
                    Rectangle().fill(SettingsTokens.rule).frame(height: 1)
                    HStack {
                        if showsCount {
                            Text(count)
                                .settingsFont(.line)
                                .foregroundStyle(SettingsTokens.secondaryText)
                        }
                        Spacer(minLength: 0)
                        if let showAll { SettingsShowAllButton(action: showAll) }
                    }
                    .padding(.horizontal, SettingsTokens.Metric.inset)
                    .frame(height: 38)
                }
            }
        }
    }

    private var count: String {
        let all = total ?? rows.count
        return rows.count == all
            ? String(localized: "\(all) items")
            : String(localized: "\(rows.count) of \(all.formatted())")
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
            HStack {
                count.settingsFont(.small).foregroundStyle(SettingsTokens.secondaryText)
                Spacer(minLength: 12)
                filter
            }
            .padding(.horizontal, inset)
            .frame(height: SettingsTokens.Metric.pageTableBar)
            Rectangle().fill(SettingsTokens.rule).frame(height: 1)
            TableHeader(columns: columns, hasAction: false, inset: inset, hasCheck: true)
            Rectangle().fill(SettingsTokens.rule).frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        TableRow(
                            row: row, columns: columns, action: nil, isSelected: selection.contains(row.id),
                            isBanded: index.isMultiple(of: 2), inset: inset, height: SettingsTokens.Metric.pageTableRow, check: checked(row.id))
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

    private var inset: CGFloat { SettingsTokens.Metric.pageTableInset }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                count.settingsFont(.small).foregroundStyle(SettingsTokens.secondaryText)
                Spacer(minLength: 12)
                filter
            }
            .padding(.horizontal, inset)
            .frame(height: SettingsTokens.Metric.logTableBar)
            Rectangle().fill(SettingsTokens.rule).frame(height: 1)
            TableHeader(columns: columns, hasAction: false, inset: inset)
            Rectangle().fill(SettingsTokens.rule).frame(height: 1)
            if rows.isEmpty {
                empty.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            TableRow(
                                row: row, columns: columns, action: nil, isSelected: false, isBanded: index.isMultiple(of: 2), inset: inset,
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
