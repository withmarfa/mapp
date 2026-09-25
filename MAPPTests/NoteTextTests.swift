import Testing
@testable import MAPP

struct NoteTextTests {
    @Test func titleIsTheFirstHeadingWithoutItsMarker() {
        #expect(NoteText.title(of: "# Kitchen quotes\n\nThree quotes.") == "Kitchen quotes")
    }

    @Test func titleSkipsBlankLinesAndStructuralLines() {
        #expect(NoteText.title(of: "\n\n---\n## Plan **for** the week") == "Plan for the week")
    }

    @Test func titleOfAnEmptyNoteIsNewNote() {
        #expect(NoteText.title(of: "") == "New Note")
        #expect(NoteText.title(of: "  \n\n") == "New Note")
    }

    @Test func titleOfAPlainFirstLineIsThatLine() {
        #expect(NoteText.title(of: "Podcast idea: short episodes") == "Podcast idea: short episodes")
    }

    @Test func previewJoinsTheLinesAfterTheTitleAsPlainText() {
        let body = """
        # Trip

        Three days in *October*.

        - [ ] Adapter
        - [x] Walking shoes
        """
        #expect(NoteText.preview(of: body) == "Three days in October. Adapter Walking shoes")
    }

    @Test func previewReadsTablesWithoutPipesOrDelimiterRows() {
        let body = """
        # Quotes
        | Supplier | Quote |
        | --- | ---: |
        | Oak & Iron | £11,850 |
        """
        #expect(NoteText.preview(of: body) == "Supplier  Quote Oak & Iron  £11,850")
    }

    @Test func previewOfATitleOnlyNoteSaysSo() {
        #expect(NoteText.preview(of: "# Just a title") == "No additional text")
    }

    @Test func previewIsCappedAtTheLimit() {
        let body = "Title\n" + String(repeating: "word ", count: 200)
        #expect(NoteText.preview(of: body, limit: 50).count == 50)
    }

    @Test(arguments: [
        ("[the revised edition](https://example.com)", "the revised edition"),
        ("![A diagram](image.png) below", "A diagram below"),
        ("Use `git restore` here", "Use git restore here"),
        ("> - quoted item", "quoted item"),
        ("1. First step", "First step"),
        ("keep snake_case intact", "keep snake_case intact"),
        ("~~struck~~ and __strong__", "struck and strong"),
        ("```sh", ""),
        ("| --- | :---: |", ""),
    ])
    func plainTextOfOneLine(line: String, expected: String) {
        #expect(NoteText.plainText(of: line[...]) == expected)
    }
}
