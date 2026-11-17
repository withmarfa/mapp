import Foundation
import Testing
@testable import MAPP

/// A link shown as a property: Parent, Children and In Collection on a row, a card and a table, and the look file that
/// keeps them.
@MainActor
struct RelationLooksTests {
    private static let specs = LookFixture.specs + [
        LookFixture.make("test.project"), LookFixture.make("test.collection"),
        LookFixture.make("test.work", parent: "core.task"),
    ]
    private static let catalogue: Catalogue = {
        var catalogue = LookFixture.catalogue(specs, edgeTypes: LookFixture.relationEdges)
        return catalogue
    }()
    private static let now = Date(timeIntervalSince1970: 1_794_000_000)

    private static func item(
        _ type: String, _ title: String, parent: ItemID? = nil, collections: [ItemID] = [], state: ItemState = .active,
        problem: ItemProblem? = nil, id: ItemID = .mint()
    ) -> Item {
        var item = Item(
            id: id, type: TypeID(type), title: title, name: title, titleRule: .firstLine, state: state,
            version: ItemVersion(1), created: now, modified: now)
        item.problem = problem
        if let parent {
            item.edgesOut.append(Edge(id: EdgeID(rawValue: "p-\(id.rawValue)"), type: "child-of", source: id, target: .item(parent), origin: .property("parent")))
        }
        for collection in collections {
            item.edgesOut.append(Edge(
                id: EdgeID(rawValue: "c-\(id.rawValue)-\(collection.rawValue)"), type: MarfaMapping.collectionEdge, source: id,
                target: .item(collection), origin: .property("parent")))
        }
        return item
    }

    private static func library(_ items: [Item]) -> FakeItemLibrary {
        let library = FakeItemLibrary(items: items, now: now)
        library.catalogue = catalogue
        return library
    }

    private static let parentFact = TypeLook(date: .off, secondary: [], facts: [.relation(.parent)])
    private static let list = RowList(day: Calendar.current.startOfDay(for: now))

    private static func content(_ item: Item, _ look: TypeLook, in library: FakeItemLibrary) -> RowContent {
        RowContent.make(
            for: item, look: look, catalogue: catalogue, list: list, relations: library.relations(of: item, wanting: look.relations))
    }

    // MARK: The look file

    @Test func theNewWordsRoundTripAndAnOlderFileStillReads() throws {
        let look = TypeLook(
            date: .off, secondary: [.parent], facts: [.relation(.parent), .relation(.children), .relation(.collections), .tags])
        let file = LooksFile(looks: [TypeID("core.task"): look])
        let text = try #require(String(data: file.encoded(), encoding: .utf8))
        #expect(text.contains(#""children""#) && text.contains(#""collections""#))
        #expect(LooksFile.read(Data(text.utf8)) == file)

        let older = #"{"format":"mapp-looks","version":1,"looks":{"core.task":{"date":"field:due_at","secondary":["field:project"],"facts":["field:priority","tags"]}}}"#
        #expect(LooksFile.read(Data(older.utf8))?.looks["core.task"]?.facts == [.field("priority"), .tags])
        let unknown = #"{"format":"mapp-looks","version":1,"looks":{"a":{"date":"none","secondary":[],"facts":["siblings"]}}}"#
        #expect(LooksFile.read(Data(unknown.utf8)) == nil)
    }

    @Test func aStoredChoiceWithRelationsDecodes() throws {
        let choice = TypeLookChoice(facts: [.relation(.children)])
        let data = try JSONEncoder().encode(choice)
        #expect(try JSONDecoder().decode(TypeLookChoice.self, from: data) == choice)
    }

    // MARK: The Task preset

    @Test func aTaskWithNoProjectOrRepositoryFieldFallsBackToItsParent() {
        let look = LookFixture.look("core.task", in: Self.catalogue)
        #expect(look.secondary == [.parent])
        let withRepository = LookFixture.catalogue(
            [LookFixture.make("t.task", [LookFixture.field("status", LookFixture.status), LookFixture.field("repository")])],
            edgeTypes: LookFixture.relationEdges)
        #expect(LookFixture.look("t.task", in: withRepository).secondary == [.field("repository")])
    }

    @Test func noOtherPresetGainsARelation() {
        for id in ["core.note", "core.event", "core.entity.person", "core.message", "core.bookmark"] {
            #expect(LookFixture.look(id, in: Self.catalogue).relations.isEmpty, "\(id)")
        }
    }

    @Test func theTaskRowSaysItsParentOnTheSecondaryLine() {
        let project = Self.item("test.project", "Launch")
        let task = Self.item("core.task", "Write", parent: project.id)
        let library = Self.library([project, task])
        let look = LookFixture.look("core.task", in: Self.catalogue)
        #expect(Self.content(task, look, in: library).secondary == "Launch")
        #expect(Self.content(Self.item("core.task", "Loose"), look, in: library).secondary == nil)
    }

    // MARK: Rows and cards

    @Test func aParentShowsAsALinkedItemChip() {
        let project = Self.item("test.project", "Launch")
        let task = Self.item("core.task", "Write", parent: project.id)
        let library = Self.library([project, task])
        let content = Self.content(task, Self.parentFact, in: library)
        #expect(content.chips == [.linked(icon: nil, title: "Launch")])
        let card = RowContent.card(
            for: task, look: Self.parentFact, catalogue: Self.catalogue, list: Self.list, shape: CardShape(),
            relations: library.relations(of: task, wanting: [.parent]))
        #expect(card.chips == [.linked(icon: nil, title: "Launch")])
    }

    @Test func severalChildrenShowTwoThenACount() {
        let project = Self.item("test.project", "Launch")
        let kids = ["C", "A", "B", "D"].map { Self.item("core.task", $0, parent: project.id) }
        let library = Self.library([project] + kids)
        let look = TypeLook(date: .off, secondary: [], facts: [.relation(.children)])
        let content = Self.content(project, look, in: library)
        #expect(content.chips == [.linked(icon: nil, title: "A"), .linked(icon: nil, title: "B")])
        #expect(content.more == 2)
    }

    @Test func severalCollectionsShowTwoThenACount() {
        let collections = ["One", "Two", "Three"].map { Self.item("test.collection", $0) }
        let note = Self.item("core.note", "N", collections: collections.map(\.id))
        let library = Self.library(collections + [note])
        let look = TypeLook(date: .off, secondary: [], facts: [.relation(.collections)])
        let content = Self.content(note, look, in: library)
        #expect(content.chips == [.linked(icon: nil, title: "One"), .linked(icon: nil, title: "Three")])
        #expect(content.more == 1)
    }

    @Test func aParentInTheBinOneUnreadableOrOutsideTheCopyShowsNothing() {
        let binned = Self.item("test.project", "Gone", state: .trashed)
        let unreadable = Self.item("test.project", "Secret", problem: ItemProblem(message: "key"))
        let absent = ItemID.mint()
        let items = [binned, unreadable]
        let library = Self.library(items)
        for parent in [binned.id, unreadable.id, absent] {
            let task = Self.item("core.task", "T", parent: parent)
            let content = Self.content(task, Self.parentFact, in: library)
            #expect(content.chips.isEmpty && content.more == 0)
            #expect(content.spoken.contains(parent.rawValue) == false)
        }
        let task = Self.item("core.task", "T", parent: binned.id)
        #expect(Self.content(task, LookFixture.look("core.task", in: Self.catalogue), in: library).secondary == nil)
    }

    @Test func noParentAndNoChildrenLeaveNoGap() {
        let lone = Self.item("test.project", "Lone")
        let library = Self.library([lone])
        let look = TypeLook(date: .off, secondary: [], facts: [.relation(.parent), .relation(.children)])
        let content = Self.content(lone, look, in: library)
        #expect(content.chips.isEmpty && content.more == 0)
    }

    @Test func aRenamedParentRefreshesItsChildrensRowsAndOnlyThem() {
        let project = Self.item("test.project", "Launch")
        let task = Self.item("core.task", "Write", parent: project.id)
        let other = Self.item("core.task", "Other")
        let library = Self.library([project, task, other])
        let looks = [TypeID("core.task"): Self.parentFact]
        let contents = RowContents()
        let entries = [task, other].map { RowContents.Entry(item: $0, showsTime: false) }
        #expect(contents.contents(of: entries, in: library, looks: looks, list: Self.list)[task.id]?.chips == [.linked(icon: nil, title: "Launch")])
        let builds = contents.builds
        #expect(contents.contents(of: entries, in: library, looks: looks, list: Self.list)[task.id] != nil)
        #expect(contents.builds == builds, "a pass that changes nothing builds nothing")

        var renamed = project
        renamed.title = "Ship"
        renamed.name = "Ship"
        library.items = [renamed, task, other]
        #expect(contents.contents(of: entries, in: library, looks: looks, list: Self.list)[task.id]?.chips == [.linked(icon: nil, title: "Ship")])

        library.items = [task, other]
        #expect(contents.contents(of: entries, in: library, looks: looks, list: Self.list)[task.id]?.chips.isEmpty == true)
    }

    @Test func aCardsContentRefreshesWhenAChildComesOrGoes() {
        let project = Self.item("test.project", "Launch")
        let library = Self.library([project])
        let looks = [TypeID("test.project"): TypeLook(date: .off, secondary: [], facts: [.relation(.children)])]
        let cards = CardContents()
        #expect(cards.contents(of: [project], in: library, looks: looks, list: Self.list, shape: CardShape())[project.id]?.chips.isEmpty == true)
        library.items.append(Self.item("core.task", "New", parent: project.id))
        #expect(cards.contents(of: [project], in: library, looks: looks, list: Self.list, shape: CardShape())[project.id]?.chips == [.linked(icon: nil, title: "New")])
    }

    // MARK: The table

    @Test func theTableOffersTheThreeColumnsAndShowsTheOnesALookAsksFor() {
        let project = Self.item("test.project", "Launch")
        let task = Self.item("core.task", "Write", parent: project.id)
        let library = Self.library([project, task])
        let rows = ItemTableRow.rows(of: [project, task], in: library)
        #expect(rows[0].children.map(\.title) == ["Write"])
        #expect(rows[1].parent?.title == "Launch")

        let plain = ItemTableLayout.columns(for: rows, catalogue: Self.catalogue, hidden: [], looks: [:])
        for id in ["parent", "children", "collections"] {
            #expect(plain.first { $0.id == id }?.isShownByDefault == false, "\(id) waits behind View Options")
        }
        #expect(plain.first { $0.id == "parent" }?.label == "Parent")
        #expect(plain.first { $0.id == "children" }?.label == "Children")
        #expect(plain.first { $0.id == "collections" }?.label == "In Collection")

        let looks = [
            TypeID("test.project"): TypeLook(date: .off, secondary: [], facts: [.relation(.children), .relation(.collections)]),
            TypeID("core.task"): Self.parentFact,
        ]
        let shown = ItemTableLayout.columns(for: rows, catalogue: Self.catalogue, hidden: [], looks: looks)
            .filter(\.isShownByDefault).map(\.id)
        #expect(shown.contains("children") && shown.contains("parent"))
        #expect(!shown.contains("collections"), "a column no row fills starts hidden")
        #expect(shown.filter { $0 == "parent" }.count == 1)
    }
}
