import Foundation
import Marfa

/// How a date the package reads (`Marfa.ItemDate`) is shown. The package reads and writes the contract's forms
/// (`types/datetime-value`), so MAPP never parses a date itself and every view that reads or writes one goes through
/// the package.
nonisolated extension ItemDate {
    /// The value as a person reads it, in their locale and time zone and the format they chose: "27 Oct 2026 at
    /// 2:00 pm", or the day alone. A day is shown on the clock of the calendar that read it, so it reads as the same
    /// day in every time zone.
    func text(format: DateFormat, now: Date = .now, locale: Locale = .current, calendar: Calendar = .current) -> String {
        Self.text(of: date, hasTime: hasTime, format: format, now: now, locale: locale, calendar: calendar)
    }

    /// A moment shown as a day alone or with its time, as `text(format:now:locale:calendar:)` shows a value.
    static func text(
        of date: Date, hasTime: Bool, format: DateFormat, now: Date = .now, locale: Locale = .current, calendar: Calendar = .current
    ) -> String {
        DateDisplay.text(of: date, hasTime: hasTime, place: .value, format: format, now: now, calendar: calendar, locale: locale)
    }
}
