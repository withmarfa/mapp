import Foundation
import Marfa
import Testing
@testable import MAPP

/// The right sidebar's sections, chosen for each type with Customize Layout and kept with the page's own choices.
struct SidebarSectionsTests {
    private static let ticket = TypeID("aic.ticket")
    private static let other = TypeID("aic.other")
    private static let person = TypeID("core.entity.person")
    private static let catalogue = Catalogue(itemTypes: [
        MarfaMapping.itemType(ItemType(id: "aic.ticket", label: "Ticket", fields: [], titleField: nil)),
        MarfaMapping.itemType(ItemType(id: "aic.other", label: "Other", fields: [], titleField: nil)),
        MarfaMapping.itemType(ItemType(id: "core.entity.person", label: "Person", fields: [], icon: "lucide:user")),
    ])
    private static let defaults = ["details", "properties", "relationships", "links-in-page", "#linked", "tags"]

    @Test func aTypeWithNoChoiceShowsTodaysSections() {
        let placements = PagePlacements()
        #expect(placements.sidebarSections(of: Self.ticket, in: Self.catalogue) == Self.defaults)
        #expect(!placements.hasChoice(for: Self.ticket))
    }

    @Test func aPersonsLinkedFromStaysOnThePageSoTheSidebarLeavesItOut() {
        let sections = PagePlacements().sidebarSections(of: Self.person, in: Self.catalogue)
        #expect(sections == Self.defaults.filter { $0 != "#linked" })
    }

    @Test func removingASectionKeepsTheOthersInOrder() {
        var placements = PagePlacements()
        placements.removeSidebarSection("relationships", of: Self.ticket, in: Self.catalogue)
        #expect(placements.sidebarSections(of: Self.ticket, in: Self.catalogue) == ["details", "properties", "links-in-page", "#linked", "tags"])
        #expect(!placements.hasChoice(for: Self.other))
    }

    @Test func addingASectionPutsItLastAndOnceOnly() {
        var placements = PagePlacements()
        placements.addSidebarSection("outline", of: Self.ticket, in: Self.catalogue)
        placements.addSidebarSection("outline", of: Self.ticket, in: Self.catalogue)
        #expect(placements.sidebarSections(of: Self.ticket, in: Self.catalogue) == Self.defaults + ["outline"])
    }

    @Test func movingASectionOrdersIt() {
        var placements = PagePlacements()
        placements.moveSidebarSection("tags", to: 0, of: Self.ticket, in: Self.catalogue)
        #expect(placements.sidebarSections(of: Self.ticket, in: Self.catalogue).first == "tags")
        placements.moveSidebarSection("tags", to: 99, of: Self.ticket, in: Self.catalogue)
        #expect(placements.sidebarSections(of: Self.ticket, in: Self.catalogue).last == "tags")
    }

    @Test func anOrderEqualToTheDefaultIsNotKept() {
        var placements = PagePlacements()
        placements.removeSidebarSection("tags", of: Self.ticket, in: Self.catalogue)
        placements.addSidebarSection("tags", of: Self.ticket, in: Self.catalogue)
        #expect(!placements.hasChoice(for: Self.ticket))
    }

    @Test func eachTypeKeepsItsOwnSections() {
        var placements = PagePlacements()
        placements.removeSidebarSection("tags", of: Self.ticket, in: Self.catalogue)
        #expect(placements.sidebarSections(of: Self.other, in: Self.catalogue) == Self.defaults)
    }

    // MARK: Linked From has one place

    @Test func removingLinkedFromFromTheSidebarPutsItOnThePage() {
        var placements = PagePlacements()
        placements.removeSidebarSection("#linked", of: Self.ticket, in: Self.catalogue)
        let placement = placements.placement(of: Self.ticket, in: Self.catalogue)
        #expect(placement.linkedFromPlace == .page)
        #expect(!placement.sidebarSections.contains("#linked"))
    }

    @Test func addingLinkedFromToTheSidebarTakesItOffThePage() {
        var placements = PagePlacements()
        placements.setLinkedFrom(.page, of: Self.ticket)
        #expect(!placements.sidebarSections(of: Self.ticket, in: Self.catalogue).contains("#linked"))
        placements.addSidebarSection("#linked", of: Self.ticket, in: Self.catalogue)
        #expect(placements.placement(of: Self.ticket, in: Self.catalogue).linkedFromPlace == .inspector)
        #expect(placements.sidebarSections(of: Self.ticket, in: Self.catalogue).last == "#linked")
    }

    @Test func showingLinkedFromOnThePageRemovesItFromTheSidebar() {
        var placements = PagePlacements()
        placements.removeSidebarSection("tags", of: Self.ticket, in: Self.catalogue)
        placements.set(true, row: PagePlacement.linkedFrom, of: Self.ticket)
        #expect(placements.sidebarSections(of: Self.ticket, in: Self.catalogue) == ["details", "properties", "relationships", "links-in-page"])
    }

    @Test func hidingLinkedFromFromThePageBringsItBackToTheSidebarWhereItWas() {
        var placements = PagePlacements()
        placements.moveSidebarSection("#linked", to: 0, of: Self.ticket, in: Self.catalogue)
        placements.set(true, row: PagePlacement.linkedFrom, of: Self.ticket)
        placements.set(false, row: PagePlacement.linkedFrom, of: Self.ticket)
        #expect(placements.sidebarSections(of: Self.ticket, in: Self.catalogue).first == "#linked")
    }

    // MARK: Storage

    @Test func aChoiceSavedBeforeTheSidebarExistedReadsAsTheDefault() throws {
        let stored = PagePlacements(rawValue: ##"{"aic.ticket":{"pins":["#type"],"rows":{}}}"##)
        let placements = try #require(stored)
        #expect(placements.sidebarSections(of: Self.ticket, in: Self.catalogue) == Self.defaults)
    }

    @Test func theSectionsSurviveTheStoredText() throws {
        var placements = PagePlacements()
        placements.addSidebarSection("app:aic.pr|github", of: Self.ticket, in: Self.catalogue)
        let again = try #require(PagePlacements(rawValue: placements.rawValue))
        #expect(again.sidebarSections(of: Self.ticket, in: Self.catalogue).last == "app:aic.pr|github")
    }

    @Test func resettingATypeGivesItsSectionsBack() {
        var placements = PagePlacements()
        placements.removeSidebarSection("tags", of: Self.ticket, in: Self.catalogue)
        placements.reset(Self.ticket)
        #expect(placements.sidebarSections(of: Self.ticket, in: Self.catalogue) == Self.defaults)
    }

    @Test func aSectionIdentifierReadsBackAsTheSameSection() {
        let sections: [SidebarSection] = SidebarSection.builtIn + [.app(type: Self.ticket, source: "github")]
        for section in sections {
            #expect(SidebarSection(id: section.id) == section)
        }
        #expect(SidebarSection(id: "nonsense") == nil)
        #expect(SidebarSection(id: "app:only-a-type") == nil)
    }

    // MARK: Outline

    @Test func theOutlineListsHeadingsByLevelAndSkipsCodeAndFrontMatter() {
        let text = """
            ---
            # not a heading
            ---
            # Title
            Words.
            ## Context ##
            ```
            # in code
            ```
            #hashtag
            ####### too deep
            ### Third level
            """
        let headings = OutlineHeading.headings(in: text)
        #expect(headings.map(\.text) == ["Title", "Context", "Third level"])
        #expect(headings.map(\.level) == [1, 2, 3])
    }

    @Test func aNoteWithoutHeadingsHasNoOutline() {
        #expect(OutlineHeading.headings(in: "just words\n\nand more").isEmpty)
        #expect(OutlineHeading.headings(in: "").isEmpty)
    }
}
