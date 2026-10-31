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

    @Test func scoresForNonASCIITitlesArePinned() {
        // A word starts after a character that is not a letter. A vowel sign belongs to the letter before it.
        #expect(PaletteMatch.score("किताब", "ताब") == 2)
        #expect(PaletteMatch.score("किताब", "ता") == 2)
        #expect(PaletteMatch.score("किताब", "ब") == 2)
        #expect(PaletteMatch.score("किताब", "किता") == 0)
        #expect(PaletteMatch.score("किTable", "Table") == 2)
        #expect(PaletteMatch.score("Café plans", "plans") == 1)
        #expect(PaletteMatch.score("Éclair", "ECL") == 0)
        // Half of a joined emoji is not a character of its own.
        #expect(PaletteMatch.score("👩‍💻 project", "👩") == nil)
        #expect(PaletteMatch.score("👩‍💻 project", "project") == 1)
        #expect(PaletteMatch.score("日本語のノート", "ノート") == 2)
    }

    @Test func keptTitlesRankAsFreshOnesDo() {
        let titles = ["किताब", "किTable", "Café plans", "Éclair", "👩‍💻 project", "日本語のノート", "New Note", "Move to Inbox", "Unpin Note", "Spinach", "Pin Note"]
        let kept = PaletteMatch.Titles()
        for typed in ["ताब", "ब", "Table", "CAFE", "plans", "ECL", "👩", "ノート", "nn", "inb", "pin", "", "zz"] {
            #expect(kept.ranked(titles, typed) == PaletteMatch.ranked(titles, typed), "\(typed)")
        }
    }
}

struct PalettePicksTests {
    @Test func withNothingTypedEveryFixedTitleIsListedAndNoItem() {
        let picks = PaletteMatch.Titles().picks(fixed: ["b", "a"], items: ["note"], " ")
        #expect(picks == [.fixed(0), .fixed(1)])
    }

    @Test func aTypedQueryListsAtMostFiftyOfTenThousandItemTitles() {
        let items = (0..<10_000).map { "Note \($0)" }
        let picks = PaletteMatch.Titles().picks(fixed: ["New Note", "Search Notes"], items: items, "note")
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

    @Test func theBestMatchesComeFirstAcrossBothLists() {
        let picks = PaletteMatch.Titles().picks(fixed: ["Show Details", "Inbox"], items: ["Tax inbox", "Inbox rules", "Other"], "inbox")
        #expect(picks == [.fixed(1), .item(1), .item(0)])
    }

    @Test func aRankingIsAsWideAsTheLimit() {
        let picks = PaletteMatch.Titles().picks(fixed: [], items: ["a1", "a2", "a3"], "a", limit: 2)
        #expect(picks == [.item(0), .item(1)])
    }
}
