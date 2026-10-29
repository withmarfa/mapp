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
        MarfaMapping.itemType(ItemType(id: "core.entity.person", label: "Person", fields: [], icon: "user")),
        MarfaMapping.itemType(ItemType(id: "aic.folder", label: "Folder", fields: [], roles: [MarfaMapping.containerRole])),
    ])

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
        // The link field is each type's own, never an inherited or sibling's: a type that names none shows it.
        #expect(placements.placement(of: Self.ticket, in: Self.catalogue).showsOnPage("github_id"))
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
        placements.setLinkedFrom(.page, of: Self.ticket)
        placements.setLinkedFrom(.inspector, of: Self.person)
        #expect(placements.placement(of: Self.comment, in: Self.catalogue).showsOnPage("github_id"))
        let ticket = placements.placement(of: Self.ticket, in: Self.catalogue)
        #expect(!ticket.showsOnPage("repo"))
        #expect(ticket.isChosen("repo"))
        #expect(!ticket.isChosen("github_id"))
        #expect(ticket.linkedFromPlace == .page)
        #expect(placements.placement(of: Self.person, in: Self.catalogue).linkedFromPlace == .inspector)
    }

    @Test func aChoiceForOneTypeLeavesEveryOtherTypeAlone() {
        var placements = PagePlacements()
        placements.setShown(false, row: "repo", of: Self.ticket)
        placements.setLinkedFrom(.page, of: Self.ticket)
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
        placements.setLinkedFrom(.page, of: Self.comment)
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
                of: item, type: type, hidden: ["title"], relationships: [], parentField: "child-of", tags: tags,
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
                parentField: "child-of", tags: [], placement: placements.placement(of: Self.ticket, in: Self.catalogue)
            ).map(\.id)
        }
        #expect(rows(PagePlacements()) == ["child-of", "about"])
        var placements = PagePlacements()
        placements.setShown(false, row: "child-of", of: Self.ticket)
        placements.setShown(false, row: "about", of: Self.ticket)
        #expect(rows(placements).isEmpty)
    }
}
