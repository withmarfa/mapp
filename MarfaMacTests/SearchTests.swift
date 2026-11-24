import Foundation
import Synchronization
import Testing
@testable import MarfaMac

@Suite struct SearchExcerptTests {
    @Test func anExcerptDescribesOnlyTheItemItWasCutFrom() {
        let date = Date(timeIntervalSince1970: 5)
        var item = LibraryFixture.item(LibraryFixture.n1, LibraryFixture.note, "Note", age: 1)
        item.modified = date
        let found = SearchExcerpt(runs: [.init(text: "x", isMatch: false)], version: item.version, modified: date)
        #expect(found?.describes(item) == true)
        item.version = ItemVersion(2)
        #expect(found?.describes(item) == false)
    }
}

@MainActor
@Suite(.hangLimit) struct MarfaLibrarySearchTests {
    typealias F = LibraryFixture

    private func loaded(filling: Bool = false) async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        if filling { source.report.update { $0.fill = LibraryFill(state: .filling, listed: 1, expected: 9) } }
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: F.items, catalogue: F.catalogue)))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    @Test func anExcerptShowsWhileTrueAndGoesWhenTheItemChanges() async throws {
        let (library, source) = try await loaded()
        let item = try #require(library.item(F.n1))
        source.hits.withLock { $0["body"] = [F.n1] }
        let excerpt = try #require(SearchExcerpt(
            runs: [.init(text: "a ", isMatch: false), .init(text: "body", isMatch: true)], version: item.version, modified: item.modified))
        source.excerpts.withLock { $0["body"] = [F.n1: excerpt] }
        #expect(await eventually { library.search("body", in: .everywhere).excerpts[F.n1] != nil })

        var edited = item
        edited.version = ItemVersion(2)
        source.send(.upserted([edited]))
        #expect(await eventually { library.item(F.n1)?.version == ItemVersion(2) })
        #expect(await eventually {
            let found = library.search("body", in: .everywhere)
            return found.items.map(\.id) == [F.n1] && found.excerpts.isEmpty
        })
    }

    @Test func anItemSentToTheBinWhileShownLeavesTheResultsAtOnce() async throws {
        let (library, source) = try await loaded()
        source.hits.withLock { $0["body"] = [F.n1, F.p1] }
        #expect(await eventually { library.search("body", in: .everywhere).items.map(\.id) == [F.n1, F.p1] })
        var binned = try #require(library.item(F.n1))
        binned.state = .trashed
        source.send(.changed(ItemChanges(upserted: [binned])))
        #expect(await eventually { library.search("body", in: .everywhere).items.map(\.id) == [F.p1] })
    }

    @Test func aFailedSearchNeverShowsAnotherQuerysOrScopesHits() async throws {
        let (library, source) = try await loaded()
        source.hits.withLock { $0["body"] = [F.n1] }
        #expect(await eventually { library.search("body", in: .everywhere).items.map(\.id) == [F.n1] })

        source.searchFails.withLock { $0 = true }
        // Another query, which the list shows the earlier hits for only while it waits.
        #expect(await eventually {
            let found = library.search("other", in: .everywhere)
            return !found.isPending
        })
        #expect(library.search("other", in: .everywhere).items.isEmpty)
        // The same query in another scope.
        #expect(await eventually { !library.search("body", in: .place(.inbox)).isPending })
        #expect(library.search("body", in: .place(.inbox)).items.isEmpty)
        #expect(library.notices.waiting.last?.title == String(localized: "Can’t Search"))
        // Its own earlier answer stands.
        #expect(library.search("body", in: .everywhere).items.map(\.id) == [F.n1])
    }

    @Test func aCancelledRefreshOfAnAnsweredSearchIsAskedAgain() async throws {
        let (library, source) = try await loaded()
        source.hits.withLock { $0["first"] = [F.n1] }
        #expect(await eventually { library.search("first", in: .everywhere).items.map(\.id) == [F.n1] })

        var renamed = try #require(library.item(F.n2))
        renamed.title = "Renamed"
        source.send(.upserted([renamed]))
        #expect(await eventually { library.item(F.n2)?.title == "Renamed" })

        source.holdSearches("first")
        _ = library.search("first", in: .everywhere)
        #expect(await eventually { source.searches.withLock { $0 } >= 2 })

        source.hits.withLock { $0["second"] = [F.p1] }
        #expect(await eventually {
            let found = library.search("second", in: .everywhere)
            return !found.isPending && found.items.map(\.id) == [F.p1]
        })

        source.hits.withLock { $0["first"] = [F.n1, F.p1] }
        let asked = source.searches.withLock { $0 }
        _ = library.search("first", in: .everywhere)
        #expect(await eventually { source.searches.withLock { $0 } > asked })
        source.releaseSearches("first")
        #expect(await eventually { library.search("first", in: .everywhere).items.map(\.id) == [F.n1, F.p1] })
    }

    @Test func anOlderAnswerThatArrivesAfterANewerOneIsNotShown() async throws {
        let (library, source) = try await loaded()
        source.hits.withLock { $0["older"] = [F.n1] }
        source.hits.withLock { $0["newer"] = [F.p1] }
        source.holdSearches("older", "newer")
        _ = library.search("older", in: .everywhere)
        #expect(await eventually { source.searches.withLock { $0 } >= 1 })
        _ = library.search("newer", in: .everywhere)
        #expect(await eventually { source.searches.withLock { $0 } >= 2 })
        source.releaseSearches("older")
        #expect(await eventually { source.searchesFinished.withLock { $0 } >= 1 })
        let waiting = library.search("newer", in: .everywhere)
        #expect(waiting.isPending)
        #expect(waiting.items.isEmpty)
        source.releaseSearches("newer")
        #expect(await eventually {
            let found = library.search("newer", in: .everywhere)
            return !found.isPending && found.items.map(\.id) == [F.p1]
        })
    }
}
