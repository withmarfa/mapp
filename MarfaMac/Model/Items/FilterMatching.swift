import Foundation
import Marfa

/// Days as a filter holds them: a calendar day, `YYYY-MM-DD`, which the person's calendar turns into the moment it
/// starts. Counting days on the calendar, never in seconds, keeps a day that is 23 or 25 hours long (a change of clocks)
/// whole. A date-only field is counted on the UTC calendar instead (`calendar(for:person:)`).
nonisolated enum FilterDays {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// The calendar a field's days are counted on: the person's own, except for a date-only field, which Marfa keeps as
    /// midnight UTC (`FilterTarget.isDateOnly`).
    static func calendar(for target: FilterTarget, person: Calendar) -> Calendar { target.isDateOnly ? utc : person }

    static func day(_ text: String) -> ItemDate.Day? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return ItemDate.Day(year: parts[0], month: parts[1], day: parts[2])
    }

    /// The first moment of the day on the calendar's clock, or nil for a day it does not have.
    static func start(of day: ItemDate.Day, calendar: Calendar) -> Date? {
        guard let noon = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)),
              calendar.component(.day, from: noon) == day.day else { return nil }
        return calendar.startOfDay(for: noon)
    }

    static func start(of text: String, calendar: Calendar) -> Date? {
        day(text).flatMap { start(of: $0, calendar: calendar) }
    }

    /// The day after the one named, as the next day's first moment.
    static func startOfNext(_ text: String, calendar: Calendar) -> Date? {
        day(text).flatMap { start(of: $0.adding(days: 1), calendar: calendar) }
    }

    /// The day a moment falls on, on the calendar's clock.
    static func text(of date: Date, calendar: Calendar) -> String { ItemDate.day(date, calendar: calendar) }

    /// A moment as the contract takes it for a bound: the instant with the calendar's own offset, `2026-11-30T00:00:00+01:00`
    /// (`search-and-filters/filter-property-instant`), so a day the person picked means their day. On the UTC calendar that is
    /// `2026-11-30T00:00:00Z`.
    static func instantText(_ date: Date, calendar: Calendar) -> String {
        let zone = calendar.timeZone
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = zone
        let parts = gregorian.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let offset = zone.secondsFromGMT(for: date)
        let zoneText = offset == 0 ? "Z" : String(format: "%@%02d:%02d", offset < 0 ? "-" : "+", abs(offset) / 3600, abs(offset) / 60 % 60)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d%@", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0,
            parts.minute ?? 0, parts.second ?? 0, zoneText)
    }

    /// The moment an instant bound names, read back; nil where it is not one.
    static func instant(_ text: String) -> Date? { ItemDate.parse(text)?.date }

    /// The days a relative date covers, as the moment it starts and the moment it ends: the last N days, today included, or
    /// the next N, today included. Nil where `op` is not a span.
    static func span(of op: FilterOp, count: Int, now: Date, calendar: Calendar) -> (start: Date, end: Date)? {
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
        switch op {
        case .inLast:
            return calendar.date(byAdding: .day, value: -(count - 1), to: today).map { ($0, tomorrow) }
        case .inNext:
            return calendar.date(byAdding: .day, value: count, to: today).map { (today, $0) }
        default:
            return nil
        }
    }
}

/// Whether a row meets a filter, worked out in the window from what the row holds: the same questions a saved view's
/// filter asks of Marfa, so the two agree (`ViewDraft`).
nonisolated enum FilterMatching {
    /// The context a day's meaning needs.
    struct Clock {
        var now: Date
        var calendar: Calendar
    }

    /// The rows the filters keep. A clause whose field no longer exists, or that says too little to filter by, keeps every row.
    static func filter(
        _ rows: [ItemTableRow], by state: FilterState, targets: [String: FilterTarget], catalogue: Catalogue, clock: Clock
    ) -> [ItemTableRow] {
        let active = state.complete.clauses.compactMap { clause in targets[clause.field].map { (clause, $0) } }
        guard !active.isEmpty else { return rows }
        let any = state.matchesAny && active.count > 1
        return rows.filter { row in
            let meets = { (entry: (FilterClause, FilterTarget)) in matches(entry.0, entry.1, row: row, catalogue: catalogue, clock: clock) }
            return any ? active.contains(where: meets) : active.allSatisfy(meets)
        }
    }

    static func matches(_ clause: FilterClause, _ target: FilterTarget, row: ItemTableRow, catalogue: Catalogue, clock: Clock) -> Bool {
        switch clause.op {
        case .isSet: return present(row, target)
        case .isEmpty: return !present(row, target)
        default: break
        }
        switch target.kind {
        case .status, .choice, .boolean, .type, .parent, .source:
            return matchesWords(clause, target, row: row, catalogue: catalogue)
        case .collection:
            let ids = Set(row.collections.map(\.id.rawValue))
            // An empty value is "in no collection", as an empty word is for a parent, a status and a choice.
            let hit = { (value: String) in value.isEmpty ? ids.isEmpty : ids.contains(value) }
            return clause.op == .isNot ? !clause.values.contains(where: hit) : clause.values.contains(where: hit)
        case .tags:
            return clause.values.contains { row.item.tags.contains($0) }
        case .people:
            let names = members(of: row, target)
            return clause.values.contains { names.contains($0) }
        case .date, .moment:
            return matchesDate(clause, target, row: row, clock: clock)
        case .number:
            guard let value = number(of: row, target), let wanted = clause.values.first.flatMap(FilterClause.number) else { return false }
            switch clause.op {
            case .equal: return value == wanted
            case .notEqual: return value != wanted
            case .less: return value < wanted
            case .lessOrEqual: return value <= wanted
            case .greater: return value > wanted
            case .greaterOrEqual: return value >= wanted
            default: return false
            }
        case .text:
            guard let text = row.item.value(of: target.key ?? "")?.string, let wanted = clause.values.first else { return false }
            switch clause.op {
            case .is: return text == wanted
            case .isNot: return text != wanted
            case .contains: return asciiFolded(text).contains(asciiFolded(wanted))
            case .startsWith: return asciiFolded(text).hasPrefix(asciiFolded(wanted))
            default: return false
            }
        }
    }

    /// Whether the row holds a value in the field, as Marfa's `exists` tests it: absent or null is empty, anything else, an
    /// empty list included, is set.
    static func present(_ row: ItemTableRow, _ target: FilterTarget) -> Bool {
        switch target.kind {
        case .type, .moment: return true
        case .tags: return !row.item.tags.isEmpty
        case .parent: return row.parent != nil
        case .collection: return !row.collections.isEmpty
        case .source: return row.item.source != nil
        default:
            guard let key = target.key, let value = row.item.value(of: key) else { return false }
            return value != .null
        }
    }

    /// The row's one word in the field, nil where it holds none.
    static func word(of row: ItemTableRow, _ target: FilterTarget) -> String? {
        switch target.kind {
        case .type: row.item.type.rawValue
        case .parent: row.parent?.id.rawValue
        case .source: row.item.source
        default: target.key.flatMap { ItemTableValue.string(row, key: $0) }
        }
    }

    /// A set of words: the row holds one of them (is), or none of them (is not). Where the filter leaves out a word,
    /// an absent value passes only for a link (Marfa tests a parent by the absence of the link), and a status group passes
    /// only a row whose own type puts its word in another group.
    private static func matchesWords(_ clause: FilterClause, _ target: FilterTarget, row: ItemTableRow, catalogue: Catalogue) -> Bool {
        let word = word(of: row, target)
        let group = word.flatMap { catalogue.itemTypes[row.item.type]?.statusGroup(of: $0) }
        func holds(_ value: String) -> Bool {
            if value.isEmpty { return word == nil }
            if let wanted = FilterClause.group(of: value) { return group == wanted }
            return word == value
        }
        switch clause.op {
        case .is: return clause.values.contains(where: holds)
        case .isNot:
            guard let word else { return target.kind == .parent && !clause.values.contains("") }
            return clause.values.allSatisfy { value in
                if value.isEmpty { return true }
                if let wanted = FilterClause.group(of: value) { return group != nil && group != wanted }
                return word != value
            }
        default: return false
        }
    }

    static func members(of row: ItemTableRow, _ target: FilterTarget) -> Set<String> {
        guard let key = target.key, let member = target.member, case .array(let entries)? = row.item.value(of: key) else { return [] }
        return Set(entries.compactMap { entry in
            guard case .object(let object) = entry else { return nil }
            return object[member]?.string
        })
    }

    private static func number(of row: ItemTableRow, _ target: FilterTarget) -> Double? {
        switch target.key.flatMap({ row.item.value(of: $0) }) {
        case .number(let value)?: value.nearestDouble
        case .double(let value)?: value
        default: nil
        }
    }

    /// The moment a date field holds, as Marfa compares it: a day alone is its midnight in UTC, in a datetime field too.
    static func date(of row: ItemTableRow, _ target: FilterTarget) -> Date? {
        switch target.id {
        case ItemTableColumn.created.id: row.item.created
        case ItemTableColumn.edited.id: row.item.modified
        case ItemTableColumn.occurred.id: row.item.occurred
        default: target.key.flatMap { row.item.value(of: $0)?.string }.flatMap { ItemDate.parse($0, calendar: FilterDays.utc)?.date }
        }
    }

    private static func matchesDate(_ clause: FilterClause, _ target: FilterTarget, row: ItemTableRow, clock: Clock) -> Bool {
        guard let date = date(of: row, target) else { return false }
        let calendar = FilterDays.calendar(for: target, person: clock.calendar)
        // Today is the Mac's day; a date-only field counts it as the same day on the UTC clock.
        let now = target.isDateOnly ? todayOnUTC(clock) : clock.now
        func start(_ index: Int) -> Date? { clause.values.indices.contains(index) ? FilterDays.start(of: clause.values[index], calendar: calendar) : nil }
        func next(_ index: Int) -> Date? { clause.values.indices.contains(index) ? FilterDays.startOfNext(clause.values[index], calendar: calendar) : nil }
        switch clause.op {
        case .on: guard let from = start(0), let to = next(0) else { return false }; return date >= from && date < to
        case .before: return start(0).map { date < $0 } ?? false
        case .after: return next(0).map { date >= $0 } ?? false
        case .between: guard let from = start(0), let to = next(1) else { return false }; return date >= from && date < to
        case .beforeToday: return date < calendar.startOfDay(for: now)
        case .afterToday:
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return false }
            return date >= tomorrow
        case .inLast, .inNext:
            guard let count = clause.values.first.flatMap({ Int($0) }),
                  let span = FilterDays.span(of: clause.op, count: count, now: now, calendar: calendar) else { return false }
            return date >= span.start && date < span.end
        default: return false
        }
    }

    /// A moment of the Mac's day today, placed on the same day of the UTC calendar.
    private static func todayOnUTC(_ clock: Clock) -> Date {
        FilterDays.start(of: FilterDays.text(of: clock.now, calendar: clock.calendar), calendar: FilterDays.utc) ?? clock.now
    }

    /// Lower-cases the letters A to Z and no other, as Marfa folds a text's case (`search-and-filters/filter-text-case`).
    static func asciiFolded(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { (65...90).contains($0.value) ? Unicode.Scalar($0.value + 32)! : $0 }))
    }
}
