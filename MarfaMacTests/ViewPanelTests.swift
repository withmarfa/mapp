import Foundation
import Marfa
import Testing
@testable import MarfaMac

/// What the panel that edits a view does: each change shows in the window as it is made, is written to a saved view as it
/// is made, and is taken back by one Undo. Closing the panel writes nothing more, except a new view's Create View.
@MainActor
// Serialised: each test drives its own undo manager's groups by hand, and tests that interleave on the main actor hung the host.
@Suite(.serialized, .hangLimit)
struct ViewPanelTests {
    static func defaults() -> UserDefaults {
        let defaults = ThrowawayDefaults.make("MarfaMac.ViewPanelTests")
        return defaults
    }

    private static let id = ItemID("view-open-tasks")
    private static let order = ItemOrder()
    private static let status = ViewDraft.columnID(of: "properties.status") ?? "field.status"

    private static func view(filter: String? = nil) -> LibraryView {
        LibraryView(
            id: id, title: "Open Tasks", version: 1,
            query: LibraryViewQuery(types: [TypeID("core.task")], states: [.active], filter: filter),
            sort: [LibraryViewSort(field: "updated_at", ascending: false)], group: LibraryViewGroup(field: "properties.status"))
    }

    private static func opened(
        filter: String? = nil, view custom: LibraryView? = nil, reachesServer: Bool = true
    ) -> (Browser, FakeItemLibrary, UndoManager) {
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let tasks = ["todo", "done", "in_progress"].enumerated().map { index, status in
            Item(
                id: ItemID("t\(index)"), type: TypeID("core.task"), title: "t\(index)", name: "t\(index)", titleRule: .firstLine,
                properties: [Property(key: "status", value: .string(status))], version: ItemVersion(1), created: date, modified: date)
        }
        let library = FakeItemLibrary(items: tasks, now: date)
        library.views = [custom ?? view(filter: filter)]
        library.viewMembers[id] = tasks.map(\.id)
        library.reachesServer = reachesServer
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        let browser = Browser()
        browser.defaults = defaults()
        browser.adopt(library, undoManager: undo)
        browser.showing = .saved(id)
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

    /// A view another app wrote, with a sort, a group and a condition this app cannot show, keeps them all when the
    /// panel changes one setting, and a setting only this Mac keeps writes nothing to it.
    @Test func oneChangeKeepsWhatTheAppCannotShow() async throws {
        let sort = [LibraryViewSort(field: "properties.mood", ascending: true), LibraryViewSort(field: "updated_at", ascending: false)]
        let group = LibraryViewGroup(field: "properties.weather", order: [.string("sunny")], hidden: [.string("rain")], otherBucket: "elsewhere")
        let unknown = LibraryView(
            id: Self.id, title: "Open Tasks", version: 1,
            query: LibraryViewQuery(types: [TypeID("core.task")], states: [.active], filter: #"properties.mood eq "calm""#),
            sort: sort, group: group)
        let (browser, library, _) = Self.opened(view: unknown)
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo"]) }
        let held = try #require(Self.held(library))
        #expect(held.version == 2)
        #expect(held.query.filter?.contains(#""calm""#) == true)
        #expect(held.query.filter?.contains(#""todo""#) == true)
        #expect(held.query.types == unknown.query.types)
        #expect(held.query.states == unknown.query.states)
        #expect(held.sort == sort)
        #expect(held.group == group)
        await Self.change(browser) { browser.setShowsQuickActions(false) }
        #expect(!browser.showsQuickActions)
        #expect(Self.held(library)?.version == 2)
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
        await Self.change(browser) { browser.tableOptions[browser.shown, default: .init()].grouping = .none }
        #expect(Self.held(library)?.group == nil)
        await Self.undo(undo, library) { $0?.group != nil }
        #expect(Self.held(library)?.group == LibraryViewGroup(field: "properties.status"))
    }

    /// Another app's sort, merged into the write of a grouping, is not the person's change, so an Undo of the grouping
    /// gives back the earlier group exactly and leaves that sort as it is.
    @Test func undoOfAGroupingAfterAMergedSortGivesBackTheEarlierGroupExactly() async throws {
        let (browser, library, undo) = Self.opened()
        let earlier = LibraryViewGroup(field: "properties.status", order: [.string("done")], hidden: [.null])
        var ordered = try #require(Self.held(library))
        ordered.version += 1
        ordered.group = earlier
        library.views = [ordered]
        browser.followView(in: library)
        let sort = [LibraryViewSort(field: "title", ascending: true)]
        library.changedElsewhere = { $0.sort = sort }
        await Self.change(browser) { browser.tableOptions[browser.shown, default: .init()].grouping = .none }
        #expect(Self.held(library)?.group == nil)
        #expect(Self.held(library)?.sort == sort)
        await Self.undo(undo, library) { $0?.group != nil }
        #expect(Self.held(library)?.group == earlier)
        #expect(Self.held(library)?.sort == sort)
        #expect(!library.notices.waiting.contains { $0.title == "Can’t Undo" })
    }

    @Test func undoOfASortWritesTheEarlierOrderBack() async {
        let (browser, library, undo) = Self.opened()
        await Self.change(browser) {
            browser.tableOptions[browser.shown, default: .init()].sort = [ItemTableComparator(column: .title, order: .forward)]
        }
        #expect(Self.held(library)?.sort != Self.view().sort)
        await Self.undo(undo, library) { $0?.sort == Self.view().sort }
        #expect(Self.held(library)?.sort == Self.view().sort)
    }

    @Test func undoTakesBackOneChangeAtATime() async {
        let (browser, library, undo) = Self.opened()
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo"]) }
        await Self.change(browser) { browser.tableOptions[browser.shown, default: .init()].grouping = .none }
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
        browser.changeViewSettings(Self.id) { $0.properties.setShown(.created, true) }
        Self.close(undo)
        #expect(ViewLayouts.stored(in: browser.defaults).settings(for: Self.id)?.properties.isShown(.created) == true)
        undo.undo()
        #expect(ViewLayouts.stored(in: browser.defaults).settings(for: Self.id)?.properties.isShown(.created) != true)
    }

    @Test func densityIsStoredAsItIsChangedAndUndoPutsItBack() {
        let (browser, _, undo) = Self.opened()
        undo.beginUndoGrouping()
        browser.changeDensity(.compact)
        Self.close(undo)
        #expect(ViewLayouts.stored(in: browser.defaults).settings(for: Self.id)?.density == .compact)
        #expect(browser.density == .compact)
        undo.undo()
        #expect(ViewLayouts.stored(in: browser.defaults).settings(for: Self.id)?.density == nil)
        #expect(browser.density == nil)
    }

    @Test func aPlaceKeepsItsDensityOnThisMacAndUndoPutsItBack() {
        let (browser, _, undo) = Self.opened()
        browser.showing = .library
        undo.beginUndoGrouping()
        browser.changeDensity(.compact)
        Self.close(undo)
        #expect(browser.density == .compact)
        #expect(PlaceDensities.stored(in: browser.defaults).density(for: .library) == .compact)
        // Opening the view stored its layout; a place's density adds nothing to it.
        #expect(ViewLayouts.stored(in: browser.defaults).settings(for: Self.id)?.density == nil)
        undo.undo()
        #expect(browser.density == nil)
        #expect(PlaceDensities.stored(in: browser.defaults).density(for: .library) == nil)
    }

    @Test func aPlacesDensityChangedInAnotherWindowIsReadAtOnce() {
        let (browser, _, _) = Self.opened()
        browser.showing = .library
        #expect(browser.density == nil)
        let other = Browser()
        other.defaults = browser.defaults
        other.store(.compact, for: .library)
        #expect(browser.density == .compact)
        PlaceDensities.update(in: browser.defaults) { $0.set(nil, for: .library) }
        #expect(browser.density == nil)
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
        browser.showing = .library
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
        let (browser, library, _) = Self.opened(filter: #"source_id eq "mail""#)
        #expect(!ViewDraft.unshownConditions(of: Self.view(filter: #"source_id eq "mail""#).query, catalogue: library.catalogue).isEmpty)
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo"]) }
        let filter = Self.held(library)?.query.filter ?? ""
        #expect(filter.contains(#"source_id eq "mail""#))
        #expect(filter.contains("todo"))
    }

    @Test func severalWordsBesideAnotherChipAreSavedAsNotTheOthersAndTheViewShowsNoChange() async {
        let (browser, library, _) = Self.opened()
        let priority = ViewDraft.columnID(of: "properties.priority") ?? "field.priority"
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo", "done"]) }
        await Self.change(browser) { browser.setFilter(priority, values: ["high"]) }
        #expect(Self.held(library)?.query.filter == #"properties.status neq "in_progress" AND properties.priority eq "high""#)
        // The window keeps the chip as the person made it, and nothing is unsaved.
        #expect(browser.tableOptions[browser.shown]?.filter.clauses.first == FilterClause(field: Self.status, op: .is, values: ["done", "todo"]))
        #expect(!browser.hasViewChanges)
        #expect(library.notices.waiting.isEmpty, "the rewrite is silent")
        // Opened again, the view shows what it holds.
        let again = Browser()
        again.defaults = Self.defaults()
        again.adopt(library, undoManager: nil)
        again.showing = .saved(Self.id)
        again.followView(in: library)
        #expect(again.tableOptions[again.shown]?.filter.clauses.first == FilterClause(field: Self.status, op: .isNot, values: ["in_progress"]))
    }

    /// The view saying a chip another way is not another app's change: a later write of the sort leaves the chip as the
    /// person made it, while a filter another app changes is shown.
    @Test func aRewrittenChipStaysAsMadeThroughALaterWriteAndAnotherAppsFilterShows() async {
        let (browser, library, _) = Self.opened()
        let priority = ViewDraft.columnID(of: "properties.priority") ?? "field.priority"
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo", "done"]) }
        await Self.change(browser) { browser.setFilter(priority, values: ["high"]) }
        let made = FilterClause(field: Self.status, op: .is, values: ["done", "todo"])
        await Self.change(browser) { browser.tableOptions[browser.shown]?.sort = [ItemTableComparator(column: .title)] }
        #expect(Self.held(library)?.sort == [LibraryViewSort(field: "title", ascending: true)])
        #expect(browser.tableOptions[browser.shown]?.filter.clauses.first == made)
        #expect(!browser.hasViewChanges)

        library.changedElsewhere = { $0.query.filter = #"properties.priority eq "low""# }
        await Self.change(browser) { browser.tableOptions[browser.shown]?.sort = [ItemTableComparator(column: .title, order: .reverse)] }
        #expect(Self.held(library)?.query.filter == #"properties.priority eq "low""#)
        #expect(browser.tableOptions[browser.shown]?.filter.clauses == [FilterClause(field: priority, op: .is, values: ["low"])])
        #expect(Self.held(library)?.sort == [LibraryViewSort(field: "title", ascending: false)])
        #expect(!browser.hasViewChanges)
    }

    @Test func aRelativeDateIsKeptInTheWindowAndNeverWrittenToTheView() async {
        let (browser, library, _) = Self.opened()
        await Self.change(browser) {
            browser.tableOptions[browser.shown]?.filter.clauses.append(FilterClause(field: "edited", op: .inLast, values: ["7"]))
        }
        #expect(Self.held(library)?.version == 1, "nothing was written")
        #expect(library.notices.waiting.isEmpty, "the row says it at once, so no dialog does")
        #expect(browser.hasViewChanges)
        #expect(browser.tableOptions[browser.shown]?.filter.relative.count == 1)
    }

    // MARK: Faults the review found

    @Test func groupByDateOnAListWritesNoSortThePersonDidNotChooseAndLeavesTheViewUnedited() async {
        let (browser, library, _) = Self.opened()
        browser.set(layout: .list)
        await Self.change(browser) {
            browser.tableOptions[browser.shown, default: .init()].grouping = .automatic
            browser.tableOptions[browser.shown, default: .init()].sort = nil
        }
        // The list's sections by date are its edited date by day, which the view keeps.
        #expect(Self.held(library)?.group == LibraryViewGroup(field: "updated_at", bucket: .day))
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

    @Test func aSecondCreateViewOnANewViewIsSilent() async {
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
        _ = await first.value
        #expect(library.views.count == 2)
    }

    @Test func aChangeMadeJustBeforeLeavingTheViewIsWrittenWhenItIsShownAgain() async {
        let (browser, library, undo) = Self.opened()
        undo.beginUndoGrouping()
        browser.setFilter(Self.status, values: ["todo"])
        let task = browser.choicesChanged()
        browser.showing = .library
        await task?.value
        #expect(Self.held(library)?.version == 1)
        browser.showing = .saved(Self.id)
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
        browser.showing = .type(TypeID("core.task"))
        browser.viewMode = .list
        undo.removeAllActions()
        undo.beginUndoGrouping()
        browser.viewMode = .table
        Self.close(undo)
        undo.undo()
        #expect(browser.viewMode == .list)
    }

    // MARK: Closing, Create View and Escape

    @Test func closingThePanelOnAViewWritesNothingMore() async {
        let (browser, library, _) = Self.opened()
        browser.openViewPanel(in: library)
        await browser.finishViewPanel(in: library, order: Self.order)
        #expect(browser.viewPanel == nil)
        #expect(Self.held(library)?.version == 1)
    }

    @Test func aTypedNameIsWrittenOnClosingAndUndoWritesTheOldNameBack() async {
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

    @Test func createViewMakesItWithTheDefaultNameAndEscapeMakesNothing() async {
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

    // MARK: Revert, offline changes and what a new view keeps

    private static let byTitle = [ItemTableComparator(column: .title, order: .forward)]

    /// Revert View puts back the sort this Mac changed and leaves the grouping another app cleared, whether that change
    /// came merged into this Mac's write or arrived after it.
    @Test(arguments: [true, false]) func revertPutsBackOnlyWhatThisMacChanged(mergedIntoTheWrite: Bool) async {
        let (browser, library, undo) = Self.opened()
        if mergedIntoTheWrite { library.changedElsewhere = { $0.group = nil } }
        await Self.change(browser) { browser.tableOptions[browser.shown, default: .init()].sort = Self.byTitle }
        if !mergedIntoTheWrite, var changed = Self.held(library) {
            changed.version += 1
            changed.group = nil
            library.views = [changed]
            browser.followView(in: library)
        }
        #expect(Self.held(library)?.group == nil)
        undo.beginUndoGrouping()
        browser.revertView(in: library)
        Self.close(undo)
        #expect(await eventually(within: .seconds(20)) { Self.held(library)?.sort == Self.view().sort })
        #expect(Self.held(library)?.group == nil)
    }

    /// Revert View writes back a sort whole, with a key the Mac cannot show.
    @Test func revertWritesBackASortTheMacCannotShow() async {
        var custom = Self.view()
        custom.sort = [LibraryViewSort(field: "source", ascending: true), LibraryViewSort(field: "updated_at", ascending: false)]
        let (browser, library, undo) = Self.opened(view: custom)
        await Self.change(browser) { browser.tableOptions[browser.shown, default: .init()].sort = Self.byTitle }
        #expect(Self.held(library)?.sort == [LibraryViewSort(field: "title", ascending: true)])
        undo.beginUndoGrouping()
        browser.revertView(in: library)
        Self.close(undo)
        #expect(await eventually(within: .seconds(20)) { Self.held(library)?.sort == custom.sort })
        #expect(!library.notices.waiting.contains { $0.title == "View Partly Reverted" })
    }

    /// Revert View puts back a grouping by day with its group order and hidden groups.
    @Test func revertWritesBackADayGroupingWithItsOrderAndHiddenGroups() async {
        var custom = Self.view()
        custom.group = LibraryViewGroup(field: "updated_at", bucket: .day, order: [.string("2026-11-02")], hidden: [.string("2026-11-01")])
        let (browser, library, undo) = Self.opened(view: custom)
        await Self.change(browser) { browser.chooseGrouping(.column(Self.status, by: .value)) }
        #expect(Self.held(library)?.group?.field == "properties.status")
        undo.beginUndoGrouping()
        browser.revertView(in: library)
        Self.close(undo)
        #expect(await eventually(within: .seconds(20)) { Self.held(library)?.group == custom.group })
    }

    /// A sort another app changed in a way the window cannot see, as Marfa holds it, stays through Revert View, and the
    /// person is told.
    @Test func revertKeepsASortAnotherAppChangedAndSaysSo() async throws {
        let (browser, library, undo) = Self.opened()
        await Self.change(browser) { browser.tableOptions[browser.shown, default: .init()].sort = Self.byTitle }
        var changed = try #require(Self.held(library))
        changed.version += 1
        changed.sort = [LibraryViewSort(field: "title", ascending: true), LibraryViewSort(field: "source", ascending: true)]
        library.views = [changed]
        browser.followView(in: library)
        undo.beginUndoGrouping()
        browser.revertView(in: library)
        Self.close(undo)
        #expect(library.notices.waiting.contains { $0.title == "View Partly Reverted" && $0.message.contains("Sort") })
        await browser.choicesChanged()?.value
        #expect(Self.held(library)?.sort == changed.sort)
    }

    /// A name typed while another app renamed the view is not written over that name: it goes to the clipboard.
    @Test(arguments: [true, false]) func aNameTypedWhileAnotherAppRenamedTheViewGoesToTheClipboard(windowSawIt: Bool) async throws {
        let (browser, library, _) = Self.opened()
        browser.openViewPanel(in: library)
        browser.viewPanel?.name = "Typed"
        var renamed = try #require(Self.held(library))
        renamed.title = "Renamed Elsewhere"
        renamed.version += 1
        library.views = [renamed]
        if windowSawIt {
            browser.reconcileViewPanel(in: library)
            browser.followView(in: library)
        }
        browser.dismissViewPanel(in: library)
        #expect(await eventually(within: .seconds(20)) { library.notices.waiting.contains { $0.isNotKept && $0.text == "Typed" } })
        #expect(Self.held(library)?.title == "Renamed Elsewhere")
    }

    @Test func aNameTypedThenClickedAwayFromOfflineGoesToTheClipboard() async {
        let (browser, library, _) = Self.opened(reachesServer: false)
        browser.openViewPanel(in: library)
        browser.viewPanel?.name = "Typed"
        browser.dismissViewPanel(in: library)
        #expect(browser.viewPanel == nil)
        #expect(await eventually(within: .seconds(20)) { library.notices.waiting.contains { $0.isNotKept && $0.text == "Typed" } })
    }

    /// A change made offline outlives the view, the window and a relaunch, and another window sends it once the server is back.
    @Test func anOfflineChangeIsWrittenOnceTheServerIsBackAfterTheWindowClosed() async {
        let (browser, library, _) = Self.opened(reachesServer: false)
        let defaults = browser.defaults
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo"]) }
        browser.showing = .library
        #expect(PendingViewChanges.holds(Self.id, in: defaults))
        // A window opened after a relaunch, on another place, reads the same defaults.
        library.reachesServer = true
        let later = Browser()
        later.defaults = defaults
        later.adopt(library)
        later.showing = .library
        later.reachabilityChanged(in: library)
        #expect(await eventually(within: .seconds(20)) { Self.held(library)?.query.filter?.contains("todo") == true })
        #expect(!PendingViewChanges.holds(Self.id, in: defaults))
    }

    @Test func anOfflineChangeMarfaRefusesLaterGoesToTheClipboard() async {
        let (browser, library, _) = Self.opened(reachesServer: false)
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo"]) }
        browser.showing = .library
        library.reachesServer = true
        library.viewFailure = ViewWriteFailure(kind: .refused, message: "No")
        browser.reachabilityChanged(in: library)
        #expect(await eventually(within: .seconds(20)) { library.notices.waiting.contains { $0.isNotKept && $0.title == "View Not Saved" } })
        #expect(!PendingViewChanges.holds(Self.id, in: browser.defaults))
        #expect(Self.held(library)?.version == 1)
    }

    /// Two windows that change different settings of a view offline both keep theirs, and both land once the server is back.
    @Test func twoWindowsOfflineKeepEachTheirOwnSetting() async throws {
        let (first, library, _) = Self.opened(reachesServer: false)
        let second = Browser()
        second.defaults = first.defaults
        second.adopt(library, undoManager: nil)
        second.showing = .saved(Self.id)
        second.viewMode = .table
        second.followView(in: library)
        await Self.change(first) { first.tableOptions[first.shown, default: .init()].sort = Self.byTitle }
        await Self.change(second) { second.setFilter(Self.status, values: ["todo"]) }
        let pending = try #require(PendingViewChanges.stored(in: first.defaults)[Self.id])
        #expect(pending.change.sort == [LibraryViewSort(field: "title", ascending: true)])
        #expect(pending.change.query?.filter?.contains("todo") == true)

        first.showing = .library
        second.showing = .library
        library.reachesServer = true
        first.reachabilityChanged(in: library)
        #expect(await eventually(within: .seconds(20)) { Self.held(library)?.query.filter?.contains("todo") == true })
        #expect(Self.held(library)?.sort == [LibraryViewSort(field: "title", ascending: true)])
        #expect(!PendingViewChanges.holds(Self.id, in: first.defaults))
    }

    /// A window still showing the view writes its offline change itself; when Marfa refuses it, the change goes to the
    /// clipboard before it is dropped.
    @Test func anOfflineChangeMarfaRefusesFromTheWindowGoesToTheClipboard() async {
        let (browser, library, _) = Self.opened(reachesServer: false)
        await Self.change(browser) { browser.setFilter(Self.status, values: ["todo"]) }
        library.reachesServer = true
        library.viewFailure = ViewWriteFailure(kind: .refused, message: "No")
        browser.reachabilityChanged(in: library)
        #expect(await eventually(within: .seconds(20)) {
            library.notices.waiting.contains { $0.isNotKept && $0.title == "View Not Saved" && $0.text?.contains("todo") == true }
        })
        #expect(!PendingViewChanges.holds(Self.id, in: browser.defaults))
    }

    /// A From changed alone is said in full on the clipboard.
    @Test func aRefusedFromChangedAloneIsGivenBackInWords() async throws {
        let (browser, library, _) = Self.opened(reachesServer: false)
        await Self.change(browser) { browser.tableOptions[browser.shown, default: .init()].scope = .feed }
        #expect(PendingViewChanges.stored(in: browser.defaults)[Self.id]?.change.query?.tier == .feed)
        browser.showing = .library
        library.reachesServer = true
        library.viewFailure = ViewWriteFailure(kind: .refused, message: "No")
        browser.reachabilityChanged(in: library)
        #expect(await eventually(within: .seconds(20)) { library.notices.waiting.contains { $0.isNotKept } })
        let text = try #require(library.notices.waiting.first { $0.isNotKept }?.text)
        #expect(text.contains("View: Open Tasks"))
        #expect(text.contains("From: Feed"))
    }

    /// A grouping chosen in a list writes only the group, so a sort the Mac cannot show stays.
    @Test func aGroupingKeepsASortTheMacCannotShow() async {
        var custom = Self.view()
        custom.sort = [LibraryViewSort(field: "source", ascending: true)]
        custom.group = nil
        let (browser, library, undo) = Self.opened(view: custom)
        undo.beginUndoGrouping()
        browser.viewMode = .list
        Self.close(undo)
        await Self.change(browser) { browser.chooseGrouping(.column(Self.status, by: .value)) }
        #expect(Self.held(library)?.group?.field == "properties.status")
        #expect(Self.held(library)?.sort == custom.sort)
    }

    @Test func createViewKeepsOpenItemsAndQuickActions() async throws {
        let (browser, library, undo) = Self.opened()
        undo.beginUndoGrouping()
        browser.setOpening(.modal)
        browser.setShowsQuickActions(false)
        browser.openNewViewPanel(in: library)
        await browser.finishViewPanel(in: library, order: Self.order)
        let made = try #require(library.views.first { $0.id != Self.id })
        let settings = ViewLayouts.stored(in: browser.defaults).settings(for: made.id)
        #expect(settings?.opening == .modal)
        #expect(settings?.quickActions == false)
    }

    // MARK: This Mac's settings, beside another Mac's

    /// Another Mac's choice reaching this Mac's defaults, as a settings sync puts it there.
    private static func arrive(on browser: Browser, _ change: (inout ViewMacSettings) -> Void) {
        ViewLayouts.update(in: browser.defaults) {
            var settings = $0.settings(for: Self.id) ?? ViewMacSettings()
            change(&settings)
            $0.set(settings, for: Self.id)
        }
    }

    @Test func aChangeOfOneSettingKeepsAnotherMacsNewerChoiceAndUndoPutsBackOnlyItsOwn() {
        let (browser, _, undo) = Self.opened()
        _ = browser.macSettings(for: Self.id)
        Self.arrive(on: browser) { $0.opening = .modal }
        undo.beginUndoGrouping()
        browser.setShowsQuickActions(false)
        Self.close(undo)
        var stored = ViewLayouts.stored(in: browser.defaults).settings(for: Self.id)
        #expect(stored?.quickActions == false)
        #expect(stored?.opening == .modal, "the other Mac's Open Items stays")
        Self.arrive(on: browser) { $0.density = .compact }
        undo.undo()
        stored = ViewLayouts.stored(in: browser.defaults).settings(for: Self.id)
        #expect(stored?.quickActions == nil)
        #expect(stored?.opening == .modal)
        #expect(stored?.density == .compact, "Undo leaves a choice made after its step")
    }

    @Test func undoOfALayoutPutsBackOnlyTheLayout() {
        let (browser, _, undo) = Self.opened()
        undo.beginUndoGrouping()
        browser.viewMode = .gallery
        Self.close(undo)
        Self.arrive(on: browser) { $0.opening = .modal }
        undo.undo()
        let stored = ViewLayouts.stored(in: browser.defaults).settings(for: Self.id)
        #expect(stored?.layout == .table)
        #expect(stored?.opening == .modal)
    }

    @Test func aLayoutChosenForANewViewIsTheDraftsAndCancelWritesNothingToTheView() async throws {
        let (browser, library, undo) = Self.opened()
        let before = ViewLayouts.stored(in: browser.defaults).settings(for: Self.id)
        browser.openNewViewPanel(in: library)
        undo.beginUndoGrouping()
        browser.viewMode = .gallery
        browser.changeDensity(.compact)
        Self.close(undo)
        #expect(ViewLayouts.stored(in: browser.defaults).settings(for: Self.id) == before, "the view's own settings stay")
        #expect(browser.density == .compact, "the window shows the draft's")
        Self.arrive(on: browser) { $0.layout = .board }
        browser.escapeViewPanel(in: library)
        #expect(ViewLayouts.stored(in: browser.defaults).settings(for: Self.id)?.layout == .board, "Cancel leaves another Mac's layout")
        #expect(browser.viewMode == .table)
        // Create View gives the new view the draft's settings, and leaves the view's own.
        Self.arrive(on: browser) { $0.layout = .table }
        browser.openNewViewPanel(in: library)
        browser.viewMode = .gallery
        browser.changeDensity(.compact)
        await browser.finishViewPanel(in: library, order: Self.order)
        let made = try #require(library.views.first { $0.id != Self.id })
        let settings = ViewLayouts.stored(in: browser.defaults).settings(for: made.id)
        #expect(settings?.layout == .gallery)
        #expect(settings?.density == .compact)
        let original = ViewLayouts.stored(in: browser.defaults).settings(for: Self.id)
        #expect(original?.layout == .table)
        #expect(original?.density == nil)
    }
}
