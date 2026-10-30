import Charts
import SwiftUI

/// The measures the three layouts share, on a 4 point grid.
private enum IndexMetrics {
    static let top: CGFloat = 16
    static let side: CGFloat = 24
    static let tile: CGFloat = 28
    static let radius: CGFloat = 12
}

/// A page of rows that each lead to a place, shown as a list, as cards or as a table, within a width. Sources and
/// Collections are two of them.
struct IndexPage: View {
    let rows: [IndexRow]
    /// The colors of the types of all the places, not only the rows shown, so a search keeps each type's color.
    let palette: IndexPalette
    let layout: IndexLayout
    let width: IndexWidth
    /// The heading of the table column that names the types of a row's items.
    let typesTitle: LocalizedStringKey
    /// Whether a card names `secondary` under its title; false where the key under the bar already says it.
    var showsSecondaryOnCards = true
    let open: (IndexRow) -> Void
    @State private var isUnderToolbar = false

    var body: some View {
        Group {
            switch layout {
            case .list: IndexList(rows: rows, isUnderToolbar: $isUnderToolbar, open: open)
            case .cards: IndexCards(rows: rows, palette: palette, showsSecondary: showsSecondaryOnCards, isUnderToolbar: $isUnderToolbar, open: open)
            case .table: IndexTable(rows: rows, typesTitle: typesTitle, open: open)
            }
        }
        .contentMargins(.top, IndexMetrics.top, for: .scrollContent)
        .frame(maxWidth: width.points.map { CGFloat($0) } ?? .infinity)
        .frame(maxWidth: .infinity)
        // The content is narrower than its column, so the band is drawn at the column's width, here, and not by the
        // scroll view at the content's.
        .toolbarBand(isUnderToolbar: isUnderToolbar)
        .accessibilityIdentifier("IndexPage")
    }
}

/// The icon of a row. Every row has the same neutral look until something about it is known that should tell
/// rows apart.
struct IndexTile: View {
    let icon: RowIcon
    var size: CGFloat = IndexMetrics.tile

    var body: some View {
        RowIconImage(icon: icon)
            .font(.system(size: size * 0.5))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: size * 0.25).strokeBorder(.separator))
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
    @Binding var isUnderToolbar: Bool
    let open: (IndexRow) -> Void
    @State private var hovered: IndexRow.ID?
    private let inset = IndexMetrics.side
    private let spacing: CGFloat = 12

    var body: some View {
        List(rows) { row in
            Button { open(row) } label: {
                HStack(spacing: spacing) {
                    IndexTile(icon: row.icon)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: row.title).fontWeight(.semibold).lineLimit(1)
                        if !row.secondary.isEmpty {
                            Text(verbatim: row.secondary).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 12)
                    Text(row.count, format: .number)
                        .monospacedDigit()
                        .frame(minWidth: 48, alignment: .trailing)
                    IndexLatest(date: row.latest)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(minWidth: 72, alignment: .trailing)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
                .padding(.horizontal, inset)
                .padding(.vertical, 10)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { inside in
                if inside { hovered = row.id } else if hovered == row.id { hovered = nil }
            }
            .listRowInsets(EdgeInsets())
            .alignmentGuide(.listRowSeparatorLeading) { _ in inset + IndexMetrics.tile + spacing }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hovered == row.id ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
                    .padding(.horizontal, 8)
            )
            .accessibilityIdentifier("IndexRow")
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .reportsContentUnderToolbar($isUnderToolbar)
    }
}

private struct IndexCards: View {
    let rows: [IndexRow]
    let palette: IndexPalette
    let showsSecondary: Bool
    @Binding var isUnderToolbar: Bool
    let open: (IndexRow) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 480), spacing: 16, alignment: .top)], spacing: 16) {
                ForEach(rows) { row in
                    IndexCard(row: row, palette: palette, showsSecondary: showsSecondary, open: open)
                }
            }
            .padding(.horizontal, IndexMetrics.side)
            .padding(.bottom, IndexMetrics.side)
        }
        .reportsContentUnderToolbar($isUnderToolbar)
    }
}

private struct IndexCard: View {
    let row: IndexRow
    let palette: IndexPalette
    let showsSecondary: Bool
    let open: (IndexRow) -> Void
    @State private var isHovered = false

    var body: some View {
        let shares = IndexRows.collapsing(row.breakdown)
        let shape = RoundedRectangle(cornerRadius: IndexMetrics.radius)
        Button { open(row) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    IndexTile(icon: row.icon)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: row.title).fontWeight(.semibold).lineLimit(1)
                        if showsSecondary, !row.secondary.isEmpty {
                            Text(verbatim: row.secondary).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(row.count, format: .number).font(.title3.weight(.semibold)).monospacedDigit()
                }
                IndexBreakdownBar(shares: shares, palette: palette)
                IndexBreakdownKey(shares: shares, palette: palette)
                Group {
                    if let latest = row.latest {
                        Text("Latest \(latest, format: .relative(presentation: .named, unitsStyle: .abbreviated))")
                    } else {
                        Text("No Items")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary), in: shape)
            .overlay(shape.strokeBorder(.separator))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier("IndexCard")
    }
}

/// The colors of the types on one page, so a type has the same color on every card. They are muted, so they sit
/// quietly in light and dark; the share that gathers the rest is gray.
struct IndexPalette: Equatable {
    private static let colors: [Color] = [Color.blue, .purple, .green, .orange, .pink, .teal, .indigo, .yellow]
        .map { $0.mix(with: Color.gray, by: 0.35) }
    private static let other = Color.gray.opacity(0.5)
    private let slots: IndexSlots

    init(slots: IndexSlots = IndexSlots()) { self.slots = slots }

    func color(for share: TypeShare) -> Color {
        slots.slot(for: share.type).map { Self.colors[$0] } ?? Self.other
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
        .frame(height: 4)
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
                HStack(spacing: 4) {
                    Circle().fill(palette.color(for: share)).frame(width: 6, height: 6).accessibilityHidden(true)
                    Text(verbatim: "\(share.count.formatted()) \(share.label)").monospacedDigit().lineLimit(1)
                }
                .font(.caption2)
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
    @State private var sorted: [IndexRow] = []
    @State private var selection: Set<IndexRow.ID> = []

    var body: some View {
        Table(sorted, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.title, comparator: .localizedStandard) { row in
                HStack(spacing: 8) {
                    IndexTile(icon: row.icon, size: 20)
                    Text(verbatim: row.title).fontWeight(.semibold).lineLimit(1)
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
        .alternatingRowBackgrounds(.disabled)
        .onChange(of: rows, initial: true) { sorted = rows.sorted(using: sortOrder) }
        .onChange(of: sortOrder) { sorted = rows.sorted(using: sortOrder) }
        .contextMenu(forSelectionType: IndexRow.ID.self) { _ in
        } primaryAction: { ids in
            if let row = rows.first(where: { ids.contains($0.id) }) { open(row) }
        }
    }
}
