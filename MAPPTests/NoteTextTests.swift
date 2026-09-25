import Foundation
import Testing
@testable import MAPP

struct NoteTextTests {
    func title(_ body: String) -> String { NoteText.titleAndPreview(of: body).title }
    func preview(_ body: String) -> String { NoteText.titleAndPreview(of: body).preview }

    @Test func titleIsTheFirstHeadingWithoutItsMarker() {
        #expect(title("# Kitchen quotes\n\nThree quotes.") == "Kitchen quotes")
    }

    @Test func titleSkipsBlankLinesAndStructuralLines() {
        #expect(title("\n\n---\n## Plan **for** the week") == "Plan for the week")
    }

    @Test func titleOfAnEmptyNoteIsNewNote() {
        #expect(title("") == "New Note")
        #expect(title("  \n\n") == "New Note")
        #expect(title("# ") == "New Note")
        #expect(title("- [ ]") == "New Note")
    }

    @Test func titleOfAPlainFirstLineIsThatLine() {
        #expect(title("Podcast idea: short episodes") == "Podcast idea: short episodes")
    }

    @Test func noteKeepsItsTitleAndPreviewInStepWithItsBody() {
        var note = Note(body: "# First", created: .now)
        #expect(note.title == "First")
        note.body = "# Second\nMore"
        #expect(note.title == "Second")
        #expect(note.preview == "More")
    }

    @Test func previewJoinsTheLinesAfterTheTitleAsPlainText() {
        let body = """
        # Trip

        Three days in *October*.

        - [ ] Adapter
        - [x] Walking shoes
        """
        #expect(preview(body) == "Three days in October. Adapter Walking shoes")
    }

    @Test func previewReadsTablesWithoutPipesOrDelimiterRows() {
        let body = """
        # Quotes
        | Supplier | Quote |
        | --- | ---: |
        | Oak & Iron | £11,850 |
        """
        #expect(preview(body) == "Supplier  Quote Oak & Iron  £11,850")
    }

    @Test func previewKeepsCodeInsideFencesAsWritten() {
        let body = """
        # Commands
        ```sh
        ls *.swift
        ```
        """
        #expect(preview(body) == "ls *.swift")
    }

    @Test func previewOfATitleOnlyNoteSaysSo() {
        #expect(preview("# Just a title") == "No additional text")
    }

    @Test func previewIsCappedAtTheLimit() {
        let body = "Title\n" + String(repeating: "word ", count: 200)
        #expect(preview(body).count == NoteText.previewLimit)
    }

    @Test(arguments: [
        ("[the revised edition](https://example.com)", "the revised edition"),
        ("[Swift](https://en.wikipedia.org/wiki/Swift_(programming_language)) is nice", "Swift is nice"),
        ("![A diagram](image.png) below", "A diagram below"),
        ("Use `git restore` here", "Use git restore here"),
        ("Use `**` for bold", "Use ** for bold"),
        ("> - quoted item", "quoted item"),
        ("1. First step", "First step"),
        ("## 3. Results", "3. Results"),
        ("keep snake_case intact", "keep snake_case intact"),
        ("ls *.swift and *.md", "ls *.swift and *.md"),
        ("~~struck~~ and **strong** and _light_", "struck and strong and light"),
        ("===", ""),
        ("| --- | :---: |", ""),
    ])
    func plainTextOfOneLine(line: String, expected: String) {
        #expect(NoteText.plainText(of: line[...]) == expected)
    }
}
