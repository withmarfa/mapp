import Foundation
import struct Marfa.ItemDate
import Testing
@testable import MAPP

struct CalendarLayoutTests {
    private static let event = TypeID("example.event")
    private static let note = TypeID("example.note")
    private static let catalogue = Catalogue(itemTypes: [
        ItemTypeInfo(id: event, label: "Event", fields: [
            .init(key: "starts_at", label: "Starts at", kind: .date(includesTime: true), declaredBy: event),
            .init(key: "due_at", label: "Due at", kind: .date(includesTime: false), declaredBy: event),
        ], titleField: nil, bodyField: nil, parent: nil),
        ItemTypeInfo(id: note, label: "Note", fields: [], titleField: nil, bodyField: nil, parent: nil),
    ])
    private static let looks: [TypeID: TypeLook] = [
        event: TypeLook(date: .field("starts_at"), secondary: [], facts: []),
        note: TypeLook(date: .off, secondary: [], facts: []),
    ]

    private static func calendar(
        _ identifier: Calendar.Identifier = .gregorian, zone: String = "America/Los_Angeles", firstWeekday: Int = 2
    ) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = firstWeekday
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private static func item(_ id: String, type: TypeID = event, _ properties: [String: PropertyValue]) -> Item {
        Item(
            id: ItemID(id), type: type, title: id, name: id, titleRule: .property("title"),
            properties: properties.map { Property(key: $0.key, value: $0.value) }, version: ItemVersion(1),
            created: .distantPast, modified: .distantPast)
    }

    private static func timed(_ id: String, _ start: String, _ end: String? = nil, zone: String? = nil) -> Item {
        var properties: [String: PropertyValue] = ["starts_at": .string(stamp(start, zone: zone ?? "America/Los_Angeles"))]
        if let end { properties["ends_at"] = .string(stamp(end, zone: zone ?? "America/Los_Angeles")) }
        if let zone { properties["timezone"] = .string(zone) }
        return item(id, properties)
    }

    private static func entries(_ items: [Item], _ calendar: Calendar) -> (entries: [CalendarEntry], leftOut: Int) {
        CalendarLayout.entries(for: items, looks: looks, catalogue: catalogue, calendar: calendar)
    }

    /// A wall-clock time such as `2026-11-04T10:30:00` or a day such as `2026-11-04`, read in `calendar`'s zone.
    private static func date(_ text: String, _ calendar: Calendar) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = text.contains("T") ? "yyyy-MM-dd'T'HH:mm:ss" : "yyyy-MM-dd"
        return formatter.date(from: text)!
    }

    /// The stored form of a wall-clock time in the Mac's zone: an instant, since Marfa's dates carry their offset.
    private static func stamp(_ text: String, zone: String = "America/Los_Angeles") -> String {
        ItemDate.instant(date(text, calendar(zone: zone)))
    }

    private static func week(_ items: [Item], around day: String, _ calendar: Calendar) -> CalendarWeek {
        CalendarWeek.make(
            entries: entries(items, calendar).entries, around: date(day, calendar), calendar: calendar,
            now: date("2026-11-04T12:00:00", calendar))
    }

    private static func month(_ items: [Item], around day: String, _ calendar: Calendar) -> CalendarMonth {
        CalendarMonth.make(
            entries: entries(items, calendar).entries, around: date(day, calendar), calendar: calendar,
            now: date("2026-11-04T12:00:00", calendar))
    }

    private static func ids(_ entries: [CalendarEntry]) -> [String] { entries.map(\.id.rawValue) }

    @Test func anAllDayEventIsAWholeDayInTheAllDayRow() {
        let calendar = Self.calendar()
        let week = Self.week([Self.item("studio", ["starts_at": .string("2026-11-02"), "all_day": .bool(true)])], around: "2026-11-04", calendar)
        #expect(week.days.map { Self.ids($0.allDay) } == [["studio"], [], [], [], [], [], []])
        #expect(week.days.allSatisfy { $0.blocks.isEmpty })
    }

    @Test func aMultiDayEventIsOnEachDayItCovers() {
        let calendar = Self.calendar()
        let item = Self.item("away", ["starts_at": .string("2026-11-04"), "ends_at": .string("2026-11-07"), "all_day": .bool(true)])
        let week = Self.week([item], around: "2026-11-04", calendar)
        #expect(week.days.map { Self.ids($0.allDay) } == [[], [], ["away"], ["away"], ["away"], [], []])
        let month = Self.month([item], around: "2026-11-04", calendar)
        let covered = month.weeks.flatMap { $0 }.filter { !$0.entries.isEmpty }.map { calendar.component(.day, from: $0.date) }
        #expect(covered == [4, 5, 6])
        #expect(month.itemCount == 1)
    }

    @Test func aTimedEventOverMidnightHasABlockOnEachDay() throws {
        let calendar = Self.calendar()
        let week = Self.week([Self.timed("late", "2026-11-04T22:00:00", "2026-11-05T02:00:00")], around: "2026-11-04", calendar)
        let wednesday = try #require(week.days[2].blocks.first)
        let thursday = try #require(week.days[3].blocks.first)
        #expect((wednesday.startMinute, wednesday.endMinute) == (22 * 60, 24 * 60))
        #expect((thursday.startMinute, thursday.endMinute) == (0, 2 * 60))
        #expect(wednesday.continuesAfter && !wednesday.continuesBefore)
        #expect(thursday.continuesBefore && !thursday.continuesAfter)
        #expect(week.days.enumerated().filter { !$0.element.blocks.isEmpty }.map(\.offset) == [2, 3])
    }

    @Test func aTimedEventOverSeveralDaysFillsTheDaysBetween() throws {
        let calendar = Self.calendar()
        let week = Self.week([Self.timed("trip", "2026-11-03T20:00:00", "2026-11-06T09:00:00")], around: "2026-11-04", calendar)
        let blocks = week.days.compactMap(\.blocks.first)
        #expect(blocks.map(\.startMinute) == [20 * 60, 0, 0, 0])
        #expect(blocks.map(\.endMinute) == [1440, 1440, 1440, 9 * 60])
    }

    @Test func anEventInAnotherZoneSitsWhereTheMacsClockPutsIt() throws {
        let calendar = Self.calendar()
        // 09:00 in Tokyo is 16:00 the day before in Los Angeles.
        let week = Self.week([Self.timed("tokyo", "2026-11-04T09:00:00", "2026-11-04T10:00:00", zone: "Asia/Tokyo")], around: "2026-11-04", calendar)
        let block = try #require(week.days[1].blocks.first)
        #expect(block.startMinute == 16 * 60)
        #expect(week.days[2].blocks.isEmpty)
    }

    @Test func aWholeDayInAnotherZoneKeepsItsDays() {
        let calendar = Self.calendar()
        let item = Self.item("tokyo-day", ["starts_at": .string("2026-11-04"), "all_day": .bool(true), "timezone": .string("Asia/Tokyo")])
        let week = Self.week([item], around: "2026-11-04", calendar)
        #expect(Self.ids(week.days[2].allDay) == ["tokyo-day"])
    }

    @Test func aTimedEventWithNoEndLastsAnHour() throws {
        let calendar = Self.calendar()
        let placed = Self.entries([Self.timed("call", "2026-11-04T10:30:00")], calendar)
        let entry = try #require(placed.entries.first)
        #expect(entry.end.timeIntervalSince(entry.start) == CalendarLayout.defaultLength)
        let week = Self.week([Self.timed("call", "2026-11-04T10:30:00")], around: "2026-11-04", calendar)
        let block = try #require(week.days[2].blocks.first)
        #expect((block.startMinute, block.endMinute) == (630, 690))
    }

    @Test func overlappingEventsAreSetSideBySide() throws {
        let calendar = Self.calendar()
        let items = [
            Self.timed("a", "2026-11-04T10:00:00", "2026-11-04T12:00:00"),
            Self.timed("b", "2026-11-04T11:00:00", "2026-11-04T13:00:00"),
            Self.timed("c", "2026-11-04T12:30:00", "2026-11-04T13:30:00"),
            Self.timed("d", "2026-11-04T15:00:00", "2026-11-04T16:00:00"),
        ]
        let blocks = Self.week(items, around: "2026-11-04", calendar).days[2].blocks
        func block(_ id: String) -> CalendarWeek.Block { blocks.first { $0.entry.id.rawValue == id }! }
        let placed: [Int] = ["a", "b", "c"].map { block($0).column }
        #expect(placed == [0, 1, 0])
        let widths: [Int] = ["a", "b", "c"].map { block($0).columns }
        #expect(widths == [2, 2, 2])
        #expect((block("d").column, block("d").columns) == (0, 1))
    }

    @Test func aShortEventDoesNotHideBehindOneStartingJustAfter() {
        let calendar = Self.calendar()
        let items = [
            Self.timed("brief", "2026-11-04T10:00:00", "2026-11-04T10:05:00"),
            Self.timed("next", "2026-11-04T10:10:00", "2026-11-04T11:00:00"),
        ]
        let blocks = Self.week(items, around: "2026-11-04", calendar).days[2].blocks
        #expect(Set(blocks.map(\.column)) == [0, 1])
    }

    @Test func aCrowdedMonthDayShowsWhatFitsAndCountsTheRest() throws {
        let calendar = Self.calendar()
        let items = (1...5).map { Self.timed("e\($0)", "2026-11-04T0\($0):00:00", "2026-11-04T0\($0):30:00") }
        let month = Self.month(items, around: "2026-11-04", calendar)
        let day = try #require(month.weeks.flatMap { $0 }.first { calendar.component(.day, from: $0.date) == 4 && $0.isInMonth })
        #expect(day.entries.count == 5)
        let crowded = day.fitting(capacity: 3)
        #expect(Self.ids(crowded.shown) == ["e1", "e2"])
        #expect(crowded.more == 3)
        let roomy = day.fitting(capacity: 5)
        #expect(roomy.shown.count == 5 && roomy.more == 0)
    }

    @Test func theWeekStartsOnThePersonsFirstWeekday() {
        let monday = Self.week([], around: "2026-11-04", Self.calendar(firstWeekday: 2))
        let sunday = Self.week([], around: "2026-11-04", Self.calendar(firstWeekday: 1))
        func days(_ week: CalendarWeek) -> [Int] { week.days.map { Self.calendar().component(.day, from: $0.date) } }
        #expect(days(monday) == [2, 3, 4, 5, 6, 7, 8])
        #expect(days(sunday) == [1, 2, 3, 4, 5, 6, 7])
        #expect(Self.month([], around: "2026-11-04", Self.calendar(firstWeekday: 1)).weeks.first?.first.map { Self.calendar().component(.day, from: $0.date) } == 1)
        #expect(Self.month([], around: "2026-11-04", Self.calendar(firstWeekday: 2)).weeks.first?.first.map { Self.calendar().component(.day, from: $0.date) } == 26)
    }

    @Test func aWeekAcrossTheDaylightSavingChangeKeepsSevenDaysAndTheClock() throws {
        // Clocks go back in Los Angeles on Sunday 1 November 2026, so that day has 25 hours.
        let calendar = Self.calendar(firstWeekday: 1)
        let items = [
            Self.timed("sunday", "2026-11-01T10:00:00", "2026-11-01T11:00:00"),
            Self.timed("monday", "2026-11-02T10:00:00", "2026-11-02T11:00:00"),
            Self.timed("overnight", "2026-10-31T23:00:00", "2026-11-01T01:00:00"),
        ]
        let week = Self.week(items, around: "2026-11-03", calendar)
        #expect(week.days.count == 7)
        #expect(Set(week.days.map(\.date)).count == 7)
        #expect(week.days.dropFirst().map { calendar.component(.day, from: $0.date) } == [2, 3, 4, 5, 6, 7])
        let sunday = try #require(week.days[0].blocks.first { $0.entry.id.rawValue == "sunday" })
        let monday = try #require(week.days[1].blocks.first)
        #expect(sunday.startMinute == 600 && monday.startMinute == 600)
        #expect(week.days[0].blocks.contains { $0.entry.id.rawValue == "overnight" })
        #expect(week.days[0].date.distance(to: week.days[1].date) == 25 * 3600)
    }

    @Test func aWeekAcrossTheSpringChangeHas23Hours() {
        // Clocks go forward in Los Angeles on Sunday 8 March 2026.
        let calendar = Self.calendar(firstWeekday: 1)
        let week = Self.week([], around: "2026-03-10", calendar)
        #expect(week.days.count == 7)
        #expect(week.days[0].date.distance(to: week.days[1].date) == 23 * 3600)
    }

    @Test func anItemWithNoDateIsLeftOut() {
        let calendar = Self.calendar()
        let items = [
            Self.timed("dated", "2026-11-04T10:00:00"),
            Self.item("undated", [:]),
            Self.item("note", type: Self.note, ["title": .string("A note")]),
        ]
        let placed = Self.entries(items, calendar)
        #expect(Self.ids(placed.entries) == ["dated"])
        #expect(placed.leftOut == 2)
    }

    @Test(arguments: [Calendar.Identifier.hebrew, .islamicUmmAlQura, .japanese, .buddhist, .persian])
    func aNonGregorianMacCalendarKeepsWholeWeeksAndTheRightDays(identifier: Calendar.Identifier) throws {
        let calendar = Self.calendar(identifier, firstWeekday: 1)
        let gregorian = Self.calendar()
        let when = gregorian.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 10))!
        let item = Self.item("event", ["starts_at": .string(ItemDate.instant(when)), "ends_at": .string(ItemDate.instant(when.addingTimeInterval(3600)))])
        let entries = CalendarLayout.entries(for: [item], looks: Self.looks, catalogue: Self.catalogue, calendar: calendar).entries
        let month = CalendarMonth.make(entries: entries, around: when, calendar: calendar, now: when)
        #expect(!month.weeks.isEmpty)
        for week in month.weeks {
            #expect(week.count == 7)
            #expect(calendar.component(.weekday, from: week[0].date) == 1)
        }
        let days = month.weeks.flatMap { $0 }
        #expect(zip(days, days.dropFirst()).allSatisfy { calendar.date(byAdding: .day, value: 1, to: $0.date) == $1.date })
        let holding = days.filter { !$0.entries.isEmpty }
        #expect(holding.count == 1)
        #expect(calendar.isDate(try #require(holding.first).date, inSameDayAs: when))
        #expect(holding.first?.isInMonth == true)
        let week = CalendarWeek.make(entries: entries, around: when, calendar: calendar, now: when)
        #expect(week.days.count == 7)
        #expect(week.days.filter { !$0.blocks.isEmpty }.count == 1)
    }

    @Test func movingStepsByWholeWeeksAndMonths() {
        let calendar = Self.calendar()
        let start = Self.date("2026-11-04T12:00:00", calendar)
        let week = CalendarLayout.moved(start, by: 1, scale: .week, calendar: calendar)
        #expect(calendar.component(.day, from: week) == 11)
        let month = CalendarLayout.moved(start, by: -1, scale: .month, calendar: calendar)
        #expect(calendar.component(.month, from: month) == 10)
    }
}
