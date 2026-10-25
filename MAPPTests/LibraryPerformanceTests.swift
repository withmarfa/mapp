import Foundation
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import MAPP

/// Times what the views ask of a large library. The ceilings are far above what a Mac takes, so they catch a
/// read that has turned quadratic, which took seconds here, rather than ordinary noise; the timings are kept for
/// comparing builds.
@MainActor @Suite(.serialized)
struct LibraryPerformanceTests {
    static let itemCount = 3_000
    static let fileCount = 200

    /// Projects, tasks under them, and notes that reference one another, with a few in the Inbox, a few favorites,
    /// a few in the bin and some files beside them.
    static func makeLibrary() async throws -> (MarfaLibrary, FakeItemSource) {
        typealias Fixture = LibraryFixture
        var items: [Item] = []
        for index in 0..<itemCount {
            let id = ItemID("item-\(index)")
            var type = Fixture.note
            var edges = [Edge(
                id: EdgeID("r-\(index)"), type: "references", source: id,
                target: .item(ItemID("item-\((index + 7) % itemCount)")), origin: .body)]
            switch index % 10 {
            case 0: type = Fixture.project
            case 1...5:
                type = Fixture.task
                edges.append(Fixture.child("c-\(index)", id, of: ItemID("item-\(index / 10 * 10)")))
            default: break
            }
            items.append(Fixture.item(
                id, type, "Item \(index)", age: index, state: index % 100 == 99 ? .trashed : .active,
                tier: index % 6 == 0 ? .feed : .library, tags: index % 50 == 0 ? [ItemTag.favorite] : [], edges: edges))
        }
        for index in 0..<fileCount {
            items.append(Fixture.item(
                ItemID("file-\(index)"), Fixture.image, "File \(index).png", age: index,
                content: .file(.png, byteCount: 1_024)))
        }
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source)
        source.send(.loaded(SourceSnapshot(items: items, catalogue: Fixture.catalogue)))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    /// The median of several runs, in milliseconds, after one run to warm caches as a running app has.
    static func measure(runs: Int = 7, _ body: () -> Void) -> Double {
        body()
        var times: [Double] = []
        for _ in 0..<runs {
            let clock = ContinuousClock()
            let elapsed = clock.measure(body)
            times.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1e3)
        }
        return times.sorted()[runs / 2]
    }

    @Test func readingALargeLibraryStaysFast() async throws {
        let (library, source) = try await Self.makeLibrary()
        let browser = Browser()
        let order = NoteOrder()
        let item = ItemID("item-1")
        let places: [SidebarItem] = [.inbox, .allNotes, .favorites, .files, .recentlyDeleted]
            + library.itemTypeCounts.map { .itemType($0.id.rawValue) }
        let active = library.count(in: .allNotes)
        #expect(active > Self.itemCount / 2)

        let all = Self.measure {
            let sections = browser.sections(in: library, order: order, now: .now)
            #expect(sections.reduce(0) { $0 + $1.items.count } == active)
        }
        // The views hold the library as `any ItemLibrary`; reading through it should cost what reading it directly does.
        let existential: any ItemLibrary = library
        let direct = Self.measure { #expect(!library.items(in: .allNotes).isEmpty) }
        let throughProtocol = Self.measure { #expect(!existential.items(in: .allNotes).isEmpty) }
        let type = Self.measure { #expect(!library.items(in: .itemType(LibraryFixture.task.rawValue)).isEmpty) }
        let relationships = Self.measure {
            #expect(library.item(item) != nil)
            #expect(!library.relationships(for: item).isEmpty)
        }
        let counts = Self.measure { #expect(places.reduce(0) { $0 + library.count(in: $1) } > 0) }

        // A keystroke: one item changes, and the list and the counts are read again.
        var typed = try #require(library.item(item))
        typed.preview = "Typed"
        source.send(.upserted([typed]))
        try #require(await eventually { library.item(item)?.preview == "Typed" })
        let keystroke = Self.measure {
            #expect(!library.items(in: .allNotes).isEmpty)
            #expect(places.reduce(0) { $0 + library.count(in: $1) } > 0)
        }

        source.hits.withLock { $0["item"] = library.items(in: .allNotes).prefix(500).map(\.id) }
        try #require(await eventually { library.items(matching: "item").count == 500 })
        let search = Self.measure { #expect(library.items(matching: "item").count == 500) }

        let timings = [
            ("items in All Items", all), ("All Items read directly", direct), ("All Items read through ItemLibrary", throughProtocol),
            ("items of a type", type), ("an item and its relationships", relationships), ("sidebar counts", counts),
            ("a keystroke's list and counts", keystroke), ("search results", search),
        ]
        let report = timings.map { "\($0): \(String(format: "%.3f", $1)) ms\n" }.joined()
        Attachment.record(report, named: "MAPP performance.txt")

        #expect(all < 50)
        #expect(direct < 50)
        #expect(throughProtocol < 50)
        #expect(type < 50)
        #expect(relationships < 50)
        #expect(counts < 50)
        #expect(keystroke < 50)
        #expect(search < 50)
    }
}
