import Foundation
import Testing
@testable import MAPP

/// What a gallery card or a board card says, from an item and the look of its type: the pure model under the cards.
@MainActor
struct CardContentsTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
    private static let now = Date(timeIntervalSince1970: 1_794_000_000)
    private static let catalogue = LookFixture.catalogue()

    private static func item(
        _ type: String, title: String = "Title", _ properties: [Property] = [], preview: String = "", tags: Set<String> = []
    ) -> Item {
        Item(
            id: .mint(), type: TypeID(type), title: title, name: title, titleRule: .firstLine, properties: properties,
            preview: preview, tags: tags, version: ItemVersion(1), created: now, modified: now)
    }

    private static let task = item("core.task", [Property(key: "status", value: .string("todo")), Property(key: "priority", value: .string("high"))])
    private static let taskLook = TypeLook(date: .edited, secondary: [], facts: [.field("priority")])

    private static func card(
        _ item: Item, look: TypeLook, mixed: Bool = false, shape: CardShape = CardShape()
    ) -> RowContent {
        RowContent.card(
            for: item, look: look, catalogue: catalogue, list: RowList(mixesTypes: mixed, day: calendar.startOfDay(for: now)),
            shape: shape, calendar: calendar, locale: Locale(identifier: "en_GB"))
    }

    private static func statuses(_ content: RowContent) -> Int {
        content.chips.filter { if case .status = $0 { true } else { false } }.count
    }

    private static func options(_ content: RowContent) -> Int {
        content.chips.filter { if case .option = $0 { true } else { false } }.count
    }

    // MARK: A board's lanes say the field it is grouped by

    @Test func aCardSaysItsStatusAndItsFactsAndNoDate() {
        let content = Self.card(Self.task, look: Self.taskLook)
        #expect(Self.statuses(content) == 1 && Self.options(content) == 1)
        #expect(content.date == nil, "a card never says a date")
    }

    @Test func aBoardGroupedByStatusLeavesTheStatusOffEveryCard() {
        let content = Self.card(Self.task, look: Self.taskLook, shape: CardShape(leaving: "status", groupsByStatus: true))
        #expect(Self.statuses(content) == 0)
        #expect(Self.options(content) == 1, "the other facts stay")
    }

    @Test func aBoardGroupedByStatusGroupsLeavesTheStatusOffWhicheverFieldHoldsIt() {
        // The lanes are the status groups of every type, so a type whose status field has another key loses its status too.
        let content = Self.card(Self.task, look: Self.taskLook, shape: CardShape(leaving: "state", groupsByStatus: true))
        #expect(Self.statuses(content) == 0)
    }

    @Test func aBoardGroupedByPriorityLeavesPriorityOffAndKeepsTheStatus() {
        let content = Self.card(Self.task, look: Self.taskLook, shape: CardShape(leaving: "priority"))
        #expect(Self.options(content) == 0)
        #expect(Self.statuses(content) == 1)
    }

    @Test func aFieldTheBoardIsGroupedByLeavesTheSecondaryLineToo() {
        let look = TypeLook(date: .off, secondary: [.field("language"), .field("title")], facts: [])
        let note = Self.item("core.note", [Property(key: "language", value: .string("English"))])
        #expect(Self.card(note, look: look).secondary?.contains("English") == true)
        #expect(Self.card(note, look: look, shape: CardShape(leaving: "language")).secondary?.contains("English") != true)
    }

    // MARK: A mixed board

    @Test func aMixedBoardNamesEachCardsType() throws {
        let mixed = Self.card(Self.task, look: Self.taskLook, mixed: true)
        guard case .type(_, let label)? = mixed.chips.first else { Issue.record("the type comes first"); return }
        #expect(label == Self.catalogue.label(for: Self.task.type))
        #expect(mixed.mixesTypes)
        let alone = Self.card(Self.task, look: Self.taskLook)
        #expect(!alone.chips.contains { if case .type = $0 { true } else { false } })
    }

    @Test func eachTypeInAMixedBoardUsesItsOwnLook() {
        let note = Self.item("core.note", [Property(key: "language", value: .string("English"))])
        let noteLook = TypeLook(date: .off, secondary: [.field("language")], facts: [])
        let task = Self.card(Self.task, look: Self.taskLook, mixed: true)
        let other = Self.card(note, look: noteLook, mixed: true)
        #expect(task.secondary == nil && other.secondary == "English")
        #expect(Self.options(task) == 1 && Self.options(other) == 0)
    }

    // MARK: What a card is left with

    @Test func aTypeWithNoneOfItsPresetsFieldsHasItsTitleAndNothingElse() {
        let bare = Self.item("test.bare", title: "Bare")
        let look = TypeLook(date: .field("due_at"), secondary: [.field("language"), .time("starts_at")], facts: [.field("priority"), .tags])
        let content = Self.card(bare, look: look)
        #expect(content.title == "Bare")
        #expect(content.secondary == nil)
        #expect(content.chips.isEmpty && content.more == 0)
    }

    @Test func anItemWithNoTextHasNoSecondaryLine() {
        let look = TypeLook(date: .off, secondary: [.opening], facts: [])
        #expect(Self.card(Self.item("core.note", preview: ""), look: look).secondary == nil)
        #expect(Self.card(Self.item("core.note", preview: "The opening line"), look: look).secondary == "The opening line")
    }

    @Test func aPictureAreaThatShowsTheOpeningLinesLeavesThemOutOfTheLineUnderTheTitle() {
        let look = TypeLook(date: .off, secondary: [.opening, .field("language")], facts: [])
        let note = Self.item("core.note", [Property(key: "language", value: .string("English"))], preview: "The opening line")
        #expect(look.shaped(by: CardShape(dropsOpening: true)).secondary == [.field("language")])
        #expect(Self.card(note, look: look, shape: CardShape(dropsOpening: true)).secondary == "English")
        #expect(look.shaped(by: CardShape()) == look)
    }

    @Test func aVeryLongTitleIsKeptWholeForTheViewToTruncate() {
        let title = String(repeating: "a very long title ", count: 300)
        #expect(Self.card(Self.item("core.note", title: title), look: .empty).title == Self.item("core.note", title: title).displayTitle)
    }

    // MARK: Worked out once for each item

    @Test func aChangeOfSelectionOrOfAnotherItemLeavesACardsContentAsItWas() {
        let library = FakeItemLibrary()
        library.catalogue = Self.catalogue
        let first = Self.item("core.note", title: "First")
        let second = Self.item("core.note", title: "Second")
        let held = CardContents()
        let list = RowList(day: Self.calendar.startOfDay(for: Self.now))
        let before = held.contents(of: [first, second], in: library, choices: [:], list: list, shape: CardShape())
        var renamed = second
        renamed.title = "Renamed"
        renamed.name = "Renamed"
        let after = held.contents(of: [first, renamed], in: library, choices: [:], list: list, shape: CardShape())
        #expect(before[first.id] == after[first.id])
        #expect(before[second.id]?.title == "Second" && after[second.id]?.title == "Renamed")
        let gone = held.contents(of: [first], in: library, choices: [:], list: list, shape: CardShape())
        #expect(gone.keys.contains(second.id) == false)
    }

    @Test func aChoiceOfLookIsReadAtOnceByEveryCard() {
        let library = FakeItemLibrary()
        library.catalogue = Self.catalogue
        let note = Self.item("core.note", [Property(key: "language", value: .string("English"))])
        let held = CardContents()
        let list = RowList(day: Self.calendar.startOfDay(for: Self.now))
        let chosen: [TypeID: TypeLookChoice] = [TypeID("core.note"): TypeLookChoice(secondary: [.field("language")])]
        #expect(held.contents(of: [note], in: library, choices: chosen, list: list, shape: CardShape())[note.id]?.secondary == "English")
        let off: [TypeID: TypeLookChoice] = [TypeID("core.note"): TypeLookChoice(secondary: [])]
        #expect(held.contents(of: [note], in: library, choices: off, list: list, shape: CardShape())[note.id]?.secondary == nil)
    }
}
