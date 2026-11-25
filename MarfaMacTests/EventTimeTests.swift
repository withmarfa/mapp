import Foundation
import Testing
@testable import MarfaMac

/// An event's time is written whole and only where the person changed it: a start, an end, All Day and the zone in one edit,
/// and a time they did not touch is never written over (marfa-mac#562).
@MainActor
@Suite(.hangLimit)
struct EventTimeTests {
    private static let event = TypeID("core.event")
    private static let fields: [ItemTypeInfo.Field] = [
        .init(key: "starts_at", label: "Starts", kind: .date(includesTime: true), declaredBy: event),
        .init(key: "ends_at", label: "Ends", kind: .date(includesTime: true), declaredBy: event),
        .init(key: "all_day", label: "All Day", kind: .boolean, declaredBy: event),
        .init(key: "timezone", label: "Time Zone", kind: .text, declaredBy: event),
    ]
    private static let catalogue = Catalogue(itemTypes: [
        ItemTypeInfo(id: event, label: "Event", fields: fields, titleField: "title", bodyField: "body", parent: nil)
    ])
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func item(_ properties: [String: PropertyValue]) -> Item {
        Item(
            id: ItemID("10000000-0000-0000-0000-000000000001"), type: event, title: "Call", titleRule: .property("title"),
            properties: properties.map { Property(key: $0, value: $1) }, version: ItemVersion(1), created: .now, modified: .now)
    }

    private static let timed: [String: PropertyValue] = [
        "starts_at": .string("2026-11-26T10:00:00Z"), "ends_at": .string("2026-11-26T10:30:00Z"), "timezone": .string("UTC"),
    ]

    private static func panel(_ properties: [String: PropertyValue]) -> (EventTimePanelModel, FakeItemLibrary) {
        let item = item(properties)
        let library = FakeItemLibrary(items: [item])
        library.catalogue = catalogue
        let spec = EventTime.of(event, in: catalogue)!
        return (EventTimePanelModel(spec: spec, item: item.id, library: library, undoManager: nil, calendar: utc), library)
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func movingTheStartKeepsTheLengthAndWritesOnlyTheStartAndTheEnd() {
        let (model, library) = Self.panel(Self.timed)
        model.part = .start
        model.choose(day: Self.day(2026, 11, 28))
        #expect(library.propertiesSet.count == 1)
        #expect(library.propertiesSet.first?.1.keys.sorted() == ["ends_at", "starts_at"])
        #expect(library.item(library.items[0].id)?.value(of: "starts_at") == .string("2026-11-28T10:00:00.000Z"))
        #expect(library.item(library.items[0].id)?.value(of: "ends_at") == .string("2026-11-28T10:30:00.000Z"))
    }

    @Test func aTimeThePersonDidNotChangeIsNotWritten() {
        let held = Self.timed.merging(["starts_at": .string("2026-11-26T10:00:00+00:00")]) { _, new in new }
        let (model, library) = Self.panel(held)
        model.part = .end
        model.beginTyping(in: .end)
        model.type("11:15", into: .end)
        model.commitTime(of: .end)
        #expect(library.propertiesSet.count == 1)
        #expect(library.propertiesSet.first?.1.keys.sorted() == ["ends_at"])
        // The start came back untouched, in the form the item held it.
        #expect(library.items[0].value(of: "starts_at") == .string("2026-11-26T10:00:00+00:00"))
        // The same day again changes nothing.
        model.part = .end
        model.choose(day: Self.day(2026, 11, 26))
        #expect(library.propertiesSet.count == 1)
    }

    @Test func anEndBeforeTheStartIsRefusedWithOneLineAndNothingIsWritten() {
        let (model, library) = Self.panel(Self.timed)
        model.part = .end
        model.choose(day: Self.day(2026, 11, 25))
        #expect(library.propertiesSet.isEmpty)
        #expect(model.notice != nil)
    }

    @Test func allDayIsOneEditOfTheFlagTheStartAndTheEndAsTheDayThatClosesTheLastDay() {
        let (model, library) = Self.panel(Self.timed)
        model.setAllDay(true)
        #expect(library.propertiesSet.count == 1)
        #expect(library.propertiesSet.first?.1.keys.sorted() == ["all_day", "ends_at", "starts_at"])
        #expect(library.items[0].value(of: "all_day") == .bool(true))
        #expect(library.items[0].value(of: "starts_at") == .string("2026-11-26"))
        #expect(library.items[0].value(of: "ends_at") == .string("2026-11-27"))
        #expect(model.reading.allDay)
    }

    @Test func aTimeTypedAgainstATimeThatChangedMeanwhileIsGivenBackNotWritten() {
        let (model, library) = Self.panel(Self.timed)
        model.beginTyping(in: .end)
        model.type("11:00", into: .end)
        // Another device moves the end while the person is typing.
        library.items[0].properties.removeAll { $0.key == "ends_at" }
        library.items[0].properties.append(Property(key: "ends_at", value: .string("2026-11-26T12:00:00Z")))
        model.commitTime(of: .end)
        #expect(library.propertiesSet.isEmpty)
        #expect(library.notices.waiting.first?.text == "Time: 11:00")
    }

    @Test func notSetTakesOnlyTheStartAndTheEndAway() {
        let (model, library) = Self.panel(Self.timed)
        model.clear()
        #expect(library.propertiesSet.first?.1.keys.sorted() == ["ends_at", "starts_at"])
        #expect(library.items[0].value(of: "timezone") == .string("UTC"))
    }

    @Test func movingTheDayKeepsTheSecondsAndTheLength() {
        let (model, library) = Self.panel(["starts_at": .string("2026-11-26T16:00:37Z"), "ends_at": .string("2026-11-26T16:30:37Z"), "timezone": .string("UTC")])
        model.part = .start
        model.choose(day: Self.day(2026, 11, 28))
        #expect(library.items[0].value(of: "starts_at") == .string("2026-11-28T16:00:37.000Z"))
        #expect(library.items[0].value(of: "ends_at") == .string("2026-11-28T16:30:37.000Z"))
    }

    private static let gap: [String: PropertyValue] = [
        "starts_at": .string("2026-03-08T15:00:00Z"), "ends_at": .string("2026-03-08T16:00:00Z"), "timezone": .string("America/New_York"),
    ]

    @Test func aTimeThatIsNotOnThatDaysClockIsRefusedAndKeptWithItsReason() {
        let (model, library) = Self.panel(Self.gap)
        model.beginTyping(in: .start)
        model.type("02:30", into: .start)
        model.commitTime(of: .start)
        #expect(library.propertiesSet.isEmpty)
        #expect(model.shownTime(of: .start) == "02:30")
        #expect(model.notice == EventTime.Refusal.noSuchTime.message)
        // The panel closing hands the input back with the same reason.
        model.finish(cancelled: false)
        #expect(library.propertiesSet.isEmpty)
        #expect(library.notices.waiting.first?.text == "Time: 02:30")
        #expect(library.notices.waiting.first?.message.contains(EventTime.Refusal.noSuchTime.message) == true)
    }

    @Test func aTimeTypedAgainstAnotherDateOrZoneIsGivenBackNotWritten() {
        let (model, library) = Self.panel(Self.timed)
        model.beginTyping(in: .end)
        model.type("11:00", into: .end)
        // Another device moves the end to the next day, at the same clock time.
        library.items[0].properties.removeAll { $0.key == "ends_at" }
        library.items[0].properties.append(Property(key: "ends_at", value: .string("2026-11-27T10:30:00Z")))
        model.commitTime(of: .end)
        #expect(library.propertiesSet.isEmpty)
        #expect(library.notices.waiting.first?.text == "Time: 11:00")
    }

    @Test func anEndBeforeTheStartKeepsWhatWasTypedUntilTheWriteIsTaken() {
        let (model, library) = Self.panel(Self.timed)
        model.beginTyping(in: .end)
        model.type("09:00", into: .end)
        model.commitTime(of: .end)
        #expect(library.propertiesSet.isEmpty)
        #expect(model.shownTime(of: .end) == "09:00")
        #expect(model.notice == EventTime.Refusal.endBeforeStart.message)
        // Closing with it refused gives the text back.
        model.finish(cancelled: false)
        #expect(library.notices.waiting.first?.text == "Time: 09:00")
        #expect(model.typed[.end] == nil)
    }

    @Test func aZoneChangeLeavesAStoredEndEarlierThanTheStartAsItIs() {
        let held: [String: PropertyValue] = ["starts_at": .string("2026-11-26T10:00:00Z"), "ends_at": .string("2026-11-26T09:00:00Z"), "timezone": .string("UTC")]
        let (model, library) = Self.panel(held)
        model.setZone(TimeZone(identifier: "America/New_York"))
        #expect(library.propertiesSet.first?.1.keys.sorted() == ["timezone"])
        #expect(library.items[0].value(of: "ends_at") == .string("2026-11-26T09:00:00Z"))
    }

    @Test func aDayTypedAtTheTopMovesTheChosenPartAndAnUntidyOneStaysWithItsReason() {
        let (model, library) = Self.panel(Self.timed)
        model.part = .start
        model.beginDay()
        model.typeDay("28 Nov 2026")
        model.commitDay()
        #expect(library.items[0].value(of: "starts_at") == .string("2026-11-28T10:00:00.000Z"))
        #expect(library.items[0].value(of: "ends_at") == .string("2026-11-28T10:30:00.000Z"))
        #expect(model.dayInput == nil)

        model.typeDay("whenever")
        model.commitDay()
        #expect(library.propertiesSet.count == 1 && model.shownDay == "whenever" && model.notice != nil)
        model.finish(cancelled: false)
        #expect(library.notices.waiting.first?.text == "Date: whenever")
    }

    @Test func aDayClickWhoseWriteIsRefusedLeavesTheTypedDayAndSaysWhy() {
        let (model, library) = Self.panel(Self.timed)
        model.part = .start
        model.beginDay()
        model.typeDay("whenever")
        model.commitDay()
        #expect(model.shownDay == "whenever" && model.notice != nil)

        library.acceptsProperties = false
        model.choose(day: Self.day(2026, 11, 28))
        #expect(model.shownDay == "whenever")
        #expect(model.notice != nil)

        library.acceptsProperties = true
        model.choose(day: Self.day(2026, 11, 28))
        #expect(model.dayInput == nil && model.notice == nil)
        #expect(library.items[0].value(of: "starts_at") == .string("2026-11-28T10:00:00.000Z"))
    }

    @Test func aRefusedAllDayKeepsATypedTime() {
        let (model, library) = Self.panel(Self.timed)
        model.beginTyping(in: .end)
        model.type("11:00", into: .end)
        library.acceptsProperties = false
        model.setAllDay(true)
        #expect(model.shownTime(of: .end) == "11:00")
    }

    @Test func movingTheDayKeepsFractionsOfASecond() {
        let (model, library) = Self.panel(["starts_at": .string("2026-11-26T16:00:37.123Z"), "ends_at": .string("2026-11-26T16:30:37.123Z"), "timezone": .string("UTC")])
        model.part = .start
        model.choose(day: Self.day(2026, 11, 28))
        #expect(library.items[0].value(of: "starts_at") == .string("2026-11-28T16:00:37.123Z"))
    }

    @Test func theWhenRowOfAnEditableEventOpensTheEventTimeAndAReadOnlyOneDoesNot() throws {
        var item = Self.item(Self.timed)
        let library = FakeItemLibrary(items: [item])
        library.catalogue = Self.catalogue
        let row = try #require(PageHead(of: item, in: library).rows.first { $0.id == EventTime.rowID })
        #expect(row.editable, "the page opens the event time only for a row marked editable")
        #expect(EventTime.of(item.type, in: Self.catalogue) != nil)

        item.readOnly = true
        library.items = [item]
        let locked = try #require(PageHead(of: item, in: library).rows.first { $0.id == EventTime.rowID })
        #expect(!locked.editable)
    }
}
