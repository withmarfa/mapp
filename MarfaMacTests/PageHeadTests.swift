import Foundation
import Marfa
import Testing
@testable import MarfaMac

/// What an item's head shows: which rows show before Show More, the pins, an event's When, and the kicker.
struct PageHeadTests {
    private static func field(_ name: String, _ type: String = "string", definition: JSONObject = [:]) -> TypeField {
        TypeField(name: name, type: type, declaredBy: "aic.ticket", definition: definition)
    }

    private static let ticket = MarfaMapping.itemType(ItemType(
        id: "aic.ticket", label: "Ticket",
        fields: [
            field("title"), field("body"),
            field("state", "status", definition: ["status_values": [["value": "pending", "group": "not_started"], ["value": "in_progress", "group": "in_progress"]]]),
            field("priority", "enum", definition: ["enum_values": ["low", "high"]]),
            field("a"), field("b"), field("c"), field("d"), field("e"), field("f"), field("summary"), field("done", "boolean"),
        ],
        titleField: "title", bodyField: "body"))

    /// A type that keeps no text.
    private static let contact = MarfaMapping.itemType(ItemType(
        id: "aic.contact", label: "Contact",
        fields: [field("title"), field("a"), field("b"), field("c"), field("d"), field("e"), field("f"), field("g")],
        titleField: "title"))

    private static let kicker = PageHead.Kicker(typeName: "Ticket", typeIcon: nil, changesType: true, flags: [])

    private static func item(
        _ properties: [String: PropertyValue] = [:], type: String = "aic.ticket", readOnly: Bool = false
    ) -> MarfaMac.Item {
        var item = MarfaMac.Item(
            id: ItemID("10000000-0000-0000-0000-000000000001"), type: TypeID(type), title: "Title", titleRule: .property("title"),
            properties: properties.map { Property(key: $0, value: $1) }, version: ItemVersion(1), created: .now, modified: .now)
        item.readOnly = readOnly
        return item
    }

    private static func link(
        _ field: String, _ label: String, _ targets: [String] = [], editability: RelationField.Editability = .editable
    ) -> RelationField {
        RelationField(
            field: field, label: label, cardinality: field == "child-of" ? .one : .many, allowedTypes: [],
            targets: targets.map { ItemRelationshipTarget(title: $0, itemID: ItemID($0), resolution: .resolved(ItemID($0))) },
            editability: editability)
    }

    private static func parent(_ title: String? = "Project") -> RelationField { link("child-of", "Parent", title.map { [$0] } ?? []) }

    private static func head(
        _ item: MarfaMac.Item, placements: PagePlacements = PagePlacements(), pins: Bool = false, tags: [String] = [],
        links: [RelationField] = [], when: PropertyRow? = nil
    ) -> PageHead {
        let type = item.type == TypeID("aic.contact") ? contact : ticket
        let catalogue = Catalogue(itemTypes: [ticket, contact])
        let candidates = PropertyRow.candidates(
            of: item, type: type, hidden: ["title", "body"], links: links, format: .standard, tags: tags,
            icon: { _ in nil }, isPerson: { _ in false })
        return PageHead(
            kicker: kicker, candidates: candidates, when: when, placement: placements.placement(of: item.type, in: catalogue),
            pinsProperties: pins, hasText: type.bodyKey != nil)
    }

    private static func shown(_ head: PageHead) -> [String] { head.rows.filter { !$0.folded }.map(\.id) }

    // MARK: Rows

    @Test func onlyRowsWithAValueShowAndEveryOtherPropertyWaitsUnderShowMoreInTheTypesOrder() {
        let head = Self.head(Self.item(["priority": .string("high"), "summary": .string("Short")]), links: [Self.parent(nil)])
        #expect(Self.shown(head) == ["priority", "summary"])
        #expect(head.order == ["state", "child-of", "priority", "a", "b", "c", "d", "e", "f", "summary", "done", "#tags"])
        #expect(head.foldedCount == 10)
        #expect(head.rows.first { $0.id == "a" }?.value == .empty(symbol: "text.alignleft"))
        #expect(head.rows.first { $0.id == "state" }?.editable == true, "an empty status opens its editor")
    }

    @Test func sixRowsShowAtMost() {
        let values = Dictionary(uniqueKeysWithValues: ["a", "b", "c", "d", "e", "f", "summary"].map { ($0, PropertyValue.string($0)) })
        let head = Self.head(Self.item(values))
        #expect(Self.shown(head) == ["a", "b", "c", "d", "e", "f"])
        #expect(head.rows.first { $0.id == "summary" }?.folded == true)
    }

    @Test func aTypeThatKeepsNoTextShowsItsFirstSixRowsEmptyOrNot() {
        let head = Self.head(Self.item(type: "aic.contact"))
        #expect(Self.shown(head) == ["a", "b", "c", "d", "e", "f"])
        #expect(head.foldedCount == 2)
    }

    @Test func alwaysShowShowsAnEmptyRowAndHiddenFoldsAndGreysOneWithAValue() {
        var placements = PagePlacements()
        placements.setShows(.always, row: "d", of: TypeID("aic.ticket"))
        placements.setShows(.hidden, row: "priority", of: TypeID("aic.ticket"))
        let head = Self.head(Self.item(["priority": .string("high")]), placements: placements)
        #expect(Self.shown(head) == ["d"])
        let hidden = head.rows.first { $0.id == "priority" }
        #expect(hidden?.folded == true)
        #expect(hidden?.muted == true)
    }

    @Test func aReadOnlyItemListsEveryRowAndOpensNoEditor() {
        let head = Self.head(Self.item(["priority": .string("high")], readOnly: true))
        #expect(head.foldedCount > 0)
        #expect(head.rows.filter { $0.id != "#tags" }.allSatisfy { !$0.editable })
    }

    @Test func longTextIsARowThatStopsAfterTwoLinesAndAYesOrNoIsAValue() {
        let long = String(repeating: "word ", count: 40)
        let head = Self.head(Self.item(["summary": .string("One\nTwo"), "a": .string(long), "done": .bool(false)]))
        #expect(head.rows.first { $0.id == "summary" }?.long == true)
        #expect(head.rows.first { $0.id == "a" }?.long == true)
        #expect(head.rows.first { $0.id == "done" }?.value == .boolean(false))
        // A list's row and a table's cell still leave long text out.
        let summary = Self.ticket.fields.first { $0.key == "summary" }!
        #expect(PropertyRow.value(of: summary, in: Self.item(["summary": .string("One\nTwo")]), format: .standard) == nil)
    }

    @Test func everyLinkTheTypeMayHoldIsARowAndAReadOnlyOneSaysWhy() {
        let reason = "A link is changed in the text that holds it."
        let head = Self.head(Self.item(), links: [
            Self.link(MarfaMapping.collectionEdge, "In Collection"), Self.link("about", "About", ["a1"]),
            Self.link("references", "References", ["r1"], editability: .readOnly(reason)),
            Self.link("inverse:parent-of", "Children", ["c1"]),
        ])
        #expect(head.rows.first { $0.id == MarfaMapping.collectionEdge }?.value == .empty(symbol: "link"), "an item in no collection has the row")
        #expect(head.rows.first { $0.id == MarfaMapping.collectionEdge }?.editable == true)
        #expect(head.rows.first { $0.id == "about" }?.editable == true)
        let references = head.rows.first { $0.id == "references" }
        #expect(references?.editable == false)
        #expect(references?.lock == reason)
        #expect(Self.shown(head) == ["about", "references"], "a link shows when it has one, and the links that point here wait under Show More")
        #expect(head.rows.first { $0.id == "inverse:parent-of" }?.folded == true)
    }

    @Test func aValueNoFieldDescribesIsTheLastReadOnlyRowUnderOther() {
        let head = Self.head(Self.item(["odd": .string("kept")]))
        let other = head.rows.last
        #expect(other?.id == PropertyRow.otherPrefix + "odd")
        #expect(other?.section == PropertyRow.otherHeading)
        #expect(other?.folded == true)
        #expect(other?.editable == false)
        #expect(!head.order.contains(PropertyRow.otherPrefix + "odd"), "it has no place in the order")
    }

    // MARK: When

    @Test func anEventsWhenLeadsTheRowsAndIsNoPersonsToPlace() {
        let when = PropertyRow(id: PagePlacement.when, label: "When", value: .when("Thu 29 Oct", note: "In 4 days"))
        var placements = PagePlacements()
        placements.setRowOrder(["priority"], of: TypeID("aic.ticket"))
        let head = Self.head(Self.item(["priority": .string("high")]), placements: placements, when: when)
        #expect(Self.shown(head) == [PagePlacement.when, "priority"])
    }

    @Test func anEventsNoteIsAllDayForOneWholeDayElseHowFarOffItIs() throws {
        let day = Self.item(["starts_at": .string("2026-11-26"), "all_day": .bool(true)], type: "core.event")
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-22T09:00:00Z"))
        let calendar = Calendar(identifier: .gregorian)
        #expect(EventHeader(item: day, now: now, calendar: calendar, locale: Locale(identifier: "en_GB"))?.note == "All Day")
        let timed = Self.item(["starts_at": .string("2026-11-26T10:00:00Z"), "timezone": .string("UTC")], type: "core.event")
        #expect(EventHeader(item: timed, now: now, calendar: calendar, locale: Locale(identifier: "en_GB"))?.note == "In 4 days")
    }

    // MARK: Pins

    @Test func pinsAreOffByDefaultAndWhenOnAPinnedRowLeavesTheRows() {
        let item = Self.item(["state": .string("pending"), "priority": .string("high")])
        let off = Self.head(item, links: [Self.parent()])
        #expect(off.pins.isEmpty)
        #expect(Self.shown(off) == ["state", "child-of", "priority"])
        let on = Self.head(item, pins: true, links: [Self.parent()])
        #expect(on.pins.map(\.id) == ["state", "child-of"], "the status and the parent are the default pins")
        #expect(Self.shown(on) == ["priority"])
    }

    @Test func aPinnedListShowsItsFirstValueAndCountsTheRest() {
        var placements = PagePlacements()
        placements.setPins([PagePlacement.tags], of: TypeID("aic.ticket"))
        let head = Self.head(Self.item(), placements: placements, pins: true, tags: ["a", "b", "c"])
        #expect(head.pins.first?.value == .tags(["a"]))
        #expect(head.pins.first?.more == 2)
        #expect(head.pins.first?.wholeValue == "a, b, c")
    }

    // MARK: Kicker and links

    @Test func theKickerSaysEachFlagInOrder() {
        let kicker = PageHead.Kicker(typeName: "Article", typeIcon: nil, changesType: false, flags: [.readOnly, .feed])
        #expect(kicker.spoken == "Article, Read Only, Feed")
        #expect(PageHead.Kicker.Flag.readOnly.symbol == "lock")
    }

    @Test func aNumberIsDialedAsItsDigitsAndALeadingPlus() {
        #expect(PageHead.dialAddress("+44 (0)20 7946 0958")?.absoluteString == "tel:+4402079460958")
        #expect(PageHead.dialAddress("ext. +1")?.absoluteString == "tel:1", "a plus that does not lead is dropped")
        #expect(PageHead.dialAddress("call me") == nil)
        #expect(BrowserTarget.webAddress("javascript:alert(1)") == nil)
        #expect(BrowserTarget.webAddress("https://example.com/a")?.host() == "example.com")
    }
}
