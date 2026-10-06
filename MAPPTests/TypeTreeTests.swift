import Foundation
import Testing
@testable import MAPP

struct TypeTreeTests {
    @Test func parentsComeBeforeTheirChildrenInLabelOrder() {
        let rows = TypeTree.flattened(TypeTree.nodes(in: TypesFixtures.catalogue))
        #expect(rows.map(\.type.label) == [
            "Album", "Live Album", "Bug", "Contact", "Entity", "Person", "File", "Image", "Raw Image", "PDF"
        ])
        #expect(rows.map(\.depth) == [0, 1, 0, 0, 0, 1, 0, 1, 2, 1])
        for (index, row) in rows.enumerated() {
            guard let parent = rows.firstIndex(where: { $0.type.id == row.type.parent }) else { continue }
            #expect(parent < index)
        }
    }

    @Test func eachTypeCountsItsDirectSubtypes() throws {
        let nodes = TypeTree.nodes(in: TypesFixtures.catalogue)
        let file = try #require(nodes.first { $0.type.label == "File" })
        #expect(file.subtypeCount == 2)
        #expect(file.children?.map(\.type.label) == ["Image", "PDF"])
        let image = try #require(file.children?.first)
        #expect(image.subtypeCount == 1)
        let raw = try #require(image.children?.first)
        #expect(raw.subtypeCount == 0 && raw.children == nil)
    }

    @Test func aTypeWhoseParentIsMissingStandsAtTheTop() throws {
        let nodes = TypeTree.nodes(in: TypesFixtures.catalogue)
        let bug = try #require(nodes.first { $0.type.id == TypeID("aic.ticket.bug") })
        #expect(bug.depth == 0)
    }

    @Test func aSearchCountsSubtypesAsTheCatalogueHasThem() throws {
        let nodes = TypeTree.nodes(in: TypesFixtures.catalogue, matching: TypeQuery("raw"))
        let file = try #require(nodes.first)
        #expect(file.type.label == "File" && file.subtypeCount == 2)
        #expect(file.children?.map(\.type.label) == ["Image"])
    }

    @Test func aLoopOfParentsIsShownOnceAndNeverEndlessly() {
        let catalogue = Catalogue(itemTypes: [
            TypesFixtures.type("a.one", "One", parent: "a.two"),
            TypesFixtures.type("a.two", "Two", parent: "a.one"),
            TypesFixtures.type("a.self", "Self", parent: "a.self")
        ])
        let rows = TypeTree.flattened(TypeTree.nodes(in: catalogue))
        #expect(rows.map(\.type.label).sorted() == ["One", "Self", "Two"])
        #expect(Set(rows.map(\.type.id)).count == 3)
    }

    @Test func anEmptyCatalogueHasNoRows() {
        #expect(TypeTree.nodes(in: Catalogue()).isEmpty)
    }

    @Test func labelsSortTheWayPeopleReadThemWithTheIdBreakingTies() {
        let catalogue = Catalogue(itemTypes: [
            TypesFixtures.type("a.b", "Item 10"), TypesFixtures.type("a.a", "Item 2"),
            TypesFixtures.type("a.d", "Same"), TypesFixtures.type("a.c", "Same")
        ])
        #expect(TypeTree.nodes(in: catalogue).map(\.type.id.rawValue) == ["a.a", "a.b", "a.c", "a.d"])
    }

    @Test func aBlankQueryIsNoQuery() {
        #expect(TypeQuery("") == nil)
        #expect(TypeQuery(" \n") == nil)
        #expect(TypeQuery(" file ") != nil)
    }
}
