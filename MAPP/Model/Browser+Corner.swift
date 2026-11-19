import Foundation

/// What the window's bottom-right corner does to the view in front. Each is also a View menu command and a palette
/// entry, so the corner's buttons, the menu and the palette share these.
extension Browser {
    /// Shows the week or month that holds `day`, and puts the month card away.
    func chooseCalendarDay(_ day: Date, calendar: Calendar = .current) {
        calendarDay = calendar.startOfDay(for: day)
        showsCalendarMonth = false
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
