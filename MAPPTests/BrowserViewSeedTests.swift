import Foundation
import Testing
@testable import MAPP

/// A window opens a saved view with the view's own order, grouping and filters, and offers Save View and Revert View only when the
/// person has changed them in any layout since.
@MainActor
struct BrowserViewSeedTests {
    private static func view(
        version: Int64 = 1, group: String = "properties.status", bucket: LibraryViewGroup.Bucket? = nil, filter: String? = nil
    ) -> LibraryView {
        LibraryView(
            id: ItemID("view-open-tasks"), title: "Open Tasks", version: version,
            query: LibraryViewQuery(types: [TypeID("core.task")], states: [.active], filter: filter),
            sort: [LibraryViewSort(field: "updated_at", ascending: false)], group: LibraryViewGroup(field: group, bucket: bucket))
    }

    private static func opened(_ view: LibraryView = view()) -> (Browser, FakeItemLibrary) {
        let library = FakeItemLibrary()
        library.views = [view]
        let browser = Browser()
        browser.adopt(library)
        browser.sidebarItem = .view(view.id)
        browser.viewMode = .table
        browser.followView(in: library)
        return (browser, library)
    }

    @Test func aViewOpensWithItsOwnOrderAndGrouping() {
        let (browser, library) = Self.opened()
        let options = browser.tableOptions[browser.item]
        #expect(options == ViewDraft.options(for: Self.view(), catalogue: library.catalogue))
        #expect(options?.grouping == .column(ViewDraft.columnID(of: "properties.status") ?? ""))
        #expect(!browser.hasViewChanges)
    }

    @Test func aChangedGroupingOffersASave() {
        let (browser, library) = Self.opened()
        browser.tableOptions[browser.item]?.grouping = .none
        #expect(browser.hasViewChanges)
        browser.tableOptions[browser.item]?.grouping = ViewDraft.options(for: Self.view(), catalogue: library.catalogue).grouping
        #expect(!browser.hasViewChanges)
    }

    @Test func foldingAGroupIsNoChange() {
        let (browser, _) = Self.opened()
        browser.tableOptions[browser.item]?.collapsed = ["done"]
        #expect(!browser.hasViewChanges)
    }

    @Test func aFilterCountsInEveryLayout() {
        for mode in ItemViewMode.allCases {
            let (browser, _) = Self.opened()
            browser.viewMode = mode
            browser.tableOptions[browser.item]?.filters = ["field.status": ["todo"]]
            #expect(browser.hasViewChanges, "\(mode) did not count a filter")
            browser.tableOptions[browser.item]?.negated = ["field.status"]
            #expect(browser.hasViewChanges)
            browser.tableOptions[browser.item]?.filters = [:]
            browser.tableOptions[browser.item]?.negated = []
            #expect(!browser.hasViewChanges, "\(mode) kept a change after the filter went")
        }
    }

    @Test func isNotIsAChangeFromIs() {
        let (browser, library) = Self.opened(Self.view(filter: #"properties.status eq "todo""#))
        #expect(!browser.hasViewChanges)
        browser.tableOptions[browser.item]?.negated.insert("field.status")
        #expect(browser.hasViewChanges)
        browser.revertView(in: library)
        #expect(browser.tableOptions[browser.item]?.negated == [])
        #expect(!browser.hasViewChanges)
    }

    @Test func aStaleNegationWithNoFilterIsNoChange() {
        let (browser, _) = Self.opened()
        browser.tableOptions[browser.item]?.negated.insert("field.status")
        #expect(!browser.hasViewChanges)
    }

    @Test func aChangedTimelineDateIsAChange() {
        let (browser, _) = Self.opened(Self.view(group: "properties.due_at", bucket: .day))
        browser.viewMode = .timeline
        #expect(browser.timelineFields[browser.item] == "due_at")
        #expect(!browser.hasViewChanges)
        browser.timelineFields[browser.item] = "starts_at"
        #expect(browser.hasViewChanges)
    }

    @Test func revertingPutsTheWindowBackToTheViewInEveryLayout() {
        let (browser, library) = Self.opened()
        browser.viewMode = .board
        browser.tableOptions[browser.item]?.grouping = .none
        browser.tableOptions[browser.item]?.sort = [ItemTableComparator(column: .title)]
        browser.tableOptions[browser.item]?.filters = ["field.status": ["todo"]]
        browser.timelineFields[browser.item] = "starts_at"
        #expect(browser.hasViewChanges)
        browser.revertView(in: library)
        #expect(!browser.hasViewChanges)
        #expect(browser.tableOptions[browser.item] == ViewDraft.options(for: Self.view(), catalogue: library.catalogue))
        #expect(browser.timelineFields[browser.item] == nil)
    }

    @Test func revertingDoesNothingWhereThePlaceIsNotAView() {
        let browser = Browser()
        let library = FakeItemLibrary()
        browser.adopt(library)
        browser.tableOptions[.allNotes] = ItemTableOptions(filters: ["field.status": ["todo"]])
        browser.revertView(in: library)
        #expect(browser.tableOptions[.allNotes]?.filters == ["field.status": ["todo"]])
        #expect(!browser.hasViewChanges)
    }

    @Test func aViewChangedElsewhereIsFollowedUnlessTheWindowChangedIt() {
        let (browser, library) = Self.opened()
        library.views = [Self.view(version: 2, group: "type")]
        browser.followView(in: library)
        #expect(browser.tableOptions[browser.item]?.grouping == ViewDraft.options(for: library.views[0], catalogue: library.catalogue).grouping)
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
        #expect(browser.tableOptions[browser.item]?.grouping == ViewDraft.options(for: library.views[0], catalogue: library.catalogue).grouping)
        #expect(browser.viewSeeds[library.views[0].id]?.version == 2)
        #expect(!browser.hasViewChanges)
    }

    @Test func anUpdateNamesOnlyWhatChangedAtTheVersionRead() throws {
        let (browser, library) = Self.opened()
        browser.tableOptions[browser.item]?.grouping = .none
        let window = ViewDraft.Window(place: browser.item, columns: [], sort: [], grouping: nil, filters: [:])
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

    @Test func aChangedOrderOrGroupingIsOfferedInEveryLayout() {
        for mode in ItemViewMode.allCases {
            let (browser, _) = Self.opened()
            browser.viewMode = mode
            browser.tableOptions[browser.item]?.grouping = .none
            #expect(browser.hasViewChanges, "\(mode) did not count a grouping")
        }
    }
}
