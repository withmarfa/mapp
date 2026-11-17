import Foundation
import Testing
@testable import MAPP

/// A card's opening lines read as text, not as Markdown source.
struct OpeningTextTests {
    private static let source = """
        Three days in October.

        | Day | Plan |
        | --- | --- |
        | Thursday | Arrive, dinner |
        ---
        - *Affordances* say what is possible
          - [ ] a nested **task**
        - [x] a done task
        1. First step
        """

    @Test func aTableShowsItsCellsAsWordsAndLeavesItsSeparatorOut() {
        let lines = OpeningText.lines(from: Self.source)
        #expect(lines.contains("Day   Plan"))
        #expect(lines.contains("Thursday   Arrive, dinner"))
        #expect(!lines.contains { $0.contains("---") || $0.contains("|") })
    }

    @Test func aRuleIsLeftOut() {
        #expect(OpeningText.lines(from: "One\n---\nTwo\n* * *\n___") == ["One", "Two"])
    }

    @Test func aCodeFenceIsLeftOutAndItsCodeKept() {
        #expect(OpeningText.lines(from: "```sh\ngit log\n```") == ["git log"])
    }

    @Test func listItemsGetABulletAndTasksShowTheirWords() {
        let lines = OpeningText.lines(from: Self.source)
        #expect(lines.contains("\u{2022} *Affordances* say what is possible"))
        #expect(lines.contains("  a nested **task**"))
        #expect(lines.contains("a done task"))
        #expect(lines.contains("1. First step"))
    }

    @Test func emphasisIsStyledNotShownAsMarks() {
        let text = OpeningText.attributed(from: Self.source).text
        #expect(text.contains("Affordances say what is possible"))
        #expect(!text.contains("*") && !text.contains("[ ]") && !text.contains("|"))
    }

    @Test func blankLinesCollapseAndNoneOpensOrClosesTheText() {
        #expect(OpeningText.lines(from: "\n\nA\n\n\n\nB\n\n---\n") == ["A", "", "B"])
    }

    @Test func plainTextAndAnUnclosedMarkAreKept() {
        #expect(OpeningText.lines(from: "Notes as I read.\n*half") == ["Notes as I read.", "*half"])
    }
}
