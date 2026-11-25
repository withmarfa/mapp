import Foundation
import Testing
@testable import MarfaMac

struct CalendarShownTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func entry(_ id: String, month: Int = 11, day: Int) -> CalendarEntry {
        let start = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 10))!
        return CalendarEntry(id: ItemID(id), title: id, start: start, end: start.addingTimeInterval(3_600), isAllDay: false)
    }

    @Test func aChoiceNarrowsToTheEventsOfTheWeekOrMonthDrawn() {
        let entries = [entry("this", day: 25), entry("next", day: 30), entry("last month", month: 10, day: 10)]
        let firstShown = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23))!
        let week = CalendarLayout.drawn(.week, firstShown: firstShown, anchor: firstShown, calendar: calendar)
        #expect(CalendarLayout.ids(in: entries, within: week) == [ItemID("this")], "the next week's event is not drawn, so a change of week drops it from the choice")
        let month = CalendarLayout.drawn(.month, firstShown: firstShown, anchor: firstShown, calendar: calendar)
        #expect(CalendarLayout.ids(in: entries, within: month) == [ItemID("this"), ItemID("next")])
    }
}
