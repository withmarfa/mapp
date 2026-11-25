import Foundation
import Testing
@testable import MarfaMac

/// What an item's page lists at its foot: a person or a place with hundreds of mentions shows 30 and pages by 30, and
/// sub-items nest with a Show More of their own.
@MainActor
@Suite struct PageFootTests {
    private static let place = TypeID("core.entity.place")
    private static let noon = Date(timeIntervalSince1970: 1_800_000_000)

    private static func library() -> FakeItemLibrary {
        let library = FakeItemLibrary(now: noon)
        let types = Array(FakeItemLibrary.testCatalogue.itemTypes.values)
            + [ItemTypeInfo(id: place, label: "Place", fields: [], titleField: "title", bodyField: nil, parent: nil)]
        library.catalogue = Catalogue(itemTypes: types, edgeTypes: Array(FakeItemLibrary.testCatalogue.edgeTypes.values))
        return library
    }

    private static func foot(of item: Item, in library: FakeItemLibrary, limits: PageFoot.Limits = [:]) -> PageFoot {
        PageFoot.of(
            item, in: library, relationships: library.relationships(for: item.id), showsLinkedFrom: true, limits: limits,
            format: .standard, now: noon, calendar: Calendar(identifier: .gregorian), locale: Locale(identifier: "en_GB"))
    }

    @Test func aPlaceWithHundredsOfMentionsShowsThirtyThenPagesByThirtyNewestFirst() throws {
        let library = Self.library()
        let place = Item(
            id: .mint(), type: Self.place, title: "Calverts", name: "Calverts", titleRule: .property("title"), version: ItemVersion(1), created: .distantPast,
            modified: .distantPast)
        library.items.append(place)
        let mentions = (0..<143).map { index in
            FakeItemLibrary.note("Mention \(index)", modified: Self.noon.addingTimeInterval(Double(index) * 60))
        }
        library.items += mentions
        library.relationshipsByItem[place.id] = [
            ItemRelationship(
                field: "inverse:references", label: "Referenced By",
                targets: mentions.map { ItemRelationshipTarget(title: $0.title, itemID: $0.id, resolution: .resolved($0.id)) },
                isEditable: false)
        ]

        let first = try #require(Self.foot(of: place, in: library).sections.first)
        #expect(first.kind == .timeline)
        #expect(first.total == 143)
        #expect(first.rows.count == PageFoot.step)
        #expect(first.hidden == 143 - PageFoot.step)
        #expect(first.rows.first?.title == "Mention 142", "the newest mention leads")

        let more = try #require(Self.foot(of: place, in: library, limits: ["timeline": 2 * PageFoot.step]).sections.first)
        #expect(more.rows.count == 2 * PageFoot.step)
        #expect(more.hidden == 143 - 2 * PageFoot.step)

        let all = try #require(Self.foot(of: place, in: library, limits: ["timeline": 500]).sections.first)
        #expect(all.rows.count == 143)
        #expect(all.hidden == 0)
    }

    @Test func subItemsNestAndEachListPagesOnItsOwn() throws {
        let library = Self.library()
        let project = Item(
            id: .mint(), type: TypeID("test.project"), title: "Zine", name: "Zine", titleRule: .property("title"), version: ItemVersion(1),
            created: .distantPast, modified: .distantPast)
        library.items.append(project)
        func child(_ title: String, of parent: ItemID) -> Item {
            let id = ItemID.mint()
            let item = Item(
                id: id, type: TypeID("core.task"), title: title, name: title, titleRule: .property("title"),
                version: ItemVersion(1), created: .distantPast, modified: .distantPast,
                edgesOut: [Edge(id: EdgeID("child-of-\(id.rawValue)"), type: "child-of", from: id, to: .item(parent), origin: .property("child-of"))])
            library.items.append(item)
            return item
        }
        let print = child("Print", of: project.id)
        for index in 0..<(PageFoot.step + 5) { _ = child("Check \(index)", of: print.id) }
        _ = child("Reply", of: project.id)

        let section = try #require(Self.foot(of: project, in: library).sections.first)
        #expect(section.kind == .subItems)
        #expect(section.total == PageFoot.step + 5 + 2, "everything beneath the item counts, sub-items of sub-items included")
        #expect(section.rows.map(\.title) == ["Print", "Reply"])
        let printed = try #require(section.rows.first)
        #expect(printed.children.count == PageFoot.step)
        #expect(printed.hiddenChildren == 5)
        #expect(printed.key == "sub:" + print.id.rawValue)

        let paged = try #require(Self.foot(of: project, in: library, limits: [printed.key: 2 * PageFoot.step]).sections.first?.rows.first)
        #expect(paged.children.count == PageFoot.step + 5)
        #expect(paged.hiddenChildren == 0)
    }
}
