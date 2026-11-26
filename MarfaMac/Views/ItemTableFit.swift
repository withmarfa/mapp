import AppKit
import Marfa

/// How wide each column of the table starts, from what its cells say: the widest of the first rows' words, with a cell's
/// room and the chip or mark it draws, and not less than its heading with the sort mark. The name is the table's flexible
/// column and has none (`ColumnResizing`). A width the person dragged is kept apart and wins (`ItemTable.setStartingWidths`).
@MainActor
enum ItemTableFit {
    /// How many rows are read: the page's first, which are the ones a person sees.
    static let sample = 120

    struct Width: Equatable {
        var minimum: CGFloat
        var ideal: CGFloat
    }

    /// A cell's room at each side, the one its heading shares.
    private static let room: CGFloat = 12
    /// What a heading keeps after its words for the sort mark.
    private static let sortRoom: CGFloat = 20
    /// A type's mark and its gap; a status's or a choice's chip around its word.
    private static let markRoom: CGFloat = 20
    private static let chipRoom: CGFloat = 34

    static func widths(
        of columns: [ItemTableColumn], rows: some Sequence<ItemTableRow>, library: any ItemLibrary, format: DateFormat, now: Date,
        scale: CGFloat
    ) -> [String: Width] {
        let body = NSFont.monospacedDigitSystemFont(ofSize: 13 * scale, weight: .regular)
        let heading = NSFont.systemFont(ofSize: 12 * scale, weight: .medium)
        let rows = Array(rows)
        var fitted: [String: Width] = [:]
        for column in columns where column.content != .title {
            let limits = column.widths
            var widest: CGFloat = 0
            var chrome: CGFloat = 0
            for entry in Set(rows.compactMap { text(of: $0, in: column, library: library, format: format, now: now) }) {
                widest = max(widest, width(of: entry.words, in: body))
                chrome = max(chrome, entry.chrome)
            }
            let headed = width(of: column.label, in: heading) + room + sortRoom * scale
            let content = widest > 0 ? widest + (chrome + room) * scale : 0
            // A column with no words to measure (links, tags) keeps its style's width.
            let ideal = content > 0 ? min(max(content, headed, limits.min), limits.max) : limits.ideal
            fitted[column.id] = Width(minimum: min(limits.min, ideal), ideal: ideal)
        }
        return fitted
    }

    private struct Entry: Hashable {
        let words: String
        let chrome: CGFloat
    }

    private static func text(
        of row: ItemTableRow, in column: ItemTableColumn, library: any ItemLibrary, format: DateFormat, now: Date
    ) -> Entry? {
        func day(_ date: Date, hasTime: Bool) -> Entry {
            Entry(words: DateDisplay.text(of: date, hasTime: hasTime, place: .table, format: format, now: now), chrome: 0)
        }
        switch column.content {
        case .title, .parent, .children, .collections, .tags, .duration: return nil
        case .type: return Entry(words: row.typeLabel, chrome: markRoom)
        case .source:
            return row.item.source.flatMap { $0.isEmpty ? nil : Entry(words: library.sources.name($0), chrome: 0) }
        case .created: return day(row.item.created, hasTime: true)
        case .edited: return day(row.item.modified, hasTime: true)
        case .occurred: return day(row.item.occurred ?? row.item.created, hasTime: true)
        case .count(let fact):
            let hasStatus = library.catalogue.itemTypes[row.item.type]?.statusField != nil
            return CountWording.text(of: fact, answer: row.counts[fact], hasStatus: hasStatus).map { Entry(words: $0, chrome: 0) }
        case .field:
            guard let own = column.field(for: row, catalogue: library.catalogue), let current = ItemTableValue.string(row, key: own.key) else { return nil }
            switch column.style(for: own) {
            case .status, .priority, .choice: return Entry(words: ItemTypeInfo.Field.label(ofOption: current), chrome: chipRoom)
            case .date: return ItemDate.parse(current).map { day($0.date, hasTime: false) }
            case .number: return Entry(words: current, chrome: 0)
            case .text: return Entry(words: current, chrome: 0)
            default: return nil
            }
        }
    }

    private static func width(of words: String, in font: NSFont) -> CGFloat {
        ceil((words as NSString).size(withAttributes: [.font: font]).width)
    }
}

/// Which columns fit the table's width, and how wide each is. The name keeps its least width and the other columns give way
/// in two steps: each shrinks from its ideal toward its least, in proportion, and only then does the last of them go,
/// whole, until the rest fit. A column the person dragged to a width keeps it and does not shrink.
nonisolated enum ItemTableRoom {
    struct Column: Equatable {
        let id: String
        let isName: Bool
        let minimum: CGFloat
        let ideal: CGFloat
        /// Whether the person set the width.
        let isKept: Bool
    }

    /// The columns that stay, with their starting widths, in order. The name's own width is the table's to fill, so its
    /// entry is its least. A width of 0 or less is an unmeasured table, which hides nothing.
    static func plan(_ columns: [Column], available: CGFloat) -> [(id: String, width: CGFloat)] {
        guard available > 0 else { return columns.map { ($0.id, $0.ideal) } }
        var kept = columns
        while true {
            let others = kept.filter { !$0.isName }
            let room = available - (kept.first { $0.isName }?.minimum ?? 0)
            let leastNeeded = others.reduce(0) { $0 + ($1.isKept ? $1.ideal : $1.minimum) }
            if leastNeeded <= room || others.isEmpty {
                let idealNeeded = others.reduce(0) { $0 + $1.ideal }
                let slack = others.reduce(0) { $0 + ($1.isKept ? 0 : $1.ideal - $1.minimum) }
                let squeeze = idealNeeded > room && slack > 0 ? min(1, (idealNeeded - room) / slack) : 0
                return kept.map { column in
                    if column.isName || column.isKept { return (column.id, column.ideal) }
                    return (column.id, floor(column.ideal - (column.ideal - column.minimum) * squeeze))
                }
            }
            guard let last = kept.lastIndex(where: { !$0.isName }) else { return kept.map { ($0.id, $0.ideal) } }
            kept.remove(at: last)
        }
    }
}
