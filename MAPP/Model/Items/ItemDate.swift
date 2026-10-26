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
        guard hour != nil else {
            return startOfDay(Int(year)!, Int(month)!, Int(dayOfMonth)!, in: calendar.timeZone)
                .map { ItemDate(date: $0, hasTime: false) }
        }
        guard let start = utcMidnight(Int(year)!, Int(month)!, Int(dayOfMonth)!),
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

    /// The value for a moment the person picked, in UTC and to the second.
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

    /// The contract's days are the proleptic Gregorian calendar of years 0000 to 9999, which Foundation's Gregorian
    /// calendar is not (it counts the Julian calendar before 1582), so the day is checked and placed by arithmetic.
    /// The result is that day's midnight in UTC.
    private static func utcMidnight(_ year: Int, _ month: Int, _ day: Int) -> Date? {
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...12).contains(month), (1...lengths[month - 1]).contains(day) else { return nil }
        // Days since 1970-01-01, counted from a year starting in March so that the leap day ends its year.
        let shifted = month <= 2 ? year - 1 : year
        let era = shifted >= 0 ? shifted / 400 : (shifted - 399) / 400
        let yearOfEra = shifted - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return Date(timeIntervalSince1970: TimeInterval((era * 146_097 + dayOfEra - 719_468) * 86_400))
    }

    /// The start of a day on the calendar's clock.
    private static func startOfDay(_ year: Int, _ month: Int, _ day: Int, in zone: TimeZone) -> Date? {
        guard let midnight = utcMidnight(year, month, day) else { return nil }
        let guess = midnight.addingTimeInterval(-TimeInterval(zone.secondsFromGMT(for: midnight)))
        return midnight.addingTimeInterval(-TimeInterval(zone.secondsFromGMT(for: guess)))
    }
}
