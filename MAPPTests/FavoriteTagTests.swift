import Foundation
import Testing
@testable import MAPP

/// A favorite is Marfa's ordinary `favorite` tag, which a file holds as a `tags` front matter list.
struct FavoriteTagTests {
    private func added(to text: String) -> String {
        var file = NoteFile(text: text)
        file.setFavorite(true)
        return file.text
    }

    private func removed(from text: String) -> String {
        var file = NoteFile(text: text)
        file.setFavorite(false)
        return file.text
    }

    // MARK: Reading

    @Test(arguments: [
        "---\ntags: [favorite]\n---\nBody\n",
        "---\ntags: [other, favorite]\n---\nBody\n",
        "---\ntags: [ \"favorite\" , 'other' ] # note\n---\nBody\n",
        "---\ntags:\n  - favorite\n---\nBody\n",
        "---\ntags:\n- other\n- favorite # kept\n---\nBody\n",
        "---\ntags: # tags\n  - \"favorite\"\n---\nBody\n",
        "---\ntags: [other,\n  favorite]\n---\nBody\n",
        "\u{FEFF}---\r\ntags: [favorite]\r\n---\r\nBody\r\n",
    ])
    func aListHoldingFavoriteMakesTheNoteAFavorite(text: String) {
        #expect(NoteFile(text: text).isFavorite)
    }

    @Test(arguments: [
        "Body\n",
        "---\ntitle: A\n---\nBody\n",
        "---\ntags: [other]\n---\nBody\n",
        "---\ntags: []\n---\nBody\n",
        "---\ntags: favorite\n---\nBody\n",
        "---\ntags:\n---\nBody\n",
        "---\ntags: [[favorite]]\n---\nBody\n",
        "---\ntags: {favorite: true}\n---\nBody\n",
        "---\ntags:\n  - other\n---\nBody\n",
        "---\ntags: [\"favorite]\n---\nBody\n",
        "---\ntags: [favorite] trailing\n---\nBody\n",
        "---\ntagsfavorite: [favorite]\n---\nBody\n",
        "---\ncustom:\n  tags: [favorite]\n---\nBody\n",
        "---\ntags: [favorites, unfavorite]\n---\nBody\n",
    ])
    func anythingElseIsNotAFavorite(text: String) {
        #expect(!NoteFile(text: text).isFavorite)
    }

    @Test func tagsAreTheScalarsOfTheList() {
        #expect(NoteFile(text: "---\ntags: [a, \"b c\", 'd']\n---\n").tags == ["a", "b c", "d"])
        #expect(NoteFile(text: "---\ntags:\n  - a\n  - \"b c\"\n---\n").tags == ["a", "b c"])
        #expect(NoteFile(text: "---\ntags: a\n---\n").tags.isEmpty)
    }

    // MARK: Adding

    @Test func aNoteWithoutTagsGetsAFlowList() {
        #expect(added(to: "Body\n") == "---\ntags: [favorite]\n---\nBody\n")
        #expect(added(to: "---\ntitle: A\n---\nBody\n") == "---\ntitle: A\ntags: [favorite]\n---\nBody\n")
    }

    @Test(arguments: [
        ("---\ntags: []\n---\n", "---\ntags: [favorite]\n---\n"),
        ("---\ntags: [one]\n---\n", "---\ntags: [one, favorite]\n---\n"),
        ("---\ntags: [one,two]\n---\n", "---\ntags: [one,two, favorite]\n---\n"),
        ("---\ntags: [one, two,]\n---\n", "---\ntags: [one, two, favorite]\n---\n"),
        ("---\ntags: [one, two, ]\n---\n", "---\ntags: [one, two, favorite]\n---\n"),
        ("---\ntags: [ \"a]\" ] # keep ]\n---\n", "---\ntags: [ \"a]\" , favorite] # keep ]\n---\n"),
        ("---\ntags: [one,\n  two]\n---\n", "---\ntags: [one,\n  two, favorite]\n---\n"),
    ])
    func aFlowListGainsTheTagInPlace(before: String, after: String) {
        #expect(added(to: before + "Body\n") == after + "Body\n")
    }

    @Test(arguments: [
        ("---\ntags:\n  - one\n---\n", "---\ntags:\n  - one\n  - favorite\n---\n"),
        ("---\ntags:\n- one\n- two\ntitle: A\n---\n", "---\ntags:\n- one\n- two\n- favorite\ntitle: A\n---\n"),
        ("---\ntags: # all\n    -   one # first\n---\n", "---\ntags: # all\n    -   one # first\n    -   favorite\n---\n"),
        ("---\ntags:\n  - one\n\ntitle: A\n---\n", "---\ntags:\n  - one\n  - favorite\n\ntitle: A\n---\n"),
    ])
    func aBlockListGainsTheTagInItsOwnForm(before: String, after: String) {
        #expect(added(to: before + "Body\n") == after + "Body\n")
    }

    @Test func addingToAListThatHasItChangesNothing() {
        let text = "---\ntags: [favorite, other]\n---\nBody\n"
        #expect(added(to: text) == text)
    }

    @Test func windowsLineEndingsAndAByteOrderMarkSurvive() {
        #expect(added(to: "\u{FEFF}---\r\ntitle: A\r\n---\r\nBody\r\n") == "\u{FEFF}---\r\ntitle: A\r\ntags: [favorite]\r\n---\r\nBody\r\n")
        #expect(added(to: "\u{FEFF}---\r\ntags:\r\n  - one\r\n---\r\nBody\r\n") == "\u{FEFF}---\r\ntags:\r\n  - one\r\n  - favorite\r\n---\r\nBody\r\n")
        #expect(added(to: "---\r\ntags: [one]\r\n---\r\nBody\r\n") == "---\r\ntags: [one, favorite]\r\n---\r\nBody\r\n")
        #expect(removed(from: "\u{FEFF}---\r\ntitle: A\r\ntags: [favorite]\r\n---\r\nBody\r\n") == "\u{FEFF}---\r\ntitle: A\r\n---\r\nBody\r\n")
        #expect(removed(from: "\u{FEFF}---\r\ntags:\r\n  - one\r\n  - favorite\r\n---\r\nBody\r\n") == "\u{FEFF}---\r\ntags:\r\n  - one\r\n---\r\nBody\r\n")
    }

    // MARK: Removing

    @Test(arguments: [
        ("---\ntags: [favorite, one]\n---\n", "---\ntags: [one]\n---\n"),
        ("---\ntags: [one, favorite]\n---\n", "---\ntags: [one]\n---\n"),
        ("---\ntags: [one, favorite, two]\n---\n", "---\ntags: [one, two]\n---\n"),
        ("---\ntags: [one,favorite,two]\n---\n", "---\ntags: [one,two]\n---\n"),
        ("---\ntags: [one, favorite,]\n---\n", "---\ntags: [one,]\n---\n"),
        ("---\ntags: [\"favorite\", 'one'] # keep\n---\n", "---\ntags: ['one'] # keep\n---\n"),
        ("---\ntags: [favorite, one, favorite]\n---\n", "---\ntags: [one]\n---\n"),
        ("---\ntags:\n  - one\n  - favorite\n  - two\n---\n", "---\ntags:\n  - one\n  - two\n---\n"),
        ("---\ntags:\n- favorite\n- one\n---\n", "---\ntags:\n- one\n---\n"),
    ])
    func removingKeepsEveryOtherTagByteForByte(before: String, after: String) {
        #expect(removed(from: before + "Body\n") == after + "Body\n")
    }

    @Test(arguments: [
        ("---\ntags: [favorite]\n---\nBody\n", "Body\n"),
        ("---\ntags:\n  - favorite\n---\nBody\n", "Body\n"),
        ("---\ntags:\n- favorite\n---\nBody\n", "Body\n"),
        ("---\ntags: [favorite, favorite]\n---\nBody\n", "Body\n"),
        ("---\ntitle: A\ntags: [favorite]\ncustom: kept\n---\nBody\n", "---\ntitle: A\ncustom: kept\n---\nBody\n"),
        ("---\ntitle: A\ntags:\n  - favorite\n---\nBody\n", "---\ntitle: A\n---\nBody\n"),
    ])
    func removingTheLastTagRemovesTheWholeLine(before: String, after: String) {
        #expect(removed(from: before) == after)
    }

    @Test func removingFromANoteWithoutTheTagChangesNothing() {
        for text in ["Body\n", "---\ntags: [one]\n---\nBody\n", "---\ntitle: A\n---\nBody\n"] {
            #expect(removed(from: text) == text)
        }
    }

    // MARK: Not a list

    @Test(arguments: [
        "---\ntags: one\n---\nBody\n",
        "---\ntags: favorite\n---\nBody\n",
        "---\ntags:\n---\nBody\n",
        "---\ntags: {favorite: true}\n---\nBody\n",
        "---\ntags: [[favorite]]\n---\nBody\n",
        "---\ntags:\n  kind: favorite\n---\nBody\n",
    ])
    func aTagsValueThatIsNotAListIsLeftAlone(text: String) {
        #expect(added(to: text) == text)
        #expect(removed(from: text) == text)
        #expect(!NoteFile(text: text).isFavorite)
    }

    @Test func otherPropertiesAndTheBodyAreNeverTouched() {
        let text = "\u{FEFF}---\r\ntype: example.task\r\ncustom:\r\n  tags: [favorite]\r\ntitle: \"A: b\" # keep\r\n---\r\nBody\r\n"
        let on = added(to: text)
        #expect(on == text.replacingOccurrences(of: "---\r\nBody", with: "tags: [favorite]\r\n---\r\nBody"))
        #expect(removed(from: on) == text)
    }
}
