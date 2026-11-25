import Foundation
import Testing
@testable import MarfaMac

/// The small card under the pointer says only what the copy and the counts Marfa answered hold, and asks for them in
/// batches the way every row does.
@MainActor
@Suite(.hangLimit) struct LinkCardTests {
    private static let calendar = Calendar(identifier: .gregorian)
    private static let english = Locale(identifier: "en_GB")

    private func content(_ item: Item, counts: [CountQuery: ItemCountAnswer]) -> LinkCardContent {
        LinkCardContent.of(
            item, in: FakeItemLibrary.testCatalogue, counts: counts, format: .standard, calendar: Self.calendar, locale: Self.english)
    }

    @Test func aCountNotYetAnsweredIsLeftOutAndNeverDrawnAsZero() {
        let project = Item(
            id: .mint(), type: TypeID("test.project"), title: "Zine", name: "Zine", titleRule: .property("title"), version: ItemVersion(1),
            created: .distantPast, modified: .distantPast)
        #expect(content(project, counts: [:]).lines.isEmpty)
        #expect(content(project, counts: [.children: ItemCountAnswer(total: 0, groups: nil)]).lines.isEmpty)
        let groups = ItemCountAnswer.Groups(notStarted: 4, inProgress: 1, completed: 2)
        let answered = content(project, counts: [.children: ItemCountAnswer(total: 7, groups: groups)])
        #expect(answered.lines == ["7 sub-items, 2 completed"])
        #expect(answered.title == "Zine")
        #expect(answered.typeName == "Project")
    }

    @Test func aDueDayIsTheSecondLineAndOneCountIsSingular() {
        var task = Item(
            id: .mint(), type: TypeID("core.task"), title: "Print", name: "Print", titleRule: .property("title"), version: ItemVersion(1),
            created: .distantPast, modified: .distantPast)
        task.properties = [Property(key: MarfaMapping.dueField, value: .string("2027-03-05"))]
        let card = content(task, counts: [.children: ItemCountAnswer(total: 1, groups: nil)])
        #expect(card.lines.count == 2)
        #expect(card.lines.first == "1 sub-item")
        #expect(card.lines.last?.hasPrefix("Due ") == true)
    }

    @Test func aCardAsksForItsItemsCountsInBatchesAndOnlyForWhatItsTypeHolds() async {
        let note = FakeItemLibrary.note("Note", modified: .distantPast)
        let collection = FakeItemLibrary.collection("Reading")
        #expect(LinkCardContent.counts(for: note, in: FakeItemLibrary.testCatalogue) == [.children])
        #expect(LinkCardContent.counts(for: collection, in: FakeItemLibrary.testCatalogue) == [.children, .members])

        // Many cards asked for at once go out in batches of at most `ItemCounts.batch`, one question for each query.
        let sizes = Sizes()
        let counts = ItemCounts { ids, _ in
            await sizes.add(ids.count)
            return Dictionary(uniqueKeysWithValues: ids.map { ($0, ItemCountAnswer(total: 1, groups: nil)) })
        }
        let ids = (0..<250).map { ItemID("item-\($0)") }
        counts.want(ids, .children)
        #expect(await eventually { counts.answer(of: ids.last!, .children) != nil })
        #expect(await sizes.all == [100, 100, 50])
    }

    @Test func aLinkInTheTextAndAnItemAreTargetsTheCorePageNames() {
        #expect(LinkCardTarget(page: ["kind": "item", "link": "abc"]) == .item(ItemID("abc")))
        #expect(LinkCardTarget(page: ["kind": "wiki", "link": "[[Plan]]"]) == .wiki("[[Plan]]"))
        #expect(LinkCardTarget(page: ["kind": "other", "link": "x"]) == nil)
        #expect(LinkCardTarget(page: ["kind": "item", "link": ""]) == nil)
        #expect(LinkCardTarget(page: nil) == nil)
    }

    private actor Sizes {
        var all: [Int] = []
        func add(_ size: Int) { all.append(size) }
    }
}
