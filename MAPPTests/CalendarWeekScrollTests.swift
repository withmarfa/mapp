import Foundation
import Testing
@testable import MAPP

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

    @Test func anHourIsHeldToItsRangeWhateverThePinchDoes() {
        #expect(CalendarHourHeight.range == 24...160)
        #expect(CalendarHourHeight.clamped(10) == 24)
        #expect(CalendarHourHeight.clamped(500) == 160)
        #expect(CalendarHourHeight.clamped(80) == 80)
        #expect(CalendarHourHeight.clamped(.nan) == CalendarHourHeight.standard)
        #expect(CalendarHourHeight.pinched(from: 59, magnification: 10) == 160)
        #expect(CalendarHourHeight.pinched(from: 59, magnification: 0.1) == 24)
        #expect(CalendarHourHeight.pinched(from: 80, magnification: 1.25) == 100)
        #expect(CalendarHourHeight.pinched(from: 80, magnification: -1) == 80)
    }

    @Test func theHourUnderThePointerStaysUnderIt() {
        // The pointer is 200 points down the grid at 50 points an hour, which is four hours in. At 100 an hour that
        // hour is 400 points down, so the grid scrolls on by 200.
        #expect(CalendarHourHeight.offset(keeping: 200, scrolled: 30, from: 50, to: 100) == 230)
        // Shrinking again: that hour is now 400 points down the grid, and 200 points down on screen.
        #expect(CalendarHourHeight.offset(keeping: 400, scrolled: 230, from: 100, to: 50) == 30)
        #expect(CalendarHourHeight.offset(keeping: 0, scrolled: 12, from: 59, to: 160) == 12)
        #expect(CalendarHourHeight.offset(keeping: 200, scrolled: 7, from: 0, to: 100) == 7)
    }

    @Test func theHourHeightIsAMacSettingThatResetClears() {
        #expect(MacSettings.keys.contains(CalendarHourHeight.key))
        #expect(MacSettings.keys.filter { $0 == CalendarHourHeight.key }.count == 1)
    }

    // MARK: The strip

    @Test func aDayHasOneIndexAndComesBackFromIt() {
        let calendar = Self.calendar()
        let middle = Self.day(2026, 11, 18, calendar)
        let strip = CalendarStrip(around: middle, calendar: calendar)
        #expect(strip.index(of: middle, calendar: calendar) == CalendarStrip.reach)
        #expect(strip.day(at: CalendarStrip.reach, calendar: calendar) == middle)
        #expect(strip.index(of: calendar.date(byAdding: .hour, value: 15, to: middle)!, calendar: calendar) == CalendarStrip.reach)
        for index in [0, 1, 400, CalendarStrip.reach + 3, strip.count - 1] {
            let day = strip.day(at: index, calendar: calendar)
            #expect(strip.index(of: day, calendar: calendar) == index)
            #expect(calendar.startOfDay(for: day) == day)
        }
    }

    @Test(arguments: ["America/Los_Angeles", "Europe/London", "Australia/Lord_Howe"])
    func everyDayIsOneColumnWhateverTheClocksDo(zone: String) {
        let calendar = Self.calendar(zone: zone)
        let strip = CalendarStrip(around: Self.day(2026, 11, 1, calendar), calendar: calendar)
        let days = (0..<strip.count).map { strip.day(at: $0, calendar: calendar) }
        #expect(days == days.sorted())
        #expect(Set(days).count == strip.count)
        #expect(days.allSatisfy { calendar.startOfDay(for: $0) == $0 })
        for index in stride(from: 0, to: strip.count, by: 37) { #expect(strip.index(of: days[index], calendar: calendar) == index) }
    }

    @Test func theDayAClockChangeLengthensIsStillOneColumn() {
        // Clocks go back in Los Angeles on Sunday 1 November 2026, so that day has 25 hours.
        let calendar = Self.calendar()
        let strip = CalendarStrip(around: Self.day(2026, 10, 30, calendar), calendar: calendar)
        let sunday = Self.day(2026, 11, 1, calendar)
        let index = strip.index(of: sunday, calendar: calendar)
        #expect(index == CalendarStrip.reach + 2)
        #expect(strip.index(of: calendar.date(byAdding: .hour, value: 24, to: sunday)!, calendar: calendar) == index)
        #expect(strip.index(of: Self.day(2026, 11, 2, calendar), calendar: calendar) == index + 1)
    }

    @Test func aScrollSettlesOnTheNearestDayEdge() {
        #expect(CalendarStrip.snapped(offset: 0, dayWidth: 100) == 0)
        #expect(CalendarStrip.snapped(offset: 149, dayWidth: 100) == 100)
        #expect(CalendarStrip.snapped(offset: 151, dayWidth: 100) == 200)
        #expect(CalendarStrip.snapped(offset: 151, dayWidth: 0) == 151)
        let rest = CalendarStrip.position(offset: 300, dayWidth: 100)
        #expect(rest == CalendarStrip.Position(leading: 3, nearest: 3, isBetween: false))
        let between = CalendarStrip.position(offset: 360, dayWidth: 100)
        #expect(between == CalendarStrip.Position(leading: 3, nearest: 4, isBetween: true))
        #expect(rest.shown() == 3..<10)
        #expect(between.shown() == 3..<11)
    }

    @Test func theStripIsBuiltAgainOnlyWhereADayIsNearItsEnd() {
        let calendar = Self.calendar()
        let strip = CalendarStrip(around: Self.day(2026, 11, 18, calendar), calendar: calendar)
        #expect(strip.holds(CalendarStrip.reach))
        #expect(strip.holds(CalendarStrip.margin))
        #expect(!strip.holds(CalendarStrip.margin - 1))
        #expect(!strip.holds(strip.count - CalendarStrip.margin))
        #expect(strip.drawn(leading: 0) == 0..<9)
        #expect(strip.drawn(leading: 500) == 499..<509)
        #expect(strip.drawn(leading: strip.count - 1) == (strip.count - 2)..<strip.count)
    }
}
