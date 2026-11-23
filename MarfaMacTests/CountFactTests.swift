import Foundation
import Testing
@testable import MarfaMac

/// A count on a type's look: its words, what it says, what Marfa is asked, and how a row, a card and the table draw
/// it only once Marfa has answered.
@MainActor
@Suite(.hangLimit) struct CountFactTests {
    private static let specs = LookFixture.specs + [LookFixture.make("test.collection")]
    private static let catalogue = LookFixture.catalogue(specs, edgeTypes: LookFixture.relationEdges)
    private static let now = Date(timeIntervalSince1970: 1_794_000_000)
    private static let list = RowList(day: Calendar.current.startOfDay(for: now))

    private static func item(
        _ type: String, _ title: String, status: String? = nil, parent: ItemID? = nil, collection: ItemID? = nil,
        state: ItemState = .active, id: ItemID = .mint()
    ) -> Item {
        var item = Item(
            id: id, type: TypeID(type), title: title, name: title, titleRule: .firstLine, state: state,
            version: ItemVersion(1), created: now, modified: now)
        if let status { item.properties.append(Property(key: "status", value: .string(status))) }
        if let parent {
            item.edgesOut.append(Edge(id: EdgeID(rawValue: "p-\(id.rawValue)"), type: "child-of", from: id, to: .item(parent), origin: .property("parent")))
        }
        if let collection {
            item.edgesOut.append(Edge(
                id: EdgeID(rawValue: "c-\(id.rawValue)"), type: MarfaMapping.collectionEdge, from: id, to: .item(collection),
                origin: .property("parent")))
        }
        return item
    }

    private static func library(_ items: [Item]) -> FakeItemLibrary {
        let library = FakeItemLibrary(items: items, now: now)
        library.catalogue = catalogue
        return library
    }

    private static let progress = TypeLook(date: .off, secondary: [], facts: [.count(.progress)])

    // MARK: The fact

    @Test func theWordsRoundTripAndANewerWordMakesTheLookUnreadable() throws {
        let facts: [CountFact] = [.children, .progress, .members, .rows(table: "messages")]
        for fact in facts { #expect(CountFact(word: fact.word) == fact) }
        let look = TypeLook(date: .off, secondary: [], facts: facts.map(LookFact.count) + [.tags])
        let file = LooksFile(looks: [TypeID("core.task"): look])
        #expect(LooksFile.read(try file.encoded()) == file)
        #expect(CountFact(word: "count:rows:") == nil)
        let unknown = #"{"format":"mapp-looks","version":1,"looks":{"a":{"date":"none","secondary":[],"facts":["count:siblings"]}}}"#
        #expect(LooksFile.read(Data(unknown.utf8)) == nil)
    }

    @Test func theTaskPresetCarriesProgressOnItsBottomLine() {
        let look = LookPreset.task.look(for: TypeID("core.task"), in: Self.catalogue)
        #expect(look.facts.first == .count(.progress))
        #expect(look.counts == [.progress])
    }

    @Test func aTypeOffersTheCountsItCanHold() {
        let task = LookSurface(TypeID("core.task"), in: Self.catalogue)
        let collection = LookSurface(TypeID("test.collection"), in: Self.catalogue)
        #expect(task.offers(.count(.children)) && task.offers(.count(.progress)))
        #expect(collection.isCollection == collection.offers(.count(.members)))
        #expect(!LookSurface(TypeID("core.note"), in: Self.catalogue).offers(.count(.members)))
    }

    // MARK: What it says

    @Test func progressCountsCompletedAndCanceledAsDoneAndAnItemWithNoStatusOnlyInTheTotal() {
        let groups = ItemCountAnswer.Groups(notStarted: 3, inProgress: 1, completed: 2, canceled: 1)
        let answer = ItemCountAnswer(total: 8, groups: groups)
        #expect(groups.finished == 3 && groups.withStatus == 7)
        #expect(CountWording.text(of: .progress, answer: answer, hasStatus: true) == "3 of 7 done")
        #expect(CountWording.text(of: .children, answer: answer, hasStatus: true) == "8 subtasks")
        #expect(CountWording.text(of: .children, answer: answer, hasStatus: false) == "8 items")
        #expect(CountWording.help(of: .progress, answer: answer) == "2 completed, 1 canceled, 1 in progress, 3 not started, 1 with no status")
    }

    @Test func aCountWithNothingToSayIsEmptyNeverAZeroOrAGuess() {
        #expect(CountWording.text(of: .children, answer: nil, hasStatus: true) == nil)
        #expect(CountWording.text(of: .children, answer: ItemCountAnswer(total: 0, groups: .init()), hasStatus: true) == nil)
        #expect(CountWording.text(of: .progress, answer: ItemCountAnswer(total: 2, groups: .init()), hasStatus: true) == nil)
        #expect(CountWording.text(of: .rows(table: "messages"), answer: nil, hasStatus: false) == nil)
        #expect(CountWording.help(of: .progress, answer: nil) == nil)
    }

    @Test func aRowCountKeepsTheTableName() {
        let many = ItemCountAnswer(total: 214, groups: nil)
        let one = ItemCountAnswer(total: 1, groups: nil)
        #expect(CountWording.text(of: .rows(table: "messages"), answer: many, hasStatus: false) == "214 messages")
        #expect(CountWording.text(of: .rows(table: "entries"), answer: one, hasStatus: false) == "1 row in entries")
        #expect(CountWording.help(of: .rows(table: "messages"), answer: many) == nil)
    }

    // MARK: Row, card and table

    @Test func aRowDrawsFirstWithoutTheCountAndThenSaysItOnceMarfaAnswers() async throws {
        let project = Self.item("core.task", "Project", status: "todo")
        let library = Self.library([
            project, Self.item("core.task", "A", status: "done", parent: project.id),
            Self.item("core.task", "B", status: "todo", parent: project.id),
            Self.item("core.task", "Gone", status: "done", parent: project.id, state: .trashed),
        ])
        let contents = RowContents()
        let entries = [RowContents.Entry(item: project, showsTime: false)]
        let looks = [project.type: Self.progress]

        let first = try #require(contents.contents(of: entries, in: library, looks: looks, list: Self.list)[project.id])
        library.counts.want([project.id], .children)
        #expect(first.chips.filter { if case .count = $0 { true } else { false } }.isEmpty)

        let arrived = await eventually {
            contents.contents(of: entries, in: library, looks: looks, list: Self.list)[project.id]?.chips
                .contains(.count("1 of 2 done", help: "1 completed, 1 not started")) == true
        }
        #expect(arrived)
    }

    @Test func aCountMarfaCannotAnswerDrawsNothingNotEvenAZero() async throws {
        let project = Self.item("core.task", "Project", status: "todo")
        let library = Self.library([project, Self.item("core.task", "A", status: "done", parent: project.id)])
        library.countsUnavailable = true
        let contents = RowContents()
        let entries = [RowContents.Entry(item: project, showsTime: false)]
        let looks = [project.type: Self.progress]
        _ = contents.contents(of: entries, in: library, looks: looks, list: Self.list)
        library.counts.want([project.id], .children)
        #expect(await eventually { library.counts.questions == 1 })
        // Let the failed request finish before checking that the row still has no count.
        try await Task.sleep(for: .milliseconds(100))
        let row = try #require(contents.contents(of: entries, in: library, looks: looks, list: Self.list)[project.id])
        #expect(!row.chips.contains { if case .count = $0 { true } else { false } })
        #expect(library.counts.answer(of: project.id, .children) == nil)
    }

    @Test func readingARowAsksForNothingAndAnEmptyCountColumnStartsHidden() async throws {
        let project = Self.item("core.task", "Project", status: "todo")
        let library = Self.library([project, Self.item("core.task", "A", status: "done", parent: project.id)])
        let looks = [project.type: Self.progress]
        let before = ItemTableRow.rows(of: [project], in: library, looks: looks)
        #expect(library.counts.questions == 0)
        let hidden = ItemTableLayout.columns(for: before, catalogue: Self.catalogue, hidden: [], looks: looks)
        let column = try #require(hidden.first { $0.content == ItemTableColumn.Content.count(.progress) })
        #expect(!column.isShownByDefault)

        library.counts.want([project.id], .children)
        #expect(await eventually { !ItemTableRow.rows(of: [project], in: library, looks: looks)[0].counts.isEmpty })
        let after = ItemTableRow.rows(of: [project], in: library, looks: looks)
        let shown = ItemTableLayout.columns(for: after, catalogue: Self.catalogue, hidden: [], looks: looks)
        #expect(shown.first { $0.content == ItemTableColumn.Content.count(.progress) }?.isShownByDefault == true)
    }

    @Test func aCardAndATableColumnSayTheSameCount() async throws {
        let project = Self.item("core.task", "Project", status: "todo")
        let library = Self.library([project, Self.item("core.task", "A", status: "done", parent: project.id)])
        let looks = [project.type: Self.progress]
        library.counts.want([project.id], .children)
        #expect(await eventually { !ItemTableRow.rows(of: [project], in: library, looks: looks)[0].counts.isEmpty })
        let row = ItemTableRow.rows(of: [project], in: library, looks: looks)[0]

        let columns = ItemTableLayout.columns(for: [row], catalogue: Self.catalogue, hidden: [], looks: looks)
        let column = try #require(columns.first { $0.content == ItemTableColumn.Content.count(.progress) })
        #expect(column.isShownByDefault && column.label == "Progress")
        #expect(!column.isSortable)
        #expect(column.sortValue(of: row) == nil)

        let card = RowContent.card(
            for: project, look: Self.progress, catalogue: Self.catalogue, list: Self.list, shape: CardShape(),
            relations: library.relations(of: project, wanting: [], counts: [.progress]))
        #expect(card.chips.contains(.count("1 of 1 done", help: "1 completed")))
    }

    @Test func aCollectionCountsItsActiveMembersOnly() async throws {
        let shelf = Self.item("test.collection", "Shelf")
        let library = Self.library([
            shelf, Self.item("core.note", "In", collection: shelf.id),
            Self.item("core.note", "Binned", collection: shelf.id, state: .trashed),
        ])
        library.counts.want([shelf.id], .members)
        #expect(await eventually { library.counts.answer(of: shelf.id, .members)?.total == 1 })
    }

    @Test func aCountColumnIsNeverSortedOrOfferedToSortByAndAStoredSortOnOneIsDropped() throws {
        let project = Self.item("core.task", "Project", status: "todo")
        let library = Self.library([project, Self.item("core.task", "A", status: "done", parent: project.id)])
        let looks = [project.type: Self.progress]
        let rows = ItemTableRow.rows(of: [project], in: library, looks: looks)
        let columns = ItemTableLayout.columns(for: rows, catalogue: Self.catalogue, hidden: [], looks: looks)
        let count = try #require(columns.first { $0.content == ItemTableColumn.Content.count(.progress) })
        #expect(!count.isSortable)
        #expect(columns.filter(\.isSortable).count == columns.count - 1)

        let offered = ItemTableLayout.sortChoices(from: columns, types: [project.type], catalogue: Self.catalogue)
        #expect(!offered.contains { $0.id == count.id })

        var options = ItemTableOptions()
        options.sort = [ItemTableComparator(column: count, order: .reverse), ItemTableComparator(column: .title, order: .forward)]
        let kept = ItemTableLayout.sort(options, columns: columns)
        #expect(kept.map(\.column.id) == ["title"])
        options.sort = [ItemTableComparator(column: count, order: .reverse)]
        #expect(!ItemTableLayout.sort(options, columns: columns).contains { $0.column.id == count.id })
    }
}
