import Foundation
import Testing
@testable import MAPP

/// What the panel that edits a view does: each change shows in the window as it is made, is written to a saved view as it
/// is made, and is taken back by one Undo. Done only closes the panel, except for a new view, which it makes.
@MainActor
// Serialised: each test drives its own undo manager's groups by hand, and tests that interleave on the main actor hung the host.
@Suite(.serialized, .hangLimit)
struct ViewPanelTests {
    static func defaults() -> UserDefaults {
        let suite = "MAPP.ViewPanelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private static let id = ItemID("view-open-tasks")
    private static let order = NoteOrder()
    private static let status = ViewDraft.columnID(of: "properties.status") ?? "field.status"

    private static func view(filter: String? = nil) -> LibraryView {
        LibraryView(
            id: id, title: "Open Tasks", version: 1,
            query: LibraryViewQuery(types: [TypeID("core.task")], states: [.active], filter: filter),
            sort: [LibraryViewSort(field: "updated_at", ascending: false)], group: LibraryViewGroup(field: "properties.status"))
    }

    private static func opened(filter: String? = nil, reachesServer: Bool = true) -> (Browser, FakeItemLibrary, UndoManager) {
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let tasks = ["todo", "done", "in_progress"].enumerated().map { index, status in
            Item(
                id: ItemID("t\(index)"), type: TypeID("core.task"), title: "t\(index)", name: "t\(index)", titleRule: .firstLine,
                properties: [Property(key: "status", value: .string(status))], version: ItemVersion(1), created: date, modified: date)
        }
        let library = FakeItemLibrary(items: tasks, now: date)
        library.views = [view(filter: filter)]
        library.viewMembers[id] = tasks.map(\.id)
        library.reachesServer = reachesServer
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        let browser = Browser()
        browser.defaults = defaults()
        browser.adopt(library, undoManager: undo)
        browser.sidebarItem = .view(id)
        browser.viewMode = .table
        browser.followView(in: library)
        browser.choicesChanged()
        // The opening is not the person's: nothing of it can be undone.
        Self.close(undo)
        undo.removeAllActions()
        return (browser, library, undo)
    }

    /// Ends the group a change was registered in, so that each change is a step of its own, as a turn of the run loop makes
    /// it in the app. The groups are the test's, since the manager's own end a group on a later turn of
    /// the loop, which the test host answers with an exception that leaves a test hanging.
    private static func close(_ undo: UndoManager) {
        while undo.groupingLevel > 0 { undo.endUndoGrouping() }
    }

    private static func held(_ library: FakeItemLibrary) -> LibraryView? { library.views.first { $0.id == id } }

    /// Makes one change as the window does, then lets the write it caused finish.
    private static func change(_ browser: Browser, _ edit: () -> Void) async {
        browser.undoManager?.beginUndoGrouping()
        edit()
        let task = browser.choicesChanged()
        if let undo = browser.undoManager { close(undo) }
        await task?.value
    }

    /// Takes back one change, then waits for the view to hold what the Undo must leave there.
    private static func undo(_ undo: UndoManager, _ library: FakeItemLibrary, until held: (LibraryView?) -> Bool) async {
        Self.close(undo)
        undo.undo()
        let reached = await eventually(within: .seconds(20)) { held(Self.held(library)) }
        #expect(reached)
    }

    // MARK: Written as made, and Undo

    @Test func aFilterIsWrittenToTheViewAsItIsMade() async {
        let (browser, library, _) = Self.opened()
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo"]) }
        #expect(Self.held(library)?.version == 2)
        #expect(Self.held(library)?.query.filter?.contains("todo") == true)
    }

    @Test func undoOfAFilterWritesTheEarlierValueBack() async {
        let (browser, library, undo) = Self.opened()
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo"]) }
        await Self.undo(undo, library) { $0?.version == 3 }
        #expect(Self.held(library)?.query.filter == nil)
        #expect(browser.filterCount == 0)
    }

    @Test func undoOfAGroupingWritesTheEarlierGroupBack() async {
        let (browser, library, undo) = Self.opened()
        await Self.change(browser) { browser.tableOptions[browser.item, default: .init()].grouping = .none }
        #expect(Self.held(library)?.group == nil)
        await Self.undo(undo, library) { $0?.group != nil }
        #expect(Self.held(library)?.group == LibraryViewGroup(field: "properties.status"))
    }

    @Test func undoOfASortWritesTheEarlierOrderBack() async {
        let (browser, library, undo) = Self.opened()
        await Self.change(browser) {
            browser.tableOptions[browser.item, default: .init()].sort = [ItemTableComparator(column: .title, order: .forward)]
        }
        #expect(Self.held(library)?.sort != Self.view().sort)
        await Self.undo(undo, library) { $0?.sort == Self.view().sort }
        #expect(Self.held(library)?.sort == Self.view().sort)
    }

    @Test func undoTakesBackOneChangeAtATime() async {
        let (browser, library, undo) = Self.opened()
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo"]) }
        await Self.change(browser) { browser.tableOptions[browser.item, default: .init()].grouping = .none }
        await Self.undo(undo, library) { $0?.group != nil }
        #expect(Self.held(library)?.query.filter?.contains("todo") == true)
        await Self.undo(undo, library) { $0?.query.filter == nil }
        #expect(Self.held(library)?.query.filter == nil)
    }

    @Test func redoWritesTheChangeAgain() async {
        let (browser, library, undo) = Self.opened()
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo"]) }
        await Self.undo(undo, library) { $0?.query.filter == nil }
        Self.close(undo)
        undo.redo()
        #expect(await eventually(within: .seconds(20)) { Self.held(library)?.query.filter?.contains("todo") == true })
    }

    @Test func undoOfALayoutPutsTheLayoutBackOnThisMac() {
        let (browser, _, undo) = Self.opened()
        undo.beginUndoGrouping()
        browser.viewMode = .gallery
        Self.close(undo)
        #expect(ViewLayouts.stored(in: browser.defaults).settings(for: Self.id)?.layout == .gallery)
        undo.undo()
        #expect(browser.viewMode == .table)
    }

    @Test func columnsAreStoredAsTheyAreChangedAndUndoPutsThemBack() {
        let (browser, _, undo) = Self.opened()
        undo.beginUndoGrouping()
        browser.changeViewSettings(Self.id) { $0.columns.setShown(.created, true) }
        Self.close(undo)
        #expect(ViewLayouts.stored(in: browser.defaults).settings(for: Self.id)?.columns.isShown(.created) == true)
        undo.undo()
        #expect(ViewLayouts.stored(in: browser.defaults).settings(for: Self.id)?.columns.isShown(.created) != true)
    }

    // MARK: Refused and offline writes

    @Test func aRefusedWriteKeepsTheWindowsChoiceAndLeavesTheViewAlone() async {
        let (browser, library, _) = Self.opened()
        library.viewFailure = ViewWriteFailure(kind: .refused, message: "No")
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo"]) }
        #expect(browser.filterCount == 1)
        #expect(Self.held(library)?.version == 1)
        #expect(Self.held(library)?.query.filter == nil)
    }

    @Test func undoAfterARefusedWriteWritesNothingThePersonNeverHad() async {
        let (browser, library, undo) = Self.opened()
        library.viewFailure = ViewWriteFailure(kind: .refused, message: "No")
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo"]) }
        library.viewFailure = nil
        Self.close(undo)
        undo.undo()
        #expect(browser.filterCount == 0)
        // Nothing was written, so there is nothing to wait for: give a wrong write the chance to show.
        await browser.choicesChanged()?.value
        #expect(Self.held(library)?.version == 1)
    }

    @Test func theNextWriteAfterARefusalCarriesTheChange() async {
        let (browser, library, _) = Self.opened()
        library.viewFailure = ViewWriteFailure(kind: .refused, message: "No")
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo"]) }
        library.viewFailure = nil
        browser.writeViewAgain()
        #expect(await eventually(within: .seconds(20)) { Self.held(library)?.query.filter?.contains("todo") == true })
    }

    @Test func anOfflineWriteDoesNotBlockAndKeepsTheChoice() async {
        let (browser, library, _) = Self.opened(reachesServer: false)
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo"]) }
        #expect(browser.filterCount == 1)
        #expect(Self.held(library)?.version == 1)
    }

    @Test func undoNeverOverwritesAChangeMadeElsewhere() async {
        let (browser, library, undo) = Self.opened()
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo"]) }
        // Another window changed the view: this window follows it.
        var elsewhere = Self.held(library) ?? Self.view()
        elsewhere.version += 1
        elsewhere.query.filter = #"properties.status eq "done""#
        library.views = [elsewhere]
        browser.seed(elsewhere, catalogue: library.catalogue)
        Self.close(undo)
        undo.undo()
        await browser.choicesChanged()?.value
        #expect(Self.held(library)?.query.filter == #"properties.status eq "done""#)
        #expect(Self.held(library)?.version == elsewhere.version)
    }

    // MARK: A condition the row cannot show

    @Test func aConditionTheRowCannotShowIsKeptThroughAWrite() async {
        let (browser, library, _) = Self.opened(filter: #"source eq "mail""#)
        #expect(!ViewDraft.unshownConditions(of: Self.view(filter: #"source eq "mail""#).query, catalogue: library.catalogue).isEmpty)
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo"]) }
        let filter = Self.held(library)?.query.filter ?? ""
        #expect(filter.contains(#"source eq "mail""#))
        #expect(filter.contains("todo"))
    }

    // MARK: Group by, from one place

    @Test func aListShowsItsDateSectionsAsItsGrouping() {
        let (browser, library, undo) = Self.opened()
        undo.beginUndoGrouping()
        browser.viewMode = .list
        Self.close(undo)
        browser.tableOptions[browser.item]?.grouping = .automatic
        browser.tableOptions[browser.item]?.sort = nil
        let content = browser.tableContent(in: library)
        let shown = SavedViews.arrangement(browser, content: content, order: NoteOrder())
        #expect(shown.grouping == .date)
        #expect(shown.isDated)
    }

    @Test func aTableShowsItsOwnGroupingNotTheListsDates() {
        let (browser, library, _) = Self.opened()
        browser.viewMode = .table
        let content = browser.tableContent(in: library)
        let shown = SavedViews.arrangement(browser, content: content, order: NoteOrder())
        #expect(shown.grouping != .date)
    }

    // MARK: Done and Escape

    @Test func doneOnAViewOnlyClosesThePanelAndWritesNothingMore() async {
        let (browser, library, _) = Self.opened()
        browser.openViewPanel(in: library)
        await browser.finishViewPanel(in: library, order: Self.order)
        #expect(browser.viewPanel == nil)
        #expect(Self.held(library)?.version == 1)
    }

    @Test func aTypedNameIsWrittenOnDoneAndUndoWritesTheOldNameBack() async {
        let (browser, library, undo) = Self.opened()
        browser.openViewPanel(in: library)
        browser.viewPanel?.name = "Renamed"
        undo.beginUndoGrouping()
        await browser.finishViewPanel(in: library, order: Self.order)
        Self.close(undo)
        #expect(Self.held(library)?.title == "Renamed")
        await Self.undo(undo, library) { $0?.title == "Open Tasks" }
        #expect(Self.held(library)?.title == "Open Tasks")
    }

    @Test func doneOnANewViewMakesItWithTheDefaultNameAndEscapeMakesNothing() async {
        let (browser, library, _) = Self.opened()
        browser.openNewViewPanel(in: library)
        browser.escapeViewPanel(in: library)
        #expect(browser.viewPanel == nil)
        #expect(library.views.count == 1)
        browser.openNewViewPanel(in: library)
        await browser.finishViewPanel(in: library, order: Self.order)
        #expect(library.views.count == 2)
        #expect(library.views.contains { $0.title == "New View" })
    }

    @Test func aTypesListOffersToSaveWhatItShowsAsAView() async {
        let library = FakeItemLibrary()
        let browser = Browser()
        browser.defaults = Self.defaults()
        browser.adopt(library, undoManager: UndoManager())
        browser.sidebarItem = .itemType("core.task")
        browser.viewMode = .table
        browser.openViewPanel(in: library)
        #expect(browser.viewPanel?.purpose == .place)
        #expect(library.views.isEmpty)
    }
}
