import Foundation

/// What the window's bottom-right corner does to the view in front. Each is also a View menu command and a palette
/// entry, so the corner's buttons, the menu and the palette share these.
extension Browser {
    /// Shows the week or month that holds `day`, and puts the month card away.
    func chooseCalendarDay(_ day: Date, calendar: Calendar = .mapp) {
        showCalendarDay(day, calendar: calendar)
        showsCalendarMonth = false
    }

    /// Brings `day` into view: the week that holds it, or in a month the month that holds it. The arrow keys use it to
    /// follow the chosen event to a day the calendar is not showing.
    func showCalendarDay(_ day: Date, calendar: Calendar = .mapp) {
        guard calendarScale == .week else {
            calendarDay = calendar.startOfDay(for: day)
            return
        }
        calendarDay = CalendarLayout.firstDay(ofWeekHolding: day, calendar: calendar)
    }

    func toggleCalendarMonth() {
        showsCalendarMonth.toggle()
    }

    /// Asks the timeline to scroll to today. The timeline answers by watching `timelineTodayRequests`.
    func requestTimelineToday() {
        timelineTodayRequests += 1
    }

    /// Sets the gallery's card size, the value Edit View's Cards section reads and writes.
    func setCardSize(_ size: ViewCards.Size) {
        changeCards { $0.size = size }
    }
}
