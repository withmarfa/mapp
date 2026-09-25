import Foundation

/// How a note's date reads in the list, as Mail writes it: the time today, "Yesterday", the weekday within
/// the week, and the date before that.
nonisolated enum NoteDate {
    static func listLabel(for date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let daysAgo = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        switch daysAgo {
        case ...0:
            style = style.hour().minute()
        case 1:
            return String(localized: "Yesterday")
        case 2...6:
            style = style.weekday(.wide)
        default:
            style = style.day(.twoDigits).month(.twoDigits).year()
        }
        return date.formatted(style)
    }
}
