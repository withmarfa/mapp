import Foundation
import Testing
@testable import MarfaMac

/// What each tab of an index page lists, how a table's header sorts it, and what choosing a container does when it goes.
@MainActor
@Suite(.hangLimit) struct IndexTabsTests {
    private func source(_ code: String, count: Int = 1, latest: Date? = nil) -> IndexRow {
        IndexRow(place: .source(code), title: code, icon: .symbol("x"), types: "", count: count, latest: latest, breakdown: [])
    }

    private func collection(_ title: String, tier: Tier, count: Int = 1) -> IndexRow {
        IndexRow(
            place: .collection(ItemID(title)), title: title, icon: .symbol("x"), types: "", count: count, latest: nil, breakdown: [],
            tier: tier)
    }

    // MARK: Tabs

    @Test func theSourcesTabsSplitAppsFromKeys() {
        let rows = [source("oauth:reader"), source("rss"), source("oauth:notes-app"), source("readwise")]
        #expect(IndexTab.all.rows(in: rows).map(\.title) == ["oauth:reader", "rss", "oauth:notes-app", "readwise"])
        #expect(IndexTab.apps.rows(in: rows).map(\.title) == ["oauth:reader", "oauth:notes-app"])
        #expect(IndexTab.keys.rows(in: rows).map(\.title) == ["rss", "readwise"])
    }

    @Test func aCodeThatOnlyContainsOauthLaterIsAKey() {
        let rows = [source("my-oauth:thing"), source("oauth"), source("OAUTH:upper"), source("keys/oauth:x"), source("")]
        #expect(IndexTab.apps.rows(in: rows).isEmpty)
        #expect(IndexTab.keys.rows(in: rows).count == rows.count)
        #expect(SourceCode.isApp("oauth:x"))
        #expect(!SourceCode.isApp("x:oauth:"))
    }

    @Test func everySourceIsInExactlyOneOfAppsAndKeys() {
        let rows = ["oauth:a", "b", "oauth:", "c-oauth:d"].map { source($0) }
        let apps = IndexTab.apps.rows(in: rows), keys = IndexTab.keys.rows(in: rows)
        #expect(apps.count + keys.count == rows.count)
        #expect(Set(apps.map(\.id)).isDisjoint(with: keys.map(\.id)))
    }

    @Test func theCollectionsTabsSplitByTier() {
        let rows = [collection("Mine", tier: .library), collection("Theirs", tier: .feed), collection("Also mine", tier: .library)]
        #expect(IndexTab.yours.rows(in: rows).map(\.title) == ["Mine", "Also mine"])
        #expect(IndexTab.fromApps.rows(in: rows).map(\.title) == ["Theirs"])
        #expect(IndexTab.all.rows(in: rows).count == 3)
    }

    @Test func aTabWithNothingInItIsEmpty() {
        let rows = [collection("Mine", tier: .library)]
        #expect(IndexTab.fromApps.rows(in: rows).isEmpty)
        #expect(IndexTab.yours.rows(in: []).isEmpty)
        // A collection is in no sources tab, and a source is in no collections tab.
        #expect(IndexTab.apps.rows(in: rows).isEmpty)
        #expect(IndexTab.yours.rows(in: [source("rss")]).isEmpty)
    }

    @Test func aCollectionRowCarriesItsTier() throws {
        let catalogue = FakeItemLibrary.testCatalogue
        var feed = FakeItemLibrary.collection("From an app")
        feed.tier = .feed
        let rows = IndexRows.collections([FakeItemLibrary.collection("Mine"), feed], membersOf: { _ in [] }, catalogue: catalogue)
        #expect(rows.map(\.tier) == [.library, .feed])
        #expect(IndexRows.sources(of: [], catalogue: catalogue).allSatisfy { $0.tier == nil })
    }

    // MARK: Sorting

    @Test func aSortIsKeptAsTextAndReadBack() {
        for column in IndexColumn.allCases {
            for ascending in [true, false] {
                let sort = IndexSort(column: column, ascending: ascending)
                #expect(IndexSort(rawValue: sort.rawValue) == sort)
                #expect(IndexSort(comparators: sort.comparators) == sort)
            }
        }
        #expect(IndexSort(rawValue: "count") == nil)
        #expect(IndexSort(rawValue: "weight.asc") == nil)
        #expect(IndexSort(comparators: [KeyPathComparator<IndexRow>]()) == nil)
    }

    @Test func equalRowsKeepTheOrderOfTheirNames() {
        let rows = [source("b", count: 2), source("a", count: 2), source("c", count: 9)]
        #expect(IndexSort(column: .count, ascending: false).sorted(rows).map(\.title) == ["c", "a", "b"])
        #expect(IndexSort(column: .count, ascending: true).sorted(rows).map(\.title) == ["a", "b", "c"])
    }

    @Test func aRowWithNoLatestItemSortsAsTheOldest() {
        let rows = [source("none"), source("new", latest: Date(timeIntervalSinceReferenceDate: 9)), source("old", latest: Date(timeIntervalSinceReferenceDate: 1))]
        #expect(IndexSort(column: .latest, ascending: false).sorted(rows).map(\.title) == ["new", "old", "none"])
    }

    // MARK: The chosen container

    @Test func theChoiceClearsWhenItsContainerGoes() {
        let choice = IndexChoice()
        let mine = collection("Mine", tier: .library), theirs = collection("Theirs", tier: .feed)
        choice.chosen = mine.id
        choice.keep(within: [mine, theirs])
        #expect(choice.chosen == mine.id)
        #expect(choice.row(in: [mine, theirs]) == mine)
        choice.keep(within: [theirs])
        #expect(choice.chosen == nil)
        #expect(choice.row(in: [theirs]) == nil)
    }

    @Test func aChoiceOfNothingStaysNothingAndAnEmptyPageClearsIt() {
        let choice = IndexChoice()
        choice.keep(within: [])
        #expect(choice.chosen == nil)
        choice.chosen = .collection(ItemID("gone"))
        choice.keep(within: [])
        #expect(choice.chosen == nil)
    }

    @Test func theChoiceFollowsItsContainerThroughANewBuildOfTheRows() {
        let choice = IndexChoice()
        choice.chosen = .source("rss")
        let before = [source("rss", count: 1)], after = [source("rss", count: 5), source("new")]
        choice.keep(within: after)
        #expect(choice.row(in: before)?.count == 1)
        #expect(choice.row(in: after)?.count == 5)
    }

    // MARK: Deleting a collection

    @Test func deletingACollectionKeepsItsMembersAndOffersUndo() async throws {
        let (library, source) = try await MarfaCollectionsTests().loaded()
        let holiday = MarfaCollectionsTests.holiday
        let members = library.items(in: .collection(holiday)).map(\.id)
        #expect(members.count == 3)
        let toasts = ToastPresenter()
        let undo = StepCountingUndoManager()
        // A test has no run loop to close an event's group, so the delete gets a group of its own.
        undo.groupsByEvent = false
        Browser.delete([holiday], in: library, undoManager: undo, toasts: toasts, naming: "Holiday")

        #expect(source.writes == [.transition(holiday, .trashed)], "the collection is written, and no member")
        #expect(toasts.current?.message == "Moved “Holiday” to Recently Deleted")
        #expect(toasts.current?.undo != nil)
        for id in members {
            let member = try #require(library.item(id))
            #expect(member.state == .active)
            #expect(member.collectionIDs.contains(holiday), "a member keeps its place in the collection that is in Recently Deleted")
        }

        source.clearWrites()
        toasts.undo()
        #expect(source.writes == [.transition(holiday, .active)], "Undo brings back the collection alone")
    }

    @Test func deletingACollectionThatIsAlreadyGoneShowsNoToast() async throws {
        let (library, source) = try await MarfaCollectionsTests().loaded()
        let toasts = ToastPresenter()
        // The collection is gone already: nothing moves, so nothing is claimed.
        Browser.delete([ItemID("vanished")], in: library, undoManager: StepCountingUndoManager(), toasts: toasts, naming: "Vanished")
        #expect(toasts.current == nil)
        #expect(source.writes.isEmpty)
    }

    @Test func theAlertNamesTheCollectionAndSaysItsItemsAreKept() {
        #expect(DeletionWords.collectionTitle("Holiday") == "Delete the collection “Holiday”?")
        #expect(DeletionWords.collectionMessage(keeping: 0).contains("kept") == false)
        #expect(DeletionWords.collectionMessage(keeping: 1).hasSuffix("Its 1 item is kept."))
        #expect(DeletionWords.collectionMessage(keeping: 3).hasSuffix("Its 3 items are kept."))
    }
}
