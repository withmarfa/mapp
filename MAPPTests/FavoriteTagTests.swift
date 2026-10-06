import Foundation
import Testing
@testable import MAPP

/// A favorite is Marfa's ordinary `favorite` tag, read from a file's `tags` front matter as Marfa's folder reads it.
struct FavoriteTagTests {
    private func file(_ yaml: String) -> NoteFile {
        NoteFile(text: "---\n" + yaml + "\n---\nBody\n")
    }

    private func added(to text: String) throws -> String {
        var file = NoteFile(text: text)
        try file.setFavorite(true)
        return file.text
    }

    private func removed(from text: String) throws -> String {
        var file = NoteFile(text: text)
        try file.setFavorite(false)
        return file.text
    }

    // MARK: Reading, as Marfa reads

    /// Front matter and the tags Marfa's folder reads from it (`tags_of` in marfa-core's `folder/fields.rs`, after
    /// `folder/document.rs` reads the YAML with yaml-rust2); nil where Marfa refuses the value or the front matter.
    /// The first rows are the cases in that file's own tests; the rest were each run through yaml-rust2 0.13 and the
    /// same function.
    nonisolated static let marfaReadings: [(String, [String]?)] = [
        ("tags: [b, a, b]", ["b", "a"]),
        ("tags: solo", ["solo"]),
        ("tags: x, y", ["x", "y"]),
        ("tags: \"b, a\"", ["b", "a"]),
        ("tags: {a: 1}", nil),
        ("tags: [1]", nil),
        ("tags: []", []),
        ("tags:", []),
        ("tags: ~", []),
        ("tags: null", []),
        ("tags: Null", ["Null"]),
        ("tags: favorite", ["favorite"]),
        ("tags: work, favorite", ["work", "favorite"]),
        ("tags: [a, a, ' a ']", ["a"]),
        ("tags: ''", nil),
        ("tags: work,", nil),
        ("tags: [\"\"]", nil),
        ("tags: 5", nil),
        ("tags: true", nil),
        ("tags: [True]", nil),
        ("tags: [1.5]", nil),
        ("tags: yes", ["yes"]),
        ("tags: [yes, on, no]", ["yes", "on", "no"]),
        ("tags: [.inf, nan, 1e999]", [".inf", "nan", "1e999"]),
        ("tags: [0x1F]", nil),
        ("tags: [0o17]", nil),
        ("tags: [+5]", nil),
        ("tags: [+-5]", nil),
        ("tags: [1e5]", nil),
        ("tags: [-.5]", nil),
        ("tags: [1.]", nil),
        ("tags: [1_000]", ["1_000"]),
        ("tags: [0x1p3]", ["0x1p3"]),
        ("tags: [~]", nil),
        ("tags: [null, a]", nil),
        ("tags: [[favorite]]", nil),
        ("tags: [a: b]", nil),
        ("tags: ['it''s, ok', b]", ["it's, ok", "b"]),
        ("tags: [a,\n  # c\n  favorite]", ["a", "favorite"]),
        ("tags: [a,\n  favorite\n]", ["a", "favorite"]),
        ("tags: [a,\nfavorite\n]", nil),
        ("tags:\n# c\n- favorite", ["favorite"]),
        ("tags:\n  - a\n  # c\n  - favorite", ["a", "favorite"]),
        ("tags:\n  - favorite\n  - \" b \"", ["favorite", "b"]),
        ("\"tags\": [a]", ["a"]),
        ("'tags': favorite", ["favorite"]),
        ("tags : [favorite]", ["favorite"]),
        ("tags: [favorite]\ntags: [b]", nil),
        ("tags: [a]\n\"tags\": [b]", nil),
        ("tags: \"work, favorite\"", ["work", "favorite"]),
        ("tags: >\n  a, b", ["a", "b"]),
        ("tags: |\n  a\n  b", ["a\nb"]),
        ("tags: &x [favorite]\nother: *x", ["favorite"]),
        ("tags: [favorite]\n1: x", nil),
        ("tags: [favorite]\nnull: x", nil),
        ("tags: !!str 5", ["5"]),
        ("tags: !foo 5", ["5"]),
        ("tags: [!!int 5]", nil),
        ("tags: [café, favorite]", ["café", "favorite"]),
        ("tags: a\n  b", ["a b"]),
        ("tags: [favorite]\nwhen: 1:30", ["favorite"]),
        ("tags: [favorite]\nflag: yes", ["favorite"]),
        ("title: A", []),
        ("- a\n- b", []),
        ("tags", []),
    ]

    @Test(arguments: marfaReadings)
    func tagsAreReadAsMarfaReadsThem(yaml: String, marfa: [String]?) {
        #expect(file(yaml).tags == marfa)
        #expect(file(yaml).isFavorite == (marfa?.contains("favorite") == true))
    }

    /// `folder/document.rs` refuses a merge key before the fields are read.
    @Test func aMergeKeyMakesTheFrontMatterUnreadable() {
        #expect(file("tags: [favorite]\n<<: {a: 1}").tags == nil)
        #expect(file("tags: [favorite]\nother:\n  <<: {a: 1}").tags == nil)
    }

    @Test(arguments: [
        "Body\n",
        "---\ntitle: A\n---\nBody\n",
        "---\ncustom:\n  tags: [favorite]\n---\nBody\n",
        "---\ntagsfavorite: [favorite]\n---\nBody\n",
        "---\ntags: [favorites, unfavorite]\n---\nBody\n",
        "---\ntags: [\"favorite]\n---\nBody\n",
    ])
    func otherFieldsAndNearMissesAreNotAFavorite(text: String) {
        #expect(!NoteFile(text: text).isFavorite)
    }

    @Test func windowsLineEndingsAndAByteOrderMarkAreRead() {
        #expect(NoteFile(text: "\u{FEFF}---\r\ntags: [favorite]\r\n---\r\nBody\r\n").isFavorite)
        #expect(NoteFile(text: "---\r\ntags:\r\n  - favorite\r\n---\r\nBody\r\n").isFavorite)
    }

    // MARK: Adding

    @Test(arguments: [
        ("Body\n", "---\ntags: [favorite]\n---\nBody\n"),
        ("---\ntitle: A\n---\nBody\n", "---\ntitle: A\ntags: [favorite]\n---\nBody\n"),
        ("---\n---\nBody\n", "---\ntags: [favorite]\n---\nBody\n"),
    ])
    func aNoteWithoutTagsGetsAFlowList(before: String, after: String) throws {
        #expect(try added(to: before) == after)
    }

    @Test(arguments: [
        ("tags:", "tags: [favorite]"),
        ("tags: ~ # none yet", "tags: [favorite] # none yet"),
        ("tags: null", "tags: [favorite]"),
        ("\"tags\":", "\"tags\": [favorite]"),
        ("tags:\n  # none yet", "tags: [favorite]\n  # none yet"),
        ("title: A\ntags:\nstatus: open", "title: A\ntags: [favorite]\nstatus: open"),
    ])
    func anEmptyValueBecomesAFlowList(before: String, after: String) throws {
        #expect(try added(to: "---\n\(before)\n---\nBody\n") == "---\n\(after)\n---\nBody\n")
    }

    @Test(arguments: [
        ("tags: work", "tags: work, favorite"),
        ("tags: work, play # kept", "tags: work, play, favorite # kept"),
        ("tags: \"work\"", "tags: \"work, favorite\""),
        ("tags: 'work'", "tags: 'work, favorite'"),
        ("'tags': work", "'tags': work, favorite"),
    ])
    func aStringGainsACommaSeparatedTag(before: String, after: String) throws {
        #expect(try added(to: "---\n\(before)\n---\nBody\n") == "---\n\(after)\n---\nBody\n")
    }

    @Test(arguments: [
        ("tags: []", "tags: [favorite]"),
        ("tags: [one]", "tags: [one, favorite]"),
        ("tags: [one,two]", "tags: [one,two, favorite]"),
        ("tags: [one, two,]", "tags: [one, two, favorite]"),
        ("tags: [one, two, ]", "tags: [one, two, favorite]"),
        ("tags: [a,]", "tags: [a, favorite]"),
        ("tags: [ \"a]\" ] # keep ]", "tags: [ \"a]\", favorite ] # keep ]"),
        ("tags: [one,\n  two]", "tags: [one,\n  two, favorite]"),
        ("tags: [a,\n  b\n]", "tags: [a,\n  b, favorite\n]"),
        ("tags: [a,\n  # c\n  b]", "tags: [a,\n  # c\n  b, favorite]"),
        ("tags: [a, b # c\n  ]", "tags: [a, b, favorite # c\n  ]"),
        ("tags: ['it''s, ok', b]", "tags: ['it''s, ok', b, favorite]"),
        ("tags: [café]", "tags: [café, favorite]"),
        ("\"tags\": [a]", "\"tags\": [a, favorite]"),
        ("tags : [a]", "tags : [a, favorite]"),
    ])
    func aFlowListGainsTheTagInPlace(before: String, after: String) throws {
        #expect(try added(to: "---\n\(before)\n---\nBody\n") == "---\n\(after)\n---\nBody\n")
    }

    @Test(arguments: [
        ("tags:\n  - one", "tags:\n  - one\n  - favorite"),
        ("tags:\n- one\n- two\ntitle: A", "tags:\n- one\n- two\n- favorite\ntitle: A"),
        ("tags: # all\n    -   one # first", "tags: # all\n    -   one # first\n    -   favorite"),
        ("tags:\n  - one\n\ntitle: A", "tags:\n  - one\n  - favorite\n\ntitle: A"),
        ("tags:\n# c\n- one", "tags:\n# c\n- one\n- favorite"),
        ("tags:\n  - one\n  # last\ntitle: A", "tags:\n  - one\n  - favorite\n  # last\ntitle: A"),
        ("tags:\n  - one\n# about the title\ntitle: A", "tags:\n  - one\n  - favorite\n# about the title\ntitle: A"),
    ])
    func aBlockListGainsTheTagInItsOwnForm(before: String, after: String) throws {
        #expect(try added(to: "---\n\(before)\n---\nBody\n") == "---\n\(after)\n---\nBody\n")
    }

    @Test(arguments: [
        "---\ntags: [favorite, other]\n---\nBody\n",
        "---\ntags: favorite\n---\nBody\n",
        "---\ntags: [a,\n  # favorite\n  favorite]\n---\nBody\n",
    ])
    func addingWhereTheTagIsAlreadyChangesNothing(text: String) throws {
        #expect(try added(to: text) == text)
    }

    @Test func aCommentNamingTheTagIsNotATag() throws {
        let text = "---\ntags: [a,\n  # favorite\n  b]\n---\nBody\n"
        #expect(!NoteFile(text: text).isFavorite)
        #expect(try added(to: text) == "---\ntags: [a,\n  # favorite\n  b, favorite]\n---\nBody\n")
    }

    @Test func windowsLineEndingsAndAByteOrderMarkSurvive() throws {
        #expect(try added(to: "\u{FEFF}---\r\ntitle: A\r\n---\r\nBody\r\n") == "\u{FEFF}---\r\ntitle: A\r\ntags: [favorite]\r\n---\r\nBody\r\n")
        #expect(try added(to: "\u{FEFF}---\r\ntags:\r\n  - one\r\n---\r\nBody\r\n") == "\u{FEFF}---\r\ntags:\r\n  - one\r\n  - favorite\r\n---\r\nBody\r\n")
        #expect(try added(to: "---\r\ntags: [one]\r\n---\r\nBody\r\n") == "---\r\ntags: [one, favorite]\r\n---\r\nBody\r\n")
        #expect(try added(to: "---\r\ntags: one\r\n---\r\nBody\r\n") == "---\r\ntags: one, favorite\r\n---\r\nBody\r\n")
        #expect(try removed(from: "\u{FEFF}---\r\ntitle: A\r\ntags: [favorite]\r\n---\r\nBody\r\n") == "\u{FEFF}---\r\ntitle: A\r\n---\r\nBody\r\n")
        #expect(try removed(from: "\u{FEFF}---\r\ntags:\r\n  - one\r\n  - favorite\r\n---\r\nBody\r\n") == "\u{FEFF}---\r\ntags:\r\n  - one\r\n---\r\nBody\r\n")
    }

    // MARK: Removing

    @Test(arguments: [
        ("tags: [favorite, one]", "tags: [one]"),
        ("tags: [one, favorite]", "tags: [one]"),
        ("tags: [one, favorite, two]", "tags: [one, two]"),
        ("tags: [one,favorite,two]", "tags: [one,two]"),
        ("tags: [one, favorite,]", "tags: [one,]"),
        ("tags: [\"favorite\", 'one'] # keep", "tags: ['one'] # keep"),
        ("tags: [favorite, one, favorite]", "tags: [one]"),
        ("tags: [one, favorite, favorite]", "tags: [one]"),
        ("tags: [' favorite ', one]", "tags: [one]"),
        ("tags: ['it''s, ok', favorite]", "tags: ['it''s, ok']"),
        ("tags: [a,  # first\n  favorite]", "tags: [a  # first\n  ]"),
        ("tags: [favorite,\n  a]", "tags: [\n  a]"),
        ("tags:\n  - one\n  - favorite\n  - two", "tags:\n  - one\n  - two"),
        ("tags:\n- favorite\n- one", "tags:\n- one"),
        ("tags:\n  - one\n  # about it\n  - favorite # mine", "tags:\n  - one\n  # about it"),
        ("tags: work, favorite", "tags: work"),
        ("tags: favorite, work", "tags: work"),
        ("tags: a,favorite, b # kept", "tags: a, b # kept"),
        ("tags: \"favorite, a\"", "tags: \"a\""),
    ])
    func removingKeepsEveryOtherTagByteForByte(before: String, after: String) throws {
        #expect(try removed(from: "---\n\(before)\n---\nBody\n") == "---\n\(after)\n---\nBody\n")
    }

    @Test(arguments: [
        ("---\ntags: [favorite]\n---\nBody\n", "Body\n"),
        ("---\ntags: favorite\n---\nBody\n", "Body\n"),
        ("---\ntags:\n  - favorite\n---\nBody\n", "Body\n"),
        ("---\ntags: [favorite, favorite]\n---\nBody\n", "Body\n"),
        ("---\ntitle: A\ntags: [favorite]\ncustom: kept\n---\nBody\n", "---\ntitle: A\ncustom: kept\n---\nBody\n"),
        ("---\ntitle: A\ntags:\n  - favorite\n---\nBody\n", "---\ntitle: A\n---\nBody\n"),
        ("---\ntags:\n  - favorite\n  # kept\ntitle: x\n---\nBody\n", "---\n  # kept\ntitle: x\n---\nBody\n"),
        ("---\ntags:\n# kept\n- favorite\ntitle: x\n---\nBody\n", "---\n# kept\ntitle: x\n---\nBody\n"),
    ])
    func removingTheLastTagRemovesTheField(before: String, after: String) throws {
        #expect(try removed(from: before) == after)
    }

    @Test func removingFromANoteWithoutTheTagChangesNothing() throws {
        for text in ["Body\n", "---\ntags: [one]\n---\nBody\n", "---\ntitle: A\n---\nBody\n", "---\ntags:\n---\nBody\n"] {
            #expect(try removed(from: text) == text)
        }
    }

    // MARK: Refusing

    @Test(arguments: [
        "---\ntags: [1]\n---\nBody\n",
        "---\ntags: 5\n---\nBody\n",
        "---\ntags: {favorite: true}\n---\nBody\n",
        "---\ntags: [[favorite]]\n---\nBody\n",
        "---\ntags:\n  kind: favorite\n---\nBody\n",
        "---\ntags: work,\n---\nBody\n",
        "---\ntitle: [\n---\nBody\n",
        "---\ntags: [a]\n\"tags\": [b]\n---\nBody\n",
    ])
    func tagsMarfaCannotReadAreRefused(text: String) {
        var file = NoteFile(text: text)
        #expect(throws: NoteFile.TagEditError.unreadable) { try file.setFavorite(true) }
        #expect(file.text == text)
    }

    @Test(arguments: [
        ("---\ntags: >\n  a, b\n---\nBody\n", true),
        ("---\ntags: a\n  b\n---\nBody\n", true),
        ("---\ntags: \"a\\tb\"\n---\nBody\n", true),
        ("---\n- a\n---\nBody\n", true),
        ("---\ntags: >\n  favorite, b\n---\nBody\n", false),
        ("---\ntags: favorite, [b]\n---\nBody\n", false),
    ])
    func aFormWithNoSafeEditIsRefused(text: String, adding: Bool) {
        var file = NoteFile(text: text)
        #expect(throws: NoteFile.TagEditError.unsafe) { try file.setFavorite(adding) }
        #expect(file.text == text)
    }

    @Test func aQuotedKeyGetsNoSecondLine() throws {
        let on = try added(to: "---\n\"tags\": [a]\ntitle: A\n---\nBody\n")
        #expect(on == "---\n\"tags\": [a, favorite]\ntitle: A\n---\nBody\n")
        #expect(NoteFile(text: on).tags == ["a", "favorite"])
    }

    @Test func otherPropertiesAndTheBodyAreNeverTouched() throws {
        let text = "\u{FEFF}---\r\ntype: example.task\r\ncustom:\r\n  tags: [favorite]\r\ntitle: \"A: b\" # keep\r\n---\r\nBody\r\n"
        let on = try added(to: text)
        #expect(on == text.replacingOccurrences(of: "---\r\nBody", with: "tags: [favorite]\r\n---\r\nBody"))
        #expect(try removed(from: on) == text)
    }
}
