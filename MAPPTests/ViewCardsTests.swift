import Foundation
import Testing
@testable import MAPP

/// What a gallery's card settings hold, how they read back, and which chips a card gets from an item.
@MainActor
struct ViewCardsTests {
    // MARK: The settings

    @Test func theDefaultsAreTheCardAsItHasAlwaysBeen() {
        let cards = ViewCards()
        #expect(cards.preview == .pictureOrText)
        #expect(!cards.fitsPicture)
        #expect(cards.size == .medium)
        #expect(cards.subtext == .typeAndDate)
        #expect(cards.properties.isEmpty)
        #expect(ViewMacSettings().cards == cards)
    }

    @Test func aSizeSetsHowWideACardIs() {
        let widths = ViewCards.Size.allCases.map(\.columnWidth)
        #expect(widths == widths.sorted())
        #expect(Set(widths).count == widths.count)
    }

    @Test func settingsRoundTripThroughTheStoredText() throws {
        var cards = ViewCards(preview: .text, fitsPicture: true, size: .large, subtext: .date)
        cards.setShown("field.status", true)
        cards.setShown("tags", true)
        let settings = ViewMacSettings(cards: cards)
        let layouts = ViewLayouts(["view": settings])
        let read = try #require(ViewLayouts(rawValue: layouts.rawValue))
        #expect(read.views["view"]?.cards == cards)
    }

    @Test func aChoiceThisVersionDoesNotKnowNeverVoidsTheRest() throws {
        let text = #"{"preview":"hologram","size":"large","fitsPicture":"yes","properties":["tags"]}"#
        let cards = try JSONDecoder().decode(ViewCards.self, from: Data(text.utf8))
        #expect(cards.preview == .pictureOrText)
        #expect(cards.size == .large)
        #expect(!cards.fitsPicture)
        #expect(cards.properties == ["tags"])
    }

    @Test func settingsStoredBeforeCardsExistOpenWithTheDefaults() throws {
        let settings = try JSONDecoder().decode(ViewMacSettings.self, from: Data(#"{"layout":"gallery"}"#.utf8))
        #expect(settings.cards == ViewCards())
    }

    @Test func choicesThatDifferInCardsAreDifferentChoices() {
        var other = ViewMacSettings()
        other.cards.size = .small
        #expect(!ViewMacSettings().sameChoices(as: other))
        var taken = ViewMacSettings(widths: Data([1]))
        taken.take(choicesOf: other)
        #expect(taken.cards.size == .small)
        #expect(taken.widths == Data([1]))
    }

    @Test func aPropertyShowsOnceAndAfterTheOthers() {
        var cards = ViewCards()
        cards.setShown("a", true)
        cards.setShown("b", true)
        cards.setShown("a", true)
        #expect(cards.properties == ["a", "b"])
        #expect(cards.shows("a"))
        cards.setShown("a", false)
        #expect(cards.properties == ["b"])
        #expect(!cards.shows("a"))
    }

    @Test func aPropertyMovesBeforeAnotherOrLast() {
        var cards = ViewCards(properties: ["a", "b", "c"])
        cards.move("c", before: "a")
        #expect(cards.properties == ["c", "a", "b"])
        cards.move("c", before: nil)
        #expect(cards.properties == ["a", "b", "c"])
        cards.move("z", before: "a")
        cards.move("a", before: "a")
        #expect(cards.properties == ["a", "b", "c"])
    }

    // MARK: The properties on offer

    private static let task = TypeID("core.task")

    private static func item(
        _ title: String, type: TypeID = task, properties: [Property] = [], tags: Set<String> = [], parent: ItemID? = nil
    ) -> Item {
        let edges = parent.map {
            [Edge(id: EdgeID("child-\(title)"), type: "child-of", source: ItemID(title), target: .item($0), origin: .body)]
        } ?? []
        return Item(
            id: ItemID(title), type: type, title: title, name: title, titleRule: .property("title"),
            properties: [Property(key: "title", value: .string(title))] + properties, tags: tags,
            version: ItemVersion(1), created: .now, modified: .now, edgesOut: edges)
    }

    private static func row(_ item: Item) -> ItemTableRow {
        ItemTableRow(item: item, typeLabel: "Task", typeIcon: nil, parent: nil)
    }

    private static func offered(_ items: [Item]) -> [GalleryProperty] {
        let rows = items.map(row)
        let columns = ItemTableLayout.columns(for: rows, catalogue: FakeItemLibrary.testCatalogue, hidden: [])
        return GalleryProperty.offered(columns: columns, rows: rows)
    }

    @Test func aPlaceOffersItsColumnsExceptTheNameAndTheType() {
        let ids = Self.offered([Self.item("A", properties: [Property(key: "status", value: .string("todo"))])]).map(\.id)
        #expect(ids.contains("field.status"))
        #expect(!ids.contains("title"))
        #expect(!ids.contains("type"))
    }

    @Test func tagsAreOfferedOnlyWhereAnItemHoldsOne() {
        #expect(!Self.offered([Self.item("A")]).map(\.id).contains(GalleryProperty.tagsID))
        #expect(!Self.offered([Self.item("A", tags: [ItemTag.favorite])]).map(\.id).contains(GalleryProperty.tagsID))
        #expect(Self.offered([Self.item("A", tags: ["work"])]).map(\.id).contains(GalleryProperty.tagsID))
    }

    // MARK: The chips

    private static func chips(_ property: String, of item: Item, in library: FakeItemLibrary = FakeItemLibrary()) -> [GalleryChip] {
        GalleryChip.chips(for: property, of: item, in: library, format: .automatic, now: .now)
    }

    @Test func aTagIsATagChipAndTheFavoriteMarkIsNone() {
        let item = Self.item("A", tags: ["work", ItemTag.favorite, "home"])
        let chips = Self.chips(GalleryProperty.tagsID, of: item)
        #expect(chips.map(\.text) == ["home", "work"])
        #expect(chips.allSatisfy { $0.look == .tag })
    }

    @Test func aChoiceIsAnOptionChipWithItsOwnWords() {
        let item = Self.item("A", properties: [Property(key: "priority", value: .string("high"))])
        let chips = Self.chips("field.priority", of: item)
        #expect(chips == [GalleryChip(text: ItemTypeInfo.Field.label(ofOption: "high"), look: .option)])
    }

    @Test func aTextValueIsAPlainChip() {
        let item = Self.item("A", properties: [Property(key: "assignee", value: .string("Sam"))])
        #expect(Self.chips("field.assignee", of: item) == [GalleryChip(text: "Sam", look: .plain)])
    }

    @Test func aPropertyTheItemDoesNotHoldDrawsNothing() {
        let item = Self.item("A")
        #expect(Self.chips("field.priority", of: item).isEmpty)
        #expect(Self.chips(GalleryProperty.tagsID, of: item).isEmpty)
        #expect(Self.chips("parent", of: item).isEmpty)
    }

    @Test func aPropertyTheItemsTypeDoesNotHaveDrawsNothing() {
        let note = Self.item("A", type: TypeID("core.note"), properties: [Property(key: "priority", value: .string("high"))])
        #expect(Self.chips("field.priority", of: note).isEmpty)
        #expect(Self.chips("field.nothing-like-it", of: note).isEmpty)
        #expect(Self.chips("something else", of: note).isEmpty)
    }

    @Test func aValueThatIsOnlySpaceIsNoChip() {
        let item = Self.item("A", properties: [Property(key: "assignee", value: .string("   "))])
        #expect(Self.chips("field.assignee", of: item).isEmpty)
    }

    @Test func aParentIsALinkChipWithItsTitle() {
        let parent = Self.item("Parent", type: FakeItemLibrary.collectionType)
        let child = Self.item("Child", parent: parent.id)
        let library = FakeItemLibrary(items: [parent, child])
        let chips = Self.chips("parent", of: child, in: library)
        #expect(chips.map(\.text) == ["Parent"])
    }

    @Test func theDatesAreChipsAndNeverEmpty() {
        let item = Self.item("A")
        #expect(Self.chips("created", of: item).count == 1)
        #expect(Self.chips("edited", of: item).count == 1)
        #expect(Self.chips("duration", of: item).isEmpty)
    }
}
