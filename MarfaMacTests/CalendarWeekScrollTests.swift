import Foundation
import Testing
@testable import MarfaMac

/// What the week's strip, its hour height and its All Day row work out, apart from the views that draw them.
struct CalendarWeekScrollTests {
    private static func calendar(zone: String = "America/Los_Angeles") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = 2
        return calendar
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int, _ calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: Hour height

    @Test func theHourHeightIsAMacSettingThatResetClears() {
        #expect(MacSettings.keys.contains(CalendarHourHeight.key))
        #expect(MacSettings.keys.filter { $0 == CalendarHourHeight.key }.count == 1)
    }
}
