import Foundation
import struct Marfa.ItemDate
import Testing
@testable import MAPP

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
    private static let yesterday = now.addingTimeInterval(-86_400)
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

    private static func listLabel(_ date: Date, hasTime: Bool = true) -> String {
        DateDisplay.text(
            of: date, hasTime: hasTime, place: hasTime ? .list : .table, format: .standard, now: now, calendar: calendar, locale: locale)
    }

    // MARK: What a row holds

    @Test func aVeryLongTitleIsKeptWhole() {
        let title = String(repeating: "A long title that goes on. ", count: 40)
        #expect(Self.make(Self.item("core.note", title: title)).title == title)
    }

    @Test func aTypeWithNoneOfItsPresetsFieldsHasATitleAndADateOnly() {
        let content = Self.make(Self.item("test.bare"))
        #expect(content.secondary == nil)
        #expect(content.chips.isEmpty)
        #expect(content.more == 0)
        #expect(content.date != nil)
    }

    @Test func anItemOfATypeWhoseLookHasNoDateShowsNone() {
        let person = Self.item("core.entity.person", [Property(key: "job_title", value: .string("Chef"))])
        let content = Self.make(person)
        #expect(content.date == nil)
        #expect(content.secondary == "Chef")
    }

    @Test func theTypeIsNamedOnlyWhereTheListMixesTypes() {
        let task = Self.item("core.task", [Property(key: "status", value: .string("todo"))])
        let single = Self.make(task)
        let mixed = Self.make(task, mixed: true)
        #expect(!single.chips.contains { if case .type = $0 { true } else { false } })
        #expect(!single.mixesTypes)
        guard case .type(_, let label)? = mixed.chips.first else { Issue.record("no type chip first"); return }
        #expect(label == "core.task")
        #expect(mixed.mixesTypes)
        guard case .status(_, let word)? = mixed.chips.dropFirst().first else { Issue.record("no status after the type"); return }
        #expect(word == "Todo")
    }

    @Test func aFactWithNoValueIsSkipped() {
        let task = Self.item("core.task", [Property(key: "assignees", value: Self.people(["Ada Lovelace"]))])
        let chips = Self.make(task).chips
        #expect(chips == [.person(initials: "AL", name: "Ada Lovelace")])
    }

    @Test func factsBeyondTwoAreCountedAndAListsFurtherValuesToo() {
        let ledger = Self.item("test.ledger", [
            Property(key: "amount", value: .number(12)), Property(key: "currency", value: .string("GBP")),
            Property(key: "fee", value: .number(1)),
        ])
        let content = Self.make(ledger)
        #expect(content.chips == [.text("amount 12"), .text("currency GBP")])
        #expect(content.more == 1)
        let meeting = Self.item("core.event", [Property(key: "attendees", value: Self.people(["Ada Lovelace", "Alan Turing", "Grace Hopper"]))])
        let people = Self.make(meeting)
        #expect(people.chips == [.person(initials: "AL", name: "Ada Lovelace")])
        #expect(people.more == 2)
    }

    @Test func aHiddenFactCountsEveryValueItHoldsIncludingWhatItLeavesOut() {
        let look = TypeLook(date: .off, secondary: [], facts: [.field("amount"), .field("currency"), .tags])
        let ledger = Self.item(
            "test.ledger", [Property(key: "amount", value: .number(12)), Property(key: "currency", value: .string("GBP"))],
            tags: ["a", "b", "c", "d", "e"])
        let content = Self.make(ledger, look: look)
        #expect(content.chips == [.text("amount 12"), .text("currency GBP")])
        #expect(content.more == 5)
    }

    @Test func aShownFactCountsWhatItLeavesOutOnceAndAHiddenOneCountsItsShownValuesToo() {
        let look = TypeLook(date: .off, secondary: [], facts: [.tags, .field("amount"), .field("fee")])
        let ledger = Self.item(
            "test.ledger", [Property(key: "amount", value: .number(12)), Property(key: "fee", value: .number(1))],
            tags: ["a", "b", "c", "d", "e"])
        let content = Self.make(ledger, look: look)
        #expect(content.chips == [.tag("a"), .tag("b"), .tag("c"), .text("amount 12")])
        #expect(content.more == 3)
    }

    // MARK: Plain facts

    @Test func aTextNumberOrDateFactShowsItsLabelThenItsValue() {
        let board = Self.item("test.board", [
            Property(key: "location", value: .string("1712")), Property(key: "due", value: .string("2026-11-14")),
            Property(key: "size", value: .number(40)),
        ])
        let due = ItemDate.parse("2026-11-14", calendar: Self.calendar)!.date
        func chips(_ key: String) -> [RowContent.Chip] {
            Self.make(board, look: TypeLook(date: .off, secondary: [], facts: [.field(key)])).chips
        }
        #expect(chips("location") == [.text("Location 1712")])
        #expect(chips("due") == [.text("Due \(Self.listLabel(due, hasTime: false))")])
        #expect(chips("size") == [.text("Size 40")])
    }

    @Test func aFlagShowsItsLabelOnlyWhenTrue() {
        func chips(_ flag: Bool?) -> [RowContent.Chip] {
            let properties = flag.map { [Property(key: "archived", value: .bool($0))] } ?? []
            let look = TypeLook(date: .off, secondary: [], facts: [.field("archived")])
            return Self.make(Self.item("test.board", properties), look: look).chips
        }
        #expect(chips(true) == [.text("Archived")])
        #expect(chips(false).isEmpty)
        #expect(chips(nil).isEmpty)
    }

    @Test func aChoiceStaysItsValueAlone() {
        let board = Self.item("test.board", [Property(key: "kind", value: .string("a"))])
        let chips = Self.make(board, look: TypeLook(date: .off, secondary: [], facts: [.field("kind")])).chips
        #expect(chips == [.option(label: "A", tone: OptionTone.tone(for: "A"))])
    }

    @Test func aFactWithNoValueLeavesNoLabelAlone() {
        let board = Self.item("test.board", [Property(key: "location", value: .string("  "))])
        #expect(Self.make(board, look: TypeLook(date: .off, secondary: [], facts: [.field("location"), .field("due")])).chips.isEmpty)
    }

    @Test func aTagsAndAPeopleFactStayValuesAlone() {
        let task = Self.item("core.task", [Property(key: "assignees", value: Self.people(["Ada Lovelace"]))], tags: ["a"])
        let chips = Self.make(task, look: TypeLook(date: .off, secondary: [], facts: [.field("assignees"), .tags])).chips
        #expect(chips == [.person(initials: "AL", name: "Ada Lovelace"), .tag("a")])
    }

    // MARK: A passage

    @Test func aHighlightsPassageIsItsOpeningLineWhereItsTextFieldIsNamed() {
        let highlight = Self.item("core.highlight", [Property(key: "start_location", value: .string("p. 12"))], preview: " A passage worth keeping \n")
        let content = Self.make(highlight)
        #expect(content.secondary == "A passage worth keeping")
        #expect(content.chips == [.text("start_location p. 12")])
    }

    @Test func aFactThatNamesTheTextFieldReadsTheOpeningLineAndOneWithNoTextHasNone() {
        let look = TypeLook(date: .off, secondary: [], facts: [.field("text")])
        let passage = Self.item("core.highlight", preview: "A passage worth keeping")
        #expect(Self.make(passage, look: look).chips == [.text("Text A passage worth keeping")])
        #expect(Self.make(Self.item("core.highlight"), look: look).chips.isEmpty)
        #expect(Self.make(Self.item("core.highlight"), look: TypeLook(date: .off, secondary: [.field("text")], facts: [])).secondary == nil)
    }

    @Test func aNotesTagsShowInSortedOrderWithTheRestCounted() {
        let note = Self.item("core.note", tags: ["d", "b", ItemTag.favorite, "a", "c"])
        let content = Self.make(note)
        #expect(content.chips == [.tag("a"), .tag("b"), .tag("c")])
        #expect(content.more == 1)
    }

    @Test func aNotesSecondaryLineIsItsOpeningLine() {
        let note = Self.item("core.note", preview: "  Opening words of the note \n")
        #expect(Self.make(note).secondary == "Opening words of the note")
    }

    // MARK: Date

    @Test func aListSortedByADateShowsThatDateAndOtherwiseTheLooksOwn() {
        let due = "2026-12-01"
        let task = Self.item("core.task", [Property(key: "due_at", value: .string(due))], modified: Self.longAgo)
        let looks = Self.make(task)
        #expect(looks.date == Self.listLabel(ItemDate.parse(due, calendar: Self.calendar)!.date, hasTime: false))
        #expect(Self.make(task, date: .edited).date == Self.listLabel(Self.longAgo))
        #expect(Self.make(task, date: .created).date == Self.listLabel(Self.longAgo))
        let field = Self.make(task, date: .field("starts_at"))
        #expect(field.date == nil)
    }

    @Test func theDateSourceFollowsTheFirstSortKeyThenTheGlobalOrder() throws {
        let starts = try #require(Self.catalogue.itemTypes[TypeID("core.event")]?.fields.first { $0.key == "starts_at" })
        let startsColumn = ItemTableColumn(id: "starts_at", label: "", content: .field(starts), style: .date)
        let nameColumn = ItemTableColumn(id: "name", label: "", content: .field(LookFixture.field("name")), style: .text)
        #expect(RowDateSource.of(sort: ItemTableComparator(column: startsColumn), order: NoteOrder(), ordersItself: false) == .field("starts_at"))
        #expect(RowDateSource.of(sort: ItemTableComparator(column: .created), order: NoteOrder(), ordersItself: false) == .created)
        #expect(RowDateSource.of(sort: ItemTableComparator(column: .edited), order: NoteOrder(), ordersItself: false) == .edited)
        #expect(RowDateSource.of(sort: ItemTableComparator(column: nameColumn), order: NoteOrder(), ordersItself: false) == .look)
        #expect(RowDateSource.of(sort: nil, order: NoteOrder(sort: .dateCreated), ordersItself: false) == .created)
        #expect(RowDateSource.of(sort: nil, order: NoteOrder(sort: .dateEdited), ordersItself: false) == .edited)
        #expect(RowDateSource.of(sort: nil, order: NoteOrder(sort: .title), ordersItself: false) == .look)
        #expect(RowDateSource.of(sort: nil, order: NoteOrder(sort: .dateEdited), ordersItself: true) == .look)
    }

    @Test func insideADaysGroupTheDateIsTheTimeAndElsewhereTheListsLabel() {
        let note = Self.item("core.note", modified: Self.yesterday)
        let time = DateDisplay.timeOfDay(of: Self.yesterday, calendar: Self.calendar, locale: Self.locale)
        #expect(Self.make(note, showsTime: true).date == time)
        #expect(Self.make(note, showsTime: false).date == Self.listLabel(Self.yesterday))
        #expect(Self.make(note, showsTime: false).date != time)
    }

    @Test func aDayToComeReadsAsADayAndNotAsATime() {
        let tomorrow = Self.now.addingTimeInterval(86_400)
        #expect(Self.listLabel(tomorrow) != DateDisplay.timeOfDay(of: tomorrow, calendar: Self.calendar, locale: Self.locale))
    }

    // MARK: Event

    @Test func anEventReadsItsTimeOfDayThenItsPlaceUnderItsDay() {
        let event = Self.item("core.event", [
            Property(key: "starts_at", value: .string("2026-11-20T19:30:00Z")), Property(key: "place", value: .string("Brat")),
        ])
        let start = ItemDate.parse("2026-11-20T19:30:00Z", calendar: Self.calendar)!.date
        let time = DateDisplay.timeOfDay(of: start, calendar: Self.calendar, locale: Self.locale)
        #expect(Self.make(event).secondary == "\(time), Brat")
    }

    @Test func anAllDayEventHasNoTimeOfDay() {
        let event = Self.item("core.event", [
            Property(key: "starts_at", value: .string("2026-11-20")), Property(key: "place", value: .string("Brat")),
        ])
        #expect(Self.make(event).secondary == "Brat")
    }

    // MARK: The list

    @Test func aListMixesTypesOnlyWhereItsItemsDo() {
        let note = FakeItemLibrary.note("Note", modified: Self.now)
        let other = FakeItemLibrary.note("Other", modified: Self.now)
        let task = Self.item("core.task", modified: Self.now)
        let library = FakeItemLibrary(items: [note, other, task], now: Self.now)
        let browser = Browser()
        browser.show(.allNotes, in: library, order: NoteOrder())
        #expect(browser.rowList(of: [note, task], in: library, order: NoteOrder(), now: Self.now, format: .standard).mixesTypes)
        #expect(!browser.rowList(of: [note, other], in: library, order: NoteOrder(), now: Self.now, format: .standard).mixesTypes)
        #expect(!browser.rowList(of: [], in: library, order: NoteOrder(), now: Self.now, format: .standard).mixesTypes)
    }

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
