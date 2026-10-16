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

    @Test func suggestionsLeaveOutFilesTitlesALinkCannotNameAndRepeats() async {
        var photo = note("Garden photo")
        photo.content = .file(.png, byteCount: 3)
        let items = [note("Garden ideas"), note("Garden ideas", minutes: 1), note("Garden | ideas"), photo, note("Garden [draft]")]
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

    @Test func aLargeLibraryIsSearchedQuicklyAndAKeystrokeFoldsNothingAgain() async {
        let titles = ["alpha", "beta", "gamma", "delta", "kitchen", "garden", "recipe", "meeting"]
        let items = (0..<20_000).map { note("\(titles[$0 % titles.count]) \($0)", minutes: $0) }
        let index = NoteLinks.Index()
        let clock = ContinuousClock()
        var names: [String] = []
        let first = await clock.measure { names = await index.names(matching: "g", among: items, limit: 12) }
        #expect(names.count == 12)
        let typed = await clock.measure { names = await index.names(matching: "garden 1", among: items, limit: 12) }
        #expect(names.count == 12)
        #expect(names.allSatisfy { $0.hasPrefix("garden 1") })
        print("NoteLinks index, 20,000 notes: first query \(first), next query \(typed)")
        #expect(typed < .seconds(1), "the next query over 20,000 notes took \(typed)")
        #expect(first < .seconds(10), "the first query over 20,000 notes took \(first)")
    }

    @Test func aTargetNamesTheNoteTheLibraryWouldResolveIt() {
        let garden = note("Garden ideas", minutes: 1)
        let newer = note("garden IDEAS", minutes: 5)
        let cafe = note("Cafe\u{301} menu")
        var photo = note("Garden photo")
        photo.content = .file(.png, byteCount: 3)
        let paths = [garden.id: "Home/garden-notes.md", cafe.id: "Cafe menu.md"]
        let items = [garden, newer, cafe, photo]
        func resolve(_ target: String) -> Item? { NoteLinks.note(named: target, among: items, pathOf: { paths[$0] }) }
        #expect(resolve("Garden ideas")?.id == newer.id, "equal titles answer with the most recently edited")
        #expect(resolve("  GARDEN IDEAS ")?.id == newer.id)
        #expect(resolve("Café menu")?.id == cafe.id, "accents compare in one form")
        #expect(resolve("Home/garden-notes.md")?.id == garden.id)
        #expect(resolve("Home/garden-notes")?.id == garden.id)
        #expect(resolve("garden-notes")?.id == garden.id)
        #expect(resolve("Garden photo") == nil, "a file is not a note")
        #expect(resolve("Nowhere") == nil)
        #expect(resolve("   ") == nil)
    }

    @Test func theLibraryAnswersWithOnlyNotesItCanLinkTo() async {
        let current = note("Current", minutes: 3)
        let library = FakeItemLibrary(items: [note("Old", minutes: 1), current, note("A|B", minutes: 5), note("New", minutes: 4)])
        #expect(library.linkableNotes(excluding: current.id).map(\.title) == ["New", "Old"])
        #expect(await library.noteNames(matching: "n", using: NoteLinks.Index()) == ["New", "Current"])
        #expect(library.note(named: "old")?.title == "Old")
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
