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
    let now: Date

    init() {
        now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 18))!
    }

    private func moment(daysAgo: Int, hour: Int = 9, minute: Int = 12) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    // MARK: Every place that writes a time or a date

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

    @Test func everyTableDateColumnReadsOneWay() {
        func text(_ date: Date, hasTime: Bool) -> String {
            DateDisplay.text(of: date, hasTime: hasTime, place: .table, format: .standard, now: now, calendar: calendar, locale: Locale(identifier: "en_GB"))
        }
        // An item's own stamp today is its time, and a day alone, a field's date, is the day in words.
        #expect(text(moment(daysAgo: 0, hour: 9, minute: 40), hasTime: true) == "09:40")
        #expect(text(moment(daysAgo: 0, hour: 9, minute: 40), hasTime: false) == "Today")
        // Any other day reads the same whether or not it has a time.
        #expect(text(moment(daysAgo: 1), hasTime: true) == "Yesterday")
        #expect(text(moment(daysAgo: 1), hasTime: false) == "Yesterday")
        #expect(text(moment(daysAgo: 3), hasTime: true) == text(moment(daysAgo: 3), hasTime: false))
        #expect(text(moment(daysAgo: 20), hasTime: true) == text(moment(daysAgo: 20), hasTime: false))
    }

    // MARK: What is stored

    @Test func aStoredChoiceIsReadBackAndAnUnknownOneIsTheStandard() throws {
        let defaults = ThrowawayDefaults.make("DateDisplayTests")
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
        let defaults = ThrowawayDefaults.make("DateDisplayTests")
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
