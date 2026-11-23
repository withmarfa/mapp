import Foundation
import struct Marfa.ItemDate
import Testing
@testable import MarfaMac

struct ItemTimelineTests {
    private static let event = TypeID("example.event")
    private static let note = TypeID("example.note")
    private static let task = TypeID("example.task")
    private static let catalogue = Catalogue(itemTypes: [
        ItemTypeInfo(id: TypeID("core.task"), label: "Core Task", fields: [], titleField: nil, bodyField: nil, parent: nil),
        ItemTypeInfo(id: task, label: "Task", fields: [
            .init(key: "due_at", label: "Due at", kind: .date(includesTime: true), declaredBy: TypeID("core.task")),
        ], titleField: nil, bodyField: nil, parent: TypeID("core.task")),
        ItemTypeInfo(id: event, label: "Event", fields: [
            .init(key: "starts_at", label: "Starts at", kind: .date(includesTime: true), declaredBy: event),
            .init(key: "due_at", label: "Due at", kind: .date(includesTime: true), declaredBy: event),
            .init(key: "published_at", label: "Published at", kind: .date(includesTime: true), declaredBy: event),
        ], titleField: nil, bodyField: nil, parent: nil),
        ItemTypeInfo(id: note, label: "Note", fields: [
            .init(key: "due_at", label: "Due at", kind: .text, declaredBy: note),
        ], titleField: nil, bodyField: nil, parent: nil),
    ])

    /// Each type's look: a task by its due date, an event by its start, a note by when it was last changed.
    private static let looks: [TypeID: TypeLook] = [
        task: TypeLook(date: .field("due_at"), secondary: [], facts: []),
        event: TypeLook(date: .field("starts_at"), secondary: [], facts: []),
        note: TypeLook(date: .edited, secondary: [], facts: []),
    ]

    private static func calendar(_ zone: String = "America/Los_Angeles") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private static func item(
        _ id: String, title: String? = nil, type: TypeID = event, date: PropertyValue? = nil,
        _ more: [String: PropertyValue] = [:], modified: Date = .distantPast
    ) -> Item {
        var properties = more.map { Property(key: $0.key, value: $0.value) }
        if let date { properties.append(Property(key: "due_at", value: date)) }
        return Item(
            id: ItemID(id), type: type, title: title ?? id, name: title ?? id, titleRule: .property("title"),
            properties: properties, version: ItemVersion(1), created: .distantPast, modified: modified)
    }

    private static func groups(
        _ items: [Item], field: String? = nil, today: Date? = nil, zone: String = "America/Los_Angeles"
    ) -> [ItemTimelineGroup] {
        ItemTimelineLayout.groups(
            for: items, field: field, looks: looks, catalogue: catalogue, today: today, calendar: calendar(zone))
    }

    private static func day(_ text: String, zone: String = "America/Los_Angeles") -> Date {
        ItemDate.parse(text, calendar: calendar(zone))!.date
    }

    private static func ids(_ groups: [ItemTimelineGroup]) -> [[String]] { groups.map { $0.rows.map(\.id.rawValue) } }

    @Test func timestampGroupsByItsLocalDayAndKeepsItsTime() throws {
        let calendar = Self.calendar()
        let raw = "2026-10-24T01:30:45.125Z"
        let groups = Self.groups([Self.item("event", date: .string(raw))], field: "due_at")
        let group = try #require(groups.first)
        guard case .day(let day) = group.id,
              case .dated(let instant, let dateOnly, let kept) = group.rows[0].value else {
            Issue.record("A valid timestamp must have a chronological group")
            return
        }
        #expect(calendar.component(.day, from: day) == 23)
        #expect(calendar.component(.hour, from: instant) == 18)
        #expect(calendar.component(.minute, from: instant) == 30)
        #expect(!dateOnly)
        #expect(kept == raw)
    }

    @Test(arguments: [
        "2026-02-30", "2025-02-29", "2026-13-01", "2026-00-02", "2026-10-00", "2026-10-32",
        "2026-02-30T12:30:00Z", "2026-10-24T25:00:00Z", "2026-10-24T12:60:00Z",
        "2026-10-24T12:30:61Z", "2026-10-24T12:30:00+25:00", "2026-10-24T12:30:00+00:60",
        "2026-10-24T12:30:00", "tomorrow", "2026-1-01", " ",
    ])
    func invalidValuesRemainVisible(raw: String) {
        let item = Self.item("invalid", date: .string(raw))
        let groups = Self.groups([item], field: "due_at")
        #expect(groups.map(\.id) == [.invalid])
        #expect(groups.flatMap(\.rows).map(\.id) == [item.id])
    }

    @Test func missingInvalidAndNonApplicableStaySeparateWhenTheFieldIsPicked() {
        let items = [
            Self.item("missing"), Self.item("null", date: .null), Self.item("empty", date: .string("")),
            Self.item("wrong-shape", date: .number(42)), Self.item("not-date-field", type: Self.note, date: .string("2026-10-24")),
        ]
        let groups = Self.groups(items, field: "due_at")
        #expect(groups.map(\.id) == [.missing, .invalid, .notApplicable])
        #expect(groups[0].rows.count == 3)
        #expect(groups[1].rows.first?.value == .invalid("42"))
        #expect(groups[2].rows.first?.value == .notApplicable)
        #expect(Set(groups.flatMap(\.rows).map(\.id)) == Set(items.map(\.id)))
    }

    @Test func aPickedFieldPlacesEveryItemByIt() {
        let task = Self.item("task", type: Self.task, date: .string("2026-10-24T10:00:00Z"))
        let event = Self.item("event", ["starts_at": .string("2026-10-25T10:00:00Z")])
        let dueOnEvent = Self.item("event-due", date: .string("2026-10-26T10:00:00Z"))
        let byDue = Self.groups([task, event, dueOnEvent], field: "due_at", today: Self.day("2026-10-24"))
        #expect(Self.ids(byDue) == [["task"], ["event-due"], ["event"]])
        #expect(byDue.last?.id == .missing)
        let byStart = Self.groups([task, event], field: "starts_at", today: Self.day("2026-10-24"))
        #expect(Self.ids(byStart) == [["event"], ["task"]])
        #expect(byStart.last?.id == .notApplicable)
    }

    @Test func aMixedTimelinePlacesEachItemOnItsTypesDate() {
        let items = [
            Self.item("event", ["starts_at": .string("2026-10-24T09:30:00-07:00")]),
            Self.item("task", type: Self.task, date: .string("2026-10-24T17:00:00-07:00")),
            Self.item("later-task", type: Self.task, date: .string("2026-10-25")),
            Self.item("undated-event"),
        ]
        let groups = Self.groups(items, today: Self.day("2026-10-24"))
        #expect(Self.ids(groups) == [["event", "task"], ["later-task"], ["undated-event"]])
        #expect(groups.map(\.id).last == .missing)
        #expect(!groups.contains { $0.id == .notApplicable })
    }

    @Test func anAllDayEventSitsOnItsDayAtTheTop() throws {
        let items = [
            Self.item("early-task", type: Self.task, date: .string("2026-10-24T07:00:00-07:00")),
            Self.item("holiday", ["starts_at": .string("2026-10-24"), "all_day": .bool(true)]),
        ]
        let group = try #require(Self.groups(items).first)
        #expect(group.rows.map(\.id.rawValue) == ["holiday", "early-task"])
        guard case .dated(_, let dateOnly, _) = group.rows[0].value else { Issue.record("The day is placed"); return }
        #expect(dateOnly)
    }

    @Test func anEventInAnotherZoneIsPlacedOnTheMacsDay() throws {
        // 9:00 on the 24th in Tokyo is 5:00 pm on the 23rd in Los Angeles.
        let timed = Self.item("tokyo", ["starts_at": .string("2026-10-24T09:00:00+09:00"), "timezone": .string("Asia/Tokyo")])
        let group = try #require(Self.groups([timed]).first)
        #expect(group.id == .day(Self.day("2026-10-23")))
        guard case .dated(let at, false, _) = group.rows[0].value else { Issue.record("A timed event"); return }
        #expect(Self.calendar().component(.hour, from: at) == 17)
        // A whole day in Tokyo is that day for a reader in Los Angeles too.
        let whole = Self.item("tokyo-day", [
            "starts_at": .string("2026-10-24T00:00:00+09:00"), "all_day": .bool(true), "timezone": .string("Asia/Tokyo"),
        ])
        #expect(try #require(Self.groups([whole]).first).id == .day(Self.day("2026-10-24")))
    }

    @Test func aWholeDayWithNoEndStaysOneDayWhateverItsEndZone() throws {
        // Kiritimati is a day ahead of Pago Pago, so the first day's midnight there already names the next date.
        let day = Self.item("dateline", [
            "starts_at": .string("2026-10-24"), "all_day": .bool(true),
            "timezone": .string("Pacific/Pago_Pago"), "end_timezone": .string("Pacific/Kiritimati"),
        ])
        let placement = ItemPlacement.of(day, look: Self.looks[Self.event]!, field: nil, catalogue: Self.catalogue, calendar: Self.calendar())
        guard case .placed(let found) = placement else { Issue.record("The day is placed"); return }
        #expect(found.start == Self.day("2026-10-24"))
        #expect(found.end == Self.day("2026-10-25"), "one day, ending at the start of the next")
    }

    @Test func anEventOverSeveralDaysIsPlacedOnItsStartDay() throws {
        let run = Self.item("conference", [
            "starts_at": .string("2026-10-24"), "ends_at": .string("2026-10-27"), "all_day": .bool(true),
        ])
        let groups = Self.groups([run])
        #expect(groups.map(\.id) == [.day(Self.day("2026-10-24"))])
        let placement = ItemPlacement.of(run, look: Self.looks[Self.event]!, field: nil, catalogue: Self.catalogue, calendar: Self.calendar())
        guard case .placed(let found) = placement else { Issue.record("The run is placed"); return }
        #expect(found.start == Self.day("2026-10-24"))
        #expect(found.end == Self.day("2026-10-27"), "the day after its last day")
        let timed = Self.item("trip", [
            "starts_at": .string("2026-10-24T20:00:00-07:00"), "ends_at": .string("2026-10-26T09:00:00-07:00"),
        ])
        #expect(Self.groups([timed]).map(\.id) == [.day(Self.day("2026-10-24"))])
    }

    @Test func aTaskDueOnADayAloneHasNoTime() throws {
        let group = try #require(Self.groups([Self.item("due", type: Self.task, date: .string("2026-10-24"))]).first)
        #expect(group.id == .day(Self.day("2026-10-24")))
        guard case .dated(_, let dateOnly, _) = group.rows[0].value else { Issue.record("A due date places"); return }
        #expect(dateOnly)
    }

    @Test func aTypeWithNoDateInItsLookPlacesNothing() {
        let quiet = TypeID("example.quiet")
        let catalogue = Catalogue(itemTypes: [
            ItemTypeInfo(id: quiet, label: "Quiet", fields: [], titleField: nil, bodyField: nil, parent: nil),
        ])
        let item = Self.item("q", type: quiet)
        let off = ItemPlacement.of(item, look: .empty, field: nil, catalogue: catalogue)
        #expect(off == .missing)
        // A look that names a field the type does not have, and a task without a due date, say the same.
        let absent = TypeLook(date: .field("due_at"), secondary: [], facts: [])
        #expect(ItemPlacement.of(item, look: absent, field: nil, catalogue: catalogue) == .missing)
        #expect(Self.groups([Self.item("t", type: Self.task)]).map(\.id) == [.missing])
        // The look's own date still places it where it gives one.
        let made = TypeLook(date: .created, secondary: [], facts: [])
        guard case .placed = ItemPlacement.of(item, look: made, field: nil, catalogue: catalogue) else {
            Issue.record("A created date places the item")
            return
        }
    }

    @Test func anItemEditedTodayIsPlacedOnToday() throws {
        let now = Self.day("2026-10-24T11:15:00-07:00")
        let edited = Self.item("note", type: Self.note, modified: now)
        let group = try #require(Self.groups([edited], today: now).first)
        #expect(group.id == .day(Self.calendar().startOfDay(for: now)))
        #expect(group.rows.map(\.id.rawValue) == ["note"])
    }

    @Test func daysFromTodayComeFirstThenAnEarlierHeaderAndTheDaysBeforeLatestFirst() {
        let items = [
            Self.item("older", type: Self.task, date: .string("2026-10-20")),
            Self.item("yesterday", type: Self.task, date: .string("2026-10-23")),
            Self.item("next", type: Self.task, date: .string("2026-10-26")),
            Self.item("today", type: Self.task, date: .string("2026-10-24")),
            Self.item("undated", type: Self.task),
        ]
        let groups = Self.groups(items, today: Self.day("2026-10-24"))
        #expect(Self.ids(groups) == [["today"], ["next"], [], ["yesterday"], ["older"], ["undated"]])
        #expect(groups.map(\.id) == [
            .day(Self.day("2026-10-24")), .day(Self.day("2026-10-26")), .earlier,
            .day(Self.day("2026-10-23")), .day(Self.day("2026-10-20")), .missing,
        ])
    }

    @Test func theEarlierHeaderMarksOnlyATurnFromDaysAheadToDaysBefore() {
        let past = [Self.item("a", type: Self.task, date: .string("2026-10-20")), Self.item("b", type: Self.task, date: .string("2026-10-22"))]
        #expect(Self.groups(past, today: Self.day("2026-10-24")).map(\.id) == [.day(Self.day("2026-10-22")), .day(Self.day("2026-10-20"))])
        let ahead = [Self.item("c", type: Self.task, date: .string("2026-10-25"))]
        #expect(!Self.groups(ahead, today: Self.day("2026-10-24")).contains { $0.id == .earlier })
    }

    @Test func anAllDayLabelBelongsToAnEventAlone() throws {
        let items = [
            Self.item("holiday", ["starts_at": .string("2026-10-24"), "all_day": .bool(true)]),
            Self.item("due", type: Self.task, date: .string("2026-10-24")),
        ]
        let rows = try #require(Self.groups(items).first).rows
        #expect(Dictionary(uniqueKeysWithValues: rows.map { ($0.id.rawValue, $0.isEvent) }) == ["holiday": true, "due": false])
        for row in rows { guard case .dated(_, true, _) = row.value else { Issue.record("Both sit on a day alone"); return } }
    }

    @Test func anAllDayEventNamingNoZoneKeepsItsDayInAnyCalendarOfTheMac() throws {
        let item = Self.item("holiday", ["starts_at": .string("2026-10-24"), "all_day": .bool(true)])
        let look = Self.looks[Self.event]!
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var tokyoBuddhist = Calendar(identifier: .buddhist)
        tokyoBuddhist.timeZone = tokyo.timeZone
        for mac in [tokyo, buddhist, tokyoBuddhist] {
            guard case .placed(let found) = ItemPlacement.of(item, look: look, field: nil, catalogue: Self.catalogue, calendar: mac) else {
                Issue.record("The day is placed")
                return
            }
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = mac.timeZone
            let parts = gregorian.dateComponents([.year, .month, .day, .hour], from: found.start)
            #expect((parts.year, parts.month, parts.day, parts.hour) == (2026, 10, 24, 0))
            let after = gregorian.dateComponents([.month, .day], from: try #require(found.end))
            #expect((after.month, after.day) == (10, 25))
            #expect(!found.hasTime)
        }
    }

    @Test func theNowLineSitsBeforeTheNextTimedRow() throws {
        let items = [
            Self.item("holiday", ["starts_at": .string("2026-10-24"), "all_day": .bool(true)]),
            Self.item("morning", ["starts_at": .string("2026-10-24T09:00:00-07:00")]),
            Self.item("evening", ["starts_at": .string("2026-10-24T19:00:00-07:00")]),
        ]
        let now = Self.day("2026-10-24T12:00:00-07:00")
        let group = try #require(Self.groups(items, today: now).first)
        #expect(ItemTimelineLayout.nowLine(in: group, now: now, calendar: Self.calendar()) == 2)
        let late = Self.day("2026-10-24T21:00:00-07:00")
        #expect(ItemTimelineLayout.nowLine(in: group, now: late, calendar: Self.calendar()) == 3)
        #expect(ItemTimelineLayout.nowLine(in: group, now: Self.day("2026-10-25T08:00:00-07:00"), calendar: Self.calendar()) == nil)
    }

    @Test func aTimeHasNoSeconds() {
        let at = Self.day("2026-10-24T09:30:45-07:00")
        #expect(DateDisplay.timeOfDay(of: at, calendar: Self.calendar(), locale: Locale(identifier: "en_GB")) == "09:30")
        #expect(DateDisplay.timeOfDay(of: at, calendar: Self.calendar(), locale: Locale(identifier: "en_US")).contains("9:30"))
    }

    @Test func fieldsComeFromPresentTypesAndRespectKinds() {
        let notes = [Self.item("note", type: Self.note)]
        #expect(ItemTimelineLayout.fields(for: notes, catalogue: Self.catalogue).isEmpty)
        let fields = ItemTimelineLayout.fields(for: notes + [Self.item("event"), Self.item("task", type: Self.task)], catalogue: Self.catalogue)
        #expect(Set(fields.map(\.key)) == ["due_at", "starts_at", "published_at"])
        #expect(ItemTimelineLayout.selectedField(nil, fields: fields) == nil, "no choice leaves each type its own date")
        #expect(ItemTimelineLayout.selectedField("published_at", fields: fields) == "published_at")
        #expect(ItemTimelineLayout.selectedField("removed", fields: fields) == nil)
    }

    @Test func aDueDateOutsideATaskDoesNotLead() {
        let fields = ItemTimelineLayout.fields(for: [Self.item("event")], catalogue: Self.catalogue)
        #expect(fields.map(\.key) == ["starts_at", "due_at", "published_at"], "a start leads, then by label, with no task present")
    }

    @Test func orderingIsChronologicalThenTitleThenIdentity() {
        let items = [
            Self.item("z", title: "Same", date: .string("2026-10-24T12:00:00Z")),
            Self.item("a", title: "Same", date: .string("2026-10-24T12:00:00Z")),
            Self.item("title", title: "Earlier title", date: .string("2026-10-24T12:00:00Z")),
            Self.item("morning", date: .string("2026-10-24T10:00:00Z")),
            Self.item("previous", date: .string("2026-10-23")),
        ]
        let expected = ["morning", "title", "a", "z", "previous"]
        for input in [items, Array(items.reversed())] {
            let groups = Self.groups(input, field: "due_at", today: Self.day("2026-10-24"))
            #expect(groups.flatMap(\.rows).map(\.id.rawValue) == expected)
        }
    }
}
