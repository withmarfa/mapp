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
}
