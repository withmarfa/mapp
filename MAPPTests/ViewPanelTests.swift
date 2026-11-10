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

    @Test func aSecondOfflineStretchIsToldAgainOnceTheServerWasBack() async {
        let (browser, library, _) = Self.opened(reachesServer: false)
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo"]) }
        #expect(library.notices.told == 1)
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo", "done"]) }
        #expect(library.notices.told == 1)
        library.reachesServer = true
        browser.reachabilityChanged(in: library)
        library.reachesServer = false
        await Self.change(browser) { browser.setFilter(Self.status, values: ["done"]) }
        #expect(library.notices.told == 2)
    }

    @Test func aNameTypedDuringARenameIsWrittenWithoutClaimingTheViewWasRenamedElsewhere() async {
        let (browser, library, undo) = Self.opened()
        undo.beginUndoGrouping()
        browser.openViewPanel(in: library)
        browser.viewPanel?.name = "First"
        var release: CheckedContinuation<Void, Never>?
        var held = false
        library.inViewChange = {
            guard !held else { return }
            held = true
            await withCheckedContinuation { release = $0 }
        }
        let first = Task { await browser.commitViewName(in: library) }
        #expect(await eventually(within: .seconds(20)) { release != nil })
        browser.viewPanel?.name = "Second"
        let second = Task { await browser.commitViewName(in: library) }
        release?.resume()
        await first.value
        await second.value
        #expect(Self.held(library)?.title == "Second")
        #expect(!library.notices.waiting.contains { $0.title == "Can’t Rename" })
    }

    @Test func aNameTypedAfterTheRenameWasSentIsGivenBackWhenThePanelCloses() async {
        let (browser, library, undo) = Self.opened()
        undo.beginUndoGrouping()
        browser.openViewPanel(in: library)
        browser.viewPanel?.name = "First"
        var release: CheckedContinuation<Void, Never>?
        library.inViewChange = { await withCheckedContinuation { release = $0 } }
        let rename = Task { await browser.commitViewName(in: library) }
        #expect(await eventually(within: .seconds(20)) { release != nil })
        browser.viewPanel?.name = "Second"
        browser.closeViewPanel(in: library)
        release?.resume()
        await rename.value
        #expect(Self.held(library)?.title == "First")
        #expect(library.notices.waiting.contains { $0.isNotKept && $0.text == "Second" })
    }

    @Test func aRefusedRenameGivesBackTheLatestNameTyped() async {
        let (browser, library, undo) = Self.opened(reachesServer: false)
        undo.beginUndoGrouping()
        browser.openViewPanel(in: library)
        browser.viewPanel?.name = "First"
        let panel = browser.viewPanel
        panel?.renaming = "First"
        panel?.name = "Second"
        browser.closeViewPanel(in: library)
        panel?.finishRename(name: "First", kept: false)
        #expect(library.notices.waiting.contains { $0.isNotKept && $0.text == "Second" })
        #expect(!library.notices.waiting.contains { $0.isNotKept && $0.text == "First" })
    }

    @Test func leavingAViewMidWriteCausesNoRewriteOfIt() async {
        let (browser, library, undo) = Self.opened()
        undo.beginUndoGrouping()
        var release: CheckedContinuation<Void, Never>?
        library.inViewChange = { await withCheckedContinuation { release = $0 } }
        browser.setFilter(Self.status, values: ["todo"])
        let task = browser.choicesChanged()
        #expect(await eventually(within: .seconds(20)) { release != nil })
        browser.sidebarItem = .allNotes
        release?.resume()
        await task?.value
        #expect(Self.held(library)?.query.filter?.contains("todo") == true)
        #expect(!browser.pendingViewWrites.contains(Self.id))
    }

    @Test func escapeOnANewViewKeepsTheStepsMadeBeforeItOpened() async {
        let (browser, library, undo) = Self.opened()
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo"]) }
        browser.openNewViewPanel(in: library)
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo", "done"]) }
        browser.escapeViewPanel(in: library)
        #expect(undo.canUndo)
        await Self.undo(undo, library) { $0?.query.filter?.contains("todo") != true }
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

    // MARK: Faults the review found

    @Test func groupByDateOnAListWritesNoSortThePersonDidNotChooseAndLeavesTheViewUnedited() async {
        let (browser, library, _) = Self.opened()
        browser.set(layout: .list)
        await Self.change(browser) {
            browser.tableOptions[browser.item, default: .init()].grouping = .automatic
            browser.tableOptions[browser.item, default: .init()].sort = nil
        }
        #expect(Self.held(library)?.group == nil)
        #expect(Self.held(library)?.sort == Self.view().sort)
        #expect(Self.held(library)?.version == 2)
        #expect(!browser.hasViewChanges)
    }

    @Test func aChoiceChangedWhileANameIsBeingWrittenIsWrittenAfterIt() async {
        let (browser, library, undo) = Self.opened()
        undo.beginUndoGrouping()
        browser.openViewPanel(in: library)
        browser.viewPanel?.name = "Renamed"
        var release: CheckedContinuation<Void, Never>?
        var held = false
        library.inViewChange = {
            guard !held else { return }
            held = true
            await withCheckedContinuation { release = $0 }
        }
        let rename = Task { await browser.commitViewName(in: library) }
        #expect(await eventually(within: .seconds(20)) { release != nil })
        browser.setFilter(Self.status, values: ["todo"])
        browser.choicesChanged()
        release?.resume()
        await rename.value
        #expect(await eventually(within: .seconds(20)) { Self.held(library)?.query.filter?.contains("todo") == true })
        #expect(Self.held(library)?.title == "Renamed")
    }

    @Test func aChangeTheViewCannotHoldIsToldEvenThoughThereIsNothingToWrite() async {
        let ors = #"tags contains "a" OR tags contains "b""#
        let (browser, library, _) = Self.opened(filter: ors)
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo"]) }
        #expect(Self.held(library)?.version == 1)
        #expect(library.notices.waiting.contains { $0.title == "View Not Fully Saved" })
    }

    @Test func aRenameStillBeingWrittenIsNotGivenToTheClipboardWhenThePanelCloses() async {
        let (browser, library, undo) = Self.opened()
        undo.beginUndoGrouping()
        browser.openViewPanel(in: library)
        browser.viewPanel?.name = "Renamed"
        var release: CheckedContinuation<Void, Never>?
        library.inViewChange = { await withCheckedContinuation { release = $0 } }
        let rename = Task { await browser.commitViewName(in: library) }
        #expect(await eventually(within: .seconds(20)) { release != nil })
        browser.closeViewPanel(in: library)
        release?.resume()
        await rename.value
        #expect(Self.held(library)?.title == "Renamed")
        #expect(!library.notices.waiting.contains { $0.isNotKept })
    }

    @Test func escapeOnANewViewLeavesNoUndoStepsBehind() {
        let (browser, library, undo) = Self.opened()
        browser.openNewViewPanel(in: library)
        undo.beginUndoGrouping()
        browser.setFilter(Self.status, values: ["todo"])
        browser.choicesChanged()
        Self.close(undo)
        browser.escapeViewPanel(in: library)
        #expect(!undo.canUndo)
    }

    @Test func aSecondDoneOnANewViewIsSilent() async {
        let (browser, library, _) = Self.opened()
        browser.openNewViewPanel(in: library)
        var release: CheckedContinuation<Void, Never>?
        library.inViewWrite = { await withCheckedContinuation { release = $0 } }
        let first = Task { await browser.finishViewPanel(in: library, order: Self.order) }
        #expect(await eventually(within: .seconds(20)) { release != nil })
        let before = library.notices.told
        await browser.finishViewPanel(in: library, order: Self.order)
        #expect(library.notices.told == before)
        release?.resume()
        await first.value
        #expect(library.views.count == 2)
    }

    @Test func aChangeMadeJustBeforeLeavingTheViewIsWrittenWhenItIsShownAgain() async {
        let (browser, library, undo) = Self.opened()
        undo.beginUndoGrouping()
        browser.setFilter(Self.status, values: ["todo"])
        let task = browser.choicesChanged()
        browser.sidebarItem = .allNotes
        await task?.value
        #expect(Self.held(library)?.version == 1)
        browser.sidebarItem = .view(Self.id)
        browser.followView(in: library)
        #expect(await eventually(within: .seconds(20)) { Self.held(library)?.query.filter?.contains("todo") == true })
    }

    @Test func undoOfALayoutOnATypesListPutsTheLayoutBack() {
        let library = FakeItemLibrary()
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        let browser = Browser()
        browser.defaults = Self.defaults()
        browser.adopt(library, undoManager: undo)
        browser.sidebarItem = .itemType("core.task")
        browser.viewMode = .list
        undo.removeAllActions()
        undo.beginUndoGrouping()
        browser.viewMode = .table
        Self.close(undo)
        undo.undo()
        #expect(browser.viewMode == .list)
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
