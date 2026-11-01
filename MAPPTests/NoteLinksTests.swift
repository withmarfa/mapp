import Foundation
import Marfa
import Testing
import UniformTypeIdentifiers
@testable import MAPP

@Suite(.hangLimit)
struct NoteLinksTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func note(_ title: String, minutes: Int = 0) -> MAPP.Item {
        FakeItemLibrary.note(title, modified: start.addingTimeInterval(Double(minutes) * 60))
    }

    @Test func aTitleIsSpelledAsALinkOnlyIfTheCoreReadsItBackWhole() {
        for title in ["Garden ideas", "Café", "Q3: plan", "日本語のノート", "A \"quoted\" title", "back\\slash", "😀 plans", "Plan\\", "a\\b"] {
            #expect(NoteLinks.spells(title, as: title), "\(title)")
            #expect(NoteLinks.isPlainName(title), "\(title)")
        }
        for title in ["", " leading", "trailing ", "A|B", "A#B", "A [x]]", "two\nlines", "two\r\nlines"] {
            #expect(!(NoteLinks.isPlainName(title) && NoteLinks.spells(title, as: title)), "\(title.debugDescription)")
        }
        for title in ["A]B", "a[b]", "a[b", "A|B", "A#B"] {
            #expect(!NoteLinks.isPlainName(title), "Inkkit draws no link for \(title.debugDescription)")
        }
    }

    @Test func aLinkIsReadByTheCoreWithUTF16RangesAfterEmoji() throws {
        let text = "😀👩‍👩‍👧 see [[Plan#Soil|soil]] then [[Next]]"
        let parts = linkParts(in: text)
        #expect(parts.count == 2)
        let ns = text as NSString
        for part in parts {
            #expect(ns.substring(with: part.range) == part.text)
            #expect(ns.substring(with: part.name.range) == part.name.text)
        }
        #expect(parts[0].name.text == "Plan" && parts[0].heading?.text == "Soil" && parts[0].alias?.text == "soil")
        let link = try #require(NoteLink(linkText: parts[0].text))
        #expect(link.raw == "Plan#Soil|soil" && link.name == "Plan" && link.heading == "Soil")
    }

    @Test func aBackslashInALinkIsPartOfTheText() throws {
        let link = try #require(NoteLink(linkText: "[[A\\B]]"))
        #expect(link.name == "A\\B" && link.raw == "A\\B")
        // The page reads a backslash as an escape; the link is read again from its raw text.
        let posted = try #require(NoteLink(page: ["raw": "[[A\\|B]]", "target": "A|B"]))
        #expect(posted.name == "A\\" && posted.raw == "A\\|B")
        #expect(NoteLink(page: ["target": "Plan"]) == nil)
        #expect(NoteLink(page: ["raw": "Plan", "target": "Plan"]) == nil)
        #expect(NoteLink(linkText: "[[Plan]] and more") == nil)
    }

    @Test func linksAreTheSameOnlyWhenWrittenTheSame() throws {
        let plain = try #require(NoteLink(linkText: "[[Plan]]"))
        let aliased = try #require(NoteLink(linkText: "[[Plan|Plan]]"))
        #expect(plain != aliased)
        #expect(plain == NoteLink(linkText: "[[Plan]]"))
        #expect(try #require(NoteLink(linkText: "[[Cafe\u{301}]]")) != NoteLink(linkText: "[[Café]]"))
    }

    @Test func suggestionsFavorPrefixesThenRecentNotes() async {
        let items = [
            note("Regarding gardens", minutes: 9), note("Gardening tools", minutes: 1), note("Garden ideas", minutes: 5),
            note("Bike service", minutes: 7),
        ]
        let names = await NoteLinks.Index().titles(matching: "gard", among: items, limit: 10)
        #expect(names == ["Garden ideas", "Gardening tools", "Regarding gardens"])
        #expect(await NoteLinks.Index().titles(matching: "  GARD ", among: items, limit: 2) == ["Garden ideas", "Gardening tools"])
        #expect(await NoteLinks.Index().titles(matching: "bk", among: items, limit: 10) == ["Bike service"], "letters in order")
    }

    @Test func suggestionsLeaveOutFiles() async {
        var photo = note("Garden photo")
        photo.content = .file(.png, byteCount: 3)
        let names = await NoteLinks.Index().titles(matching: "garden", among: [note("Garden ideas"), photo], limit: 10)
        #expect(names == ["Garden ideas"])
    }

    @Test func anEmptyQueryOffersTheMostRecentNotesUpToTheLimit() async {
        let items = (0..<30).map { note("Note \($0)", minutes: $0) }
        let index = NoteLinks.Index()
        let names = await index.titles(matching: "", among: items, limit: 12)
        #expect(names == (18..<30).reversed().map { "Note \($0)" })
        #expect(await index.titles(matching: "zzz", among: items, limit: 12).isEmpty)
    }

    @Test func theIndexFollowsEditsAndRemovalsOfNotes() async {
        let index = NoteLinks.Index()
        var garden = note("Garden ideas")
        let bike = note("Bike service")
        #expect(await index.titles(matching: "ga", among: [garden, bike], limit: 5) == ["Garden ideas"])
        garden.title = "Allotment plan"
        garden.version = ItemVersion(garden.version.rawValue + 1)
        #expect(await index.titles(matching: "ga", among: [garden, bike], limit: 5).isEmpty, "a renamed note is found by its new title")
        #expect(await index.titles(matching: "allot", among: [garden, bike], limit: 5) == ["Allotment plan"])
        #expect(await index.titles(matching: "allot", among: [bike], limit: 5).isEmpty, "a removed note is forgotten")
    }

    @Test func aLargeLibraryIsReadOnceAndAKeystrokeFoldsNothingAgain() async {
        let titles = ["alpha", "beta", "gamma", "delta", "kitchen", "garden", "recipe", "meeting"]
        var items = (0..<20_000).map { note("\(titles[$0 % titles.count]) \($0)", minutes: $0) }
        let index = NoteLinks.Index()
        let clock = ContinuousClock()
        var names: [String] = []
        let first = await clock.measure { names = await index.titles(matching: "g", among: items, limit: 12) }
        #expect(names.count == 12)
        #expect(await index.foldedCount == 20_000)
        for typed in ["ga", "gar", "gard", "garden 1"] {
            names = await index.titles(matching: typed, among: items, limit: 12)
        }
        #expect(names.count == 12)
        #expect(names.allSatisfy { $0.hasPrefix("garden 1") })
        #expect(await index.foldedCount == 20_000, "typing on folded nothing again")
        items[7].title = "garden shed"
        items[7].version = ItemVersion(items[7].version.rawValue + 1)
        #expect(await index.titles(matching: "garden s", among: items, limit: 12).first == "garden shed")
        #expect(await index.foldedCount == 20_001, "an edit folds only the note edited")
        FileHandle.standardError.write(Data("NoteLinks index, 20,000 notes: first query \(first)\n".utf8))
    }

    @Test func aLibraryNamesTheNoteChosenByTitleOrByIdentity() async {
        let alone = note("Garden ideas", minutes: 1)
        let twin = note("garden IDEAS", minutes: 2)
        let odd = note("A|B", minutes: 3)
        let library = FakeItemLibrary(items: [alone, twin, odd, note("Old", minutes: 4)])
        #expect(await library.bodyLink(to: alone.id, in: nil) == "[[\(alone.id.rawValue)|Garden ideas]]", "a twin goes by the same name, so its identity names it")
        #expect(await library.bodyLink(to: odd.id, in: nil) == "[[\(odd.id.rawValue)|A B]]", "a link cannot spell this title, so its identity names it")
        #expect(await library.bodyLink(to: library.items[3].id, in: nil) == "[[Old]]")
        #expect(library.notesToLink(excluding: library.items[3].id).map(\.title) == ["A|B", "garden IDEAS", "Garden ideas"])
    }

    @Test func aTitleLinkIsWrittenOnlyWhereTheCoreBindsItToTheNote() async {
        let plan = note("Plan")
        let library = FakeItemLibrary(items: [plan])
        library.linkAnswerOverrides["Plan"] = LinkAnswer(target: "Plan", state: .unresolved, item: nil, candidates: [plan.id])
        #expect(await library.bodyLink(to: plan.id, in: nil) == "[[\(plan.id.rawValue)|Plan]]", "one held note is not proof it is the only one")
        library.linkAnswerOverrides["Plan"] = LinkAnswer(target: "Plan", state: .bound, item: plan.id, candidates: [plan.id])
        #expect(await library.bodyLink(to: plan.id, in: nil) == "[[Plan]]")
    }

    @Test func aSuggestionIsATitleTheCoreBindsToItsOwnNote() async {
        let library = FakeItemLibrary(items: [note("Garden", minutes: 1), note("garden", minutes: 2), note("Gardening", minutes: 3), note("Garden | x", minutes: 4)])
        let index = NoteLinks.Index()
        #expect(await library.noteNames(matching: "gard", using: index) == ["Gardening"], "twins are ambiguous, and a title with a bar cannot be spelled")
        // The core, not the app, decides: a name it says is unresolved is not offered.
        library.linkAnswerOverrides["Gardening"] = LinkAnswer(target: "Gardening", state: .ambiguous, item: nil, candidates: [])
        #expect(await library.noteNames(matching: "gard", using: index).isEmpty)
    }

    @Test func aBackslashIsLiteralInEverySpelling() {
        #expect(NoteLinks.spells("id|Plan\\", as: "id", alias: "Plan\\"))
        #expect(NoteLinks.spells("id|C:\\dir", as: "id", alias: "C:\\dir"))
        #expect(NoteLinks.spells("Plan\\", as: "Plan\\"))
        #expect(NoteLinks.spells("a\\b", as: "a\\b"))
    }

    @Test func eachAwkwardTitleIsLinkedWithoutAnAddedBackslash() async {
        let titles = ["Plan\\", "a|b", "a#b", "a[b]", "a\\b"]
        let notes = titles.map { note($0) }
        let library = FakeItemLibrary(items: notes)
        for (title, item) in zip(titles, notes) {
            let link = await library.bodyLink(to: item.id, in: nil)
            let text = link
            #expect(text?.filter { $0 == "\\" }.count == title.filter { $0 == "\\" }.count, "\(title): \(link ?? "nil")")
            let parts = linkParts(in: text ?? "")
            #expect(parts.count == 1 && parts.first?.text == text, "\(title): \(link ?? "nil")")
            let name = parts.first?.name.text
            #expect(name == item.id.rawValue || name == title, "\(title) names \(name ?? "nil")")
            #expect(parts.first?.heading == nil, "\(title)")
        }
        #expect(await library.bodyLink(to: notes[0].id, in: nil) == "[[Plan\\]]", "both readers take the trailing backslash literally")
        #expect(await library.bodyLink(to: notes[1].id, in: nil) == "[[\(notes[1].id.rawValue)|a b]]")
        #expect(await library.bodyLink(to: notes[2].id, in: nil) == "[[\(notes[2].id.rawValue)|a b]]")
        #expect(await library.bodyLink(to: notes[3].id, in: nil) == "[[\(notes[3].id.rawValue)|a b]]")
        #expect(await library.bodyLink(to: notes[4].id, in: nil) == "[[a\\b]]")
    }

    @Test func aLabelIsOneLineAndNothingIsEscaped() {
        let cases = [("Plan", "Plan"), ("A|B", "A B"), ("a#b", "a b"), ("a[b]", "a b"), ("back\\slash", "back\\slash"), ("Plan\\", "Plan\\"), ("A\\|B", "A\\ B"), ("two\nlines", "two lines"), (" padded ", "padded"), ("\n\u{0}", ""), ("[]|#", "")]
        for (title, label) in cases { #expect(NoteLinks.label(title) == label, "\(title.debugDescription)") }
    }
}

extension NoteLinks.Index {
    func titles(matching text: String, among items: [MAPP.Item], limit: Int) async -> [String] {
        await matches(for: text, among: items, limit: limit).map(\.title)
    }
}
