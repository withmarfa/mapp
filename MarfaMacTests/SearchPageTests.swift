import Foundation
import Marfa
import MarfaTesting
import Synchronization
import SwiftUI
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
        narrowing.includesFeed = false
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
        return SearchLeaveOutList.entries(for: leaveOut, catalogue: catalogue, typesLoaded: true, sources: sources, labels: labels)
    }

    @Test func aSourceTheCopyNoLongerHasIsKeptAndShownAsUnknown() {
        var directory = SourceDirectory()
        directory.infos = ["github": SourceInfo(code: "github", name: "GitHub", mark: nil, nameOrigin: .key)]
        directory.counts = ["github": 1_840]
        let entries = entries(SearchLeaveOut(sources: ["github", "gone"]), sources: directory)
        let github = entries.first { $0.kind == .source("github") }
        let gone = entries.first { $0.kind == .source("gone") }
        #expect(github?.isKnown == true && github?.count == 1_840)
        #expect(gone?.isKnown == false)
        #expect(gone?.title == "gone")
    }

    @MainActor @Test func anUnknownSourceCanBeRemovedAndTheRestStays() throws {
        let defaults = ThrowawayDefaults.make("SearchLeaveOutList")
        let store = SearchLeaveOuts(defaults: defaults)
        store.update("marfa:a") { $0.sources = ["gone", "github"]; $0.types = [F.ticket] }
        store.update("marfa:a") { $0.sources.remove("gone") }
        #expect(store.leaveOut(for: "marfa:a") == SearchLeaveOut(types: [F.ticket], sources: ["github"]))
    }

    @MainActor @Test func openingSearchBeforeAnotherMacsRemovalArrivesKeepsThatRemoval() throws {
        let a = ThrowawayDefaults.make("SearchPageTests.first")
        let b = ThrowawayDefaults.make("SearchPageTests.second")
        let libraries = Libraries(host: HostBench().host(), defaults: b)
        let key = libraries.libraryKey
        let first = SearchLeaveOuts(defaults: a)
        first.update(key) { $0.sources = ["github"] }
        libraries.searchLeaveOuts.update(key) { $0.sources = ["github"] }
        let setting = try #require(PreferencesMap.synced.first { $0.key == SearchLeaveOuts.defaultsKey })
        func units(_ defaults: UserDefaults) throws -> PreferenceUnits {
            guard case .units(let units) = setting.read(defaults, library: key) else {
                throw CocoaError(.coderReadCorrupt)
            }
            return units
        }
        let base = try units(a)
        first.update(key) { $0.remove(.source("github")) }
        let before = b.data(forKey: SearchLeaveOuts.defaultsKey)
        let library = FakeItemLibrary()
        library.sources.infos = ["github": SourceInfo(code: "github", name: "GitHub", mark: nil, nameOrigin: .key)]
        let page = SearchPage().environment(libraries).environment(\.library, library).defaultAppStorage(b)
        let host = NSHostingView(rootView: page)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 700, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        #expect(b.data(forKey: SearchLeaveOuts.defaultsKey) == before)

        let merge = try PreferencesMerge.reconcile(local: units(b), remote: units(a), base: base)
        #expect(merge.toRemote.isEmpty)
        setting.write(merge.merged, to: b, library: key)
        libraries.searchLeaveOuts.reload()
        #expect(first.leaveOut(for: key).isEmpty)
        #expect(libraries.searchLeaveOut.isEmpty)
    }

    @MainActor @Test func missingExclusionsKeepTheirNamesAfterReopeningTheStore() {
        let defaults = ThrowawayDefaults.make("SearchLeaveOutList.names")
        let type = TypeID("plugin.gone")
        SearchLeaveOuts(defaults: defaults).update("one") {
            $0.exclude(.type(type), named: "Press Cuttings")
            $0.exclude(.source("old"), named: "Studio Archive")
        }
        let reopened = SearchLeaveOuts(defaults: defaults)
        let saved = reopened.leaveOut(for: "one")
        var directory = SourceDirectory()
        directory.counts = [:]
        let rows = entries(saved, catalogue: Catalogue(), sources: directory)
        #expect(rows.map(\.title) == ["Press Cuttings", "Studio Archive"])
        #expect(rows.allSatisfy { !$0.isKnown })
        reopened.update("one") { $0.remove(.type(type)) }
        #expect(reopened.leaveOut(for: "one").names == ["source:old": "Studio Archive"])
    }
}
