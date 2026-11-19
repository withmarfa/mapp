import Foundation
import Marfa

/// How much of the calendar shows at once.
nonisolated enum CalendarScale: String, Codable, CaseIterable, Sendable {
    case week, month

    var title: LocalizedStringResource {
        switch self {
        case .week: "Week"
        case .month: "Month"
        }
    }
}

/// An item on the calendar: what it is called and the span it occupies, which the week and the month both lay out.
nonisolated struct CalendarEntry: Identifiable, Hashable, Sendable {
    let id: ItemID
    let title: String
    /// The first moment, or the start of the first day for a whole-day item.
    let start: Date
    /// Where it ends, exclusive, always after `start`. A whole-day item ends at the start of the day after its last.
    let end: Date
    /// Whether the item is a whole day or a run of days, rather than hours.
    let isAllDay: Bool
}

/// Where items sit on a calendar, worked out from the same rule as the timeline (`ItemPlacement`), as pure values: the
/// week's day columns with their blocks, and the month's grid. Every date is read in the calendar passed, which is the
/// Mac's own, so its first weekday, its zone and its months decide the days.
nonisolated enum CalendarLayout {
    /// How long a timed item with no end lasts, one hour.
    static let defaultLength: TimeInterval = 3600
    /// The shortest a block is taken to be when blocks are set side by side, so a short item does not hide behind its neighbour.
    static let shortestBlock = 30

    /// The items placed on the calendar, and how many had no date to place them by and were left out.
    static func entries(
        for items: [Item], looks: [TypeID: TypeLook], catalogue: Catalogue, calendar: Calendar = .current
    ) -> (entries: [CalendarEntry], leftOut: Int) {
        var entries: [CalendarEntry] = []
        var leftOut = 0
        for item in items {
            let outcome = ItemPlacement.of(item, look: looks[item.type] ?? .empty, field: nil, catalogue: catalogue, calendar: calendar)
            guard case .placed(let placement) = outcome else {
                leftOut += 1
                continue
            }
            entries.append(entry(of: item, placement, calendar: calendar))
        }
        return (entries, leftOut)
    }

    static func entry(of item: Item, _ placement: ItemPlacement, calendar: Calendar) -> CalendarEntry {
        if !placement.hasTime {
            let first = calendar.startOfDay(for: placement.start)
            let next = calendar.date(byAdding: .day, value: 1, to: first) ?? first.addingTimeInterval(86_400)
            let end = placement.end.map { max($0, next) } ?? next
            return CalendarEntry(id: item.id, title: item.displayTitle, start: first, end: end, isAllDay: true)
        }
        let end = placement.end.flatMap { $0 > placement.start ? $0 : nil } ?? placement.start.addingTimeInterval(defaultLength)
        return CalendarEntry(id: item.id, title: item.displayTitle, start: placement.start, end: end, isAllDay: false)
    }

    // MARK: Time

    /// The span the scale shows around `anchor`: the week that holds it, from the calendar's first weekday, or its month.
    static func interval(of scale: CalendarScale, containing anchor: Date, calendar: Calendar) -> DateInterval {
        let component: Calendar.Component = scale == .week ? .weekOfYear : .month
        if let interval = calendar.dateInterval(of: component, for: anchor) { return interval }
        let day = calendar.startOfDay(for: anchor)
        return DateInterval(start: day, end: calendar.date(byAdding: .day, value: scale == .week ? 7 : 30, to: day) ?? day)
    }

    /// The date `steps` weeks or months from `anchor`.
    static func moved(_ anchor: Date, by steps: Int, scale: CalendarScale, calendar: Calendar) -> Date {
        calendar.date(byAdding: scale == .week ? .weekOfYear : .month, value: steps, to: anchor) ?? anchor
    }

    /// The days of `interval`, each as the start of the day.
    static func days(in interval: DateInterval, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end, days.count < 400 {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return days
    }

    /// The start of the day after `day`.
    private static func nextDay(_ day: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
    }

    /// Whether `entry` has any of its time inside the day that starts at `day`.
    static func covers(_ entry: CalendarEntry, day: Date, calendar: Calendar) -> Bool {
        entry.start < nextDay(day, calendar: calendar) && entry.end > day
    }

    /// What a week's block shows for the room it has: the title first, on up to two lines, and the time only where
    /// room is left for it, on a line of its own wide enough to read. A block with room for one line gets one.
    static func blockLabel(height: CGFloat, width: CGFloat, scale: CGFloat) -> (titleLines: Int, showsTime: Bool) {
        let line = 14 * scale
        let room = height - 6 * scale
        let titleLines = max(1, min(2, Int(room / line)))
        let timeFits = room - CGFloat(titleLines) * line >= 12 * scale && width >= 34 * scale
        return (titleLines, timeFits)
    }

    /// A title broken at word boundaries into at most `lines` lines, for a block too narrow for it on one. Each line but
    /// the last takes the words that fit `width` by `measure`, and the last takes every word left, for the view to end
    /// with an ellipsis. A word wider than the line stands alone and is cut by its own ellipsis, never split mid-word.
    static func titleLines(_ title: String, lines: Int, fitting width: CGFloat, measure: (String) -> CGFloat) -> [String] {
        let words = title.split(whereSeparator: \.isWhitespace).map(String.init)
        guard lines > 1, words.count > 1 else { return [words.joined(separator: " ")] }
        var result: [String] = []
        var current = ""
        for (offset, word) in words.enumerated() {
            let candidate = current.isEmpty ? word : current + " " + word
            if current.isEmpty || measure(candidate) <= width {
                current = candidate
                continue
            }
            result.append(current)
            if result.count == lines - 1 { return result + [words[offset...].joined(separator: " ")] }
            current = word
        }
        return result + [current]
    }

    static func precedes(_ lhs: CalendarEntry, _ rhs: CalendarEntry) -> Bool {
        if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        let title = lhs.title.localizedStandardCompare(rhs.title)
        return title == .orderedSame ? lhs.id.rawValue < rhs.id.rawValue : title == .orderedAscending
    }
}

// MARK: Week

/// A week of the calendar: seven day columns, each with its whole-day items above and its timed blocks laid out by the
/// minute, side by side where they overlap.
nonisolated struct CalendarWeek: Equatable, Sendable {
    /// One timed item's stretch of one day. An item over midnight, or over several days, has a block on each.
    struct Block: Identifiable, Hashable, Sendable {
        let entry: CalendarEntry
        let day: Date
        /// Minutes from the day's start by the clock on the wall, so a day of 23 or 25 hours still reads 0 to 1440.
        let startMinute: Int
        let endMinute: Int
        /// The block's column among those it overlaps, and how many columns they take together.
        var column = 0
        var columns = 1
        /// Whether the item began on an earlier day, or goes on to a later one.
        let continuesBefore: Bool
        let continuesAfter: Bool

        var id: String { "\(entry.id.rawValue)@\(day.timeIntervalSinceReferenceDate)" }
    }

    struct Day: Identifiable, Equatable, Sendable {
        let date: Date
        let isToday: Bool
        let isWeekend: Bool
        let allDay: [CalendarEntry]
        let blocks: [Block]
        var id: Date { date }
    }

    let interval: DateInterval
    let days: [Day]

    static func make(entries: [CalendarEntry], around anchor: Date, calendar: Calendar, now: Date) -> CalendarWeek {
        let interval = CalendarLayout.interval(of: .week, containing: anchor, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let inWeek = entries.filter { $0.start < interval.end && $0.end > interval.start }
        let days = CalendarLayout.days(in: interval, calendar: calendar).map { day -> Day in
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            let here = inWeek.filter { CalendarLayout.covers($0, day: day, calendar: calendar) }
            let whole = here.filter(\.isAllDay).sorted(by: CalendarLayout.precedes)
            let timed = here.filter { !$0.isAllDay }.sorted(by: CalendarLayout.precedes).map { entry in
                Block(
                    entry: entry, day: day, startMinute: minute(of: entry.start, day: day, next: next, calendar: calendar),
                    endMinute: max(minute(of: entry.end, day: day, next: next, calendar: calendar), minute(of: entry.start, day: day, next: next, calendar: calendar) + 1),
                    continuesBefore: entry.start < day, continuesAfter: entry.end > next)
            }
            return Day(date: day, isToday: day == today, isWeekend: calendar.isDateInWeekend(day), allDay: whole, blocks: sideBySide(timed))
        }
        return CalendarWeek(interval: interval, days: days)
    }

    private static func minute(of date: Date, day: Date, next: Date, calendar: Calendar) -> Int {
        if date <= day { return 0 }
        if date >= next { return 24 * 60 }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return min((parts.hour ?? 0) * 60 + (parts.minute ?? 0), 24 * 60)
    }

    /// Gives each block of a day a column. Blocks that overlap, one reaching another through a chain, share the width
    /// of their group, each in the first column free where it starts.
    static func sideBySide(_ blocks: [Block]) -> [Block] {
        var placed: [Block] = []
        var group: [Block] = []
        var columnEnds: [Int] = []
        var groupEnd = 0
        func close() {
            placed += group.map { block in
                var block = block
                block.columns = max(columnEnds.count, 1)
                return block
            }
            group = []
            columnEnds = []
        }
        for block in blocks.sorted(by: { ($0.startMinute, $1.endMinute) < ($1.startMinute, $0.endMinute) }) {
            if !group.isEmpty, block.startMinute >= groupEnd { close() }
            let shown = max(block.endMinute, block.startMinute + CalendarLayout.shortestBlock)
            var block = block
            if let free = columnEnds.firstIndex(where: { $0 <= block.startMinute }) {
                block.column = free
                columnEnds[free] = shown
            } else {
                block.column = columnEnds.count
                columnEnds.append(shown)
            }
            groupEnd = group.isEmpty ? shown : max(groupEnd, shown)
            group.append(block)
        }
        close()
        return placed
    }

    /// The minutes into today where the line of the present moment sits, or nil where today is not in this week.
    func nowMinute(now: Date, calendar: Calendar) -> (day: Date, minute: Int)? {
        let today = calendar.startOfDay(for: now)
        guard days.contains(where: { $0.date == today }) else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        return (today, (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }
}

// MARK: Month

/// A month of the calendar: whole weeks that hold it, with each day's items.
nonisolated struct CalendarMonth: Equatable, Sendable {
    struct Day: Identifiable, Equatable, Sendable {
        let date: Date
        /// Whether the day is in the month, as against one of the days either side that finish its first and last week.
        let isInMonth: Bool
        let isToday: Bool
        let isWeekend: Bool
        /// Every item that has time on the day: whole-day items first, then by start.
        let entries: [CalendarEntry]
        var id: Date { date }

        /// What fits in `capacity` lines: all the items where they fit, otherwise one line fewer and the count of the
        /// rest, which takes the last line.
        func fitting(capacity: Int) -> (shown: [CalendarEntry], more: Int) {
            let room = max(capacity, 1)
            if entries.count <= room { return (entries, 0) }
            let shown = max(room - 1, 0)
            return (Array(entries.prefix(shown)), entries.count - shown)
        }
    }

    let interval: DateInterval
    let weeks: [[Day]]
    /// How many items have time in the month itself.
    let itemCount: Int

    /// The row of the week that `span` holds the start of, or nil where no row does. A span ends where the next week
    /// begins, so the end itself belongs to the next row, which is not marked.
    func row(startingIn span: DateInterval) -> Int? {
        weeks.firstIndex { week in week.first.map { $0.date >= span.start && $0.date < span.end } ?? false }
    }

    static func make(entries: [CalendarEntry], around anchor: Date, calendar: Calendar, now: Date) -> CalendarMonth {
        let month = CalendarLayout.interval(of: .month, containing: anchor, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let first = CalendarLayout.interval(of: .week, containing: month.start, calendar: calendar).start
        var weeks: [[Day]] = []
        var weekStart = first
        while weekStart < month.end, weeks.count < 7 {
            let week = CalendarLayout.interval(of: .week, containing: weekStart, calendar: calendar)
            let inWeek = entries.filter { $0.start < week.end && $0.end > week.start }
            weeks.append(CalendarLayout.days(in: week, calendar: calendar).map { day in
                Day(
                    date: day, isInMonth: day >= month.start && day < month.end, isToday: day == today,
                    isWeekend: calendar.isDateInWeekend(day),
                    entries: inWeek.filter { CalendarLayout.covers($0, day: day, calendar: calendar) }.sorted(by: CalendarLayout.precedes))
            })
            weekStart = week.end
        }
        let inMonth = entries.filter { $0.start < month.end && $0.end > month.start }
        return CalendarMonth(interval: month, weeks: weeks, itemCount: inMonth.count)
    }
}

// MARK: Keyboard

/// Moving the chosen event with the arrow keys, over every event and not only those on screen, so the choice can cross
/// to the week or the month beside the one shown. An event over midnight is on each day it covers, so a choice is an
/// event on a day (`Spot`).
nonisolated enum CalendarNavigation {
    enum Direction: Sendable { case up, down, left, right }

    struct Spot: Equatable, Sendable {
        let id: ItemID
        let day: Date
    }

    /// The events with time on `day`: whole-day ones first, then by start.
    static func entries(on day: Date, in entries: [CalendarEntry], calendar: Calendar) -> [CalendarEntry] {
        entries.filter { CalendarLayout.covers($0, day: day, calendar: calendar) }.sorted(by: CalendarLayout.precedes)
    }

    /// The day of the chosen event to move from: `day` where the event is on it, else its first day in `visible`, else
    /// its own first day. Nil where the event is not on the calendar.
    static func spot(of id: ItemID, near day: Date?, in entries: [CalendarEntry], visible: DateInterval, calendar: Calendar) -> Spot? {
        guard let entry = entries.first(where: { $0.id == id }) else { return nil }
        if let day, CalendarLayout.covers(entry, day: day, calendar: calendar) { return Spot(id: id, day: day) }
        let first = CalendarLayout.days(in: visible, calendar: calendar).first { CalendarLayout.covers(entry, day: $0, calendar: calendar) }
        return Spot(id: id, day: first ?? calendar.startOfDay(for: entry.start))
    }

    /// Where an arrow key takes the choice. Up and down stay within the day's events, in order; left and right go to
    /// the nearest day beside it that has any, at the same place in its order or its last, however far away and in
    /// whichever week or month. Nil where there is nowhere to go. From no choice, the first event shown, or the last
    /// for up and left.
    static func move(
        from spot: Spot?, _ direction: Direction, in entries: [CalendarEntry], visible: DateInterval, calendar: Calendar
    ) -> Spot? {
        guard let spot else { return edge(direction, in: entries, visible: visible, calendar: calendar) }
        let here = Self.entries(on: spot.day, in: entries, calendar: calendar)
        let index = here.firstIndex { $0.id == spot.id } ?? 0
        switch direction {
        case .up, .down:
            let next = index + (direction == .down ? 1 : -1)
            return here.indices.contains(next) ? Spot(id: here[next].id, day: spot.day) : nil
        case .left, .right:
            guard let earliest = entries.map(\.start).min(), let latest = entries.map(\.end).max() else { return nil }
            let step = direction == .right ? 1 : -1
            var day = spot.day
            while let next = calendar.date(byAdding: .day, value: step, to: day), next != day {
                day = next
                if day >= latest || day < calendar.startOfDay(for: earliest) { return nil }
                let there = Self.entries(on: day, in: entries, calendar: calendar)
                if !there.isEmpty { return Spot(id: there[min(index, there.count - 1)].id, day: day) }
            }
            return nil
        }
    }

    private static func edge(_ direction: Direction, in entries: [CalendarEntry], visible: DateInterval, calendar: Calendar) -> Spot? {
        let days = CalendarLayout.days(in: visible, calendar: calendar)
        let backwards = direction == .up || direction == .left
        for day in backwards ? days.reversed() : days {
            let here = Self.entries(on: day, in: entries, calendar: calendar)
            if let entry = backwards ? here.last : here.first { return Spot(id: entry.id, day: day) }
        }
        return nil
    }
}
