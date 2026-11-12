import Foundation
import Marfa
import Testing
@testable import MAPP

/// The properties pinned under an item's title, resolved to what each shows.
struct PagePinsTests {
    private static func field(_ name: String, _ type: String = "string", definition: JSONObject = [:]) -> TypeField {
        TypeField(name: name, type: type, declaredBy: "aic.ticket", definition: definition)
    }

    private static let ticket = MarfaMapping.itemType(ItemType(
        id: "aic.ticket", label: "Ticket",
        fields: [
            field("title"), field("body"),
            field("state", "status", definition: ["status_values": [["value": "pending", "group": "not_started"], ["value": "in_progress", "group": "in_progress"]]]),
            field("priority", "enum", definition: ["enum_values": ["low", "high"]]),
            field("mobiles"), field("labels"),
        ],
        titleField: "title", bodyField: "body"))

    private static let bookmark = MarfaMapping.itemType(ItemType(
        id: "core.bookmark", label: "Bookmark",
        fields: [
            field("title"), field("body"), field("description"), field("publisher"), field("source_title"),
            field("published_at", "datetime"), field("image_url"),
        ],
        titleField: "title", bodyField: "body"))

    private static let catalogue = Catalogue(itemTypes: [
        ticket,
        ItemTypeInfo(id: TypeID("core.event"), label: "Event", fields: [], titleField: "title", bodyField: "body", parent: nil),
        bookmark,
    ])

    private static let created = Date(timeIntervalSince1970: 1_700_000_000)
    private static let now = Date(timeIntervalSince1970: 1_700_100_000)

    private static func item(_ properties: [String: PropertyValue] = [:], type: String = "aic.ticket", source: String? = nil) -> MAPP.Item {
        var item = MAPP.Item(
            id: ItemID("10000000-0000-0000-0000-000000000001"), type: TypeID(type), title: "Title", titleRule: .property("title"),
            properties: properties.map { Property(key: $0, value: $1) }, version: ItemVersion(1), created: created, modified: created)
        item.source = source
        return item
    }

    private static func parent(_ title: String? = "Project") -> ItemRelationship {
        ItemRelationship(
            field: "child-of", label: "Parent",
            targets: title.map { [ItemRelationshipTarget(title: $0, itemID: ItemID("p1"), resolution: .resolved(ItemID("p1")))] } ?? [],
            isEditable: true, allowsMultiple: false)
    }

    private struct Drawn {
        let pins: PagePins
        let block: [PropertyRow]
    }

    private static func resolve(
        _ item: MAPP.Item, placements: PagePlacements = PagePlacements(), tags: [String] = [], relationships: [ItemRelationship] = [],
        kind: PageHeaderKind? = nil, offersEmpty: Bool = false
    ) -> Drawn {
        let type = catalogue.itemTypes[item.type]
        let placement = placements.placement(of: item.type, in: catalogue)
        let lead = PageHeaderLead(for: item, kind: kind ?? PageHeaderKind.of(item.type, in: catalogue), now: now)
        let candidates = PropertyRow.candidates(
            of: item, type: type, hidden: Set(["title", "body"]).union(lead.consumed), relationships: relationships, parentField: "child-of",
            format: .automatic, tags: tags, typeLabel: type?.label, typeIcon: type?.icon, sourceName: item.source, now: now,
            calendar: .current, locale: Locale(identifier: "en_GB"), offersEmpty: offersEmpty, icon: { _ in nil }, isPerson: { _ in false })
        let pins = PagePins.resolve(
            for: item, type: type, placement: placement, lead: lead, relationships: relationships, candidates: candidates,
            offersEmpty: offersEmpty, icon: { _ in nil }, isPerson: { _ in false })
        return Drawn(pins: pins, block: PropertyRow.block(candidates, placement: placement, excluding: pins.leftOutOfBlock))
    }

    // MARK: Defaults

    @Test func withNoChoiceTheTypeStatusParentAndUpdatedArePinnedInThatOrder() {
        let drawn = Self.resolve(Self.item(["state": .string("pending")]), relationships: [Self.parent()])
        #expect(drawn.pins.pins.map(\.id) == ["#type", "state", "child-of", "#updated"])
        #expect(drawn.pins.pins[0].value == .type("Ticket", icon: nil))
        #expect(drawn.pins.pins[1].value == .status)
        #expect(drawn.pins.pins[2].value == .items([PropertyRow.Target(title: "Project", item: ItemID("p1"))]), "a pinned parent opens it and has no menu")
        // The pinned rows are not in the property block too.
        #expect(drawn.block.map(\.id) == [])
    }

    @Test func aPinnedRowIsNotAlsoInThePropertyBlock() {
        let drawn = Self.resolve(Self.item(["state": .string("pending"), "priority": .string("high")]), relationships: [Self.parent()])
        #expect(drawn.block.map(\.id) == ["priority"])
        var unpinned = PagePlacements()
        unpinned.setPins([], of: TypeID("aic.ticket"))
        let block = Self.resolve(Self.item(["state": .string("pending"), "priority": .string("high")]), placements: unpinned, relationships: [Self.parent()])
        #expect(block.pins.pins.isEmpty)
        #expect(block.block.map(\.id) == ["#type", "#updated", "state", "child-of", "priority"], "unpinned, the type and the last edit are rows")
    }

    @Test func aSavedChoiceThatTurnedAPinnedStatusOffLeavesItOut() {
        var placements = PagePlacements()
        placements.setShown(false, row: "state", of: TypeID("aic.ticket"))
        let drawn = Self.resolve(Self.item(["state": .string("pending")]), placements: placements, relationships: [Self.parent()])
        #expect(drawn.pins.pins.map(\.id) == ["#type", "child-of", "#updated"])
    }

    @Test func aStatusWithNoValueAndAParentThatIsNotThereAreHiddenWithNoPlaceholder() {
        let drawn = Self.resolve(Self.item(), relationships: [Self.parent(nil)])
        #expect(drawn.pins.pins.map(\.id) == ["#type", "#updated"])
        let noRelationships = Self.resolve(Self.item(["state": .string("")]))
        #expect(noRelationships.pins.pins.map(\.id) == ["#type", "#updated"])
        // A pinned row is not in the block either, empty or not: an empty status or parent is set from the sidebar.
        #expect(drawn.block.isEmpty)
        var unpinned = PagePlacements()
        unpinned.setPins([], of: TypeID("aic.ticket"))
        // Unpinned, the status row is back in the block with its plus, which is how the page sets it.
        #expect(Self.resolve(Self.item(), placements: unpinned).block.map(\.id).contains("state"))
    }

    @Test func aPinNamingAFieldTheTypeDoesNotHaveIsSkippedAndTheRestKeepTheirOrder() {
        var placements = PagePlacements()
        placements.setPins(["gone", "#updated", "#type"], of: TypeID("aic.ticket"))
        let drawn = Self.resolve(Self.item(), placements: placements)
        #expect(drawn.pins.pins.map(\.id) == ["#updated", "#type"])
        #expect(placements.choices["aic.ticket"]?.pins == ["gone", "#updated", "#type"])
    }

    @Test func fiveStoredPinsShowTheFirstFour() throws {
        let placements = try #require(PagePlacements(rawValue: ##"{"aic.ticket":{"rows":{},"pins":["#type","#source","#updated","priority","state"]}}"##))
        let drawn = Self.resolve(Self.item(["state": .string("pending"), "priority": .string("low")], source: "folder"), placements: placements)
        #expect(drawn.pins.pins.map(\.id) == ["#type", "#source", "#updated", "priority"])
    }

    // MARK: Empty values

    @Test func whereEmptiesAreOfferedAValueTheItemLacksIsAnEditableEmptyRow() {
        let drawn = Self.resolve(Self.item(), relationships: [Self.parent(nil)], offersEmpty: true)
        let empty = Dictionary(uniqueKeysWithValues: (drawn.pins.pins + drawn.block).filter(\.isEmpty).map { ($0.id, $0) })
        #expect(Set(empty.keys) == ["state", "child-of", "priority", "mobiles", "#tags"])
        #expect(empty.values.allSatisfy { $0.editable })
        #expect(empty["state"]?.value == .empty(symbol: PropertyRow.Value.status.symbol))
        #expect(drawn.pins.pins.map(\.id) == ["#type", "state", "child-of", "#updated"])
    }

    @Test func emptiesAreNotOfferedByDefaultNorOnAnItemThatCannotBeEdited() {
        let plain = Self.resolve(Self.item(), relationships: [Self.parent(nil)])
        #expect((plain.pins.pins + plain.block).allSatisfy { !$0.isEmpty })
        var trashed = Self.item()
        trashed.state = .trashed
        let readOnly = Self.resolve(trashed, relationships: [Self.parent(nil)], offersEmpty: true)
        #expect((readOnly.pins.pins + readOnly.block).allSatisfy { !$0.isEmpty })
    }

    // MARK: Values

    @Test func theTypeSourceAndUpdatedAreRowsThatOnlyHaveSomethingToShowWhenTheyDo() {
        let candidates = PropertyRow.candidates(
            of: Self.item(source: "  workbench "), type: Self.catalogue.itemTypes[TypeID("aic.ticket")], hidden: ["title", "body"], relationships: [],
            parentField: "child-of", format: .automatic, tags: [], typeLabel: "Ticket", typeIcon: nil, sourceName: nil, now: Self.now,
            calendar: .current, locale: Locale(identifier: "en_GB"), icon: { _ in nil }, isPerson: { _ in false })
        #expect(candidates.prefix(3).map(\.id) == ["#type", "#source", "#updated"])
        #expect(candidates[1].value == .source("workbench"))
        let bare = PropertyRow.candidates(
            of: Self.item(), type: nil, hidden: [], relationships: [], parentField: "child-of", format: .automatic, tags: [], typeLabel: nil,
            typeIcon: nil, sourceName: nil, now: Self.now, calendar: .current, locale: .current, icon: { _ in nil }, isPerson: { _ in false })
        #expect(bare.map(\.id) == ["#updated"])
    }

    @Test func aPriorityRowCarriesItsRankColorsToThePageAndPins() throws {
        let priority = try #require(Self.catalogue.itemTypes[TypeID("aic.ticket")]?.fields.first { $0.key == "priority" })
        let candidates = PropertyRow.candidates(
            of: Self.item(["priority": .string("high")]), type: Self.catalogue.itemTypes[TypeID("aic.ticket")], hidden: ["title", "body"],
            relationships: [], parentField: "child-of", format: .automatic, tags: [], typeLabel: nil, typeIcon: nil, sourceName: nil,
            now: Self.now, calendar: .current, locale: Locale(identifier: "en_GB"), isPriority: { $0.key == "priority" },
            icon: { _ in nil }, isPerson: { _ in false })
        let row = try #require(candidates.first { $0.id == "priority" })
        #expect(row.optionTones == [OptionTone.tone(of: "high", in: priority, isPriority: true)])
        #expect(row.optionTones != [OptionTone.tone(for: "High")])
        let sent = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any]
        let options = try #require(sent?["options"] as? [[String: Any]])
        #expect(options.map { $0["tone"] as? String } == [row.optionTones[0].rawValue])
        let others = PropertyRow.candidates(
            of: Self.item(["priority": .string("high")]), type: Self.catalogue.itemTypes[TypeID("aic.ticket")], hidden: ["title", "body"],
            relationships: [], parentField: "child-of", format: .automatic, tags: [], typeLabel: nil, typeIcon: nil, sourceName: nil,
            now: Self.now, calendar: .current, locale: Locale(identifier: "en_GB"), icon: { _ in nil }, isPerson: { _ in false })
        #expect(others.first { $0.id == "priority" }?.optionTones == [])
    }

    @Test func aListShowsItsFirstValueAndHowManyItLeftOut() {
        var placements = PagePlacements()
        placements.setPins(["#tags", "#updated"], of: TypeID("aic.ticket"))
        func tags(_ values: [String]) -> Drawn { Self.resolve(Self.item(), placements: placements, tags: values) }
        // None: the pin has nothing to show, and is left out.
        #expect(tags([]).pins.pins.map(\.id) == ["#updated"])
        // One: just the value.
        #expect(tags(["a"]).pins.pins[0].value == .tags(["a"]))
        #expect(tags(["a"]).pins.pins[0].more == 0)
        // Two: the first, and one more.
        #expect(tags(["a", "b"]).pins.pins[0].value == .tags(["a"]))
        #expect(tags(["a", "b"]).pins.pins[0].more == 1)
        // Five: the first, and four more.
        let five = tags(["a", "b", "c", "d", "e"])
        #expect(five.pins.pins[0].value == .tags(["a"]))
        #expect(five.pins.pins[0].more == 4)
        #expect(five.pins.pins[1].more == 0)
        // The block shows every value of a list.
        placements.setPins([], of: TypeID("aic.ticket"))
        #expect(Self.resolve(Self.item(), placements: placements, tags: ["a", "b", "c"]).block.last?.value == .tags(["a", "b", "c"]))
    }

    @Test func everyKindOfListKeepsItsFirstValueAndCountsTheOthers() {
        var placements = PagePlacements()
        placements.setPins(["labels", "child-of"], of: TypeID("aic.ticket"))
        let labels = (0..<5).map { PropertyValue.string("label \($0)") }
        let drawn = Self.resolve(Self.item(["labels": .array(labels)]), placements: placements, relationships: [Self.parent()])
        #expect(drawn.pins.pins[0].value == .options(["label 0"]))
        #expect(drawn.pins.pins[0].more == 4)
        // The block keeps all five.
        placements.setPins([], of: TypeID("aic.ticket"))
        let block = Self.resolve(Self.item(["labels": .array(labels)]), placements: placements)
        #expect(block.block.first { $0.id == "labels" }?.value == .options((0..<5).map { "label \($0)" }))

        func capped(_ value: PropertyRow.Value) -> PropertyRow {
            PagePins.capped(PropertyRow(id: "list", label: "List", value: value))
        }
        let people = capped(.people(["Ruth", "Ada", "Cher"]))
        #expect(people.value == .people(["Ruth"]))
        #expect(people.more == 2)
        let targets = (0..<3).map { PropertyRow.Target(title: "Item \($0)", item: ItemID("i\($0)")) }
        let items = capped(.items(targets))
        #expect(items.value == .items([targets[0]]))
        #expect(items.more == 2)
    }

    @Test func theWordsForTheRestComeFromTheAppAndReachThePageAsText() throws {
        #expect(PagePins.moreText(1) == "+1 more")
        #expect(PagePins.moreText(4) == "+4 more")
        var placements = PagePlacements()
        placements.setPins(["#tags"], of: TypeID("aic.ticket"))
        let drawn = Self.resolve(Self.item(), placements: placements, tags: ["a", "b", "c", "d", "e"])
        let sent = try JSONSerialization.jsonObject(with: JSONEncoder().encode(drawn.pins.pins[0])) as? [String: Any]
        #expect(sent?["more"] as? String == PagePins.moreText(4))
        #expect(sent?["texts"] as? [String] == ["a"])
        let whole = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.resolve(Self.item(), placements: placements, tags: ["a"]).pins.pins[0])) as? [String: Any]
        #expect(whole?["more"] == nil)
    }

    // MARK: Kinds with a line of their own

    @Test func anEventsTimeIsItsFirstPinAndTheRestFollow() throws {
        let item = Self.item(["starts_at": .string("2026-10-29T10:00:00Z")], type: "core.event")
        let drawn = Self.resolve(item)
        #expect(drawn.pins.pins.map(\.id) == [PagePlacement.when, "#type", "#updated"])
        let when = try #require(drawn.pins.pins.first)
        guard case .when(let text, let help) = when.value else { Issue.record("the first pin is not a when"); return }
        #expect(help.hasPrefix(text), "the help keeps the whole of a time a narrow page cuts")
        #expect(drawn.pins.leftOutOfBlock.isSuperset(of: EventHeader.keys))
        var placements = PagePlacements()
        placements.setPins(["starts_at", "#type"], of: TypeID("core.event"))
        #expect(Self.resolve(item, placements: placements).pins.pins.map(\.id) == [PagePlacement.when, "#type"], "the when is not pinned again")
    }

    @Test func anEventWithNoDayToPlaceHasNoTimePin() {
        let item = Self.item(["starts_at": .string("soon")], type: "core.event")
        #expect(!Self.resolve(item).pins.pins.map(\.id).contains(PagePlacement.when))
    }

    @Test func aPinTheEventsTimePushesOutGoesBackToThePropertyBlock() {
        let item = Self.item(["starts_at": .string("2026-10-29T10:00:00Z")], type: "core.event")
        var placements = PagePlacements()
        placements.setPins(["#type", "#updated", "child-of", "#tags"], of: TypeID("core.event"))
        let drawn = Self.resolve(item, placements: placements, tags: ["a"], relationships: [Self.parent()])
        #expect(drawn.pins.pins.map(\.id) == [PagePlacement.when, "#type", "#updated", "child-of"])
        #expect(drawn.block.map(\.id) == ["#tags"])
    }

    @Test func aReadingItemPinsItsTypeSourceAndDayLikeAnyOtherPage() {
        var placements = PagePlacements()
        placements.setPins(["#type", "#source", "publisher", "published_at"], of: TypeID("core.bookmark"))
        let item = Self.item(Self.reading, type: "core.bookmark", source: "feed")
        let drawn = Self.resolve(item, placements: placements)
        #expect(drawn.pins.pins.map(\.id) == ["#type", "#source", "publisher", "published_at"])
        #expect(drawn.pins.pins[1].value == .source("feed"))
        // The default pins name the type, and nothing the page draws itself.
        #expect(Self.resolve(item, relationships: [Self.parent()]).pins.pins.map(\.id) == ["#type", "child-of", "#updated"])
    }

    @Test func aReadingItemsSourceAndPublishedDayAreInThePropertyBlock() {
        let item = Self.item(Self.reading, type: "core.bookmark", source: "feed")
        let block = Self.resolve(item).block.map(\.id)
        for key in ["publisher", "source_title", "published_at", "#source"] { #expect(block.contains(key), "\(key)") }
        // The description is the page's dek, and the picture's address is never drawn.
        for key in ["description", "image_url"] { #expect(!block.contains(key), "\(key)") }
    }

    private static let reading: [String: PropertyValue] = [
        "url": .string("https://example.com/a"), "publisher": .string("YC"), "source_title": .string("Y Combinator Blog"),
        "published_at": .string("2025-10-02T00:00:00Z"), "description": .string("Why startups fail"), "image_url": .string("https://example.com/a.png"),
    ]

    @Test func aPersonsNumberToCallStaysALink() {
        let person = PageHeaderLead(for: Self.item(type: "core.entity.person"), kind: .person, now: Self.now)
        #expect(person.consumed == PersonHeader.keys)
    }

    // MARK: Status

    @Test func thePinnedStatusIsTheTypesOwnStatusFieldWhateverItIsCalled() {
        let field = Self.catalogue.itemTypes[TypeID("aic.ticket")]?.statusField
        #expect(field?.key == "state")
        #expect(PagePins.statusValue(of: Self.item(["state": .string("pending")]), in: field!) == "pending")
        #expect(PagePins.statusValue(of: Self.item(["state": .string("")]), in: field!) == nil)
        #expect(PagePins.statusValue(of: Self.item(), in: field!) == nil)
    }
}
