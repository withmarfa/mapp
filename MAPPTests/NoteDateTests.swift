import Foundation
import Testing
@testable import MAPP

struct NoteDateTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()
    let locale = Locale(identifier: "en_GB")

    func label(_ day: Int, _ month: Int = 9, hour: Int = 9, minute: Int = 12) -> String {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 18))!
        let date = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
        return NoteDate.listLabel(for: date, now: now, calendar: calendar, locale: locale)
    }

    @Test func todayShowsTheTime() {
        #expect(label(25) == "09:12")
    }

    @Test func yesterdaySaysSo() {
        #expect(label(24) == "Yesterday")
    }

    @Test func theRestOfTheWeekShowsTheWeekday() {
        #expect(label(23) == "Wednesday")
        #expect(label(19) == "Saturday")
    }

    @Test func olderDatesShowTheDate() {
        #expect(label(18) == "18/09/2026")
        #expect(label(2, 9) == "02/09/2026")
    }
}
