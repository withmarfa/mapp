import Foundation

/// The run of days the calendar's week scrolls along: one column for each day, side by side, with day `index` being `index`
/// calendar days after the strip's first. A swipe moves along the run and settles on a day's edge, so the week shown can
/// start on any day. Days are counted on the calendar passed (the Mac's), never by a fixed 24 hours, so the day a clock
/// change shortens or lengthens is still one column. A strip that skips weekends leaves those days out, so a column is
/// each of the others and `index` counts only them.
nonisolated struct CalendarStrip: Equatable, Sendable {
    /// How many days the strip reaches either side of the day it is built around.
    static let reach = 1000
    /// How close to an end of the strip a day may be before the strip is built again around it.
    static let margin = 60

    /// The start of the first calendar day of the strip.
    let first: Date
    let skipsWeekends: Bool
    /// The start of each day the strip holds, where it skips weekends. Empty otherwise, when a day's index is its distance.
    private let kept: [Date]
    /// How many columns a week has: seven, or those a week has without its weekend.
    let columns: Int

    /// A strip built around `day`, which sits in the middle.
    init(around day: Date, calendar: Calendar, skipsWeekends: Bool = false) {
        let middle = calendar.startOfDay(for: day)
        let first = calendar.date(byAdding: .day, value: -Self.reach, to: middle) ?? middle
        self.first = first
        self.skipsWeekends = skipsWeekends
        guard skipsWeekends else {
            kept = []
            columns = 7
            return
        }
        var days: [Date] = []
        var date = first
        for _ in 0..<(Self.reach * 2 + 1) {
            if !calendar.isDateInWeekend(date) { days.append(date) }
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        }
        kept = days
        let weekend = (0..<7).filter { offset in
            calendar.date(byAdding: .day, value: offset, to: middle).map(calendar.isDateInWeekend) ?? false
        }.count
        columns = max(7 - weekend, 1)
    }

    /// The same run of days built around `day`.
    func rebuilt(around day: Date, calendar: Calendar) -> CalendarStrip {
        CalendarStrip(around: day, calendar: calendar, skipsWeekends: skipsWeekends)
    }

    var count: Int { skipsWeekends ? kept.count : Self.reach * 2 + 1 }

    /// The start of the day at `index`.
    func day(at index: Int, calendar: Calendar) -> Date {
        if skipsWeekends { return kept.indices.contains(index) ? kept[index] : first }
        return calendar.date(byAdding: .day, value: index, to: first) ?? first.addingTimeInterval(TimeInterval(index) * 86_400)
    }

    /// The index of the day that holds `date`, or of the next day the strip holds where that is a weekend it skips. It
    /// may lie outside the strip.
    func index(of date: Date, calendar: Calendar) -> Int {
        let day = calendar.startOfDay(for: date)
        guard skipsWeekends else { return calendar.dateComponents([.day], from: first, to: day).day ?? 0 }
        var low = 0, high = kept.count
        while low < high {
            let middle = (low + high) / 2
            if kept[middle] < day { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// Whether `index` is far enough inside the strip to scroll to, with room to scroll on either side of it.
    func holds(_ index: Int) -> Bool {
        index >= Self.margin && index < count - Self.margin
    }

    /// The columns to draw for a week that starts at `leading`: the days in view and one more either side, so a column
    /// is there before it scrolls in.
    func drawn(leading: Int) -> Range<Int> {
        max(leading - 1, 0)..<min(leading + 9, count)
    }

    /// Where a scroll offset is along the strip, in days.
    struct Position: Equatable, Sendable {
        /// The day at the left edge of the view, or the one the left edge is part way through.
        let leading: Int
        /// The day nearest the left edge, which is where a settling scroll ends.
        let nearest: Int
        /// Whether the left edge is part way through a day.
        let isBetween: Bool

        /// The days at least partly in view, for a week of `days` columns.
        func shown(days: Int = 7) -> Range<Int> {
            leading..<(leading + days + (isBetween ? 1 : 0))
        }
    }

    static func position(offset: CGFloat, dayWidth: CGFloat) -> Position {
        guard dayWidth > 0, offset.isFinite else { return Position(leading: 0, nearest: 0, isBetween: false) }
        let days = offset / dayWidth
        let nearest = Int(days.rounded())
        let isBetween = abs(days - CGFloat(nearest)) > 0.01
        // A scroll that rests on a day's edge by a fraction of a point short of it is on that day, not the one before.
        return Position(leading: isBetween ? Int(days.rounded(.down)) : nearest, nearest: nearest, isBetween: isBetween)
    }

    /// The offset of the day nearest `offset`, which a scroll that is let go of settles on.
    static func snapped(offset: CGFloat, dayWidth: CGFloat) -> CGFloat {
        guard dayWidth > 0 else { return offset }
        return (offset / dayWidth).rounded() * dayWidth
    }
}
