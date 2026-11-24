import Foundation
import Marfa
import MarfaTesting
import Synchronization
import Testing
@testable import MarfaMac

/// What the Search page's choices do to a search and to the items the palette matches by title.
@Suite(.hangLimit) struct SearchOptionsTests {
    typealias F = LibraryFixture

    @Test func theChoicesAreMacSettingsThatResetClears() {
        for key in SearchOptions.keys { #expect(MacSettings.keys.contains(key)) }
        #expect(MacSettings.keys.contains(SearchLeaveOuts.defaultsKey))
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
}

/// The list the Search page shows of what a server leaves out.
@Suite struct SearchLeaveOutListTests {
    typealias F = LibraryFixture

    private func entries(
        _ leaveOut: SearchLeaveOut, catalogue: Catalogue = F.catalogue, sources: SourceDirectory = SourceDirectory(), offered: [TypeID] = []
    ) -> [SearchLeaveOutList.Entry] {
        let labels = SearchLeaveOutList.labels(offered: offered, leaveOut: leaveOut, catalogue: catalogue)
        return SearchLeaveOutList.entries(for: leaveOut, catalogue: catalogue, sources: sources, labels: labels)
    }

    @Test func aSourceTheCopyNoLongerHasIsKeptAndShownAsUnknown() {
        var directory = SourceDirectory()
        directory.infos = ["github": SourceInfo(code: "github", name: "GitHub", mark: nil, hasChosenName: false)]
        directory.counts = ["github": 1_840]
        let entries = entries(SearchLeaveOut(sources: ["github", "gone"]), sources: directory)
        let github = entries.first { $0.kind == .source("github") }
        let gone = entries.first { $0.kind == .source("gone") }
        #expect(github?.isKnown == true && github?.count == 1_840)
        #expect(gone?.isKnown == false)
        #expect(gone?.title == "gone")
    }

    @MainActor @Test func anUnknownSourceCanBeRemovedAndTheRestStays() throws {
        let defaults = try #require(UserDefaults(suiteName: "SearchLeaveOutList-\(UUID())"))
        let store = SearchLeaveOuts(defaults: defaults)
        store.update("marfa:a") { $0.sources = ["gone", "github"]; $0.types = [F.ticket] }
        store.update("marfa:a") { $0.sources.remove("gone") }
        #expect(store.leaveOut(for: "marfa:a") == SearchLeaveOut(types: [F.ticket], sources: ["github"]))
    }
}
