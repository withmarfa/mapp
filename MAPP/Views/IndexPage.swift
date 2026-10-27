import Charts
import SwiftUI

/// A page of rows that each lead to a place, shown as a list, as cards or as a table, within a width. Sources and
/// Collections are two of them.
struct IndexPage: View {
    let rows: [IndexRow]
    let layout: IndexLayout
    let width: IndexWidth
    /// The heading of the table column that names the types of a row's items.
    let typesTitle: LocalizedStringKey
    /// Whether a card names `secondary` under its title; false where the key under the bar already says it.
    var showsSecondaryOnCards = true
    let open: (IndexRow) -> Void

    var body: some View {
        Group {
            switch layout {
            case .list: IndexList(rows: rows, open: open)
            case .cards: IndexCards(rows: rows, palette: IndexPalette(rows: rows), showsSecondary: showsSecondaryOnCards, open: open)
            case .table: IndexTable(rows: rows, typesTitle: typesTitle, open: open)
            }
        }
        .frame(maxWidth: width.points.map { CGFloat($0) } ?? .infinity)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("IndexPage")
    }
}

/// The icon of a row. Every row has the same neutral look until something about it is known that should tell
/// rows apart.
struct IndexTile: View {
    let symbol: String
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(.quaternary, in: .rect(cornerRadius: size * 0.25))
            .accessibilityHidden(true)
    }
}

/// When a row's latest item changed, as the system words a time before now.
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

private struct IndexList: View {
    let rows: [IndexRow]
    let open: (IndexRow) -> Void

    var body: some View {
        List(rows) { row in
            Button { open(row) } label: {
                HStack(spacing: 12) {
                    IndexTile(symbol: row.symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.title).font(.headline).lineLimit(1)
                        if !row.secondary.isEmpty {
                            Text(verbatim: row.secondary).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(row.count, format: .number).monospacedDigit()
                        if let latest = row.latest {
                            Text("Latest \(latest, format: .relative(presentation: .named, unitsStyle: .abbreviated))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
                }
                .padding(.vertical, 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("IndexRow")
        }
        .listStyle(.inset)
    }
}

private struct IndexCards: View {
    let rows: [IndexRow]
    let palette: IndexPalette
    let showsSecondary: Bool
    let open: (IndexRow) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 480), spacing: 16, alignment: .top)], spacing: 16) {
                ForEach(rows) { row in
                    Button { open(row) } label: { card(row) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("IndexCard")
                }
            }
            .padding(20)
        }
    }

    private func card(_ row: IndexRow) -> some View {
        let shares = IndexRows.collapsing(row.breakdown)
        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    IndexTile(symbol: row.symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.title).font(.headline).lineLimit(1)
                        if showsSecondary, !row.secondary.isEmpty {
                            Text(verbatim: row.secondary).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(row.count, format: .number).font(.title2.weight(.semibold)).monospacedDigit()
                }
                IndexBreakdownBar(shares: shares, palette: palette)
                IndexBreakdownKey(shares: shares, palette: palette)
                Divider()
                HStack {
                    Text("Latest Item")
                    Spacer()
                    IndexLatest(date: row.latest)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(4)
        }
        .contentShape(.rect)
    }
}

/// The colors of the types on one page, so a type has the same color on every card. The most numerous types take
/// the first colors; the share that gathers the rest is gray.
struct IndexPalette {
    private static let colors: [Color] = [.blue, .purple, .green, .orange, .pink, .teal, .indigo, .yellow]
    private let order: [TypeID]

    init(rows: [IndexRow]) {
        var totals: [TypeID: Int] = [:]
        for share in rows.flatMap(\.breakdown) { if let type = share.type { totals[type, default: 0] += share.count } }
        order = totals.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }.map(\.key)
    }

    func color(for share: TypeShare) -> Color {
        guard let type = share.type, let index = order.firstIndex(of: type) else { return .gray }
        return Self.colors[index % Self.colors.count]
    }
}

/// One bar split by type. The key beside it gives the numbers, so the bar is not read out on its own.
struct IndexBreakdownBar: View {
    let shares: [TypeShare]
    let palette: IndexPalette

    var body: some View {
        Chart(shares) { share in
            BarMark(x: .value("Items", share.count))
                .foregroundStyle(palette.color(for: share))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 8)
        .clipShape(.capsule)
        .accessibilityHidden(true)
    }
}

struct IndexBreakdownKey: View {
    let shares: [TypeShare]
    let palette: IndexPalette

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(shares) { share in
                HStack(spacing: 5) {
                    Circle().fill(palette.color(for: share)).frame(width: 7, height: 7).accessibilityHidden(true)
                    Text(verbatim: "\(share.count.formatted()) \(share.label)").lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct IndexTable: View {
    let rows: [IndexRow]
    let typesTitle: LocalizedStringKey
    let open: (IndexRow) -> Void
    @State private var sortOrder = [KeyPathComparator(\IndexRow.title, comparator: .localizedStandard)]
    @State private var selection: Set<IndexRow.ID> = []

    var body: some View {
        Table(rows.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.title, comparator: .localizedStandard) { row in
                HStack(spacing: 10) {
                    IndexTile(symbol: row.symbol, size: 24)
                    Text(verbatim: row.title).lineLimit(1)
                }
            }
            .width(min: 140, ideal: 220)
            TableColumn(typesTitle, value: \.types, comparator: .localizedStandard) { row in
                Text(verbatim: row.types).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 140, ideal: 260)
            TableColumn("Items", value: \.count) { row in
                Text(row.count, format: .number).monospacedDigit()
            }
            .width(min: 60, ideal: 80, max: 120)
            .alignment(.numeric)
            TableColumn("Latest Item", value: \.latestOrOldest) { row in
                IndexLatest(date: row.latest).foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 140, max: 200)
        }
        .contextMenu(forSelectionType: IndexRow.ID.self) { _ in
        } primaryAction: { ids in
            if let row = rows.first(where: { ids.contains($0.id) }) { open(row) }
        }
    }
}
