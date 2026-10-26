import Foundation
import Testing
@testable import MAPP

struct ItemTimelineTests {
    private static let event = TypeID("example.event")
    private static let note = TypeID("example.note")
    private static let catalogue = Catalogue(itemTypes: [
        ItemTypeInfo(id: event, label: "Event", fields: [
            .init(key: "starts_at", label: "Starts at", kind: .date(includesTime: true), declaredBy: event),
            .init(key: "due_at", label: "Due at", kind: .date(includesTime: true), declaredBy: event),
            .init(key: "published_at", label: "Published at", kind: .date(includesTime: true), declaredBy: event),
        ], titleField: nil, bodyField: nil, parent: nil),
        ItemTypeInfo(id: note, label: "Note", fields: [
            .init(key: "due_at", label: "Due at", kind: .text, declaredBy: note),
        ], titleField: nil, bodyField: nil, parent: nil),
    ])

    private static func calendar(_ zone: String = "America/Los_Angeles") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private static func item(
        _ id: String, title: String? = nil, type: TypeID = event, date: PropertyValue? = nil
    ) -> Item {
        Item(id: ItemID(id), type: type, title: title ?? id, titleRule: .property("title"),
             properties: date.map { [Property(key: "due_at", value: $0)] } ?? [],
             version: ItemVersion(1), created: .distantPast, modified: .distantPast)
    }

    @Test func timestampGroupsByItsLocalDayAndKeepsItsTime() throws {
        let calendar = Self.calendar()
        let raw = "2026-10-24T01:30:45.125Z"
        let groups = ItemTimelineLayout.groups(for: [Self.item("event", date: .string(raw))], field: "due_at", catalogue: Self.catalogue, calendar: calendar)
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
        #expect(ItemDate.parse("2026-10-24T03:30:45.125+02:00", calendar: calendar)?.date == instant)
    }

    @Test(arguments: [
        "2026-02-30", "2025-02-29", "2026-13-01", "2026-00-02", "2026-10-00", "2026-10-32",
        "2026-02-30T12:30:00Z", "2026-10-24T25:00:00Z", "2026-10-24T12:60:00Z",
        "2026-10-24T12:30:61Z", "2026-10-24T12:30:00+25:00", "2026-10-24T12:30:00+00:60",
        "2026-10-24T12:30:00", "tomorrow", "2026-1-01", " ",
    ])
    func invalidValuesRemainVisible(raw: String) {
        let item = Self.item("invalid", date: .string(raw))
        #expect(ItemTimelineLayout.value(of: item, field: "due_at", catalogue: Self.catalogue) == .invalid(raw))
        let groups = ItemTimelineLayout.groups(for: [item], field: "due_at", catalogue: Self.catalogue)
        #expect(groups.map(\.id) == [.invalid])
        #expect(groups.flatMap(\.rows).map(\.id) == [item.id])
    }

    @Test func missingInvalidAndNonApplicableStaySeparate() {
        let items = [
            Self.item("missing"), Self.item("null", date: .null), Self.item("empty", date: .string("")),
            Self.item("wrong-shape", date: .number(42)), Self.item("not-date-field", type: Self.note, date: .string("2026-10-24")),
        ]
        let groups = ItemTimelineLayout.groups(for: items, field: "due_at", catalogue: Self.catalogue)
        #expect(groups.map(\.id) == [.missing, .invalid, .notApplicable])
        #expect(groups[0].rows.count == 3)
        #expect(groups[1].rows.first?.value == .invalid("42"))
        #expect(groups[2].rows.first?.value == .notApplicable)
        #expect(Set(groups.flatMap(\.rows).map(\.id)) == Set(items.map(\.id)))
    }

    @Test func fieldsComeFromPresentTypesAndRespectKinds() {
        let notes = [Self.item("note", type: Self.note)]
        #expect(ItemTimelineLayout.fields(for: notes, catalogue: Self.catalogue).isEmpty)
        let fields = ItemTimelineLayout.fields(for: notes + [Self.item("event")], catalogue: Self.catalogue)
        #expect(Set(fields.map(\.key)) == ["due_at", "starts_at", "published_at"])
        #expect(ItemTimelineLayout.selectedField(nil, fields: fields) == "due_at")
        #expect(ItemTimelineLayout.selectedField("published_at", fields: fields) == "published_at")
        #expect(ItemTimelineLayout.selectedField("removed", fields: fields) == "due_at")
        #expect(ItemTimelineLayout.selectedField(nil, fields: fields.filter { $0.key != "due_at" }) == "starts_at")
    }

    @Test func noAvailableFieldStillShowsEveryItem() {
        let items = [Self.item("one", type: Self.note), Self.item("two", type: Self.note)]
        let groups = ItemTimelineLayout.groups(for: items, field: nil, catalogue: Self.catalogue)
        #expect(groups.map(\.id) == [.notApplicable])
        #expect(groups.flatMap(\.rows).count == 2)
        #expect(ItemTimelineLayout.groups(for: [], field: nil, catalogue: Self.catalogue).isEmpty)
    }

    @Test func orderingIsChronologicalThenTitleThenIdentity() {
        let items = [
            Self.item("z", title: "Same", date: .string("2026-10-24T12:00:00Z")),
            Self.item("a", title: "Same", date: .string("2026-10-24T12:00:00Z")),
            Self.item("title", title: "Earlier title", date: .string("2026-10-24T12:00:00Z")),
            Self.item("morning", date: .string("2026-10-24T10:00:00Z")),
            Self.item("previous", date: .string("2026-10-23")),
        ]
        let expected = ["previous", "morning", "title", "a", "z"]
        for input in [items, Array(items.reversed())] {
            let groups = ItemTimelineLayout.groups(for: input, field: "due_at", catalogue: Self.catalogue, calendar: Self.calendar())
            #expect(groups.flatMap(\.rows).map(\.id.rawValue) == expected)
        }
    }
}
