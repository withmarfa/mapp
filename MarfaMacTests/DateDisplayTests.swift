import Foundation
import SwiftUI
import Testing
@testable import MarfaMac

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

    private func text(_ date: Date, hasTime: Bool = true, _ place: DateDisplay.Place, _ format: DateFormat = .standard, locale: Locale? = nil) -> String {
        DateDisplay.text(of: date, hasTime: hasTime, place: place, format: format, now: now, calendar: calendar, locale: locale ?? self.locale)
    }

    // MARK: The standard format keeps the app's own wording

    @Test func aListLineForADayToComeIsTheDayAndTheTimeOfDayIsAvailableApart() {
        let tomorrow = moment(daysAgo: -1)
        #expect(text(tomorrow, .list) == "Tomorrow")
        #expect(DateDisplay.timeOfDay(of: tomorrow, calendar: calendar, locale: locale) == text(moment(daysAgo: 0), .list))
    }

    @Test func aListLineIsTheTimeTodayThenWordsThenTheShortDate() {
        #expect(text(moment(daysAgo: 0), .list) == "09:12")
        #expect(text(moment(daysAgo: 0, hour: 23, minute: 59), .list) == "23:59")
        #expect(text(moment(daysAgo: 1), .list) == "Yesterday")
        #expect(text(moment(daysAgo: 2), .list) == "Wednesday")
        #expect(text(moment(daysAgo: 6), .list) == "Saturday")
        #expect(text(moment(daysAgo: 7), .list) == "18/09/2026")
    }

    @Test func theShortDateOfAListLineFollowsTheLocale() {
        let date = calendar.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 9))!
        #expect(text(date, .list, locale: Locale(identifier: "en_GB")) == "31/12/2025")
        #expect(text(date, .list, locale: Locale(identifier: "en_US")) == "12/31/2025")
    }

    @Test func aTableCellReadsAsPeopleSayIt() {
        func label(_ days: Int) -> String {
            text(calendar.date(byAdding: .day, value: days, to: now)!, hasTime: false, .table)
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
    @Test func valuesAreAbbreviatedWithTheTimeWhereThereIsOneAndNeverSayToday() {
        let date = moment(daysAgo: 0, hour: 14, minute: 30)
        #expect(text(date, .value) == "25 Sep 2026 at 14:30")
        #expect(text(date, hasTime: false, .value) == "25 Sep 2026")
    }

    // MARK: Today and Yesterday off

    @Test func withoutWordsAListAndATableSayTheDate() {
        let format = DateFormat(usesWords: false)
        #expect(text(moment(daysAgo: 0), .list, format) == "25/09/2026")
        #expect(text(moment(daysAgo: 1), .list, format) == "24/09/2026")
        #expect(text(moment(daysAgo: 1), hasTime: false, .table, format) == "24 Sep")
        #expect(text(moment(daysAgo: 400), hasTime: false, .table, format).hasSuffix("2025"))
    }

    @Test func withoutWordsAValueIsUnchanged() {
        let date = moment(daysAgo: 0, hour: 14, minute: 30)
        #expect(text(date, .value, DateFormat(usesWords: false)) == text(date, .value))
    }

    // MARK: The date formats

    @Test func numericWritesTheDateInNumbersEverywhere() {
        let format = DateFormat(date: .numeric)
        let date = moment(daysAgo: 1, hour: 14, minute: 30)
        #expect(text(date, .value, format) == "24/09/2026, 14:30")
        #expect(text(date, hasTime: false, .value, format) == "24/09/2026")
        #expect(text(moment(daysAgo: 20), .list, format) == "05/09/2026")
        #expect(text(moment(daysAgo: 20), hasTime: false, .table, DateFormat(usesWords: false, date: .numeric)) == "05/09/2026")
        #expect(text(date, .value, format, locale: Locale(identifier: "en_US")).hasPrefix("9/24/2026"))
    }

    @Test func abbreviatedWritesTheMonthShortEverywhere() {
        let format = DateFormat(date: .abbreviated)
        #expect(text(moment(daysAgo: 1, hour: 14, minute: 30), .value, format) == "24 Sep 2026 at 14:30")
        #expect(text(moment(daysAgo: 20), .list, format) == "5 Sep 2026")
        #expect(text(moment(daysAgo: 20), hasTime: false, .table, format) == "5 Sep 2026")
    }

    @Test func longWritesTheMonthInFullEverywhere() {
        let format = DateFormat(date: .long)
        let date = moment(daysAgo: 1, hour: 14, minute: 30)
        #expect(text(date, .value, format) == "24 September 2026 at 14:30")
        #expect(text(date, hasTime: false, .value, format) == "24 September 2026")
        #expect(text(moment(daysAgo: 20), .list, format) == "5 September 2026")
        #expect(text(moment(daysAgo: 20), hasTime: false, .table, format) == "5 September 2026")
    }

    @Test func wordsStillWinWhileADayIsRecentWhateverTheDateFormat() {
        let format = DateFormat(date: .long)
        #expect(text(moment(daysAgo: 1), .list, format) == "Yesterday")
        #expect(text(moment(daysAgo: 0), hasTime: false, .table, format) == "Today")
    }

    // MARK: The clock

    @Test func theClockFollowsTheLocalesHoursUnlessChosen() {
        let afternoon = moment(daysAgo: 0, hour: 14, minute: 30)
        #expect(text(afternoon, .value, locale: Locale(identifier: "en_GB")).hasSuffix("14:30"))
        #expect(text(afternoon, .value, locale: Locale(identifier: "en_US")).contains("2:30"))
    }

    @Test func aChosenClockHoldsInTheLocalesOfEitherKind() {
        let afternoon = moment(daysAgo: 0, hour: 14, minute: 30)
        let twelve = DateFormat(time: .twelveHour)
        let twentyFour = DateFormat(time: .twentyFourHour)
        for identifier in ["en_GB", "en_US"] {
            let locale = Locale(identifier: identifier)
            #expect(text(afternoon, .value, twelve, locale: locale).contains("2:30"))
            #expect(!text(afternoon, .value, twelve, locale: locale).contains("14:30"))
            #expect(text(afternoon, .value, twentyFour, locale: locale).hasSuffix("14:30"))
            #expect(DateDisplay.timeOfDay(of: afternoon, format: twelve, calendar: calendar, locale: locale).contains("2:30"))
            #expect(DateDisplay.timeOfDay(of: afternoon, format: twentyFour, calendar: calendar, locale: locale) == "14:30")
        }
        // A list says the time of today on the chosen clock too.
        #expect(text(afternoon, .list, twelve).contains("2:30"))
    }

    // MARK: Every place that writes a time or a date

    @Test func theCalendarsHourGutterFollowsTheChosenClock() {
        let twelve = DateFormat(time: .twelveHour)
        let twentyFour = DateFormat(time: .twentyFourHour)
        for identifier in ["en_GB", "en_US"] {
            let locale = Locale(identifier: identifier)
            #expect(DateDisplay.hourLabel(13, format: twentyFour, locale: locale) == "13")
            #expect(DateDisplay.hourLabel(13, format: twelve, locale: locale).contains("1"))
            #expect(!DateDisplay.hourLabel(13, format: twelve, locale: locale).contains("13"))
        }
        #expect(DateDisplay.hourLabel(9, format: twentyFour, locale: Locale(identifier: "en_US")) == "09")
    }

    @Test func theTimelinesNowMarkerFollowsTheChosenClock() {
        let evening = moment(daysAgo: 0, hour: 18, minute: 5)
        let en = Locale(identifier: "en_US")
        #expect(DateDisplay.timeOfDay(of: evening, format: DateFormat(time: .twentyFourHour), calendar: calendar, locale: en) == "18:05")
        #expect(DateDisplay.timeOfDay(of: evening, format: DateFormat(time: .twelveHour), calendar: calendar, locale: en).contains("6:05"))
    }

    @Test func aTimeTheClockWritesIsReadBackByTheTimeField() {
        let evening = moment(daysAgo: 0, hour: 18, minute: 5)
        for identifier in ["en_GB", "en_US", "en_AU"] {
            for time in DateFormat.TimeStyle.allCases {
                let written = DateDisplay.timeOfDay(
                    of: evening, format: DateFormat(time: time), calendar: calendar, locale: Locale(identifier: identifier))
                #expect(TimeOfDay.parse(written).map { [$0.hour, $0.minute] } == [18, 5], "\(identifier) \(time): \(written)")
            }
        }
        #expect(TimeOfDay.parse("6:05 p.m.").map { [$0.hour, $0.minute] } == [18, 5])
        #expect(TimeOfDay.parse("6:05\u{202F}PM").map { [$0.hour, $0.minute] } == [18, 5])
    }

    @Test func aQuickDatesDayFollowsTheChosenDateFormat() {
        let entry = QuickDates.Entry(id: "today", title: "Today", symbol: "sun.max", date: moment(daysAgo: 0))
        let detail = { (format: DateFormat) in
            QuickDates.detail(of: entry, now: now, calendar: calendar, locale: locale, format: format)
        }
        #expect(detail(.standard).contains("Fri"))
        #expect(detail(DateFormat(date: .numeric)) == "25/09/2026")
        #expect(detail(DateFormat(date: .long)) == "25 September 2026")
    }

    @Test func aSettingsPageWritesItsDatesInTheChosenFormat() {
        let aWhileAgo = moment(daysAgo: 30)
        #expect(RecentlyDeletedPage.when(moment(daysAgo: 0), now: now, calendar: calendar, format: .standard) == "Today")
        #expect(RecentlyDeletedPage.when(aWhileAgo, now: now, calendar: calendar, format: DateFormat(usesWords: false, date: .long)).contains("2026"))
        let answered = moment(daysAgo: 0, hour: 14, minute: 30)
        let twentyFour = MarfaPageGate<EmptyView>.notAnswering(answered, now: now, calendar: calendar, format: DateFormat(time: .twentyFourHour))
        #expect(twentyFour.contains("14:30"))
    }

    // MARK: What is stored

    @Test func aStoredChoiceIsReadBackAndAnUnknownOneIsTheStandard() throws {
        let suite = "DateDisplayTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(DateFormat.stored(in: defaults) == .standard)
        let chosen = DateFormat(usesWords: false, date: .long, time: .twelveHour)
        defaults.set(chosen.rawValue, forKey: DateFormat.key)
        #expect(DateFormat.stored(in: defaults) == chosen)
        for style in DateFormat.DateStyle.allCases {
            let format = DateFormat(date: style)
            #expect(DateFormat(rawValue: format.rawValue) == format)
        }
        defaults.set("calendar", forKey: DateFormat.key)
        #expect(DateFormat.stored(in: defaults) == .standard)
        defaults.set("automatic", forKey: DateFormat.key)
        #expect(DateFormat.stored(in: defaults) == .standard)
    }

    @Test func aStoredValueThatDoesNotReadIsSetAsideBeforeAnythingWritesOverIt() throws {
        let suite = "DateDisplayTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let unreadable = ["automatic", "relative", #"{"date":"weird"}"#]
        for text in unreadable {
            defaults.set(text, forKey: DateFormat.key)
            DateFormat.setAsideUnreadable(in: defaults)
            #expect(defaults.object(forKey: DateFormat.key) == nil)
        }
        #expect(defaults.stringArray(forKey: DateFormat.setAsideKey) == unreadable)
        #expect(DateFormat.stored(in: defaults) == .standard)
        // A readable value is left where it is.
        let chosen = DateFormat(date: .long)
        defaults.set(chosen.rawValue, forKey: DateFormat.key)
        DateFormat.setAsideUnreadable(in: defaults)
        #expect(defaults.string(forKey: DateFormat.key) == chosen.rawValue)
        #expect(defaults.stringArray(forKey: DateFormat.setAsideKey)?.count == 3)
    }

    @Test func aFormatWithAFieldMissingStillReadsAndTheMissingFieldIsTheStandard() throws {
        // A new field on a stored value is optional: a value saved without one reads with its standard.
        let format = try #require(DateFormat(rawValue: #"{"date":"long"}"#))
        #expect(format == DateFormat(usesWords: true, date: .long, time: .system))
    }

    @Test func formatsAreEqualByTheirChoicesAndRoundTripThroughTheStoredForm() throws {
        let format = DateFormat(usesWords: false, date: .numeric, time: .twentyFourHour)
        #expect(format == DateFormat(usesWords: false, date: .numeric, time: .twentyFourHour))
        #expect(format != DateFormat(usesWords: false, date: .numeric, time: .twelveHour))
        #expect(Set([format, DateFormat(usesWords: false, date: .numeric, time: .twentyFourHour)]).count == 1)
        #expect(try #require(DateFormat(rawValue: format.rawValue)) == format)
    }
}
