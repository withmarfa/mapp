import Foundation
import Testing
@testable import MarfaMac

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

    @Test func aFencesLinesStayPlainText() {
        let source = "Setup\n```sh\n# install it\n- not a bullet\n---\n| a | b |\n```\nAfter"
        #expect(OpeningText.lines(from: source) == ["Setup", "# install it", "- not a bullet", "---", "| a | b |", "After"])
        #expect(String(OpeningText.attributed(from: "```\n*star* # x\n```").characters) == "*star* # x")
    }

    @Test func aFenceThatTheTextCutsOffStillHoldsTheRest() {
        #expect(OpeningText.lines(from: "```\n# comment") == ["# comment"])
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

    @Test func aLinkCutBeforeItsAddressEndsShowsItsWords() {
        #expect(OpeningText.lines(from: "See [the revised edition](https") == ["See the revised edition"])
        #expect(OpeningText.lines(from: "One\n\nSee ![a chart](") == ["One", "", "See a chart"])
        #expect(OpeningText.lines(from: "See [the revised ed") == ["See the revised ed"])
        #expect(OpeningText.lines(from: "[a](b) and [the second](htt\n") == ["[a](b) and the second"])
    }

    @Test func aWholeLinkShowsItsWordsAndIsNotALink() {
        let text = OpeningText.attributed(from: "Read [the edition](https://example.com/a) now")
        #expect(text.text == "Read the edition now")
        #expect(!text.runs.contains { $0.link != nil })
    }
}
