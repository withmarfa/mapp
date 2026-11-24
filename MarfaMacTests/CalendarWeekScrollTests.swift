import Testing
@testable import MarfaMac

struct CalendarWeekScrollTests {
    @Test func theHourHeightIsAMacSettingThatResetClears() {
        #expect(MacSettings.keys.contains(CalendarHourHeight.key))
        #expect(MacSettings.keys.filter { $0 == CalendarHourHeight.key }.count == 1)
    }
}
