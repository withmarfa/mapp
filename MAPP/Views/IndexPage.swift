import SwiftUI

/// The measures of an index page, on a 4 point grid.
private enum IndexMetrics {
    static let top: CGFloat = 12
    static let side: CGFloat = 16
    static let icon: CGFloat = 16
}

/// The title of a tab, as the page words it.
extension IndexTab {
    var title: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .yours: "Yours"
        case .fromApps: "From Apps"
        case .apps: "Apps"
        case .keys: "Keys"
        }
    }
}

extension IndexColumn {
    /// The column's heading: a source writes types and its latest item is when it last wrote, and a collection's date is
    /// its own update.
    func title(in place: IndexPlace) -> LocalizedStringKey {
        switch self {
        case .name: place == .sources ? "Source" : "Name"
        case .types: "Writes"
        case .source: "Source"
        case .count: "Items"
        case .latest: place == .sources ? "Latest" : "Updated"
        }
    }
}

/// An index of containers drawn as a table, under its tabs. The page holds no state of its own about the chosen row:
/// the table and the right sidebar read it from `IndexChoice`, so choosing one runs no row's body.
struct IndexPage: View {
    let place: IndexPlace
    /// The rows of the chosen tab and the search, in no order; the table orders them.
    let rows: [IndexRow]
    let tabs: [(tab: IndexTab, count: Int)]
    @Binding var tab: IndexTab
    let choice: IndexChoice
    /// Opens the row's place: a double click, Return, or the context menu.
    let open: (IndexRow) -> Void
    /// Set where a row's source can be renamed or given a mark, by its context menu.
    var edit: ((SourceEditRequest) -> Void)?
    /// Set where a row's collection can be deleted, by its context menu and the Delete key.
    var delete: ((IndexRow) -> Void)?
    /// The button at the trailing edge of the tabs.
    var newCollection: (() -> Void)?
    /// What the table says while the tab has no rows.
    let emptyTab: EmptyState<EmptyView>

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(tabs, id: \.tab) { entry in
                    IndexTabButton(tab: entry.tab, count: entry.count, isSelected: tab == entry.tab) { tab = entry.tab }
                }
                Spacer(minLength: 12)
                if let newCollection {
                    Button("New Collection", systemImage: "plus", action: newCollection)
                        .mappButton(.secondary)
                        .accessibilityIdentifier("NewCollection")
                }
            }
            .padding(.horizontal, IndexMetrics.side)
            .padding(.top, IndexMetrics.top)
            .padding(.bottom, 8)
            if rows.isEmpty {
                emptyTab
            } else {
                IndexTable(place: place, rows: rows, choice: choice, open: open, edit: edit, delete: delete)
            }
        }
        .accessibilityIdentifier("IndexPage")
    }
}

/// One tab: its name and how many rows it holds. The chosen one has the secondary button's fill.
private struct IndexTabButton: View {
    let tab: IndexTab
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(tab.title)
                Text(count, format: .number).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .mappButton(isSelected ? .secondary : .plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("IndexTab.\(tab.rawValue)")
    }
}

/// The mark of a container in the Name column: gray, with no tile, whatever the container is.
private struct IndexNameCell: View {
    let row: IndexRow

    var body: some View {
        HStack(spacing: 8) {
            RowIconImage(icon: row.icon)
                .font(.system(size: IndexMetrics.icon * 0.8))
                .foregroundStyle(.secondary)
                .frame(width: IndexMetrics.icon, height: IndexMetrics.icon)
                .accessibilityHidden(true)
            Text(verbatim: row.title).lineLimit(1)
        }
    }
}

/// The types a source writes: each type's icon in the type's color, with no tile, and its name.
/// A type with no icon takes the neutral color and mark. Three are named and the rest counted.
private struct IndexTypesCell: View {
    @Environment(\.colorScheme) private var scheme
    let shares: [TypeShare]
    private static let shown = 3

    var body: some View {
        HStack(spacing: 10) {
            ForEach(shares.prefix(Self.shown)) { share in
                HStack(spacing: 4) {
                    TypeGlyph(id: share.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(TypeTone(icon: share.icon).color(for: scheme))
                        .accessibilityHidden(true)
                    Text(verbatim: share.label).lineLimit(1)
                }
            }
            if shares.count > Self.shown {
                Text("+\(shares.count - Self.shown)").foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

/// When a container's latest item changed, as the system words a time before now.
struct IndexLatest: View {
    let date: Date?

    var body: some View {
        if let date {
            Text(date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
        } else {
            Text("No Items")
        }
    }
}

/// The rows as a table, as wide as the page. Its cells are views of plain values, so a change of the chosen row
/// finds each unchanged and runs none of their bodies. The order is worked out from the rows and the sort each time
/// this body runs, so the table never draws the rows of another tab or one that has gone; the chosen row is read only
/// by the table's own closures, so choosing one does not run this body.
private struct IndexTable: View {
    let place: IndexPlace
    let rows: [IndexRow]
    let choice: IndexChoice
    let open: (IndexRow) -> Void
    let edit: ((SourceEditRequest) -> Void)?
    let delete: ((IndexRow) -> Void)?
    @AppStorage private var sort: IndexSort

    init(
        place: IndexPlace, rows: [IndexRow], choice: IndexChoice, open: @escaping (IndexRow) -> Void,
        edit: ((SourceEditRequest) -> Void)?, delete: ((IndexRow) -> Void)?
    ) {
        self.place = place
        self.rows = rows
        self.choice = choice
        self.open = open
        self.edit = edit
        self.delete = delete
        _sort = AppStorage(wrappedValue: place.defaultSort, place.sortKey)
    }

    /// The table's second column: what a source writes, or the source that wrote a collection.
    private var secondColumn: IndexColumn { place.columns[1] }
    private var secondKey: KeyPath<IndexRow, String> { place == .sources ? \.types : \.sourceName }

    /// The kept sort, or the page's own while what is kept is of a column the page lacks.
    private var shownSort: IndexSort { place.columns.contains(sort.column) ? sort : place.defaultSort }

    private var sortOrder: Binding<[KeyPathComparator<IndexRow>]> {
        Binding { shownSort.comparators } set: { if let next = IndexSort(comparators: $0) { sort = next } }
    }

    private var selection: Binding<IndexRow.ID?> {
        Binding { choice.chosen } set: { choice.chosen = $0 }
    }

    var body: some View {
        let ordered = shownSort.sorted(rows)
        Table(ordered, selection: selection, sortOrder: sortOrder) {
            TableColumn(IndexColumn.name.title(in: place), value: \.title, comparator: .localizedStandard) { row in
                IndexNameCell(row: row)
            }
            .width(min: 140, ideal: 240)
            TableColumn(secondColumn.title(in: place), value: secondKey, comparator: .localizedStandard) { row in
                if place == .sources {
                    IndexTypesCell(shares: row.breakdown)
                } else {
                    Text(verbatim: row.sourceName).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .width(min: 140, ideal: 280)
            TableColumn(IndexColumn.count.title(in: place), value: \.count) { row in
                Text(row.count, format: .number).monospacedDigit()
            }
            .width(min: 60, ideal: 80, max: 120)
            .alignment(.numeric)
            TableColumn(IndexColumn.latest.title(in: place), value: \.latestOrOldest) { row in
                IndexLatest(date: row.latest).foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 140, max: 200)
        }
        .alternatingRowBackgrounds(.disabled)
        .softSelection(rows: ordered.map(\.id), hovers: true, selection: { choice.chosen })
        .contextMenu(forSelectionType: IndexRow.ID.self) { ids in
            if let row = ordered.first(where: { ids.contains($0.id) }), ids.count == 1 {
                Button("Open") { open(row) }
                if let edit, let code = row.sourceCode {
                    Button("Rename…") { edit(SourceEditRequest(code: code, mode: .name)) }
                    Button("Choose Mark…") { edit(SourceEditRequest(code: code, mode: .mark)) }
                }
                if let delete, row.canDelete {
                    Divider()
                    Button("Delete…", role: .destructive) { delete(row) }
                }
            }
        } primaryAction: { ids in
            if let row = ordered.first(where: { ids.contains($0.id) }) { open(row) }
        }
        .onDeleteCommand {
            if let delete, let row = choice.row(in: ordered), row.canDelete { delete(row) }
        }
        .contentMargins(.horizontal, IndexMetrics.side, for: .scrollContent)
        .accessibilityIdentifier("IndexTable")
    }
}
