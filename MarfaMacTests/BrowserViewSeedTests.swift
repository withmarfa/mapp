import Foundation
import Testing
@testable import MarfaMac

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

    /// A window on the view, whose layout is `layout` as the Mac kept it, so a layout is not itself a change.
    private static func opened(_ view: LibraryView = view(), layout: ItemViewMode = .table) -> (Browser, FakeItemLibrary) {
        let library = FakeItemLibrary()
        library.views = [view]
        let browser = Browser()
        browser.defaults = ViewPanelTests.defaults()
        ViewLayouts.update(in: browser.defaults) { $0.set(ViewMacSettings(layout: layout), for: view.id) }
        browser.adopt(library)
        browser.showing = .view(view.id)
        browser.viewMode = .table
        browser.followView(in: library)
        return (browser, library)
    }

    /// Takes the window's layout to be the one the view was saved in, so that the layout alone is no change.
    private static func take(_ layout: ItemViewMode, in browser: Browser) {
        let id = view().id
        guard var seed = browser.viewSeeds[id] else { return }
        seed.mac.layout = layout
        browser.viewSeeds[id] = seed
    }

    @Test func aChangedGroupingOffersASave() {
        let (browser, library) = Self.opened()
        browser.tableOptions[browser.shown]?.grouping = .none
        #expect(browser.hasViewChanges)
        browser.tableOptions[browser.shown]?.grouping = ViewDraft.options(for: Self.view(), catalogue: library.catalogue).grouping
        #expect(!browser.hasViewChanges)
    }

    @Test func aFilterCountsInEveryLayout() {
        for mode in ItemViewMode.allCases {
            let (browser, _) = Self.opened()
            browser.viewMode = mode
            // The layout alone is a change too; the view is taken to have been saved in it, to see the filter's.
            Self.take(mode, in: browser)
            browser.tableOptions[browser.shown]?.filter = FilterState(is: ["field.status": ["todo"]])
            #expect(browser.hasViewChanges, "\(mode) did not count a filter")
            browser.tableOptions[browser.shown]?.filter = FilterState(clauses: [FilterClause(field: "field.status", op: .isNot, values: ["todo"])])
            #expect(browser.hasViewChanges)
            browser.tableOptions[browser.shown]?.filter = FilterState()
            #expect(!browser.hasViewChanges, "\(mode) kept a change after the filter went")
        }
    }

    @Test func isNotIsAChangeFromIs() {
        let (browser, library) = Self.opened(Self.view(filter: #"properties.status eq "todo""#))
        #expect(!browser.hasViewChanges)
        browser.tableOptions[browser.shown]?.filter = FilterState(clauses: [FilterClause(field: "field.status", op: .isNot, values: ["todo"])])
        #expect(browser.hasViewChanges)
        browser.revertView(in: library)
        #expect(browser.tableOptions[browser.shown]?.filter.clauses.first?.op == .is)
        #expect(!browser.hasViewChanges)
    }

    @Test func aFilterThatSaysTooLittleIsNoChange() {
        let (browser, _) = Self.opened()
        browser.tableOptions[browser.shown]?.filter = FilterState(clauses: [FilterClause(field: "field.status", op: .is)])
        #expect(!browser.hasViewChanges)
    }

    @Test func aChangedTimelineDateIsAChange() {
        let (browser, _) = Self.opened(Self.view(group: "properties.due_at", bucket: .day), layout: .timeline)
        #expect(browser.timelineFields[browser.shown] == "due_at")
        #expect(!browser.hasViewChanges)
        browser.timelineFields[browser.shown] = "starts_at"
        #expect(browser.hasViewChanges)
    }

    @Test func pickingADateFieldIsAChangeAndEachTypesDateTakesItBack() throws {
        let event = TypeID("test.event")
        let eventType = ItemTypeInfo(
            id: event, label: "Event", fields: [
                .init(key: "starts_at", label: "Starts at", kind: .date(includesTime: true), declaredBy: event),
                .init(key: "ends_at", label: "Ends at", kind: .date(includesTime: true), declaredBy: event),
            ], titleField: "title", bodyField: "body", parent: nil)
        let (browser, library) = Self.opened()
        library.catalogue = Catalogue(
            itemTypes: Array(FakeItemLibrary.testCatalogue.itemTypes.values) + [eventType],
            edgeTypes: Array(FakeItemLibrary.testCatalogue.edgeTypes.values))
        let item = Item(
            id: ItemID("e1"), type: event, title: "E", titleRule: .property("title"), version: ItemVersion(1), created: .distantPast,
            modified: .distantPast)
        library.items = [item]
        library.viewMembers[Self.view().id] = [item.id]
        browser.viewMode = .timeline
        Self.take(.timeline, in: browser)
        // Each type's own date is no choice, so choosing it again keeps the view as it was.
        browser.setTimelineField(nil, in: library)
        #expect(!browser.hasViewChanges)
        let field = try #require(browser.timelineFieldChoices(in: library).first?.key)
        browser.setTimelineField(field, in: library)
        #expect(browser.hasViewChanges)
        browser.setTimelineField(nil, in: library)
        #expect(!browser.hasViewChanges)
    }

    @Test func revertingPutsTheWindowBackToTheViewInEveryLayout() {
        let (browser, library) = Self.opened()
        browser.viewMode = .board
        browser.tableOptions[browser.shown]?.grouping = .none
        browser.tableOptions[browser.shown]?.sort = [ItemTableComparator(column: .title)]
        browser.tableOptions[browser.shown]?.filter = FilterState(is: ["field.status": ["todo"]])
        browser.timelineFields[browser.shown] = "starts_at"
        #expect(browser.hasViewChanges)
        browser.revertView(in: library)
        #expect(!browser.hasViewChanges)
        #expect(browser.tableOptions[browser.shown] == ViewDraft.options(for: Self.view(), catalogue: library.catalogue))
        #expect(browser.timelineFields[browser.shown] == nil)
    }

    @Test func revertingDoesNothingWhereThePlaceIsNotAView() {
        let browser = Browser()
        let library = FakeItemLibrary()
        browser.adopt(library)
        browser.tableOptions[.library] = ItemTableOptions(filter: FilterState(is: ["field.status": ["todo"]]))
        browser.revertView(in: library)
        #expect(browser.tableOptions[.library]?.filter.valuesByField == ["field.status": ["todo"]])
        #expect(!browser.hasViewChanges)
    }

    @Test func aViewChangedElsewhereIsFollowedUnlessTheWindowChangedIt() {
        let (browser, library) = Self.opened()
        library.views = [Self.view(version: 2, group: "type")]
        browser.followView(in: library)
        #expect(browser.tableOptions[browser.shown]?.grouping == ViewDraft.options(for: library.views[0], catalogue: library.catalogue).grouping)
        #expect(browser.viewSeeds[library.views[0].id]?.version == 2)

        browser.tableOptions[browser.shown]?.grouping = .none
        library.views = [Self.view(version: 3)]
        browser.followView(in: library)
        #expect(browser.tableOptions[browser.shown]?.grouping == ItemTableOptions.Grouping.none)
        // The update stays based on the version the person's change was made on, so the server can refuse it.
        #expect(browser.viewSeeds[library.views[0].id]?.version == 2)
        #expect(browser.hasViewChanges)
    }

    @Test func aRefusedUpdatePutsTheWindowBackToTheView() {
        let (browser, library) = Self.opened()
        browser.tableOptions[browser.shown]?.grouping = .none
        library.views = [Self.view(version: 2)]
        browser.viewRefused(library.views[0].id, in: library)
        #expect(browser.tableOptions[browser.shown]?.grouping == ViewDraft.options(for: library.views[0], catalogue: library.catalogue).grouping)
        #expect(browser.viewSeeds[library.views[0].id]?.version == 2)
        #expect(!browser.hasViewChanges)
    }

    @Test func anUpdateNamesOnlyWhatChangedAtTheVersionRead() throws {
        let (browser, library) = Self.opened()
        browser.tableOptions[browser.shown]?.grouping = .none
        let window = ViewDraft.Window(place: browser.shown, columns: [], sort: [], grouping: nil)
        let update = try #require(browser.viewUpdate(window, in: library))
        #expect(update.baseVersion == 1)
        #expect(update.change.group == .clear)
        #expect(update.change.title == nil)
        #expect(update.change.query == nil)
    }

    @Test func anotherLibraryStartsWithNoSeeds() {
        // The first library is kept, so the second is not made at its address and taken for it.
        let (browser, first) = Self.opened()
        browser.deletingView = Self.view().id
        browser.openViewPanel(in: first)
        browser.changeViewSettings(Self.view().id) { $0.hidesEmptyGroups = true }
        let second = FakeItemLibrary()
        browser.adopt(second)
        withExtendedLifetime(first) {}
        #expect(browser.viewSeeds.isEmpty)
        #expect(browser.deletingView == nil)
        #expect(browser.viewPanel == nil)
        #expect(browser.writingViews.isEmpty)
    }

    @Test func aChangedOrderOrGroupingIsOfferedInEveryLayout() {
        for mode in ItemViewMode.allCases {
            let (browser, _) = Self.opened()
            browser.viewMode = mode
            browser.tableOptions[browser.shown]?.grouping = .none
            #expect(browser.hasViewChanges, "\(mode) did not count a grouping")
        }
    }
}
