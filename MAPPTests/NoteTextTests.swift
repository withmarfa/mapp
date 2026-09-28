import Foundation
import Testing
@testable import MAPP

struct NoteTextTests {
    /// A new note's title and preview, as the list shows them while its name follows its first line.
    func title(_ body: String) -> String { Note(text: body, created: .now).title }
    func preview(_ body: String) -> String { Note(text: body, created: .now).preview }

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
        var note = Note(text: "# First", created: .now)
        #expect(note.title == "First")
        note.file.body = "# Second\nMore"
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

    @Test func previewNamesAnImageWithoutTheWidthItWasGiven() {
        #expect(preview("Title\n\n![Dusk|320](Attachments/Dusk.png) and ![Photo\\|400](a.png)") == "Dusk and Photo")
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
        ("R\\&D budget", "R&D budget"),
        ("\\[Draft\\] plan", "[Draft] plan"),
        ("\\#work and 5 \\* 3", "#work and 5 * 3"),
        ("Hello&#x20;", "Hello"),
        ("Tom &amp; Jerry &#233;t&#xE9;", "Tom & Jerry été"),
        ("Keep `\\*code\\*` as written", "Keep \\*code\\* as written"),
        ("&bogus; stays", "&bogus; stays"),
    ])
    func plainTextOfOneLine(line: String, expected: String) {
        #expect(NoteText.plainText(of: line[...]) == expected)
    }

    @Test(arguments: [
        ("Groceries", "Groceries"),
        ("Podcast idea: short episodes", "Podcast idea- short episodes"),
        ("a/b\\c", "a-b-c"),
        (".hidden plan", "hidden plan"),
        ("  spaced  ", "spaced"),
        ("", "New Note"),
        ("...", "New Note"),
    ])
    func nameForAFirstLine(line: String, expected: String) {
        #expect(NoteText.name(for: line) == expected)
    }

    @Test func aNameIsCutToFitAnyFileSystemAtACharacter() {
        let name = NoteText.name(for: String(repeating: "é", count: 300))
        #expect(name.utf8.count <= 200)
        #expect(name.allSatisfy { $0 == "é" })
    }

    @Test func aFileIsKnownByTheNameItsFirstLineGivesNumberedOrNot() {
        #expect(NoteText.isName("Groceries", of: "Groceries"))
        #expect(NoteText.isName("Groceries 2", of: "Groceries"))
        #expect(NoteText.isName("Plan- week", of: "Plan: week"))
        #expect(!NoteText.isName("Groceries 1", of: "Groceries"))
        #expect(!NoteText.isName("Shopping", of: "Groceries"))
        #expect(!NoteText.isName("Groceries list", of: "Groceries"))
        // A name an earlier version gave kept the line's character references and escapes as written.
        #expect(NoteText.isName("Plan&#x20;", of: "Plan"))
        #expect(NoteText.isName("R\\&D", of: "R&D"))
        #expect(!NoteText.isName("Plan&#x20;", of: "Plan", exactly: true))
        #expect(!NoteText.isName("Plan&#x20;", of: "Other"))
    }

    @Test func onlyALineANameCannotHoldNeedsATitle() {
        #expect(NoteText.needsTitle("Plan: week"))
        #expect(NoteText.needsTitle(".profile"))
        #expect(!NoteText.needsTitle("R&D budget"))
    }

    @Test func aNoteOfMarkersAloneIsBlank() {
        #expect(NoteText.isBlank(""))
        #expect(NoteText.isBlank("- [ ] \n"))
        #expect(NoteText.isBlank("#\n\n> \n1. "))
        #expect(!NoteText.isBlank("- [ ] Milk"))
        #expect(!NoteText.isBlank("![](Attachments/a.png)"))
    }

    @Test func aTitleReadsAsWrittenWhateverTheEditorEscaped() {
        #expect(title("R\\&D: plan\n\nNext") == "R&D: plan")
        #expect(preview("R\\&D: plan\n\nsnake\\_case") == "snake_case")
    }

    @Test func attachmentLinksFollowANoteToAnotherDepthAndOtherLinksStay() {
        let body = "![a](Attachments/Photo%201.png) [site](https://e.com) ![b](<Attachments/b c.png>) ![x](Other/x.png)"
        let moved = NoteText.rebasingAttachmentLinks(in: body, from: "", to: "Work")
        #expect(moved == "![a](../Attachments/Photo%201.png) [site](https://e.com) ![b](../Attachments/b%20c.png) ![x](Other/x.png)")
        #expect(NoteText.rebasingAttachmentLinks(in: moved, from: "Work", to: "") == "![a](Attachments/Photo%201.png) [site](https://e.com) ![b](Attachments/b%20c.png) ![x](Other/x.png)")
    }

    @Test func aSnippetShowsTheTextAroundWhatWasFound() {
        let body = "# Recipes\n\nA proper **ragù** takes three hours on a low heat, stirred now and then."
        #expect(NoteText.snippet(of: body, around: "RAGU", reach: 10) == "…A proper ragù takes thr…")
        #expect(NoteText.snippet(of: body, around: "Recipes", reach: 8) == "Recipes A prope…")
        #expect(NoteText.snippet(of: body, around: "missing") == nil)
        #expect(NoteText.snippet(of: body, around: "  ") == nil)
    }

}
