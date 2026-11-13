import Testing
@testable import MAPP

struct StatusSymbolTests {
    @Test(arguments: [
        (StatusGroup.notStarted, "circle", StatusSymbol.Tint.secondary),
        (.inProgress, "circle.lefthalf.filled", .blue),
        (.completed, "largecircle.fill.circle", .secondary),
        (.canceled, "xmark.circle", .tertiary),
    ])
    func eachGroupHasItsOwnSymbolAndTint(group: StatusGroup, name: String, tint: StatusSymbol.Tint) {
        let symbol = StatusSymbol(group: group)
        #expect(symbol.systemName == name)
        #expect(symbol.tint == tint)
    }

    @Test func aStatusNoGroupClaimsDrawsAsNotStarted() {
        #expect(StatusSymbol(group: nil) == .notStarted)
    }

    @Test func theFourSymbolsAreDistinctAndAllSentToThePage() {
        #expect(Set(StatusSymbol.systemNames).count == 4)
        #expect(StatusSymbol.systemNames == StatusSymbol.allCases.map(\.systemName))
    }
}
