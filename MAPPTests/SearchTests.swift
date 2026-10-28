import Foundation
import Synchronization
import Testing
@testable import MAPP

@Suite struct SearchExcerptTests {
    private func excerpt(_ html: String) -> SearchExcerpt? {
        SearchExcerpt(html: html, version: ItemVersion(1), modified: Date(timeIntervalSince1970: 0))
    }

    @Test func marksBecomeMatchesAndEscapesBecomeText() throws {
        let found = try #require(excerpt("...the <mark>R&amp;D</mark> plan &quot;now&quot;\n  here &#39;ok&#39;..."))
        #expect(found.runs.map(\.isMatch) == [false, true, false])
        #expect(found.runs[1].text == "R&D")
        #expect(found.plainText == "...the R&D plan \"now\" here 'ok'...")
    }

    @Test func anExcerptWithNoTextIsNone() {
        #expect(excerpt("") == nil)
        #expect(excerpt(" <mark></mark> \n ") == nil)
    }

    @Test func aVeryLongStretchIsCutNearTheMatch() throws {
        let long = String(repeating: "word ", count: 200)
        let found = try #require(excerpt("\(long)<mark>hit</mark>\(long)"))
        #expect(found.runs.count == 3)
        #expect(found.runs[0].text.count <= SearchExcerpt.reach + 1)
        #expect(found.runs[0].text.hasPrefix("…"))
        #expect(found.runs[2].text.hasSuffix("…"))
        #expect(found.runs[1].text == "hit")
    }

    @Test func anExcerptDescribesOnlyTheItemItWasCutFrom() {
        let date = Date(timeIntervalSince1970: 5)
        var item = LibraryFixture.item(LibraryFixture.n1, LibraryFixture.note, "Note", age: 1)
        item.modified = date
        let found = SearchExcerpt(html: "x", version: item.version, modified: date)
        #expect(found?.describes(item) == true)
        item.version = ItemVersion(2)
        #expect(found?.describes(item) == false)
    }

    @Test func onlyAPlaceThatStandsForAQueryNarrows() {
        #expect(SearchScope.narrows(.inbox))
        #expect(SearchScope.narrows(.itemType("core.note")))
        #expect(SearchScope.narrows(.view(ItemID("v"))))
        #expect(!SearchScope.narrows(.allNotes))
        #expect(!SearchScope.narrows(.recents))
        #expect(!SearchScope.narrows(.recentlyDeleted))
        #expect(!SearchScope.narrows(.favoriteItem(ItemID("f"))))
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

    @Test func anEmptyQueryAsksNothing() async throws {
        let (library, source) = try await loaded()
        let none = library.search(" \n", in: .everywhere)
        #expect(none.items.isEmpty && !none.isPending && !none.isIncomplete)
        #expect(source.searches.withLock { $0 } == 0)
    }

    @Test func wordsThatFindNothingAnswerNothingOnceAsked() async throws {
        let (library, _) = try await loaded()
        #expect(await eventually {
            let found = library.search("the", in: .everywhere)
            return !found.isPending && found.items.isEmpty && !found.isIncomplete
        })
    }

    @Test func aQuotedPhraseGoesToTheCopyAsTyped() async throws {
        let (library, source) = try await loaded()
        source.hits.withLock { $0["\"exact phrase\""] = [F.n1] }
        #expect(await eventually { library.search(" \"exact phrase\" ", in: .everywhere).items.map(\.id) == [F.n1] })
    }

    @Test func anExcerptShowsWhileTrueAndGoesWhenTheItemChanges() async throws {
        let (library, source) = try await loaded()
        let item = try #require(library.item(F.n1))
        source.hits.withLock { $0["body"] = [F.n1] }
        let excerpt = try #require(SearchExcerpt(html: "a <mark>body</mark>", version: item.version, modified: item.modified))
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

    @Test func anItemRemovedWhileShownLeavesTheResults() async throws {
        let (library, source) = try await loaded()
        source.hits.withLock { $0["body"] = [F.n1, F.p1] }
        #expect(await eventually { library.search("body", in: .everywhere).items.map(\.id) == [F.n1, F.p1] })
        source.send(.removed([F.n1]))
        #expect(await eventually { library.search("body", in: .everywhere).items.map(\.id) == [F.p1] })
    }

    @Test func aPartialAnswerSaysSoAndIsAskedAgainOnceTheCopyIsWhole() async throws {
        let (library, source) = try await loaded(filling: true)
        source.hits.withLock { $0["body"] = [F.n1] }
        source.searchIncomplete.withLock { $0 = true }
        #expect(await eventually {
            let found = library.search("body", in: .everywhere)
            return found.isIncomplete && !found.isPending
        })

        source.searchIncomplete.withLock { $0 = false }
        source.hits.withLock { $0["body"] = [F.n1, F.p1] }
        source.report.update { $0.fill = LibraryFill(state: .complete, listed: 9, expected: 9) }
        #expect(await eventually {
            let found = library.search("body", in: .everywhere)
            return !found.isIncomplete && found.items.map(\.id) == [F.n1, F.p1]
        })
    }

    @Test func aCappedAnswerSaysSo() async throws {
        let (library, source) = try await loaded()
        source.hits.withLock { $0["body"] = [F.n1] }
        source.searchCapped.withLock { $0 = true }
        #expect(await eventually { library.search("body", in: .everywhere).isCapped })
    }

    @Test func aCapNoticeCountsTheRowsShownNotTheLimit() async throws {
        let (library, source) = try await loaded()
        // The copy cuts its list at the limit before the bin's items are dropped from it, so fewer rows can show.
        source.hits.withLock { $0["body"] = [F.n1, F.n3, F.p1] }
        source.searchCapped.withLock { $0 = true }
        #expect(await eventually { library.search("body", in: .everywhere).cappedCount != nil })
        let found = library.search("body", in: .everywhere)
        #expect(found.items.map(\.id) == [F.n1, F.p1])
        #expect(found.cappedCount == found.items.count)

        source.searchCapped.withLock { $0 = false }
        var renamed = try #require(library.item(F.n2))
        renamed.title = "Other"
        source.send(.upserted([renamed]))
        #expect(await eventually { library.search("body", in: .everywhere).cappedCount == nil })
    }

    @Test func aSearchThatBeganWholeButFoundTheCopyStaleIsAskedAgainWhenItsFillChanges() async throws {
        let (library, source) = try await loaded()
        source.hits.withLock { $0["body"] = [F.n1] }
        source.searchIncomplete.withLock { $0 = true }
        #expect(await eventually { library.search("body", in: .everywhere).isIncomplete })

        // A copy that stays stale is not searched again and again.
        let asked = source.searches.withLock { $0 }
        for _ in 0..<5 {
            _ = library.search("body", in: .everywhere)
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(source.searches.withLock { $0 } == asked, "gives the running search time to be asked again")

        source.searchIncomplete.withLock { $0 = false }
        source.report.update { $0.fill = LibraryFill(state: .updating, listed: 9, expected: 9) }
        source.report.update { $0.fill = LibraryFill(state: .complete, listed: 9, expected: 9) }
        #expect(await eventually {
            let found = library.search("body", in: .everywhere)
            return !found.isIncomplete && !found.isPending
        })
    }

    @Test func aRerunThatFailsFollowsHowTheCopyStandsNotTheOldAnswer() async throws {
        let (library, source) = try await loaded(filling: true)
        source.hits.withLock { $0["body"] = [F.n1] }
        source.searchIncomplete.withLock { $0 = true }
        #expect(await eventually { library.search("body", in: .everywhere).isIncomplete })

        source.searchFails.withLock { $0 = true }
        source.report.update { $0.fill = LibraryFill(state: .complete, listed: 9, expected: 9) }
        #expect(await eventually {
            let found = library.search("body", in: .everywhere)
            return !found.isIncomplete && library.notices.waiting.last?.title == String(localized: "Can’t Search")
        })
        #expect(library.search("body", in: .everywhere).items.map(\.id) == [F.n1])
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

    @Test func aPlaceIsSearchedByTheQueryItStandsFor() async throws {
        let (library, source) = try await loaded()
        _ = library.search("body", in: .place(.inbox))
        _ = library.search("body", in: .place(.favorites))
        _ = library.search("body", in: .place(.recents))
        #expect(await eventually { source.targets.withLock { $0.count } == 3 })
        let targets = source.targets.withLock { $0 }
        let inbox = try #require(targets.first { if case .items(let query, _) = $0 { query.tier == .feed } else { false } })
        #expect(inbox != .items(MarfaLibrary.searchScope))
        #expect(targets.contains { if case .items(_, let filter) = $0 { filter?.contains("tags") == true } else { false } })
        // Recents stands for no query, so it searches everywhere.
        #expect(targets.contains(.items(MarfaLibrary.searchScope)))
    }

    @Test func aSavedViewIsSearchedInItself() async throws {
        let (library, source) = try await loaded()
        let view = LibraryView(id: ItemID("v-one"), title: "One")
        source.send(.views([view]))
        try #require(await eventually { library.views.contains { $0.id == view.id } })
        _ = library.search("body", in: .place(.view(view.id)))
        #expect(await eventually { source.targets.withLock { $0.contains(.view(view.id)) } })
    }
}
