import Foundation
import Testing
@testable import MarfaMac

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
    private static func card(
        _ item: Item, look: TypeLook, mixed: Bool = false, shape: CardShape = CardShape()
    ) -> RowContent {
        RowContent.card(
            for: item, look: look, catalogue: catalogue, list: RowList(mixesTypes: mixed, day: calendar.startOfDay(for: now)),
            shape: shape, calendar: calendar, locale: Locale(identifier: "en_GB"))
    }

    // MARK: Worked out once for each item

    @Test func aChangeOfSelectionOrOfAnotherItemLeavesACardsContentAsItWas() {
        let library = FakeItemLibrary()
        library.catalogue = Self.catalogue
        let first = Self.item("core.note", title: "First")
        let second = Self.item("core.note", title: "Second")
        let held = CardContents()
        let list = RowList(day: Self.calendar.startOfDay(for: Self.now))
        let before = held.contents(of: [first, second], in: library, looks: [:], list: list, shape: CardShape())
        var renamed = second
        renamed.title = "Renamed"
        renamed.name = "Renamed"
        let after = held.contents(of: [first, renamed], in: library, looks: [:], list: list, shape: CardShape())
        #expect(before[first.id] == after[first.id])
        #expect(before[second.id]?.title == "Second" && after[second.id]?.title == "Renamed")
        let gone = held.contents(of: [first], in: library, looks: [:], list: list, shape: CardShape())
        #expect(gone.keys.contains(second.id) == false)
    }

    @Test func aPassThatChangesNothingMakesNoCard() {
        let library = FakeItemLibrary()
        library.catalogue = Self.catalogue
        let items = [Self.item("core.note", title: "First"), Self.item("core.note", title: "Second")]
        let held = CardContents()
        let list = RowList(day: Self.calendar.startOfDay(for: Self.now))
        let first = held.contents(of: items, in: library, looks: [:], list: list, shape: CardShape())
        #expect(held.builds == 2)
        let again = held.contents(of: items, in: library, looks: [:], list: list, shape: CardShape())
        #expect(held.builds == 2 && again == first, "the same items, looks, list and shape build nothing")
        _ = held.contents(of: items, in: library, looks: [:], list: list, shape: CardShape(dropsOpening: true))
        #expect(held.builds == 4, "a different shape builds every card again")
    }

    @Test func aChangeOfLooksBuildsEveryCardAgainAndAnItemsEditBuildsOne() {
        let library = FakeItemLibrary()
        library.catalogue = Self.catalogue
        let note = Self.item("core.note", [Property(key: "language", value: .string("English"))])
        let other = Self.item("core.note", title: "Other")
        let held = CardContents()
        let list = RowList(day: Self.calendar.startOfDay(for: Self.now))
        let chosen = [TypeID("core.note"): TypeLook(date: .off, secondary: [.field("language")], facts: [])]
        let shown = held.contents(of: [note, other], in: library, looks: chosen, list: list, shape: CardShape())
        #expect(shown[note.id]?.secondary == "English" && held.builds == 2)
        let off = [TypeID("core.note"): TypeLook.empty]
        let hidden = held.contents(of: [note, other], in: library, looks: off, list: list, shape: CardShape())
        #expect(hidden[note.id]?.secondary == nil && held.builds == 4)
        var renamed = other
        renamed.title = "Renamed"
        renamed.name = "Renamed"
        _ = held.contents(of: [note, renamed], in: library, looks: off, list: list, shape: CardShape())
        #expect(held.builds == 5)
    }

    // MARK: Looks are resolved in one place

    @Test func theBrowserResolvesTheLooksOnceForTheChoicesAndEveryViewReadsThem() {
        let library = FakeItemLibrary()
        library.catalogue = Self.catalogue
        let browser = Browser()
        let note = TypeID("core.note")
        #expect(browser.looks(in: library) == Self.catalogue.looks(choices: [:]))
        browser.lookChoices = [note: TypeLookChoice(secondary: [.field("language")])]
        let resolved = browser.looks(in: library)
        #expect(resolved[note]?.secondary == [.field("language")])
        #expect(resolved == Self.catalogue.looks(choices: browser.lookChoices))
        #expect(browser.looks(in: library) == resolved, "held until the choices or the library's membership change")
        let item = Self.item("core.note", [Property(key: "language", value: .string("English"))])
        let list = RowList(day: Self.calendar.startOfDay(for: Self.now))
        let card = CardContents().contents(of: [item], in: library, looks: resolved, list: list, shape: CardShape())
        let row = RowContents().contents(of: [.init(item: item, showsTime: false)], in: library, looks: resolved, list: list)
        #expect(card[item.id]?.secondary == "English" && row[item.id]?.secondary == "English")
    }

    @Test func aRowsContentIsMadeAgainOnlyForAChangedLookOrItem() {
        let library = FakeItemLibrary()
        library.catalogue = Self.catalogue
        let item = Self.item("core.note", [Property(key: "language", value: .string("English"))])
        let entries = [RowContents.Entry(item: item, showsTime: false)]
        let held = RowContents()
        let list = RowList(day: Self.calendar.startOfDay(for: Self.now))
        let on = [TypeID("core.note"): TypeLook(date: .off, secondary: [.field("language")], facts: [])]
        _ = held.contents(of: entries, in: library, looks: on, list: list)
        _ = held.contents(of: entries, in: library, looks: on, list: list)
        #expect(held.builds == 1)
        #expect(held.contents(of: entries, in: library, looks: [:], list: list)[item.id]?.secondary == nil)
        #expect(held.builds == 2)
    }
}
