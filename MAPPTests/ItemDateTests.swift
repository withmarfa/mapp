import Foundation
import struct Marfa.ItemDate
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

    @Test(arguments: ["America/Los_Angeles", "Pacific/Auckland", "Europe/London", "Pacific/Kiritimati", "Etc/GMT+12"])
    func aDayOnlyValueIsTheSameDayInEveryTimeZoneAndWritesBackAsItWasRead(zone: String) throws {
        let calendar = Self.calendar(zone)
        let parsed = try #require(ItemDate.parse("2026-10-24", calendar: calendar))
        #expect(!parsed.hasTime)
        #expect(parsed.text(format: .automatic, locale: Locale(identifier: "en_GB"), calendar: calendar) == "24 Oct 2026")
        #expect(ItemDate.day(parsed.date, calendar: calendar) == "2026-10-24")
    }

    @Test func aMomentRoundTripsThroughTheInstantForm() throws {
        let parsed = try #require(ItemDate.parse("2026-10-27T15:30:00+01:30"))
        #expect(parsed.hasTime)
        #expect(parsed.date == Self.utc(2026, 10, 27, 14, 0))
        #expect(ItemDate.parse(ItemDate.instant(parsed.date))?.date == parsed.date)
    }

    @Test func aStatusFieldTakesAWordAndNothingElse() {
        let status = ItemTypeInfo.Field.Kind.status([StatusWord(value: "pending", group: .notStarted)])
        #expect(status.accepts(.string("pending")))
        #expect(status.accepts(.string("blocked")), "a status can hold a word its type does not declare")
        #expect(!status.accepts(.bool(true)))
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
        let moment = ItemDate.instant(Self.utc(2026, 10, 27, 14, 0))
        #expect(moment == "2026-10-27T14:00:00.000Z")
        #expect(ItemDate.parse(moment)?.date == Self.utc(2026, 10, 27, 14, 0))
    }

    @Test func aValueReadsInThePersonsLocaleAndTimeZone() throws {
        let london = Self.calendar("Europe/London")
        let locale = Locale(identifier: "en_GB")
        let moment = try #require(ItemDate.parse("2026-10-27T14:00:00.000Z", calendar: london))
        #expect(moment.text(format: .automatic, locale: locale, calendar: london) == "27 Oct 2026 at 14:00")
        let tokyo = Self.calendar("Asia/Tokyo")
        #expect(moment.text(format: .automatic, locale: locale, calendar: tokyo) == "27 Oct 2026 at 23:00")
        let day = try #require(ItemDate.parse("2026-10-27", calendar: tokyo))
        #expect(day.text(format: .automatic, locale: locale, calendar: tokyo) == "27 Oct 2026")
    }
}
