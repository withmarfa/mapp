import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MAPP

struct NoteLinksTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func note(_ title: String, minutes: Int = 0) -> Item {
        FakeItemLibrary.note(title, modified: start.addingTimeInterval(Double(minutes) * 60))
    }

    @Test func aTitleCanBeLinkedOnlyIfALinkReadsItBack() {
        for title in ["Garden ideas", "Café", "Q3: plan", "日本語のノート", "A \"quoted\" title"] {
            #expect(NoteLinks.canName(title), "\(title)")
        }
        for title in ["", " leading", "trailing ", "A|B", "A#B", "A [x]", "A]B", "back\\slash", "two\nlines", "two\r\nlines"] {
            #expect(!NoteLinks.canName(title), "\(title.debugDescription)")
        }
        #expect(NoteLinks.link(to: "Garden ideas") == "[[Garden ideas]]")
    }

    @Test func suggestionsFavorPrefixesThenRecentNotes() async {
        let items = [
            note("Regarding gardens", minutes: 9), note("Gardening tools", minutes: 1), note("Garden ideas", minutes: 5),
            note("Bike service", minutes: 7),
        ]
        let names = await NoteLinks.Index().names(matching: "gard", among: items, limit: 10)
        #expect(names == ["Garden ideas", "Gardening tools", "Regarding gardens"])
        #expect(await NoteLinks.Index().names(matching: "  GARD ", among: items, limit: 2) == ["Garden ideas", "Gardening tools"])
        #expect(await NoteLinks.Index().names(matching: "bk", among: items, limit: 10) == ["Bike service"], "letters in order")
    }

    @Test func suggestionsLeaveOutFilesTitlesALinkCannotNameAndSharedNames() async {
        var photo = note("Garden photo")
        photo.content = .file(.png, byteCount: 3)
        let items = [note("Garden ideas"), note("Garden notes"), note("Garden notes", minutes: 1), note("Garden | ideas"), photo, note("Garden [draft]")]
        let names = await NoteLinks.Index().names(matching: "garden", among: items, limit: 10)
        #expect(names == ["Garden ideas"])
    }

    @Test func anEmptyQueryOffersTheMostRecentNotesUpToTheLimit() async {
        let items = (0..<30).map { note("Note \($0)", minutes: $0) }
        let index = NoteLinks.Index()
        let names = await index.names(matching: "", among: items, limit: 12)
        #expect(names == (18..<30).reversed().map { "Note \($0)" })
        #expect(await index.names(matching: "zzz", among: items, limit: 12).isEmpty)
    }

    @Test func theIndexFollowsEditsAndRemovalsOfNotes() async {
        let index = NoteLinks.Index()
        var garden = note("Garden ideas")
        let bike = note("Bike service")
        #expect(await index.names(matching: "ga", among: [garden, bike], limit: 5) == ["Garden ideas"])
        garden.title = "Allotment plan"
        garden.version = ItemVersion(garden.version.rawValue + 1)
        #expect(await index.names(matching: "ga", among: [garden, bike], limit: 5).isEmpty, "a renamed note is found by its new title")
        #expect(await index.names(matching: "allot", among: [garden, bike], limit: 5) == ["Allotment plan"])
        #expect(await index.names(matching: "allot", among: [bike], limit: 5).isEmpty, "a removed note is forgotten")
    }

    @Test func aLargeLibraryIsReadOnceAndAKeystrokeFoldsNothingAgain() async {
        let titles = ["alpha", "beta", "gamma", "delta", "kitchen", "garden", "recipe", "meeting"]
        var items = (0..<20_000).map { note("\(titles[$0 % titles.count]) \($0)", minutes: $0) }
        let index = NoteLinks.Index()
        let clock = ContinuousClock()
        var names: [String] = []
        let first = await clock.measure { names = await index.names(matching: "g", among: items, limit: 12) }
        #expect(names.count == 12)
        #expect(await index.foldedCount == 20_000)
        for typed in ["ga", "gar", "gard", "garden 1"] {
            names = await index.names(matching: typed, among: items, limit: 12)
        }
        #expect(names.count == 12)
        #expect(names.allSatisfy { $0.hasPrefix("garden 1") })
        #expect(await index.foldedCount == 20_000, "typing on folded nothing again")
        items[7].title = "garden shed"
        items[7].version = ItemVersion(items[7].version.rawValue + 1)
        #expect(await index.names(matching: "garden s", among: items, limit: 12).first == "garden shed")
        #expect(await index.foldedCount == 20_001, "an edit folds only the note edited")
        FileHandle.standardError.write(Data("NoteLinks index, 20,000 notes: first query \(first)\n".utf8))
    }

    @Test func aTitleAnotherNoteAlsoGoesByIsNotOffered() async {
        let items = [note("Garden", minutes: 1), note("garden", minutes: 2), note("Gardening", minutes: 3), note("Café", minutes: 4), note("Cafe\u{301}", minutes: 5)]
        let index = NoteLinks.Index()
        #expect(await index.names(matching: "gard", among: items, limit: 10) == ["Gardening"], "case-only twins are one name")
        #expect(await index.names(matching: "caf", among: items, limit: 10).isEmpty, "accent forms compare as the library compares them")
        // Once a twin goes, the other is offered.
        #expect(await index.names(matching: "gard", among: Array(items.dropFirst()), limit: 10).contains("garden"))
    }

    @Test func theSuggestionScoresAreTheCommandPalettesForTheSameTitles() {
        let pairs = [
            ("किताब", "ताब"), ("किताब", "ता"), ("किताब", "ब"), ("किताब", "किता"), ("किTable", "Table"),
            ("Café plans", "plans"), ("Café plans", "CAFE"), ("Éclair", "ECL"), ("👩‍💻 project", "👩"), ("👩‍💻 project", "project"),
            ("日本語のノート", "ノート"), ("New Note", "nn"), ("New Note", "nx"), ("Move to Inbox", "inb"), ("Unpin Note", "pin"),
            ("Spinach", "pin"), ("Pin Note", "pin"),
        ]
        for (title, typed) in pairs {
            #expect(NoteLinks.score(folded: Array(NoteLinks.fold(title)), NoteLinks.Query(typed)) == PaletteMatch.score(title, typed), "\(title) for \(typed)")
        }
    }

    @Test func aLibraryNamesTheNoteChosenOrNoneWhenOnlyAnotherCouldBeMeant() {
        let alone = note("Garden ideas", minutes: 1)
        let twin = note("garden IDEAS", minutes: 2)
        let odd = note("A|B", minutes: 3)
        let library = FakeItemLibrary(items: [alone, twin, odd, note("Old", minutes: 4)])
        #expect(library.bodyLink(to: alone.id) == nil, "a twin goes by the same name")
        #expect(library.bodyLink(to: odd.id) == nil, "a link cannot spell this title")
        #expect(library.bodyLink(to: library.items[3].id) == "[[Old]]")
        #expect(library.notesToLink(excluding: library.items[3].id).map(\.title) == ["A|B", "garden IDEAS", "Garden ideas"])
    }

    @Test func aTitleShapedLikeAnIdentityIsNeverLinkedByTitle() {
        // A link spelled as an identity names the item with that identity, not one that has the text as its title.
        let identity = "11111111-1111-4111-8111-111111111111"
        let shaped = note(identity, minutes: 1)
        let plain = note("Other", minutes: 2)
        let library = FakeItemLibrary(items: [shaped, plain])
        #expect(!NoteLinks.canName(identity))
        #expect(library.bodyLink(to: shaped.id) == nil, "the spelling would name another item")
        #expect(library.bodyLink(to: plain.id) == "[[Other]]")
    }

    @Test func aTitleShapedLikeAnIdentityIsNotSuggested() async {
        let identity = "11111111-1111-4111-8111-111111111111"
        let names = await NoteLinks.Index().names(matching: "1111", among: [note(identity), note("Other")], limit: 10)
        #expect(names.isEmpty)
    }

    @Test func requestsFromThePageAreReadOrRefused() {
        #expect(NoteRequest(body: ["type": "suggest", "query": "gar"]) == .suggest("gar"))
        #expect(NoteRequest(body: ["type": "suggest", "query": ""]) == .suggest(""))
        #expect(NoteRequest(body: ["type": "pick", "item": "abc"]) == .pick(ItemID("abc")))
        #expect(NoteRequest(body: ["type": "pick", "item": ""]) == nil)
        #expect(NoteRequest(body: ["type": "suggest"]) == nil)
        #expect(NoteRequest(body: ["type": "delete", "item": "abc"]) == nil)
        #expect(NoteRequest(body: "suggest") == nil)
    }
}
