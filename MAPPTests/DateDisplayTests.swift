import Foundation
import Testing
@testable import MAPP

struct DateDisplayTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()
    let locale = Locale(identifier: "en_GB")
    let now: Date

    init() {
        now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 18))!
    }

    private func moment(daysAgo: Int, hour: Int = 9, minute: Int = 12) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func text(_ date: Date, hasTime: Bool = true, _ place: DateDisplay.Place, _ format: DateFormat, locale: Locale? = nil) -> String {
        DateDisplay.text(of: date, hasTime: hasTime, place: place, format: format, now: now, calendar: calendar, locale: locale ?? self.locale)
    }

    // MARK: Automatic and relative keep the app's own wording

    @Test func aListLineForADayToComeIsTheDayAndTheTimeOfDayIsAvailableApart() {
        let tomorrow = moment(daysAgo: -1)
        #expect(text(tomorrow, .list, .automatic) == "Tomorrow")
        #expect(DateDisplay.timeOfDay(of: tomorrow, calendar: calendar, locale: locale) == text(moment(daysAgo: 0), .list, .automatic))
    }

    @Test(arguments: [DateFormat.automatic, .relative])
    func aListLineIsTheTimeTodayThenWordsThenTheShortDate(_ format: DateFormat) {
        #expect(text(moment(daysAgo: 0), .list, format) == "09:12")
        #expect(text(moment(daysAgo: 0, hour: 23, minute: 59), .list, format) == "23:59")
        #expect(text(moment(daysAgo: 1), .list, format) == "Yesterday")
        #expect(text(moment(daysAgo: 2), .list, format) == "Wednesday")
        #expect(text(moment(daysAgo: 6), .list, format) == "Saturday")
        #expect(text(moment(daysAgo: 7), .list, format) == "18/09/2026")
    }

    @Test func theShortDateOfAListLineFollowsTheLocale() {
        let date = calendar.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 9))!
        #expect(text(date, .list, .automatic, locale: Locale(identifier: "en_GB")) == "31/12/2025")
        #expect(text(date, .list, .automatic, locale: Locale(identifier: "en_US")) == "12/31/2025")
    }

    @Test(arguments: [DateFormat.automatic, .relative])
    func aTableCellReadsAsPeopleSayIt(_ format: DateFormat) {
        func label(_ days: Int) -> String {
            text(calendar.date(byAdding: .day, value: days, to: now)!, hasTime: false, .table, format)
        }
        #expect(label(0) == "Today")
        #expect(label(1) == "Tomorrow")
        #expect(label(-1) == "Yesterday")
        #expect(label(-3) == "Tuesday")
        // The month's abbreviation is the locale's own, so only what the label must hold is checked.
        #expect(label(-30).hasPrefix("26 Aug") && !label(-30).contains("2026"))
        #expect(label(-400).hasSuffix("2025"))
    }

    // Value tests use an afternoon time: the morning hour's padding (9:12 or 09:12) is the system's to decide.
    @Test func automaticValuesAreAbbreviatedWithTheTimeWhereThereIsOne() {
        let date = moment(daysAgo: 0, hour: 14, minute: 30)
        #expect(text(date, .value, .automatic) == "25 Sep 2026 at 14:30")
        #expect(text(date, hasTime: false, .value, .automatic) == "25 Sep 2026")
    }

    // MARK: The other formats

    @Test func relativeValuesSayTheDayInWordsAndKeepTheTime() {
        #expect(text(moment(daysAgo: 0, hour: 14, minute: 30), .value, .relative) == "Today at 14:30")
        #expect(text(moment(daysAgo: 1, hour: 14, minute: 30), .value, .relative) == "Yesterday at 14:30")
        #expect(text(moment(daysAgo: 1, hour: 14, minute: 30), hasTime: false, .value, .relative) == "Yesterday")
        #expect(text(moment(daysAgo: 30), hasTime: false, .value, .relative).hasPrefix("26 Aug"))
    }

    @Test func shortWritesTheDateInNumbersEverywhere() {
        let date = moment(daysAgo: 1, hour: 14, minute: 30)
        #expect(text(date, .value, .short) == "24/09/2026, 14:30")
        #expect(text(date, hasTime: false, .value, .short) == "24/09/2026")
        #expect(text(date, .list, .short) == "24/09/2026")
        #expect(text(date, hasTime: false, .table, .short) == "24/09/2026")
        #expect(text(date, .value, .short, locale: Locale(identifier: "en_US")).hasPrefix("9/24/2026"))
    }

    @Test func longWritesTheMonthInFullEverywhere() {
        let date = moment(daysAgo: 1, hour: 14, minute: 30)
        #expect(text(date, .value, .long) == "24 September 2026 at 14:30")
        #expect(text(date, hasTime: false, .value, .long) == "24 September 2026")
        #expect(text(date, .list, .long) == "24 September 2026")
        #expect(text(date, hasTime: false, .table, .long) == "24 September 2026")
    }

    @Test func theClockFollowsTheLocalesHours() {
        let afternoon = moment(daysAgo: 0, hour: 14, minute: 30)
        #expect(text(afternoon, .value, .long, locale: Locale(identifier: "en_GB")).hasSuffix("14:30"))
        #expect(text(afternoon, .value, .long, locale: Locale(identifier: "en_US")).contains("2:30"))
    }

    @Test func aStoredChoiceIsReadBackAndAnUnknownOneIsAutomatic() throws {
        let suite = "DateDisplayTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(DateFormat.stored(in: defaults) == .automatic)
        for format in DateFormat.allCases {
            defaults.set(format.rawValue, forKey: DateFormat.key)
            #expect(DateFormat.stored(in: defaults) == format)
        }
        defaults.set("calendar", forKey: DateFormat.key)
        #expect(DateFormat.stored(in: defaults) == .automatic)
    }
}
