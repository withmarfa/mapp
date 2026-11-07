import Foundation
import Testing
@testable import MAPP

/// A window that changes a saved view's filters lists what the changed filters select at once, from the view's own query
/// with the chips' conditions taken out, and not only after Save.
@MainActor
struct BrowserViewPreviewTests {
    private static let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let task = TypeID("core.task")
    private static let status = "field.status"

    private static func item(_ id: String, status: String) -> Item {
        Item(
            id: ItemID(id), type: task, title: id, name: id, titleRule: .firstLine,
            properties: [Property(key: "status", value: .string(status))], version: ItemVersion(1), created: date, modified: date)
    }

    private static func view(version: Int64 = 1, filter: String? = #"properties.status neq "done""#) -> LibraryView {
        LibraryView(
            id: ItemID("view-open"), title: "Open", version: version,
            query: LibraryViewQuery(types: [task], states: [.active], filter: filter))
    }

    /// Four tasks. The saved view lists those not done; with its filter taken out it lists all four.
    private static func library(_ view: LibraryView = view()) -> FakeItemLibrary {
        let library = FakeItemLibrary(
            items: [item("t0", status: "todo"), item("t1", status: "done"), item("t2", status: "in_progress"), item("t3", status: "todo")],
            now: date)
        library.views = [view]
        library.viewMembers[view.id] = [ItemID("t0"), ItemID("t2"), ItemID("t3")]
        library.previewMembers[LibraryViewQuery(types: [task], states: [.active])] = ["t0", "t1", "t2", "t3"].map { ItemID($0) }
        return library
    }

    private static func window(_ library: FakeItemLibrary, view: LibraryView = view()) -> Browser {
        let browser = Browser()
        browser.adopt(library)
        browser.sidebarItem = .view(view.id)
        browser.viewMode = .table
        browser.followView(in: library)
        return browser
    }

    private func titles(_ browser: Browser, _ library: FakeItemLibrary) -> [String] {
        browser.tableContent(in: library).rows.map(\.item.title).sorted()
    }

    @Test func anUnchangedWindowListsTheViewAndReadsNoPreview() {
        let library = Self.library()
        let browser = Self.window(library)
        #expect(browser.viewPreview == nil)
        #expect(titles(browser, library) == ["t0", "t2", "t3"])
        #expect(library.previewsAsked.isEmpty)
    }

    @Test func aChipTakenOffBringsItsRowsBackAtOnce() {
        let library = Self.library()
        let browser = Self.window(library)
        browser.tableOptions[browser.item]?.filters = [:]
        browser.tableOptions[browser.item]?.negated = []
        #expect(browser.hasViewChanges)
        #expect(titles(browser, library) == ["t0", "t1", "t2", "t3"])
        #expect(library.previewsAsked.last == LibraryViewQuery(types: [Self.task], states: [.active]))
    }

    @Test func aChangedChipNarrowsThePreviewLocally() {
        let library = Self.library()
        let browser = Self.window(library)
        browser.tableOptions[browser.item]?.filters = [Self.status: ["todo"]]
        browser.tableOptions[browser.item]?.negated = []
        #expect(titles(browser, library) == ["t0", "t3"])
        // The chip's other values are still on offer, though no row of the saved view held "done".
        let content = browser.tableContent(in: library)
        let column = content.columns.first { $0.id == Self.status }
        #expect(column.map { ItemTableLayout.offered(in: content.allRows, by: $0, keeping: ["todo"]).map(\.id) }?.contains("done") == true)
    }

    @Test func revertingReturnsToTheSavedList() {
        let library = Self.library()
        let browser = Self.window(library)
        browser.tableOptions[browser.item]?.filters = [:]
        browser.tableOptions[browser.item]?.negated = []
        #expect(titles(browser, library).count == 4)
        browser.revertView(in: library)
        #expect(browser.viewPreview == nil)
        #expect(titles(browser, library) == ["t0", "t2", "t3"])
    }

    @Test func savingMakesTheChangedFiltersTheViewsOwn() {
        let library = Self.library()
        let browser = Self.window(library)
        browser.tableOptions[browser.item]?.filters = [Self.status: ["todo"]]
        browser.tableOptions[browser.item]?.negated = []
        #expect(browser.viewPreview != nil)
        let saved = Self.view(version: 2, filter: #"properties.status eq "todo""#)
        browser.viewUpdated(saved, in: library)
        #expect(!browser.hasViewChanges)
        #expect(browser.viewPreview == nil)
    }

    @Test func aChangedPreviewListChangesWhatTheWindowDraws() {
        let library = Self.library()
        let browser = Self.window(library)
        browser.tableOptions[browser.item]?.filters = [:]
        browser.tableOptions[browser.item]?.negated = []
        let first = browser.tableContent(in: library)
        #expect(browser.tableContent(in: library) === first)
        // A preview that lands later, with no revision of the library's own to tell the table of it.
        library.previewMembers[LibraryViewQuery(types: [Self.task], states: [.active])] = [ItemID("t1")]
        let second = browser.tableContent(in: library)
        #expect(second !== first)
        #expect(second.rows.map(\.item.title) == ["t1"])
    }

    @Test func aConditionTheChipsCannotShowStaysInThePreview() {
        let view = Self.view(filter: #"tags contains "x" AND properties.status neq "done""#)
        let library = Self.library(view)
        let browser = Self.window(library, view: view)
        browser.tableOptions[browser.item]?.filters = [:]
        browser.tableOptions[browser.item]?.negated = []
        _ = browser.tableContent(in: library)
        #expect(library.previewsAsked.last?.filter == #"tags contains "x""#)
    }

    @Test func aViewWhoseFilterTheCoreRefusesHasNoPreview() {
        let view = Self.view(filter: "not a filter ((")
        let library = Self.library(view)
        let browser = Self.window(library, view: view)
        browser.tableOptions[browser.item]?.filters = [Self.status: ["todo"]]
        #expect(browser.hasViewChanges)
        #expect(browser.viewPreview == nil)
        // The view's own list, narrowed by the chip.
        #expect(titles(browser, library) == ["t0", "t3"])
        #expect(library.previewsAsked.isEmpty)
    }

    @Test func mixedAndOrConditionsStayWhole() {
        let view = Self.view(filter: #"properties.status eq "todo" OR properties.done eq true"#)
        let library = Self.library(view)
        let browser = Self.window(library, view: view)
        #expect(browser.tableOptions[browser.item]?.filters.isEmpty == true)
        browser.tableOptions[browser.item]?.filters = [Self.status: ["todo"]]
        _ = browser.tableContent(in: library)
        #expect(library.previewsAsked.last?.filter == view.query.filter)
    }

    @Test func aWindowWithChangesKeepsItsPreviewWhenTheViewChangesElsewhere() {
        let library = Self.library()
        let browser = Self.window(library)
        browser.tableOptions[browser.item]?.filters = [:]
        browser.tableOptions[browser.item]?.negated = []
        let before = browser.viewPreview
        let elsewhere = Self.view(version: 2, filter: #"properties.status eq "todo""#)
        library.views = [elsewhere]
        browser.followView(in: library)
        #expect(browser.viewPreview?.query == before?.query)
        #expect(browser.viewPreview?.query.filter == nil)
    }

    @Test func twoWindowsOnOneViewReadTheirOwnPreviews() {
        let library = Self.library()
        let changed = Self.window(library)
        let plain = Self.window(library)
        changed.tableOptions[changed.item]?.filters = [:]
        changed.tableOptions[changed.item]?.negated = []
        #expect(titles(changed, library).count == 4)
        #expect(titles(plain, library) == ["t0", "t2", "t3"])
    }
}
