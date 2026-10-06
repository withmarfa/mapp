import Foundation
import Testing
@testable import MAPP

struct NoteFileTests {
    // MARK: What is front matter, by Marfa's rule

    @Test(arguments: [
        ("---\ntitle: A\n---\nBody\n", "---\ntitle: A\n---\n"),
        ("---\n---\nBody", "---\n---\n"),
        ("---\ntags:\n  - a\n---", "---\ntags:\n  - a\n---"),
    ])
    func frontMatterIsWhatTheFileOpensWithBetweenFences(text: String, frontMatter: String) {
        let file = NoteFile(text: text)
        #expect(file.text == text)
        #expect(file.body == String(text.dropFirst(frontMatter.count)))
    }

    @Test(arguments: [
        "---\n\nNote: remember the milk\n\n---\n",
        "----\ntitle: A\n----\n",
        "--- x\ntitle: A\n---\n",
        "---\ntitle: never closed\n",
        "Body\n---\ntitle: A\n---\n",
    ])
    func aFileThatDoesNotOpenWithFrontMatterIsAllBody(text: String) {
        #expect(NoteFile(text: text).body == text)
    }

    // MARK: Kept as written

    @Test func aByteOrderMarkAndWindowsLineEndingsComeBack() {
        let text = "\u{FEFF}---\r\ntitle: A\r\n---\r\nOne\r\n\r\nTwo\r\n"
        var file = NoteFile(text: text)
        #expect(file.body == "One\n\nTwo\n")
        #expect(file.title == "A")
        #expect(file.text == text)
        file.body = "One\n\nTwo\n\nThree\n"
        #expect(file.text == "\u{FEFF}---\r\ntitle: A\r\n---\r\nOne\r\n\r\nTwo\r\n\r\nThree\r\n")
    }

    @Test func aBodyAddedAfterFrontMatterClosedAtTheEndStartsOnItsOwnLine() {
        var file = NoteFile(text: "---\ntitle: X\nstatus: open\n---")
        file.body = "Hello\n"
        #expect(file.text == "---\ntitle: X\nstatus: open\n---\nHello\n")
        #expect(NoteFile(text: file.text).title == "X")
    }

    @Test func frontMatterFencesMayEndWindowsStyleInAMixedFile() {
        let text = "---\r\ntitle: A\r\n---\r\nBody\n"
        let file = NoteFile(text: text)
        #expect(file.body == "Body\n")
        #expect(file.title == "A")
        #expect(file.text == text)
    }

    @Test func aMixtureOfLineEndingsIsLeftAsItStands() {
        let text = "One\r\nTwo\n"
        #expect(NoteFile(text: text).body == text)
    }

    // MARK: Properties

    @Test func propertiesAreReadAsScalars() {
        let file = NoteFile(text: """
        ---
        title: "Quoted: yes"
        other: 'it''s'
        status: open
        list:
          - a
        plain: value # comment
        ---
        Body
        """)
        #expect(file.title == "Quoted: yes")
        #expect(file.property("other") == "it's")
        #expect(file.property("status") == "open")
        #expect(file.property("list") == nil)
        #expect(file.property("plain") == "value")
        #expect(file.property("missing") == nil)
        #expect(file.property("titl") == nil)
    }

    @Test func settingAPropertyChangesOnlyItsOwnLines() {
        var file = NoteFile(text: "---\nmarfa_id: 1\ntags:\n  - a\n# kept\ntitle: Old\n---\nBody\n")
        file.setProperty("tags", "one")
        file.setProperty("title", "New: one")
        file.setProperty("status", "open")
        #expect(file.text == "---\nmarfa_id: 1\ntags: one\n# kept\ntitle: \"New: one\"\nstatus: open\n---\nBody\n")
        file.setProperty("status", nil)
        file.setProperty("absent", nil)
        #expect(file.text == "---\nmarfa_id: 1\ntags: one\n# kept\ntitle: \"New: one\"\n---\nBody\n")
    }

    @Test func changingAPropertyPreservesUnrelatedLineEndingsAndBlankLines() {
        let text = "---\r\ntype: example.task\ntitle: Old\r\n\r\nchild-of: \"[[Project]]\"\r\ncustom:\n  labels: [one, two]\r\n---\r\nBody\n"
        var file = NoteFile(text: text)
        file.setProperty("title", "New")
        #expect(file.text == text.replacingOccurrences(of: "title: Old", with: "title: New"))
        file.setProperty("status", "open")
        #expect(file.text == text.replacingOccurrences(of: "title: Old", with: "title: New")
            .replacingOccurrences(of: "---\r\nBody", with: "status: open\r\n---\r\nBody"))
        file.setProperty("status", nil)
        #expect(file.text == text.replacingOccurrences(of: "title: Old", with: "title: New"))
    }

    @Test func changingAMultilinePropertyKeepsTheSeparatorAfterItsValue() {
        var file = NoteFile(text: "---\ntitle: |\n  Old\n\n  title\n\nchild-of: \"[[Project]]\"\n---\nBody\n")
        file.setProperty("title", "New")
        #expect(file.text == "---\ntitle: New\n\nchild-of: \"[[Project]]\"\n---\nBody\n")
    }

    @Test func aPropertyEditKeepsTheClosingFenceAtTheEndOfTheFile() {
        var file = NoteFile(text: "---\ntitle: Old\ncustom: untouched\n---")
        file.setProperty("title", "New")
        #expect(file.text == "---\ntitle: New\ncustom: untouched\n---")
    }

    @Test(arguments: [("\n", "\n"), ("\r\n", "\r\n"), ("\r\n", "\n")])
    func removingTheFirstPropertyKeepsTheHeaderReadable(opening: String, following: String) {
        let remainder = "type: example.task\(following)child-of: \"[[Parent]]\"\(following)\(following)custom: [one, two]\(following)---\(opening)Body\(following)"
        var file = NoteFile(text: "---\(opening)status: open\(opening)\(following)\(remainder)")
        file.setProperty("status", nil)
        #expect(file.text == "---\(opening)\(remainder)")
        let reread = NoteFile(text: file.text)
        #expect(reread.property("type") == "example.task")
        #expect(reread.property("child-of") == "[[Parent]]")
        #expect(reread.body == "Body\n")
    }

    @Test(arguments: [("\n", "\n"), ("\r\n", "\r\n"), ("\r\n", "\n")])
    func removingTheLastPropertyRemovesTheHeaderAndItsBlankSeparators(opening: String, following: String) {
        var file = NoteFile(text: "---\(opening)status: open\(opening)\(following) \t\(following)---\(opening)Body\(following)")
        file.setProperty("status", nil)
        #expect(file.text == "Body\(following)")
        #expect(NoteFile(text: file.text).body == "Body\n")
    }

    @Test func frontMatterIsMadeForTheFirstPropertyAndGoesWithTheLast() {
        var file = NoteFile(text: "Body\n")
        file.setProperty("status", "open")
        #expect(file.text == "---\nstatus: open\n---\nBody\n")
        file.setProperty("status", nil)
        #expect(file.text == "Body\n")
    }

    @Test(arguments: [
        ("Plain", "Plain"),
        ("true", "\"true\""),
        ("12", "\"12\""),
        ("- dash", "\"- dash\""),
        ("a \"b\"", "a \"b\""),
        ("'quote", "\"'quote\""),
        ("Todo:", "\"Todo:\""),
        ("R&D: plan", "\"R&D: plan\""),
    ])
    func valuesAreQuotedOnlyWhereYAMLNeedsIt(value: String, written: String) {
        var file = NoteFile(text: "")
        file.setProperty("title", value)
        #expect(file.text == "---\ntitle: \(written)\n---\n")
        #expect(file.title == value)
    }
}
