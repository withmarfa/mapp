import Testing
@testable import MAPP

struct PaletteMatchTests {
    @Test func aTitleStartingWithTheQueryComesBeforeOneHoldingIt() {
        let titles = ["Move to Inbox", "Inbox", "New Note", "Bike service"]
        #expect(PaletteMatch.ranked(titles, "inb") == [1, 0])
    }

    @Test func caseAndAccentsAreIgnored() {
        #expect(PaletteMatch.score("Café plans", "CAFE") == 0)
    }

    @Test func aWordStartingWithTheQueryBeatsTheMiddleOfAWord() {
        #expect(PaletteMatch.ranked(["Unpin Note", "Pin Note", "Spinach"], "pin") == [1, 0, 2])
    }

    @Test func lettersInOrderFindATitleLast() {
        #expect(PaletteMatch.score("New Note", "nn") == 3)
        #expect(PaletteMatch.score("New Note", "nx") == nil)
        #expect(PaletteMatch.ranked(["New Note", "Nnn"], "nn") == [1, 0])
    }

    @Test func anEmptyQueryKeepsEveryTitleInOrder() {
        #expect(PaletteMatch.ranked(["b", "a"], "  ") == [0, 1])
    }
}
