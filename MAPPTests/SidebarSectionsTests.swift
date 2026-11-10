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

    @Test func linkedFromBroughtBackToItsDefaultPlaceIsNotKept() {
        var placements = PagePlacements()
        placements.removeSidebarSection("#linked", of: Self.ticket, in: Self.catalogue)
        #expect(placements.hasChoice(for: Self.ticket))
        // Added back it goes last, which is a choice of order; moved to its default place nothing is left to keep.
        placements.addSidebarSection("#linked", of: Self.ticket, in: Self.catalogue)
        placements.moveSidebarSection("#linked", to: 4, of: Self.ticket, in: Self.catalogue)
        #expect(placements.sidebarSections(of: Self.ticket, in: Self.catalogue) == Self.defaults)
        #expect(!placements.hasChoice(for: Self.ticket))
        // A person's Linked From is on the page by default, so adding it to the sidebar and removing it again is no choice.
        placements.addSidebarSection("#linked", of: Self.person, in: Self.catalogue)
        #expect(placements.hasChoice(for: Self.person))
        placements.removeSidebarSection("#linked", of: Self.person, in: Self.catalogue)
        #expect(!placements.hasChoice(for: Self.person))
    }

    @Test func aStoredIdThatNamesNoSectionIsLeftOutSoMovesAndTheViewAgree() throws {
        let stored = ##"{"aic.ticket":{"rows":{},"sidebar":["tags","gone","details"]}}"##
        var placements = try #require(PagePlacements(rawValue: stored))
        #expect(placements.sidebarSections(of: Self.ticket, in: Self.catalogue).filter { SidebarSection(id: $0) == nil }.isEmpty)
        placements.moveSidebarSection("details", to: 0, of: Self.ticket, in: Self.catalogue)
        #expect(placements.sidebarSections(of: Self.ticket, in: Self.catalogue).first == "details")
        #expect(placements.sidebarSections(of: Self.ticket, in: Self.catalogue).contains("tags"))
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
        placements.setLinkedFrom(.page, of: Self.ticket, in: Self.catalogue)
        #expect(!placements.sidebarSections(of: Self.ticket, in: Self.catalogue).contains("#linked"))
        placements.addSidebarSection("#linked", of: Self.ticket, in: Self.catalogue)
        #expect(placements.placement(of: Self.ticket, in: Self.catalogue).linkedFromPlace == .inspector)
        #expect(placements.sidebarSections(of: Self.ticket, in: Self.catalogue).last == "#linked")
    }

    @Test func showingLinkedFromOnThePageRemovesItFromTheSidebar() {
        var placements = PagePlacements()
        placements.removeSidebarSection("tags", of: Self.ticket, in: Self.catalogue)
        placements.set(true, row: PagePlacement.linkedFrom, of: Self.ticket, in: Self.catalogue)
        #expect(placements.sidebarSections(of: Self.ticket, in: Self.catalogue) == ["details", "properties", "relationships", "links-in-page"])
    }

    @Test func hidingLinkedFromFromThePageBringsItBackToTheSidebarWhereItWas() {
        var placements = PagePlacements()
        placements.moveSidebarSection("#linked", to: 0, of: Self.ticket, in: Self.catalogue)
        placements.set(true, row: PagePlacement.linkedFrom, of: Self.ticket, in: Self.catalogue)
        placements.set(false, row: PagePlacement.linkedFrom, of: Self.ticket, in: Self.catalogue)
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

    private func headingsMessage(_ entries: [(Int, String)], generation: Int = 3) -> [String: Any] {
        ["type": "headings", "headings": entries.map { ["level": $0.0, "text": $0.1] }, "generation": generation]
    }

    @Test func thePagesHeadingsDecodeWithTheirPlaceInItsList() throws {
        let message = try #require(EditorMessage(body: headingsMessage([(1, "Soil"), (2, "Soil"), (3, "Water")])))
        guard case .headings(let headings, let generation) = message else { Issue.record("Not headings"); return }
        #expect(generation == 3)
        #expect(headings.map(\.text) == ["Soil", "Soil", "Water"])
        #expect(headings.map(\.level) == [1, 2, 3])
        #expect(headings.map(\.index) == [0, 1, 2])
        #expect(Set(headings.map(\.id)).count == 3)
    }

    @Test func aHeadingWithNoWordsIsCountedButNotListed() throws {
        let message = try #require(EditorMessage(body: headingsMessage([(1, ""), (1, "  "), (1, "Next")])))
        guard case .headings(let headings, _) = message else { Issue.record("Not headings"); return }
        #expect(headings.map(\.text) == ["Next"])
        #expect(headings.map(\.index) == [2])
    }

    @Test func aPageWithNoHeadingsReportsAnEmptyList() throws {
        guard case .headings(let headings, _) = try #require(EditorMessage(body: headingsMessage([]))) else { Issue.record("Not headings"); return }
        #expect(headings.isEmpty)
    }

    @Test func aMalformedHeadingsMessageIsRefused() {
        #expect(EditorMessage(body: ["type": "headings", "generation": 1]) == nil)
        #expect(EditorMessage(body: ["type": "headings", "headings": [["level": 1]], "generation": 1]) == nil)
        #expect(EditorMessage(body: ["type": "headings", "headings": [["level": 1, "text": "A"]]]) == nil)
    }

    @Test func aListForAnEarlierLoadIsKeptForNothing() {
        let heading = OutlineHeading(level: 1, text: "Soil", index: 0)
        let note = ItemID("note")
        #expect(PageOutline.accepting([heading], generation: 2, current: 3, item: note) == nil)
        #expect(PageOutline.accepting([heading], generation: 3, current: 3, item: nil) == nil)
        #expect(PageOutline.accepting([heading], generation: 3, current: 3, item: note) == PageOutline(item: note, generation: 3, headings: [heading]))
    }

    @Test func theOutlineListsHeadingsOnlyForTheItemOnThePage() {
        let heading = OutlineHeading(level: 1, text: "Soil", index: 0)
        let outline = PageOutline(item: ItemID("note"), generation: 3, headings: [heading])
        #expect(outline.headings(for: ItemID("note")) == [heading])
        #expect(outline.headings(for: ItemID("other")).isEmpty)
    }

    // MARK: What the sections read from the library

    private static let pageHeadings = [OutlineHeading(level: 1, text: "Soil", index: 0), OutlineHeading(level: 1, text: "Soil", index: 1)]

    @MainActor private static func fixture() -> (library: FakeItemLibrary, note: MAPP.Item, relationships: [ItemRelationship]) {
        let pr = TypeID("test.pr")
        let library = FakeItemLibrary()
        library.catalogue = Catalogue(itemTypes: Array(FakeItemLibrary.testCatalogue.itemTypes.values) + [
            ItemTypeInfo(id: pr, label: "Pull Request", plural: "Pull Requests", fields: [], titleField: "title", bodyField: nil, parent: nil, linkField: "github_id"),
        ], edgeTypes: Array(FakeItemLibrary.testCatalogue.edgeTypes.values))
        library.sources = SourceDirectory(infos: ["gh": SourceInfo(code: "gh", name: "GitHub", mark: nil, hasChosenName: true)])
        let note = library.add("# Soil\n\ntext\n\n# Soil\n")
        var collection = FakeItemLibrary.collection("Garden")
        collection.name = "Garden"
        library.items.append(collection)
        library.items[library.items.firstIndex { $0.id == note.id }!].edgesOut = [
            Edge(id: EdgeID("c"), type: MarfaMapping.collectionEdge, source: note.id, target: .item(collection.id), origin: .property("in-collection")),
        ]
        func pull(_ title: String, source: String?) -> MAPP.Item {
            var item = FakeItemLibrary.note(title, modified: .distantPast)
            item.type = pr
            item.source = source
            library.items.append(item)
            return item
        }
        let fromApp = pull("Fix soil", source: "gh")
        let second = pull("Fix water", source: "gh")
        let noSource = pull("Local pull request", source: nil)
        let plainNote = library.add("Plain note")
        func target(_ item: MAPP.Item) -> ItemRelationshipTarget {
            ItemRelationshipTarget(title: item.name ?? "", itemID: item.id, resolution: .resolved(item.id))
        }
        let relationships = [ItemRelationship(
            field: "related", label: "Related", targets: [fromApp, second, noSource, plainNote, fromApp].map(target), isEditable: true, allowsMultiple: true)]
        return (library, library.item(note.id)!, relationships)
    }

    @MainActor @Test func theExtrasGroupAnAppsItemsByTypeAndSourceFromRealLinksOnly() {
        let (library, note, relationships) = Self.fixture()
        let extras = SidebarExtras.of(note, in: library, relationships: relationships, outline: Self.pageHeadings)
        #expect(extras.apps.map(\.title) == ["Pull Requests (GitHub)"])
        // Each item once, and neither one with no source nor a note with no link field.
        #expect(extras.apps.first?.targets.map(\.title) == ["Fix soil", "Fix water"])
        #expect(extras.outline.map(\.text) == ["Soil", "Soil"])
        #expect(extras.collections.map(\.title) == ["Garden"])
        #expect(extras.count(of: .app(type: TypeID("test.pr"), source: "gh")) == 2)
    }

    @MainActor @Test func theExtrasReadOnlyTheSectionsAskedFor() {
        let (library, note, relationships) = Self.fixture()
        let outlineOnly = SidebarExtras.of(note, in: library, relationships: relationships, sections: [.outline], outline: Self.pageHeadings)
        #expect(outlineOnly.outline.count == 2)
        #expect(outlineOnly.count(of: .outline) == 2)
        #expect(outlineOnly.collections.isEmpty)
        #expect(outlineOnly.apps.isEmpty)
        let none = SidebarExtras.of(note, in: library, relationships: relationships, sections: [.details], outline: Self.pageHeadings)
        #expect(none.outline.isEmpty)
    }

    @MainActor @Test func theOutlineHasNoRowsUntilThePageHasReportedForTheItem() {
        let (library, note, relationships) = Self.fixture()
        let extras = SidebarExtras.of(note, in: library, relationships: relationships)
        #expect(extras.outline.isEmpty)
        #expect(extras.count(of: .outline) == 0)
    }
}
