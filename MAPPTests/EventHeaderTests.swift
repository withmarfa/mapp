import Foundation
import Marfa
import Testing
@testable import MAPP

struct EventHeaderTests {
    private static let english = Locale(identifier: "en_GB")

    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private static func item(_ properties: [String: PropertyValue]) -> MAPP.Item {
        MAPP.Item(
            id: ItemID("10000000-0000-0000-0000-000000000002"), type: TypeID("core.event"), title: "Event", titleRule: .property("title"),
            properties: properties.map { Property(key: $0, value: $1) }, version: ItemVersion(1), created: .distantPast, modified: .distantPast)
    }

    private static func date(_ text: String) -> Date { ItemDate.parse(text)!.date }

    private static func header(
        _ properties: [String: PropertyValue], now: String = "2026-10-27T09:00:00Z", viewer: String = "UTC"
    ) -> EventHeader? {
        EventHeader(item: item(properties), now: date(now), calendar: calendar(viewer), locale: english)
    }

    @Test func aTimedEventReadsInItsOwnZone() throws {
        let event = try #require(Self.header([
            "starts_at": .string("2026-10-29T09:00:00Z"), "ends_at": .string("2026-10-29T10:00:00Z"),
            "timezone": .string("Europe/London"),
        ], viewer: "Pacific/Auckland"))
        #expect(event.month == "OCT")
        #expect(event.day == "29")
        #expect(event.weekday == "Thursday")
        #expect(event.time == "09:00 to 10:00")
        #expect(event.zone == "London time (GMT)")
        #expect(event.relative == "in 2 days")
    }

    @Test func theDayIsTheEventsDayNotTheViewers() throws {
        // 23:30 in New York is already the next day for a viewer in London.
        let event = try #require(Self.header([
            "starts_at": .string("2026-10-30T03:30:00Z"), "ends_at": .string("2026-10-30T03:50:00Z"),
            "timezone": .string("America/New_York"),
        ], viewer: "Europe/London"))
        #expect(event.day == "29")
        #expect(event.weekday == "Thursday")
        #expect(event.time == "23:30 to 23:50")
    }

    @Test func anAllDayEventKeepsItsDateWhateverTheViewersZone() throws {
        let properties: [String: PropertyValue] = ["starts_at": .string("2026-10-29"), "all_day": .bool(true), "timezone": .string("Asia/Tokyo")]
        for viewer in ["Pacific/Auckland", "UTC", "Pacific/Honolulu"] {
            let event = try #require(Self.header(properties, viewer: viewer))
            #expect(event.day == "29")
            #expect(event.time == "All day")
            #expect(event.zone == nil)
        }
    }

    @Test func anAllDayEventWithNoZoneIsInUTC() throws {
        let event = try #require(Self.header(["starts_at": .string("2026-10-29"), "all_day": .bool(true)], viewer: "Pacific/Honolulu"))
        #expect(event.day == "29")
    }

    @Test func aRunOfDaysEndsAtTheMidnightThatClosesItsLastDay() throws {
        let event = try #require(Self.header([
            "starts_at": .string("2026-10-29"), "ends_at": .string("2026-11-01"), "all_day": .bool(true),
        ]))
        #expect(event.time == "29 Oct to 31 Oct")
        let one = try #require(Self.header(["starts_at": .string("2026-10-29"), "ends_at": .string("2026-10-30"), "all_day": .bool(true)]))
        #expect(one.time == "All day")
    }

    @Test func aDurationStandsInForAnEnd() throws {
        let event = try #require(Self.header([
            "starts_at": .string("2026-10-29T09:00:00Z"), "duration": .number(5_400), "timezone": .string("UTC"),
        ]))
        #expect(event.time == "09:00 to 10:30")
    }

    @Test func anEventThatEndsAnotherDayOrZoneSaysSo() throws {
        let overnight = try #require(Self.header([
            "starts_at": .string("2026-10-29T22:00:00Z"), "ends_at": .string("2026-10-30T02:00:00Z"), "timezone": .string("UTC"),
        ]))
        // The words joining a date and a time differ between system releases, so check the parts, not the phrase.
        for part in ["29 Oct", "22:00", "30 Oct", "02:00"] { #expect(overnight.time.contains(part)) }
        let flight = try #require(Self.header([
            "starts_at": .string("2026-10-29T10:00:00Z"), "ends_at": .string("2026-10-29T18:00:00Z"),
            "timezone": .string("Europe/London"), "end_timezone": .string("America/New_York"),
        ]))
        #expect(["(GMT-4)", "(EDT)"].contains { flight.time.hasSuffix($0) })
    }

    @Test func aStartWithNoDayToPlaceStaysInThePropertyBlock() {
        #expect(Self.header([:]) == nil)
        #expect(Self.header(["starts_at": .string("soon")]) == nil)
        #expect(Self.header(["starts_at": .string("2026-10-29"), "precision": .string("month")]) == nil)
        #expect(Self.header(["starts_at": .string("2026-10-29"), "precision": .string("year")]) == nil)
    }

    @Test func theRelativePhraseFollowsTheEventsOwnDays() throws {
        func relative(_ start: String, now: String, _ extra: [String: PropertyValue] = [:]) throws -> String {
            try #require(Self.header(["starts_at": .string(start), "timezone": .string("UTC")].merging(extra) { $1 }, now: now)).relative
        }
        #expect(try relative("2026-10-29T09:00:00Z", now: "2026-10-27T09:00:00Z") == "in 2 days")
        #expect(try relative("2026-10-28T09:00:00Z", now: "2026-10-27T22:00:00Z") == "tomorrow")
        #expect(try relative("2026-10-26T09:00:00Z", now: "2026-10-27T09:00:00Z") == "yesterday")
        #expect(try relative("2026-10-20T09:00:00Z", now: "2026-10-27T09:00:00Z") == "7 days ago")
        #expect(try relative("2026-10-27T15:00:00Z", now: "2026-10-27T09:00:00Z") == "in 6 hours")
        #expect(try relative("2026-10-27T09:00:00Z", now: "2026-10-27T09:00:00Z", ["ends_at": .string("2026-10-27T10:00:00Z")]) == "Happening now")
        #expect(try relative("2026-10-27", now: "2026-10-27T09:00:00Z", ["all_day": .bool(true)]) == "today")
        #expect(try relative("2026-10-25", now: "2026-10-27T09:00:00Z", ["all_day": .bool(true), "ends_at": .string("2026-10-30")]) == "Happening now")
    }
}
