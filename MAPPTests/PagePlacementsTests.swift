import Foundation
import Marfa
import Testing
@testable import MAPP

/// Where the page shows an item's properties, chosen for each type and kept in the defaults.
struct PagePlacementsTests {
    private static let ticket = TypeID("aic.ticket")
    private static let comment = TypeID("aic.comment")
    private static let person = TypeID("core.entity.person")
    private static let folder = TypeID("aic.folder")

    private static func field(_ name: String, _ owner: String) -> TypeField {
        TypeField(name: name, type: "string", declaredBy: owner)
    }

    private static let catalogue = Catalogue(itemTypes: [
        MarfaMapping.itemType(ItemType(
            id: "aic.ticket", label: "Ticket", fields: [field("title", "aic.ticket"), field("github_id", "aic.ticket"), field("repo", "aic.ticket")],
            titleField: "title")),
        MarfaMapping.itemType(ItemType(
            id: "aic.comment", label: "Comment", fields: [field("title", "aic.comment"), field("github_id", "aic.comment")],
            titleField: "title", linkField: "github_id")),
        MarfaMapping.itemType(ItemType(id: "core.entity.person", label: "Person", fields: [], icon: "lucide:user")),
        MarfaMapping.itemType(ItemType(id: "aic.folder", label: "Folder", fields: [], roles: [MarfaMapping.containerRole])),
        MarfaMapping.itemType(ItemType(
            id: "aic.task", label: "Task",
            fields: [
                field("title", "aic.task"),
                TypeField(
                    name: "state", type: "status", declaredBy: "aic.task",
                    definition: ["status_values": [["value": "open", "group": "not_started"], ["value": "shut", "group": "completed"]]]),
            ],
            titleField: "title")),
        MarfaMapping.itemType(ItemType(id: "aic.subtask", label: "Subtask", parent: "aic.task", fields: [])),
    ])
    private static let task = TypeID("aic.task")
    private static let subtask = TypeID("aic.subtask")

    private static func item(_ type: TypeID, _ properties: [String: PropertyValue] = [:]) -> MAPP.Item {
        MAPP.Item(
            id: ItemID("10000000-0000-0000-0000-000000000001"), type: type, title: "Title", titleRule: .property("title"),
            properties: properties.map { Property(key: $0, value: $1) }, version: ItemVersion(1), created: .now, modified: .now)
    }

    // MARK: Defaults

    @Test func withNoChoiceEveryRowShowsExceptTheLinkField() {
        let placements = PagePlacements()
        let comment = placements.placement(of: Self.comment, in: Self.catalogue)
        #expect(comment.showsOnPage("repo"))
        #expect(comment.showsOnPage("#tags"))
        #expect(comment.showsOnPage("child-of"))
        #expect(!comment.showsOnPage("github_id"))
        // The link field is each type's own, never an inherited or sibling's. A type that names none still keeps
        // a connector's identifier off the page, as bookkeeping.
        #expect(!placements.placement(of: Self.ticket, in: Self.catalogue).showsOnPage("github_id"))
    }

    @Test func aConnectorsIdentifiersAndChecksumsStayOffThePageByDefault() {
        let rows = ["entry_id", "feed_hash", "github_id", "blob_sha", "todoist_id", "ical_uid", "etag"]
        let catalogue = Catalogue(itemTypes: [
            MarfaMapping.itemType(ItemType(
                id: "rss.entry", label: "RSS Entry",
                fields: rows.map { Self.field($0, "rss.entry") } + ["feed_origin", "number", "title", "author", "repository", "private", "url", "reader_reading_progress"]
                    .map { Self.field($0, "rss.entry") } + [Self.field("source_id", "core.bookmark")],
                titleField: "title"))
        ])
        let placement = PagePlacements().placement(of: TypeID("rss.entry"), in: catalogue)
        for row in rows { #expect(!placement.showsOnPage(row), "\(row) is bookkeeping") }
        for row in ["feed_origin", "number", "title", "author", "repository", "private", "url", "reader_reading_progress"] {
            #expect(placement.showsOnPage(row), "\(row) is for a person to read")
        }
        // A core type declares its own fields as content, even one whose key ends the same way.
        #expect(placement.showsOnPage("source_id"))
        // Show on Page and Customize Layout override the default either way.
        var chosen = PagePlacements()
        chosen.setShown(true, row: "feed_hash", of: TypeID("rss.entry"))
        chosen.setShown(false, row: "url", of: TypeID("rss.entry"))
        let overridden = chosen.placement(of: TypeID("rss.entry"), in: catalogue)
        #expect(overridden.showsOnPage("feed_hash"))
        #expect(!overridden.showsOnPage("url"))
    }

    @Test func linkedFromGoesToTheInspectorExceptForAPersonAndACollection() {
        let placements = PagePlacements()
        #expect(placements.placement(of: Self.ticket, in: Self.catalogue).linkedFromPlace == .inspector)
        #expect(placements.placement(of: Self.person, in: Self.catalogue).linkedFromPlace == .page)
        #expect(placements.placement(of: Self.folder, in: Self.catalogue).linkedFromPlace == .page)
        // A type the catalogue does not hold is an ordinary one.
        #expect(placements.placement(of: TypeID("aic.unknown"), in: Self.catalogue).linkedFromPlace == .inspector)
    }

    // MARK: Choices

    @Test func aChoiceOverridesTheDefaultEitherWay() {
        var placements = PagePlacements()
        placements.setShown(true, row: "github_id", of: Self.comment)
        placements.setShown(false, row: "repo", of: Self.ticket)
        placements.setLinkedFrom(.page, of: Self.ticket, in: Self.catalogue)
        placements.setLinkedFrom(.inspector, of: Self.person, in: Self.catalogue)
        #expect(placements.placement(of: Self.comment, in: Self.catalogue).showsOnPage("github_id"))
        let ticket = placements.placement(of: Self.ticket, in: Self.catalogue)
        #expect(!ticket.showsOnPage("repo"))
        #expect(ticket.linkedFromPlace == .page)
        #expect(placements.placement(of: Self.person, in: Self.catalogue).linkedFromPlace == .inspector)
    }

    @Test func showingLinkedFromOnThePageMovesItThereAndHidingItMovesItBack() {
        var placements = PagePlacements()
        placements.set(true, row: PagePlacement.linkedFrom, of: Self.ticket, in: Self.catalogue)
        #expect(placements.placement(of: Self.ticket, in: Self.catalogue).linkedFromPlace == .page)
        placements.set(false, row: PagePlacement.linkedFrom, of: Self.ticket, in: Self.catalogue)
        #expect(placements.placement(of: Self.ticket, in: Self.catalogue).linkedFromPlace == .inspector)
        // A property row is a row of its own and never changes where Linked From is.
        placements.set(false, row: "repo", of: Self.ticket, in: Self.catalogue)
        #expect(!placements.placement(of: Self.ticket, in: Self.catalogue).showsOnPage("repo"))
        #expect(placements.placement(of: Self.ticket, in: Self.catalogue).linkedFromPlace == .inspector)
    }

    @Test func aLinkedFromPlaceEqualToTheTypesDefaultIsNotKept() {
        var placements = PagePlacements()
        placements.setLinkedFrom(.page, of: Self.ticket, in: Self.catalogue)
        #expect(placements.hasChoice(for: Self.ticket))
        // Back to the default, by either path, leaves no choice behind.
        placements.setLinkedFrom(.inspector, of: Self.ticket, in: Self.catalogue)
        #expect(!placements.hasChoice(for: Self.ticket))
        placements.set(true, row: PagePlacement.linkedFrom, of: Self.person, in: Self.catalogue)
        #expect(!placements.hasChoice(for: Self.person))
        placements.set(false, row: PagePlacement.linkedFrom, of: Self.person, in: Self.catalogue)
        #expect(placements.hasChoice(for: Self.person))
        placements.set(true, row: PagePlacement.linkedFrom, of: Self.person, in: Self.catalogue)
        #expect(!placements.hasChoice(for: Self.person))
        #expect(placements.rawValue == "{}")
    }

    @Test func aChoiceForOneTypeLeavesEveryOtherTypeAlone() {
        var placements = PagePlacements()
        placements.setShown(false, row: "repo", of: Self.ticket)
        placements.setLinkedFrom(.page, of: Self.ticket, in: Self.catalogue)
        let comment = placements.placement(of: Self.comment, in: Self.catalogue)
        #expect(comment.showsOnPage("repo"))
        #expect(comment.linkedFromPlace == .inspector)
        #expect(!placements.hasChoice(for: Self.comment))
        #expect(placements.hasChoice(for: Self.ticket))
    }

    @Test func resettingATypeGivesItsDefaultsBack() {
        var placements = PagePlacements()
        placements.setShown(false, row: "repo", of: Self.ticket)
        placements.setShown(false, row: "repo", of: Self.comment)
        placements.reset(Self.ticket)
        #expect(placements.placement(of: Self.ticket, in: Self.catalogue).showsOnPage("repo"))
        #expect(!placements.placement(of: Self.comment, in: Self.catalogue).showsOnPage("repo"))
        #expect(!placements.hasChoice(for: Self.ticket))
    }

    // MARK: Stored value

    @Test func theChoiceRoundTripsThroughItsStoredText() {
        var placements = PagePlacements()
        placements.setShown(false, row: "repo", of: Self.ticket)
        placements.setShown(true, row: "github_id", of: Self.comment)
        placements.setLinkedFrom(.page, of: Self.comment, in: Self.catalogue)
        #expect(PagePlacements(rawValue: placements.rawValue) == placements)
        #expect(PagePlacements().rawValue == "{}")
    }

    @Test func textThatIsNotAChoiceIsNotOne() {
        #expect(PagePlacements(rawValue: "not json") == nil)
        #expect(PagePlacements(rawValue: "[]") == nil)
        #expect(PagePlacements(rawValue: #"{"aic.ticket":{"linkedFrom":"somewhere"}}"#) == nil)
    }

    @Test func theDefaultsHoldTheChoicesUnderOneKey() throws {
        let suite = "MAPP.PagePlacementsTests"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(PagePlacements.stored(in: defaults) == PagePlacements())
        PagePlacements.update(in: defaults) { $0.setShown(false, row: "repo", of: Self.ticket) }
        #expect(PagePlacements.stored(in: defaults).placement(of: Self.ticket, in: Self.catalogue).showsOnPage("repo") == false)
        PagePlacements.update(in: defaults) { $0.reset(Self.ticket) }
        #expect(PagePlacements.stored(in: defaults) == PagePlacements())
    }

    // MARK: The page's rows

    @Test func theRowsFollowThePlacementOfTheItemsType() {
        let type = Self.catalogue.itemTypes[Self.comment]
        let item = Self.item(Self.comment, ["github_id": .string("IC_kwDO")])
        func rows(_ placements: PagePlacements, tags: [String] = ["a"]) -> [String] {
            PropertyRow.rows(
                of: item, type: type, hidden: ["title"], relationships: [], parentField: "child-of", format: .automatic, tags: tags,
                placement: placements.placement(of: Self.comment, in: Self.catalogue)
            ).map(\.id)
        }
        // The link field is left off until asked for.
        #expect(rows(PagePlacements()) == ["#tags"])
        var placements = PagePlacements()
        placements.setShown(true, row: "github_id", of: Self.comment)
        #expect(rows(placements) == ["github_id", "#tags"])
        placements.setShown(false, row: "#tags", of: Self.comment)
        #expect(rows(placements) == ["github_id"])
        // Another type's choice changes nothing here.
        var other = PagePlacements()
        other.setShown(true, row: "github_id", of: Self.ticket)
        other.setShown(false, row: "#tags", of: Self.ticket)
        #expect(rows(other) == ["#tags"])
    }

    @Test func aRelationshipRowAndTheParentCanBeKeptOffThePage() {
        let relationships = [
            ItemRelationship(
                field: "child-of", label: "Parent",
                targets: [ItemRelationshipTarget(title: "Project", itemID: ItemID("p"), resolution: .resolved(ItemID("p")))],
                isEditable: true, allowsMultiple: false),
            ItemRelationship(
                field: "about", label: "About",
                targets: [ItemRelationshipTarget(title: "Notes", itemID: ItemID("n"), resolution: .resolved(ItemID("n")))],
                isEditable: true, allowsMultiple: true),
        ]
        func rows(_ placements: PagePlacements) -> [String] {
            PropertyRow.rows(
                of: Self.item(Self.ticket), type: Self.catalogue.itemTypes[Self.ticket], hidden: ["title"], relationships: relationships,
                parentField: "child-of", format: .automatic, tags: [], placement: placements.placement(of: Self.ticket, in: Self.catalogue)
            ).map(\.id)
        }
        #expect(rows(PagePlacements()) == ["child-of", "about"])
        var placements = PagePlacements()
        placements.setShown(false, row: "child-of", of: Self.ticket)
        placements.setShown(false, row: "about", of: Self.ticket)
        #expect(rows(placements).isEmpty)
    }

    // MARK: Pins

    @Test func withNoChoiceTheTypeStatusParentAndUpdatedArePinnedInThatOrder() {
        let placements = PagePlacements()
        // The status is the type's own status field, whatever it is called.
        #expect(placements.pins(of: Self.task, in: Self.catalogue) == ["#type", "state", "child-of", "#updated"])
        // A type with no status has none to pin.
        #expect(placements.pins(of: Self.ticket, in: Self.catalogue) == ["#type", "child-of", "#updated"])
        #expect(placements.pins(of: TypeID("aic.unknown"), in: Self.catalogue) == ["#type", "child-of", "#updated"])
    }

    @Test func aSubtypeDoesNotFollowItsParentsPins() {
        var placements = PagePlacements()
        placements.setPins(["#source"], of: Self.task)
        #expect(placements.pins(of: Self.task, in: Self.catalogue) == ["#source"])
        #expect(placements.pins(of: Self.subtask, in: Self.catalogue) == ["#type", "child-of", "#updated"])
    }

    @Test func aDefaultPinThatASavedChoiceTurnedOffStaysOff() {
        var placements = PagePlacements()
        placements.setShown(false, row: "state", of: Self.task)
        placements.setShown(false, row: "#updated", of: Self.task)
        #expect(placements.pins(of: Self.task, in: Self.catalogue) == ["#type", "child-of"])
        // Turning it on again gives the default pin back.
        placements.setShown(true, row: "state", of: Self.task)
        #expect(placements.pins(of: Self.task, in: Self.catalogue) == ["#type", "state", "child-of"])
    }

    @Test func aChosenListTakesThePlaceOfTheDefaultPins() {
        var placements = PagePlacements()
        placements.setPins(["#updated", "repo"], of: Self.ticket)
        #expect(placements.pins(of: Self.ticket, in: Self.catalogue) == ["#updated", "repo"])
        // A hidden row is the person's word about the property block; a pin they chose is theirs too.
        placements.setShown(false, row: "repo", of: Self.ticket)
        #expect(placements.pins(of: Self.ticket, in: Self.catalogue) == ["#updated", "repo"])
    }

    @Test func aFifthPinIsRefusedAndTheListIsLeftAlone() {
        var placements = PagePlacements()
        placements.setPins(["#type", "#source", "#updated", "repo"], of: Self.ticket)
        var took = placements.pin("child-of", of: Self.ticket, in: Self.catalogue)
        #expect(!took)
        #expect(placements.pins(of: Self.ticket, in: Self.catalogue) == ["#type", "#source", "#updated", "repo"])
        // One already pinned stays pinned, where it is.
        took = placements.pin("#source", of: Self.ticket, in: Self.catalogue)
        #expect(took)
        #expect(placements.pins(of: Self.ticket, in: Self.catalogue) == ["#type", "#source", "#updated", "repo"])
        placements.unpin("#type", of: Self.ticket, in: Self.catalogue)
        took = placements.pin("child-of", of: Self.ticket, in: Self.catalogue)
        #expect(took)
        #expect(placements.pins(of: Self.ticket, in: Self.catalogue) == ["#source", "#updated", "repo", "child-of"])
    }

    @Test func pinningStartsFromTheDefaultPinsAndMovingKeepsThemWithinTheList() {
        var placements = PagePlacements()
        var took = placements.pin("#source", of: Self.task, in: Self.catalogue)
        #expect(!took, "four defaults fill the list")
        placements.unpin("#type", of: Self.task, in: Self.catalogue)
        took = placements.pin("#source", of: Self.task, in: Self.catalogue)
        #expect(took)
        #expect(placements.pins(of: Self.task, in: Self.catalogue) == ["state", "child-of", "#updated", "#source"])
        placements.movePin("#source", to: 0, of: Self.task, in: Self.catalogue)
        #expect(placements.pins(of: Self.task, in: Self.catalogue) == ["#source", "state", "child-of", "#updated"])
        placements.movePin("#source", to: 99, of: Self.task, in: Self.catalogue)
        #expect(placements.pins(of: Self.task, in: Self.catalogue) == ["state", "child-of", "#updated", "#source"])
        placements.movePin("repo", to: 0, of: Self.task, in: Self.catalogue)
        #expect(placements.pins(of: Self.task, in: Self.catalogue) == ["state", "child-of", "#updated", "#source"])
    }

    @Test func fiveStoredPinsShowFourAndADuplicateCountsOnce() throws {
        let stored = try #require(PagePlacements(rawValue: ##"{"aic.ticket":{"rows":{},"pins":["#type","#type","repo","#source","#updated","child-of"]}}"##))
        #expect(stored.pins(of: Self.ticket, in: Self.catalogue) == ["#type", "repo", "#source", "#updated"])
        // The list in storage is not cut by reading it.
        #expect(stored.choices["aic.ticket"]?.pins?.count == 6)
    }

    @Test func aPinNamingAFieldTheTypeNoLongerHasStaysInStorage() throws {
        var placements = try #require(PagePlacements(rawValue: ##"{"aic.ticket":{"rows":{},"pins":["gone","#type"]}}"##))
        #expect(placements.pins(of: Self.ticket, in: Self.catalogue) == ["gone", "#type"])
        // Another change to the list does not drop it.
        placements.unpin("#type", of: Self.ticket, in: Self.catalogue)
        #expect(placements.choices["aic.ticket"]?.pins == ["gone"])
        #expect(PagePlacements(rawValue: placements.rawValue) == placements)
    }

    @Test func aChoiceSavedBeforePinsStillReadsAndKeepsEverythingItHeld() throws {
        let old = #"{"aic.ticket":{"linkedFrom":"page","rows":{"repo":false}}}"#
        let placements = try #require(PagePlacements(rawValue: old))
        let choice = try #require(placements.choices["aic.ticket"])
        #expect(choice.pins == nil)
        #expect(choice.rows == ["repo": false])
        #expect(choice.linkedFrom == .page)
        #expect(placements.pins(of: Self.ticket, in: Self.catalogue) == ["#type", "child-of", "#updated"])
        #expect(placements.rawValue == old, "written back as it was read")
    }

    @Test func aChoiceSavedBeforeOrderingStillReadsAndAnOrderRoundTrips() throws {
        let old = ##"{"aic.ticket":{"pins":["#type"],"rows":{"repo":false}}}"##
        let placements = try #require(PagePlacements(rawValue: old))
        #expect(placements.choices["aic.ticket"]?.rowOrder == nil)
        #expect(placements.rawValue == old, "written back as it was read")

        var ordered = placements
        ordered.setRowOrder(["repo", "#tags", "repo"], of: Self.ticket)
        #expect(ordered.choices["aic.ticket"]?.rowOrder == ["repo", "#tags"], "each row once")
        #expect(PagePlacements(rawValue: ordered.rawValue) == ordered)
        ordered.setRowOrder(nil, of: Self.ticket)
        #expect(ordered == placements)
    }

    @Test func thePropertyBlockFollowsTheChosenOrderAndRowsNotNamedKeepTheirOrderAfterIt() {
        func row(_ id: String) -> PropertyRow { PropertyRow(id: id, label: id, value: .text(id)) }
        let candidates = ["a", "b", "c", "d"].map(row)
        var placements = PagePlacements()
        placements.setRowOrder(["c", "gone", "a"], of: Self.task)
        let placement = placements.placement(of: Self.task, in: Self.catalogue)
        #expect(PropertyRow.block(candidates, placement: placement).map(\.id) == ["c", "a", "b", "d"])
    }

    @Test func noPinsIsAChoiceThatSurvivesStorage() throws {
        var placements = PagePlacements()
        placements.setPins([], of: Self.task)
        #expect(placements.hasChoice(for: Self.task), "an empty list is not dropped as no choice")
        #expect(placements.pins(of: Self.task, in: Self.catalogue).isEmpty)
        let again = try #require(PagePlacements(rawValue: placements.rawValue))
        #expect(again == placements)
        #expect(again.choices["aic.task"]?.pins == [])
        #expect(again.pins(of: Self.task, in: Self.catalogue).isEmpty)
        #expect(PagePlacements(["aic.task": .init(pins: [])]).hasChoice(for: Self.task))
    }

    @Test func resettingATypeGivesItsDefaultPinsBackToo() {
        var placements = PagePlacements()
        placements.setPins(["#source"], of: Self.task)
        placements.setShown(false, row: "repo", of: Self.ticket)
        placements.reset(Self.task)
        #expect(placements.pins(of: Self.task, in: Self.catalogue) == ["#type", "state", "child-of", "#updated"])
        #expect(!placements.hasChoice(for: Self.task))
        #expect(placements.hasChoice(for: Self.ticket))
    }

    @Test func storedTextThatCannotBeReadIsSetAsideBeforeItIsWrittenOver() throws {
        let suite = "PagePlacementsTests.setAside"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let unreadable = #"{"aic.ticket":{"rows":{"repo":"not a flag"}}}"#
        defaults.set(unreadable, forKey: PagePlacements.key)

        PagePlacements.update(in: defaults) { $0.setShown(false, row: "repo", of: Self.ticket) }
        PagePlacements.update(in: defaults) { $0.setShown(true, row: "repo", of: Self.ticket) }

        #expect(defaults.stringArray(forKey: PagePlacements.setAsideKey) == [unreadable])
        #expect(PagePlacements.stored(in: defaults).choices["aic.ticket"]?.rows == ["repo": true])
    }

    @Test func theTypeSourceAndUpdatedRowsShowOnThePageByDefault() {
        let placement = PagePlacements().placement(of: Self.ticket, in: Self.catalogue)
        for row in ["#type", "#source", "#updated"] { #expect(placement.showsOnPage(row)) }
    }
}
