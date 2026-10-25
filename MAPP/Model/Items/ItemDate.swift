import Foundation

/// A value of a Marfa `date` or `datetime` field, read and written in the forms the contract allows
/// (`types/datetime-value`): a calendar day, `YYYY-MM-DD`, or a day followed by `T`, a time of `HH:MM`, `HH:MM:SS`
/// or `HH:MM:SS` with a fraction, and `Z` or a `±HH:MM` offset. Every view that reads or writes such a value goes
/// through this, so a value one of them accepts reads the same in the others.
nonisolated struct ItemDate: Equatable, Sendable {
    /// The moment the value names. A day is its start in the calendar's time zone, the person's own.
    let date: Date
    /// Whether the value names a time, rather than a whole day.
    let hasTime: Bool

    /// Reads a value as Marfa writes it, or nil where it is not one of the contract's forms or names a day or time
    /// the calendar does not have.
    static func parse(_ text: String, calendar: Calendar = .current) -> ItemDate? {
        guard let match = text.wholeMatch(of: pattern) else { return nil }
        let (_, year, month, dayOfMonth, hour, minute, second, fraction, zone) = match.output
        var gregorian = Calendar(identifier: .gregorian)
        guard hour != nil else {
            gregorian.timeZone = calendar.timeZone
            return day(Int(year)!, Int(month)!, Int(dayOfMonth)!, in: gregorian).map { ItemDate(date: $0, hasTime: false) }
        }
        gregorian.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let start = day(Int(year)!, Int(month)!, Int(dayOfMonth)!, in: gregorian),
              let hour = hour.flatMap({ Int($0) }), let minute = minute.flatMap({ Int($0) }),
              hour <= 23, minute <= 59 else { return nil }
        let seconds = second.flatMap { Int($0) } ?? 0
        guard seconds <= 59 else { return nil }
        let offset: Int
        if let zone, zone != "Z" {
            let sign = zone.first == "-" ? -1 : 1
            let parts = zone.dropFirst().split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, parts[0] <= 23, parts[1] <= 59 else { return nil }
            offset = sign * (parts[0] * 3600 + parts[1] * 60)
        } else {
            offset = 0
        }
        let fractional = fraction.flatMap { Double("0." + $0) } ?? 0
        let interval = TimeInterval(hour * 3600 + minute * 60 + seconds - offset) + fractional
        return ItemDate(date: start.addingTimeInterval(interval), hasTime: true)
    }

    /// The value for the day a picked date falls on in the person's calendar.
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The value for a moment the person picked, in UTC and to the second, as Marfa answers one.
    static func moment(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle())
    }

    /// The value as a person reads it, in their locale and time zone: "27 Oct 2026 at 2:00 pm", or the day alone.
    func text(locale: Locale = .current, calendar: Calendar = .current) -> String {
        let style = Date.FormatStyle(date: .abbreviated, time: hasTime ? .shortened : .omitted,
                                     locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        return date.formatted(style)
    }

    nonisolated(unsafe) private static let pattern = #/([0-9]{4})-([0-9]{2})-([0-9]{2})(?:T([0-9]{2}):([0-9]{2})(?::([0-9]{2})(?:\.([0-9]+))?)?(Z|[+-][0-9]{2}:[0-9]{2}))?/#

    /// Foundation moves an impossible day to a real one, so the written day is checked against the one it makes.
    private static func day(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) -> Date? {
        guard year > 0, let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let made = calendar.dateComponents([.year, .month, .day], from: date)
        return made.year == year && made.month == month && made.day == day ? date : nil
    }
}
