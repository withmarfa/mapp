import Foundation
import Marfa
import MarfaTesting
import Synchronization
import Testing
@testable import MAPP

private func item(
    _ id: String, type: TypeID = LibraryFixture.note, source: String? = nil, state: MAPP.ItemState = .active, tier: MAPP.Tier = .library,
    modified: Double = 0
) -> MAPP.Item {
    var item = MAPP.Item(
        id: ItemID(id), type: type, title: id, titleRule: .property("title"), properties: [], version: ItemVersion(1),
        created: Date(timeIntervalSince1970: 0), modified: Date(timeIntervalSince1970: modified))
    item.source = source
    item.state = state
    item.tier = tier
    return item
}

/// What the Search page's choices do to a search and to the items the palette matches by title.
@Suite struct SearchOptionsTests {
    typealias F = LibraryFixture

    @Test func theChoicesAreMacSettingsThatResetClears() {
        for key in SearchOptions.keys { #expect(MacSettings.keys.contains(key)) }
        #expect(MacSettings.keys.contains(SearchLeaveOuts.defaultsKey))
    }

    @Test func bestMatchKeepsTheCopysOrderAndMostRecentSortsByDateKeepingTiesInOrder() {
        let items = [item("a", modified: 5), item("b", modified: 9), item("c", modified: 5), item("d", modified: 1)]
        #expect(SearchOptions.Order.bestMatch.ordered(items).map(\.id.rawValue) == ["a", "b", "c", "d"])
        #expect(SearchOptions.Order.mostRecent.ordered(items).map(\.id.rawValue) == ["b", "a", "c", "d"])
    }

    @Test func anOrderThisVersionDoesNotKnowIsBestMatch() throws {
        let defaults = try #require(UserDefaults(suiteName: "SearchOptions-\(UUID())"))
        #expect(SearchOptions.order(in: defaults) == .bestMatch)
        defaults.set("newest", forKey: SearchOptions.orderKey)
        #expect(SearchOptions.order(in: defaults) == .bestMatch)
        defaults.set("mostRecent", forKey: SearchOptions.orderKey)
        #expect(SearchOptions.order(in: defaults) == .mostRecent)
    }

    @Test func archivedAndInboxItemsAreKeptOnlyWhileTheirChoicesAreOn() {
        let archived = item("archived", state: .archived)
        let feed = item("feed", tier: .feed)
        var narrowing = SearchNarrowing()
        #expect(narrowing.isEmpty)
        #expect(narrowing.admitsOptions(archived) && narrowing.admitsOptions(feed))
        narrowing.includesArchived = false
        #expect(!narrowing.isEmpty)
        #expect(!narrowing.admitsOptions(archived) && narrowing.admitsOptions(feed))
        narrowing.includesInbox = false
        #expect(!narrowing.admitsOptions(feed))
        #expect(narrowing.searchedStates == [.active])
        #expect(narrowing.searchedTier == .library)
    }

    @Test func theChoicesReachTheCopyInsideTheSearchCall() async throws {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: F.items, catalogue: F.catalogue)))
        try #require(await eventually { library.isLoaded })
        var narrowing = SearchNarrowing()
        narrowing.includesArchived = false
        narrowing.includesInbox = false
        _ = await eventually { !library.search("alpha", narrowedBy: narrowing).isPending }
        let target = try #require(source.targets.withLock { $0.last })
        guard case .items(let query, _, _) = target else { Issue.record("not an items search"); return }
        #expect(query.states == [.active])
        #expect(query.tier == .library)
    }

    @Test func aTypedPaletteKeepsWhatIsLeftOutApartAndCountsIt() {
        let kept = item("kept")
        let bug = item("bug", type: F.bug)
        let github = item("github", source: "github")
        let archived = item("archived", state: .archived)
        var narrowing = SearchNarrowing(leaveOut: SearchLeaveOut(types: [F.ticket], sources: ["github"]))
        let split = narrowing.split([kept, bug, github, archived], in: F.catalogue)
        #expect(split.kept.map(\.id.rawValue) == ["kept", "archived"])
        #expect(split.leftOut.map(\.id.rawValue) == ["bug", "github"], "a type left out takes its subtypes with it")
        narrowing.includesArchived = false
        #expect(narrowing.split([kept, archived], in: F.catalogue).kept.map(\.id.rawValue) == ["kept"])
        let line = SearchLeftOutLine.text(
            for: split.leftOut, isCapped: false, narrowing: narrowing, catalogue: F.catalogue, sources: SourceDirectory())
        #expect(line == "2 more in Tickets and github, left out of search.")
    }
}

/// The list the Search page shows of what a server leaves out.
@Suite struct SearchLeaveOutListTests {
    typealias F = LibraryFixture

    @Test func aTypeLeftOutListsItsSubtypesAsLeftOutToo() {
        let entries = SearchLeaveOutList.entries(for: SearchLeaveOut(types: [F.ticket]), catalogue: F.catalogue, sources: SourceDirectory())
        #expect(entries.map(\.title) == ["Tickets", "Bugs", "Tasks"])
        #expect(entries.map(\.kind) == [.type(F.ticket), .subtype(F.bug, parent: F.ticket), .subtype(F.task, parent: F.ticket)])
    }

    @Test func aSourceTheCopyNoLongerHasIsKeptAndShownAsUnknown() {
        var directory = SourceDirectory()
        directory.infos = ["github": SourceInfo(code: "github", name: "GitHub", mark: nil, hasChosenName: false)]
        directory.counts = ["github": 1_840]
        let entries = SearchLeaveOutList.entries(
            for: SearchLeaveOut(sources: ["github", "gone"]), catalogue: F.catalogue, sources: directory)
        let github = entries.first { $0.kind == .source("github") }
        let gone = entries.first { $0.kind == .source("gone") }
        #expect(github?.isKnown == true && github?.count == 1_840)
        #expect(gone?.isKnown == false)
        #expect(gone?.title == "gone")
    }

    @Test func beforeTheServerHasAnsweredNoSourceIsCalledUnknown() {
        let entries = SearchLeaveOutList.entries(for: SearchLeaveOut(sources: ["github"]), catalogue: F.catalogue, sources: SourceDirectory())
        #expect(entries.map(\.isKnown) == [true])
    }

    @MainActor @Test func anUnknownSourceCanBeRemovedAndTheRestStays() throws {
        let defaults = try #require(UserDefaults(suiteName: "SearchLeaveOutList-\(UUID())"))
        let store = SearchLeaveOuts(defaults: defaults)
        store.update("marfa:a") { $0.sources = ["gone", "github"]; $0.types = [F.ticket] }
        store.update("marfa:a") { $0.sources.remove("gone") }
        #expect(store.leaveOut(for: "marfa:a") == SearchLeaveOut(types: [F.ticket], sources: ["github"]))
    }

    @Test func aTypeOrSourceAlreadyLeftOutIsNotOffered() {
        let counts = [
            ItemTypeCount(id: F.note, label: "Notes", icon: nil, count: 3), ItemTypeCount(id: F.ticket, label: "Tickets", icon: nil, count: 2),
            ItemTypeCount(id: F.bug, label: "Bugs", icon: nil, count: 1), ItemTypeCount(id: F.project, label: "Projects", icon: nil, count: 1),
        ]
        let offered = SearchLeaveOutList.typesToAdd(counts, leaveOut: SearchLeaveOut(types: [F.ticket]), catalogue: F.catalogue)
        #expect(offered.map(\.id) == [F.note, F.project], "Tickets is left out and Bugs go with it")
        let sources = SearchLeaveOutList.sourcesToAdd(
            [SourceCount(code: "a", name: "A", count: 1), SourceCount(code: "b", name: "B", count: 2)], leaveOut: SearchLeaveOut(sources: ["a"]))
        #expect(sources.map(\.code) == ["b"])
    }
}
