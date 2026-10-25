import Foundation
import Testing
@testable import MAPP

struct NoteTextTests {
    /// The preview a list row shows under an item with this title.
    func preview(_ body: String, title: String = "") -> String { ItemPreview.text(of: body, title: title) }

    @Test func previewJoinsTheLinesAfterTheTitleAsPlainText() {
        let body = """
        # Trip

        Three days in *October*.

        - [ ] Adapter
        - [x] Walking shoes
        """
        #expect(preview(body) == "Three days in October. Adapter. Walking shoes")
    }

    @Test func previewReadsTablesWithoutPipesOrDelimiterRows() {
        let body = """
        # Quotes
        | Supplier | Quote |
        | --- | ---: |
        | Oak & Iron | £11,850 |
        """
        #expect(preview(body) == "Supplier Quote. Oak & Iron £11,850")
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

    @Test func previewNamesAnImageWithoutTheWidthItWasGiven() {
        #expect(preview("Title\n\n![Dusk|320](Attachments/Dusk.png) and ![Photo\\|400](a.png)", title: "Title") == "Dusk and Photo")
    }

    @Test func previewOfATitleOnlyNoteIsEmpty() {
        #expect(preview("# Just a title") == "")
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
        ("R\\&D budget", "R&D budget"),
        ("\\[Draft\\] plan", "[Draft] plan"),
        ("\\#work and 5 \\* 3", "#work and 5 * 3"),
        ("Hello&#x20;", "Hello"),
        ("Tom &amp; Jerry &#233;t&#xE9;", "Tom & Jerry été"),
        ("Keep `\\*code\\*` as written", "Keep \\*code\\* as written"),
        ("&bogus; stays", "&bogus; stays"),
        ("first<br>second<br />third<BR/>last", "first second third last"),
        ("![[Dusk.png|320]] and [[Plan|the plan]]", "Dusk.png and the plan"),
        ("[[Plan#Next steps]] and ![[Clip.mov#t=2|400]]", "Plan#Next steps and Clip.mov"),
        ("Use `<br>` and `![[Dusk.png|320]]` literally", "Use <br> and ![[Dusk.png|320]] literally"),
        ("\\!\\[\\[literal\\]\\]", "![[literal]]"),
        ("Keep \\<br> literal", "Keep <br> literal"),
        ("\\\\<br>text", "\\ text"),
        ("[[Name\\|part]]", "Name|part"),
        ("[[Target|Label\\|part]]", "Label|part"),
        ("![[A\\#B.png]]", "A#B.png"),
        ("![[A\\|B.png|400]]", "A|B.png"),
        ("![[A\\#B.png#section|400]]", "A#B.png"),
        ("![[A\\\\#section|400]]", "A\\"),
        ("\\[[Name\\|part]]", "[[Name|part]]"),
        ("Keep `\\<br>` and `[[Name\\|part]]` literal", "Keep \\<br> and [[Name\\|part]] literal"),
    ])
    func plainTextOfOneLine(line: String, expected: String) {
        #expect(NoteText.plainText(of: line[...]) == expected)
    }

    @Test func escapedWikiDelimitersReadAsWritten() {
        let body = "![[A\\#B.png]]\n\n[[Name\\|part]] and \\<br>"
        #expect(preview(body, title: "A#B.png") == "Name|part and <br>")
    }

    @Test func aPreviewReadsAsWrittenWhateverTheEditorEscaped() {
        #expect(preview("R\\&D: plan\n\nsnake\\_case", title: "R&D: plan") == "snake_case")
    }

    @Test func aSnippetShowsTheTextAroundWhatWasFound() {
        let body = "# Recipes\n\nA proper **ragù** takes three hours on a low heat, stirred now and then."
        #expect(NoteText.snippet(of: body, around: "RAGU", reach: 10) == "…A proper ragù takes thr…")
        #expect(NoteText.snippet(of: body, around: "Recipes", reach: 8) == "Recipes A prope…")
        #expect(NoteText.snippet(of: body, around: "missing") == nil)
        #expect(NoteText.snippet(of: body, around: "  ") == nil)
    }

}
