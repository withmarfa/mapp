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
        pinned: true
        list:
          - a
        plain: value # comment
        ---
        Body
        """)
        #expect(file.title == "Quoted: yes")
        #expect(file.property("other") == "it's")
        #expect(file.isPinned)
        #expect(file.property("list") == nil)
        #expect(file.property("plain") == "value")
        #expect(file.property("missing") == nil)
        #expect(file.property("titl") == nil)
    }

    @Test func settingAPropertyChangesOnlyItsOwnLines() {
        var file = NoteFile(text: "---\nmarfa_id: 1\ntags:\n  - a\n# kept\ntitle: Old\n---\nBody\n")
        file.setProperty("tags", "one")
        file.setProperty("title", "New: one")
        file.setProperty("pinned", "true")
        #expect(file.text == "---\nmarfa_id: 1\ntags: one\n# kept\ntitle: \"New: one\"\npinned: true\n---\nBody\n")
        file.setProperty("pinned", nil)
        file.setProperty("absent", nil)
        #expect(file.text == "---\nmarfa_id: 1\ntags: one\n# kept\ntitle: \"New: one\"\n---\nBody\n")
    }

    @Test func frontMatterIsMadeForTheFirstPropertyAndGoesWithTheLast() {
        var file = NoteFile(text: "Body\n")
        file.setProperty("pinned", "true")
        #expect(file.text == "---\npinned: true\n---\nBody\n")
        file.setProperty("pinned", nil)
        #expect(file.text == "Body\n")
    }

    @Test(arguments: [
        ("Plain", "Plain"),
        ("true", "\"true\""),
        ("12", "\"12\""),
        ("- dash", "\"- dash\""),
        ("a \"b\"", "a \"b\""),
        ("'quote", "\"'quote\""),
    ])
    func valuesAreQuotedOnlyWhereYAMLNeedsIt(value: String, written: String) {
        var file = NoteFile(text: "")
        file.setProperty("title", value)
        #expect(file.text == "---\ntitle: \(written)\n---\n")
        #expect(file.title == value)
    }
}
