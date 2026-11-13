import Foundation

/// How the app writes the dates it shows, as the person chose in Settings. The 12 or 24 hour clock is the system's.
nonisolated enum DateFormat: String, CaseIterable, Identifiable, Sendable {
    /// Each place writes a date as it fits: in words in lists and tables, abbreviated where a value is read.
    case automatic
    /// "Today", "Yesterday", a weekday this week, then the date.
    case relative
    /// The date in numbers: 27/10/2026.
    case short
    /// The date with the month in full: 27 October 2026.
    case long

    static let key = "dateFormat"
    static let standard = DateFormat.automatic

    static func stored(in defaults: UserDefaults = .standard) -> DateFormat {
        defaults.string(forKey: key).flatMap(Self.init(rawValue:)) ?? standard
    }

    var id: Self { self }
}

/// The one place a date becomes text, so a choice of format reaches every list, table, header and inspector alike.
/// The package reads and writes the contract's forms (`Marfa.ItemDate`); this only decides how a moment reads.
nonisolated enum DateDisplay {
    /// Where the date is shown, since a row has little room and a value is read by itself.
    enum Place: Sendable {
        /// A property, the inspector or a version: the day, and the time where there is one.
        case value
        /// A line of the list, where the time shows only today.
        case list
        /// A cell of the table, where a day is all there is.
        case table
    }

    /// `hasTime` is false for a value that names only a day. `now` matters only to the relative formats.
    static func text(
        of date: Date, hasTime: Bool = true, place: Place, format: DateFormat, now: Date = .now,
        calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        switch (format, place) {
        case (.automatic, .value):
            return absolute(date, hasTime: hasTime, style: .abbreviated, calendar: calendar, locale: locale)
        case (.automatic, .list), (.relative, .list):
            return listLabel(date, now: now, calendar: calendar, locale: locale)
        case (.automatic, .table), (.relative, .table):
            return dayLabel(date, now: now, calendar: calendar, locale: locale)
        case (.relative, .value):
            let day = dayLabel(date, now: now, calendar: calendar, locale: locale)
            guard hasTime else { return day }
            return String(localized: "\(day) at \(time(date, calendar: calendar, locale: locale))")
        case (.short, _):
            return absolute(date, hasTime: hasTime && place == .value, style: .numeric, calendar: calendar, locale: locale)
        case (.long, _):
            return absolute(date, hasTime: hasTime && place == .value, style: .long, calendar: calendar, locale: locale)
        }
    }

    private static func absolute(
        _ date: Date, hasTime: Bool, style: Date.FormatStyle.DateStyle, calendar: Calendar, locale: Locale
    ) -> String {
        date.formatted(Date.FormatStyle(
            date: style, time: hasTime ? .shortened : .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
    }

    /// The time of day alone, which a row shows inside the group of a day, where the day is already said. It is
    /// written as a list line writes the time today, so a row reads the same in any group.
    static func timeOfDay(of date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute())
    }

    private static func time(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        date.formatted(Date.FormatStyle(
            date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
    }

    /// As Mail writes it: the time today, "Yesterday", the weekday within the week, and the system's short date
    /// before that. A day to come, such as a due date or the start of an event, is a day as people say it.
    private static func listLabel(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let daysAgo = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        switch daysAgo {
        case ..<0:
            return dayLabel(date, now: now, calendar: calendar, locale: locale)
        case 0:
            style = style.hour().minute()
        case 1:
            return String(localized: "Yesterday")
        case 2...6:
            style = style.weekday(.wide)
        default:
            style = Date.FormatStyle(date: .numeric, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        }
        return date.formatted(style)
    }

    /// A day as people say it: Today, Yesterday, Tomorrow, a weekday within a week, then the date.
    private static func dayLabel(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return String(localized: "Today")
        case -1: return String(localized: "Yesterday")
        case 1: return String(localized: "Tomorrow")
        case -6...(-2), 2...6:
            return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.wide))
        default:
            let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
            var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated)
            if !sameYear { style = style.year() }
            return date.formatted(style)
        }
    }
}
