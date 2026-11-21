import SwiftUI

/// A column of a Settings table. A column with no `width` takes what the others leave.
struct SettingsTableColumn<Row> {
    let title: LocalizedStringKey
    var width: CGFloat?
    let cell: (Row) -> AnyView

    init(_ title: LocalizedStringKey, width: CGFloat? = nil, @ViewBuilder cell: @escaping (Row) -> some View) {
        self.title = title
        self.width = width
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
    var hasCheck = false

    var body: some View {
        HStack(spacing: 12) {
            if hasCheck { Color.clear.frame(width: CheckWidth.value) }
            ForEach(columns.indices, id: \.self) { index in
                Text(columns[index].title)
                    .settingsFont(.line)
                    .foregroundStyle(SettingsTokens.secondaryText)
                    .frame(width: columns[index].width, alignment: .leading)
                    .frame(maxWidth: columns[index].width == nil ? .infinity : nil, alignment: .leading)
            }
            if hasAction { Color.clear.frame(width: ActionWidth.value) }
        }
        .padding(.horizontal, inset)
        .frame(height: 30)
        .accessibilityHidden(true)
    }
}

private enum ActionWidth { static let value: CGFloat = 70 }
private enum CheckWidth { static let value: CGFloat = 18 }

private struct TableRow<Row>: View {
    let row: Row
    let columns: [SettingsTableColumn<Row>]
    let action: SettingsRowAction<Row>?
    let isSelected: Bool
    var isBanded = false
    var inset = SettingsTokens.Metric.inset
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
                columns[index].cell(row)
                    .settingsFont(.title)
                    .lineLimit(1)
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
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
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

    var body: some View {
        SettingsCard {
            VStack(spacing: 0) {
                TableHeader(columns: columns, hasAction: action != nil)
                Rectangle().fill(SettingsTokens.rule).frame(height: 1)
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    TableRow(row: row, columns: columns, action: action, isSelected: false, isBanded: index.isMultiple(of: 2))
                }
                Rectangle().fill(SettingsTokens.rule).frame(height: 1)
                HStack {
                    Text(count)
                        .settingsFont(.count)
                        .foregroundStyle(SettingsTokens.secondaryText)
                    Spacer(minLength: 0)
                    if let showAll { SettingsButton("Show All", small: true, action: showAll) }
                }
                .padding(.horizontal, SettingsTokens.Metric.inset)
                .frame(height: 38)
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
                            isBanded: index.isMultiple(of: 2), inset: inset, check: checked(row.id))
                            .onTapGesture { checked(row.id).wrappedValue.toggle() }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            Rectangle().fill(SettingsTokens.rule).frame(height: 1)
            HStack(spacing: 8) {
                Text(selected)
                    .settingsFont(.count)
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
