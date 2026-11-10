import Foundation
import Testing
@testable import MAPP

struct PaletteFiltersTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Wednesday 11 November 2026, noon.
    private static let now = Date(timeIntervalSince1970: 1_794_398_400)

    private func day(_ offset: Int) -> Date { Self.calendar.date(byAdding: .day, value: offset, to: Self.now)! }

    private let kitchen = ItemID.mint()
    private let garden = ItemID.mint()

    private func item(_ title: String, type: String = "core.note", modified: Date, in collections: [ItemID] = []) -> Item {
        var item = FakeItemLibrary.note(title, modified: modified)
        item.type = TypeID(type)
        item.edgesOut = collections.map {
            Edge(id: EdgeID(rawValue: UUID().uuidString), type: MarfaMapping.collectionEdge, source: item.id, target: .item($0), origin: .property("collections"))
        }
        return item
    }

    private func titles(_ filters: PaletteFilters, _ items: [Item]) -> [String] {
        filters.apply(to: items, now: Self.now, calendar: Self.calendar).map(\.title)
    }

    private var items: [Item] {
        [
            item("Kitchen quotes", modified: day(-1), in: [kitchen]),
            item("Kitchen quotation", type: "core.file", modified: day(-3), in: [kitchen]),
            item("Garden beds", modified: day(-40), in: [garden]),
            item("Loose note", type: "core.file", modified: day(-400)),
        ]
    }

    @Test func noFilterKeepsEveryItemAndCountsNothing() {
        let filters = PaletteFilters()
        #expect(filters.count == 0)
        #expect(titles(filters, items).count == 4)
    }

    @Test func aTypeFilterKeepsItemsOfAnyChosenType() {
        var filters = PaletteFilters()
        filters.types = [TypeID("core.file")]
        #expect(titles(filters, items) == ["Kitchen quotation", "Loose note"])
        filters.types.insert(TypeID("core.note"))
        #expect(titles(filters, items).count == 4)
    }

    @Test func isNotKeepsTheOthers() {
        var filters = PaletteFilters()
        filters.types = [TypeID("core.file")]
        filters.negated = [.type]
        #expect(titles(filters, items) == ["Kitchen quotes", "Garden beds"])
    }

    @Test func aCollectionFilterKeepsItsMembers() {
        var filters = PaletteFilters()
        filters.collections = [kitchen]
        #expect(titles(filters, items) == ["Kitchen quotes", "Kitchen quotation"])
    }

    @Test func eachPeriodReachesBackToTheStartOfItsDayWeekMonthOrYear() {
        var filters = PaletteFilters()
        filters.period = .today
        #expect(titles(filters, items).isEmpty)
        filters.period = .thisWeek
        #expect(titles(filters, items) == ["Kitchen quotes"], "Monday to Sunday, so three days back is last week")
        filters.period = .thisMonth
        #expect(titles(filters, items) == ["Kitchen quotes", "Kitchen quotation"])
        filters.period = .thisYear
        #expect(titles(filters, items) == ["Kitchen quotes", "Kitchen quotation", "Garden beds"])
    }

    @Test func fieldsNarrowTogetherAndTheCountFollowsThem() {
        var filters = PaletteFilters()
        filters.types = [TypeID("core.note")]
        #expect(filters.count == 1)
        filters.collections = [kitchen]
        #expect(filters.count == 2)
        #expect(titles(filters, items) == ["Kitchen quotes"])
        filters.period = .thisYear
        #expect(filters.count == 3)
        filters.clear(.type)
        filters.clear(.collection)
        #expect(filters.count == 1)
        #expect(titles(filters, items) == ["Kitchen quotes", "Kitchen quotation", "Garden beds"])
    }

    @Test func clearingAFieldDropsItsIsNot() {
        var filters = PaletteFilters()
        filters.types = [TypeID("core.note")]
        filters.negated = [.type]
        filters.clear(.type)
        #expect(filters.negated.isEmpty)
        #expect(filters.isEmpty)
    }
}
