import Foundation
import struct Marfa.ItemDate
import Testing
@testable import MarfaMac

/// What a row says, from an item and the look of its type: the pure model under the row, with nothing drawn.
@MainActor
struct RowContentTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
    private static let locale = Locale(identifier: "en_GB")
    /// Friday 13 November 2026, mid-afternoon.
    private static let now = Date(timeIntervalSince1970: 1_794_000_000)
    private static let longAgo = now.addingTimeInterval(-86_400 * 90)

    private static let people = ItemTypeInfo.Field.Kind.list(ListShape(members: [
        ListShape.Member(key: "name", label: "Name", kind: .text(nil)),
        ListShape.Member(key: "email", label: "Email", kind: .text(.email)),
    ]))

    private static let catalogue: Catalogue = {
        var specs = LookFixture.specs.map { spec -> LookFixture.Spec in
            var spec = spec
            spec.fields = spec.fields.map { field in
                ["attendees", "assignees"].contains(field.key) ? LookFixture.field(field.key, people) : field
            }
            return spec
        }
        specs.append(LookFixture.make("test.bare"))
        specs.append(LookFixture.make("test.board", [
            LookFixture.field("location", label: "Location"), LookFixture.field("due", LookFixture.day, label: "Due"),
            LookFixture.field("archived", .boolean, label: "Archived"), LookFixture.field("size", .number, label: "Size"),
            LookFixture.field("kind", .choice(["a"]), label: "Kind"),
        ]))
        specs.append(LookFixture.make("test.ledger", [
            LookFixture.field("amount", .number), LookFixture.field("currency", format: .currency), LookFixture.field("fee", .number),
            LookFixture.field("category"),
        ]))
        return LookFixture.catalogue(specs)
    }()

    private static func item(
        _ type: String, title: String = "Title", _ properties: [Property] = [], modified: Date = longAgo, tags: Set<String> = [],
        preview: String = ""
    ) -> Item {
        var item = Item(
            id: .mint(), type: TypeID(type), title: title, name: title, titleRule: .firstLine, properties: properties, preview: preview,
            tags: tags, version: ItemVersion(1), created: modified, modified: modified)
        item.occurred = nil
        return item
    }

    private static func people(_ names: [String]) -> PropertyValue {
        .array(names.map { .object(["name": .string($0)]) })
    }

    private static func make(
        _ item: Item, look: TypeLook? = nil, mixed: Bool = false, date: RowDateSource = .look, showsTime: Bool = false
    ) -> RowContent {
        let look = look ?? LookFixture.look(item.type.rawValue, in: catalogue)
        let list = RowList(mixesTypes: mixed, date: date, day: calendar.startOfDay(for: now))
        return RowContent.make(
            for: item, look: look, catalogue: catalogue, list: list, showsTime: showsTime, calendar: calendar, locale: locale)
    }

    // MARK: The list

    @Test func contentIsWorkedOutOncePerItemValueAndRebuiltWhenTheItemChanges() {
        let note = Self.item("core.note", title: "First", modified: Self.now)
        let library = FakeItemLibrary(items: [note], now: Self.now)
        let contents = RowContents()
        let list = RowList(day: Self.calendar.startOfDay(for: Self.now))
        let entries = [RowContents.Entry(item: note, showsTime: false)]
        let first = contents.contents(of: entries, in: library, looks: [:], list: list)
        #expect(first[note.id]?.title == "First")
        var renamed = note
        renamed.name = "Second"
        let second = contents.contents(of: [RowContents.Entry(item: renamed, showsTime: false)], in: library, looks: [:], list: list)
        #expect(second[note.id]?.title == "Second")
        #expect(contents.contents(of: [], in: library, looks: [:], list: list).isEmpty)
    }

    @Test func anItemThatIsGoneIsLetGoAndOneThatStaysIsKept() {
        let kept = Self.item("core.note", title: "Kept", modified: Self.now)
        let gone = Self.item("core.note", title: "Gone", modified: Self.now)
        let library = FakeItemLibrary(items: [kept, gone], now: Self.now)
        let contents = RowContents()
        let list = RowList(day: Self.calendar.startOfDay(for: Self.now))
        let both = contents.contents(
            of: [kept, gone].map { RowContents.Entry(item: $0, showsTime: false) }, in: library, looks: [:], list: list)
        #expect(Set(both.keys) == [kept.id, gone.id])
        let one = contents.contents(of: [RowContents.Entry(item: kept, showsTime: false)], in: library, looks: [:], list: list)
        #expect(Set(one.keys) == [kept.id])
        #expect(one[kept.id] == both[kept.id])
        let again = contents.contents(of: [RowContents.Entry(item: kept, showsTime: true)], in: library, looks: [:], list: list)
        #expect(again[kept.id]?.title == "Kept")
    }
}
