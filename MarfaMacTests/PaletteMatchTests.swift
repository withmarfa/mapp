import Testing
@testable import MarfaMac

struct PalettePicksTests {
    @Test func aTypedQueryListsAtMostFiftyOfTenThousandItemTitles() {
        let items = (0..<10_000).map { "Item \($0)" }
        let picks = PaletteMatch.Titles().picks(fixed: ["New Item", "Search Items"], items: items, "item")
        #expect(picks.count == PaletteMatch.listLimit + 2)
        #expect(picks.first == .item(0))
    }

    @Test func everyMatchingFixedEntryIsKeptHoweverManyItemsMatchBetter() {
        let fixed = (0..<80).map { "Zoom note \($0)" }
        let items = (0..<200).map { "Note \($0)" }
        let picks = PaletteMatch.Titles().picks(fixed: fixed, items: items, "note")
        #expect(picks.filter { if case .fixed = $0 { true } else { false } }.count == 80)
        #expect(picks.filter { if case .item = $0 { true } else { false } }.count == PaletteMatch.listLimit)
        #expect(picks.prefix(PaletteMatch.listLimit).allSatisfy { if case .item = $0 { true } else { false } }, "rank order is kept")
    }

    @Test func aRankingIsAsWideAsTheLimit() {
        let picks = PaletteMatch.Titles().picks(fixed: [], items: ["a1", "a2", "a3"], "a", limit: 2)
        #expect(picks == [.item(0), .item(1)])
    }
}
