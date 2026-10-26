import Foundation
import Testing
@testable import MAPP

/// A window opens a saved view with the view's own order and grouping, and offers Update View only when the person
/// has changed them since.
@MainActor
struct BrowserViewSeedTests {
    private static func view(version: Int64 = 1, group: String = "properties.status") -> LibraryView {
        LibraryView(
            id: ItemID("view-open-tasks"), title: "Open Tasks", version: version,
            query: LibraryViewQuery(types: [TypeID("core.task")], states: [.active]),
            sort: [LibraryViewSort(field: "updated_at", ascending: false)], group: LibraryViewGroup(field: group))
    }

    private static func opened(_ view: LibraryView = view()) -> (Browser, FakeItemLibrary) {
        let library = FakeItemLibrary()
        library.views = [view]
        let browser = Browser()
        browser.adopt(library)
        browser.sidebarItem = .view(view.id)
        browser.followView(in: library)
        return (browser, library)
    }

    @Test func aViewOpensWithItsOwnOrderAndGrouping() {
        let (browser, _) = Self.opened()
        let options = browser.tableOptions[browser.item]
        #expect(options == ViewDraft.options(for: Self.view()))
        #expect(options?.grouping == .column(ViewDraft.columnID(of: "properties.status") ?? ""))
        #expect(!browser.hasViewChanges)
    }

    @Test func aChangedGroupingOffersAnUpdate() {
        let (browser, _) = Self.opened()
        browser.tableOptions[browser.item]?.grouping = .none
        #expect(browser.hasViewChanges)
        browser.tableOptions[browser.item]?.grouping = ViewDraft.options(for: Self.view()).grouping
        #expect(!browser.hasViewChanges)
    }

    @Test func foldingAGroupIsNoChange() {
        let (browser, _) = Self.opened()
        browser.tableOptions[browser.item]?.collapsed = ["done"]
        #expect(!browser.hasViewChanges)
    }

    @Test func filtersCountOnlyWhereTheTableAppliesThem() {
        let (browser, _) = Self.opened()
        browser.tableOptions[browser.item]?.filters = ["status": ["todo"]]
        browser.viewMode = .list
        #expect(!browser.hasViewChanges)
        browser.viewMode = .table
        #expect(browser.hasViewChanges)
    }

    @Test func aViewChangedElsewhereIsFollowedUnlessTheWindowChangedIt() {
        let (browser, library) = Self.opened()
        library.views = [Self.view(version: 2, group: "type")]
        browser.followView(in: library)
        #expect(browser.tableOptions[browser.item]?.grouping == ViewDraft.options(for: library.views[0]).grouping)
        #expect(browser.viewSeeds[library.views[0].id]?.version == 2)

        browser.tableOptions[browser.item]?.grouping = .none
        library.views = [Self.view(version: 3)]
        browser.followView(in: library)
        #expect(browser.tableOptions[browser.item]?.grouping == ItemTableOptions.Grouping.none)
        // The update stays based on the version the person's change was made on, so the server can refuse it.
        #expect(browser.viewSeeds[library.views[0].id]?.version == 2)
        #expect(browser.hasViewChanges)
    }

    @Test func aRefusedUpdatePutsTheWindowBackToTheView() {
        let (browser, library) = Self.opened()
        browser.tableOptions[browser.item]?.grouping = .none
        library.views = [Self.view(version: 2)]
        browser.viewRefused(library.views[0].id, in: library)
        #expect(browser.tableOptions[browser.item]?.grouping == ViewDraft.options(for: library.views[0]).grouping)
        #expect(browser.viewSeeds[library.views[0].id]?.version == 2)
        #expect(!browser.hasViewChanges)
    }

    @Test func anUpdateNamesOnlyWhatChangedAtTheVersionRead() throws {
        let (browser, library) = Self.opened()
        browser.tableOptions[browser.item]?.grouping = .none
        let window = ViewDraft.Window(place: browser.item, columns: [], sort: [], grouping: nil)
        let update = try #require(browser.viewUpdate(window, in: library))
        #expect(update.baseVersion == 1)
        #expect(update.change.group == .clear)
        #expect(update.change.title == nil)
        #expect(update.change.query == nil)
    }

    @Test func anotherLibraryStartsWithNoSeeds() {
        // The first library is kept, so the second is not made at its address and taken for it.
        let (browser, first) = Self.opened()
        browser.viewEditing = .rename(Self.view().id)
        let second = FakeItemLibrary()
        browser.adopt(second)
        withExtendedLifetime(first) {}
        #expect(browser.viewSeeds.isEmpty)
        #expect(browser.viewEditing == nil)
    }
}
