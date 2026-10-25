import Foundation
import Testing
@testable import MAPP

struct ItemDateTests {
    nonisolated private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    nonisolated private static func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar("UTC").date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    @Test func aDayIsItsStartInThePersonsTimeZone() throws {
        for zone in ["America/Los_Angeles", "Pacific/Auckland", "Europe/London"] {
            let calendar = Self.calendar(zone)
            let parsed = try #require(ItemDate.parse("2026-10-24", calendar: calendar))
            #expect(!parsed.hasTime)
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: parsed.date)
            #expect(parts.year == 2026 && parts.month == 10 && parts.day == 24 && parts.hour == 0 && parts.minute == 0)
        }
    }

    @Test(arguments: [
        ("2026-10-27T14:00:00.000Z", utc(2026, 10, 27, 14, 0)),
        ("2026-10-27T14:00:00Z", utc(2026, 10, 27, 14, 0)),
        ("2026-10-27T14:00Z", utc(2026, 10, 27, 14, 0)),
        ("2026-10-27T15:30:00+01:30", utc(2026, 10, 27, 14, 0)),
        ("2026-10-27T09:00:00-05:00", utc(2026, 10, 27, 14, 0)),
        ("2026-10-28T00:15:00+10:15", utc(2026, 10, 27, 14, 0)),
        ("2024-02-29T23:59:59Z", utc(2024, 2, 29, 23, 59, 59)),
    ])
    func everyMomentFormTheContractTakesIsRead(text: String, expected: Date) throws {
        let parsed = try #require(ItemDate.parse(text))
        #expect(parsed.hasTime)
        #expect(parsed.date == expected)
    }

    @Test func aFractionKeepsItsPlace() throws {
        let parsed = try #require(ItemDate.parse("2026-10-24T01:30:45.125Z"))
        #expect(abs(parsed.date.timeIntervalSince(Self.utc(2026, 10, 24, 1, 30, 45)) - 0.125) < 0.000_001)
        let long = try #require(ItemDate.parse("2026-10-24T01:30:45.123456789Z"))
        #expect(abs(long.date.timeIntervalSince(Self.utc(2026, 10, 24, 1, 30, 45)) - 0.123456789) < 0.000_001)
    }

    @Test(arguments: [
        "2026-02-30", "2025-02-29", "2026-13-01", "2026-00-02", "2026-10-00", "2026-10-32", "0000-01-01",
        "2026-02-30T12:30:00Z", "2026-10-24T24:00:00Z", "2026-10-24T12:60:00Z", "2026-10-24T12:30:60Z",
        "2026-10-24T12:30:00+24:00", "2026-10-24T12:30:00+00:60", "2026-10-24T12:30:00+0100",
        "2026-10-24T12:30:00", "2026-10-24T12Z", "2026-10-24T12:30:00.Z", "2026-10-24 12:30:00Z",
        "2026-10-24t12:30:00z", "tomorrow", "2026-1-01", " ", "", " 2026-10-24",
    ])
    func whatTheContractRefusesIsNotADate(text: String) {
        #expect(ItemDate.parse(text) == nil)
    }

    @Test func aDayFieldTakesNoTime() {
        let day = ItemTypeInfo.Field.Kind.date(includesTime: false)
        let moment = ItemTypeInfo.Field.Kind.date(includesTime: true)
        #expect(day.accepts(.string("2026-10-27")))
        #expect(!day.accepts(.string("2026-10-27T14:00:00.000Z")))
        #expect(moment.accepts(.string("2026-10-27")))
        #expect(moment.accepts(.string("2026-10-27T14:00:00.000Z")))
        #expect(moment.accepts(.string("")))
        #expect(!moment.accepts(.string("2026-10-27T14:00:00")))
    }

    @Test func aPickedDayAndMomentAreWrittenAsMarfaReadsThem() throws {
        let london = Self.calendar("Europe/London")
        let lateEvening = try #require(london.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 23, minute: 30)))
        #expect(ItemDate.day(lateEvening, calendar: london) == "2026-10-27")
        let moment = ItemDate.moment(Self.utc(2026, 10, 27, 14, 0))
        #expect(moment == "2026-10-27T14:00:00Z")
        #expect(ItemDate.parse(moment)?.date == Self.utc(2026, 10, 27, 14, 0))
    }

    @Test func aValueReadsInThePersonsLocaleAndTimeZone() throws {
        let london = Self.calendar("Europe/London")
        let locale = Locale(identifier: "en_GB")
        let moment = try #require(ItemDate.parse("2026-10-27T14:00:00.000Z", calendar: london))
        #expect(moment.text(locale: locale, calendar: london) == "27 Oct 2026 at 14:00")
        let tokyo = Self.calendar("Asia/Tokyo")
        #expect(moment.text(locale: locale, calendar: tokyo) == "27 Oct 2026 at 23:00")
        let day = try #require(ItemDate.parse("2026-10-27", calendar: tokyo))
        #expect(day.text(locale: locale, calendar: tokyo) == "27 Oct 2026")
    }
}
