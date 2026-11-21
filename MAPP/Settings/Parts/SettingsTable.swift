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

/// A table's search field, small, at the trailing edge of a section's name or of the page's count.
struct SettingsTableSearch: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(SettingsTokens.tertiaryText)
            TextField("Search", text: $text)
                .labelsHidden()
                .textFieldStyle(.plain)
                .settingsFont(.small)
        }
        .padding(.horizontal, 7)
        .frame(width: 160, height: 24)
        .background(SettingsTokens.buttonFill, in: .rect(cornerRadius: 7, style: .continuous))
    }
}

/// A table's filter and search together, which sit at the trailing edge of a section's name, or of the page's count.
struct SettingsTableFilter<Value: Hashable, Choices: View>: View {
    @Binding var choice: Value
    @Binding var search: String
    @ViewBuilder let choices: Choices

    var body: some View {
        HStack(spacing: 8) {
            Picker("Filter", selection: $choice) { choices }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            SettingsTableSearch(text: $search)
        }
    }
}

private struct TableHeader<Row>: View {
    let columns: [SettingsTableColumn<Row>]
    let hasAction: Bool
    var inset = SettingsTokens.Metric.inset

    var body: some View {
        HStack(spacing: 12) {
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

private enum ActionWidth { static let value: CGFloat = 88 }

private struct TableRow<Row>: View {
    let row: Row
    let columns: [SettingsTableColumn<Row>]
    let action: SettingsRowAction<Row>?
    let isSelected: Bool
    var isBanded = false
    var inset = SettingsTokens.Metric.inset
    var height = SettingsTokens.Metric.sectionTableRow
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            ForEach(columns.indices, id: \.self) { index in
                columns[index].cell(row)
                    .settingsFont(.title)
                    .lineLimit(columns[index].lines)
                    .truncationMode(columns[index].truncation)
                    .frame(width: columns[index].width, alignment: .leading)
                    .frame(maxWidth: columns[index].width == nil ? .infinity : nil, alignment: .leading)
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
                                .settingsFont(.count)
                                .foregroundStyle(SettingsTokens.secondaryText)
                        }
                        Spacer(minLength: 0)
                        if let showAll { SettingsButton("Show All", small: true, action: showAll) }
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

/// A table that is a page of its own: its count on the left and its filter and search together on the right, in one row
/// under the toolbar, then the columns, with selection, and actions at the foot.
struct SettingsPageTable<Row: Identifiable, Filter: View, Foot: View>: View {
    let rows: [Row]
    let columns: [SettingsTableColumn<Row>]
    let count: Text
    @Binding var selection: Set<Row.ID>
    var action: SettingsRowAction<Row>?
    @ViewBuilder let filter: Filter
    @ViewBuilder let foot: Foot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                count.settingsFont(.small).foregroundStyle(SettingsTokens.secondaryText)
                Spacer(minLength: 12)
                filter
            }
            .padding(.horizontal, SettingsTokens.Metric.inset)
            SettingsCard {
                VStack(spacing: 0) {
                    TableHeader(columns: columns, hasAction: action != nil)
                    Rectangle().fill(SettingsTokens.rule).frame(height: 1)
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            TableRow(
                                row: row, columns: columns, action: action, isSelected: selection.contains(row.id),
                                height: SettingsTokens.Metric.pageTableRow
                            )
                            .onTapGesture { toggle(row.id) }
                        }
                    }
                    Rectangle().fill(SettingsTokens.rule).frame(height: 1)
                    HStack(spacing: 8) { foot }
                        .padding(.horizontal, SettingsTokens.Metric.inset)
                        .frame(maxWidth: .infinity, minHeight: SettingsTokens.Metric.pageTableFoot, alignment: .leading)
                }
            }
        }
    }

    private func toggle(_ id: Row.ID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
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
            .frame(height: SettingsTokens.Metric.pageTableBar)
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
                .frame(maxWidth: .infinity, minHeight: SettingsTokens.Metric.pageTableFoot, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SettingsTokens.page)
    }
}
