import Foundation
import Testing
@testable import MAPP

/// What the panel that edits a view holds, keeps and gives back: nothing changes on Marfa or on this Mac until Save,
/// and a Save writes Marfa's part before this Mac's.
@MainActor
@Suite(.hangLimit)
struct ViewPanelTests {
    static func defaults() -> UserDefaults {
        let suite = "MAPP.ViewPanelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private static let id = ItemID("view-open-tasks")
    private static let order = NoteOrder()

    private static func view(version: Int64 = 1) -> LibraryView {
        LibraryView(
            id: id, title: "Open Tasks", version: version,
            query: LibraryViewQuery(types: [TypeID("core.task")], states: [.active]),
            sort: [LibraryViewSort(field: "updated_at", ascending: false)], group: LibraryViewGroup(field: "properties.status"))
    }

    private static func opened(reachesServer: Bool = true) -> (Browser, FakeItemLibrary) {
        let library = FakeItemLibrary()
        library.views = [view()]
        library.reachesServer = reachesServer
        let browser = Browser()
        browser.defaults = defaults()
        browser.adopt(library)
        browser.sidebarItem = .view(id)
        browser.viewMode = .table
        browser.followView(in: library)
        return (browser, library)
    }

    private static func window(_ browser: Browser, _ library: FakeItemLibrary) -> ViewDraft.Window {
        SavedViews.window(browser, in: library)
    }

    private static func save(_ browser: Browser, _ library: FakeItemLibrary, confirmed: Bool = true) async {
        await browser.saveViewPanel(
            window: window(browser, library), newView: SavedViews.newViewSettings(browser, in: library), confirmed: confirmed,
            in: library, order: order)
    }

    private static func store(_ browser: Browser) -> ViewMacSettings? {
        ViewLayouts.stored(in: browser.defaults).settings(for: id)
    }

    // MARK: Held until Save

    @Test func aLayoutIsHeldAndCountsAsAChange() {
        let (browser, _) = Self.opened()
        #expect(!browser.hasViewChanges)
        browser.viewMode = .gallery
        #expect(browser.hasViewChanges)
        #expect(Self.store(browser) == nil)
        #expect(browser.macSettings(for: Self.id).layout == .gallery)
    }

    @Test func columnsAreHeldAndRevertPutsThemBack() {
        let (browser, library) = Self.opened()
        browser.changeViewSettings(Self.id) { $0.columns.setShown(.created, true) }
        #expect(browser.hasViewChanges)
        #expect(Self.store(browser) == nil)
        browser.viewMode = .gallery
        browser.revertView(in: library)
        #expect(!browser.hasViewChanges)
        #expect(browser.viewMode == .table)
        #expect(browser.macSettings(for: Self.id).columns == ViewColumns())
    }

    @Test func aLayoutTheAppPutsBackIsNoChangeOfThePersons() {
        let (browser, _) = Self.opened()
        browser.set(layout: .gallery)
        #expect(!browser.hasViewChanges)
    }

    @Test func columnsAreShownInTheOrderHeld() {
        let (browser, _) = Self.opened()
        let columns: [ItemTableColumn] = [.title, .type, .edited, .created]
        browser.changeViewSettings(Self.id) {
            $0.columns.setShown(.created, true)
            $0.columns.move("created", before: "type", in: columns)
        }
        let shown = browser.macSettings(for: Self.id).columns.shownColumns(columns).map(\.id)
        #expect(shown == ["title", "created", "type", "edited"])
    }

    // MARK: Save

    @Test func nothingChangedIsOneDone() {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        #expect(browser.viewPanelState(window: Self.window(browser, library), in: library) == .unchanged)
    }

    @Test func aMacOnlyChangeNeedsNoServer() async {
        let (browser, library) = Self.opened(reachesServer: false)
        browser.openViewPanel(in: library)
        browser.viewMode = .gallery
        browser.changeViewSettings(Self.id) { $0.hidesEmptyGroups = true }
        #expect(browser.viewPanelState(window: Self.window(browser, library), in: library) == .ready)
        await Self.save(browser, library)
        #expect(Self.store(browser)?.layout == .gallery)
        #expect(Self.store(browser)?.hidesEmptyGroups == true)
        #expect(library.views.first?.version == 1)
        #expect(browser.viewPanel == nil)
        #expect(!browser.hasViewChanges)
    }

    @Test func aMarfaOnlyChangeIsSentAndTheMacKeepsNothing() async {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        browser.tableOptions[browser.item]?.grouping = .none
        await Self.save(browser, library)
        #expect(library.views.first?.group == nil)
        #expect(library.views.first?.version == 2)
        #expect(Self.store(browser) == nil)
        #expect(browser.viewPanel == nil)
        #expect(!browser.hasViewChanges)
    }

    @Test func aNameAndAMacChangeAreKeptTogether() async {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        browser.viewPanel?.name = "  Tasks Still Open  "
        browser.viewMode = .gallery
        await Self.save(browser, library)
        #expect(library.views.first?.title == "Tasks Still Open")
        #expect(Self.store(browser)?.layout == .gallery)
    }

    @Test func anEmptyNameDimsSave() {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        browser.viewPanel?.name = "   "
        #expect(browser.viewPanelState(window: Self.window(browser, library), in: library) == .blocked(nil))
    }

    @Test func offlineMarfaChangesDimSaveWithAReasonAndWriteNothing() async {
        let (browser, library) = Self.opened(reachesServer: false)
        browser.openViewPanel(in: library)
        browser.tableOptions[browser.item]?.grouping = .none
        browser.viewMode = .gallery
        guard case .blocked(let reason?) = browser.viewPanelState(window: Self.window(browser, library), in: library) else {
            Issue.record("Save was not dimmed with a reason")
            return
        }
        #expect(!reason.isEmpty)
        await Self.save(browser, library)
        #expect(Self.store(browser) == nil)
        #expect(library.views.first?.version == 1)
        #expect(browser.viewPanel?.failure != nil)
    }

    @Test func aRefusedSaveKeepsThePanelAndTheMacUntouched() async {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        browser.tableOptions[browser.item]?.grouping = .none
        browser.viewMode = .gallery
        library.viewFailure = ViewWriteFailure(kind: .refused, message: "Marfa refused it")
        await Self.save(browser, library)
        #expect(browser.viewPanel?.failure == "Marfa refused it")
        #expect(Self.store(browser) == nil)
        #expect(browser.hasViewChanges)
        #expect(library.views.first?.version == 1)
    }

    @Test func aViewChangedElsewhereGoesBackToTheViewAsItIs() async {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        browser.tableOptions[browser.item]?.grouping = .none
        browser.viewMode = .gallery
        // Another app saves first.
        library.views = [Self.view(version: 2)]
        await Self.save(browser, library)
        #expect(browser.viewPanel?.failure != nil)
        #expect(Self.store(browser) == nil)
        #expect(!browser.hasViewChanges)
        #expect(browser.viewMode == .table)
    }

    @Test func aViewDeletedWhileSavingClosesThePanel() async {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        browser.tableOptions[browser.item]?.grouping = .none
        library.views = []
        await Self.save(browser, library)
        #expect(browser.viewPanel == nil)
    }

    @Test func aSaveThatLeavesSomethingOutAsksFirst() async {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        browser.tableOptions[browser.item]?.grouping = .none
        browser.searchText = "plans"
        await Self.save(browser, library, confirmed: false)
        #expect(browser.viewPanel?.confirmation?.unkept.isEmpty == false)
        #expect(library.views.first?.version == 1)
    }

    // MARK: Cancel and the place

    @Test func cancelPutsTheViewBackAsSaved() {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        browser.tableOptions[browser.item]?.grouping = .none
        browser.viewMode = .gallery
        browser.changeViewSettings(Self.id) { $0.columns.setShown(.created, true) }
        browser.cancelViewPanel(in: library)
        #expect(browser.viewPanel == nil)
        #expect(!browser.hasViewChanges)
        #expect(browser.viewMode == .table)
        #expect(browser.tableOptions[browser.item]?.grouping != ItemTableOptions.Grouping.none)
    }

    @Test func aChangeOfPlaceClosesThePanelAndLeavesTheChangesHeld() {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        browser.changeViewSettings(Self.id) { $0.hidesEmptyGroups = true }
        browser.sidebarItem = .allNotes
        #expect(browser.viewPanel == nil)
        browser.sidebarItem = .view(Self.id)
        #expect(browser.macSettings(for: Self.id).hidesEmptyGroups)
        browser.followView(in: library)
        #expect(browser.hasViewChanges)
        browser.revertView(in: library)
        #expect(!browser.hasViewChanges)
    }

    @Test func aViewDeletedElsewhereClosesThePanelAndSaysSo() {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        library.views = []
        browser.reconcileViewPanel(in: library)
        #expect(browser.viewPanel == nil)
        #expect(library.notices.waiting.isEmpty == false)
    }

    @Test func aViewRenamedElsewhereShowsItsNewNameUnlessTheNameIsBeingTyped() {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        var renamed = Self.view(version: 2)
        renamed.title = "Open"
        library.views = [renamed]
        browser.reconcileViewPanel(in: library)
        #expect(browser.viewPanel?.name == "Open")

        browser.viewPanel?.name = "Mine"
        renamed.title = "Other"
        library.views = [renamed]
        browser.reconcileViewPanel(in: library)
        #expect(browser.viewPanel?.name == "Mine")
    }

    // MARK: New View

    @Test func newViewStartsEmptyAndCancelGoesBackToThePlace() {
        let (browser, library) = Self.opened()
        browser.sidebarItem = .allNotes
        browser.tableOptions[.allNotes, default: .init()].filters = ["type": ["core.task"]]
        browser.viewMode = .table
        browser.openNewViewPanel(in: library)
        #expect(browser.viewPanel?.isNew == true)
        #expect(browser.viewPanel?.shownName == "")
        browser.tableOptions[.allNotes, default: .init()].filters = [:]
        browser.viewMode = .gallery
        browser.cancelViewPanel(in: library)
        #expect(browser.viewPanel == nil)
        #expect(browser.tableOptions[.allNotes]?.filters == ["type": ["core.task"]])
        #expect(browser.viewMode == .table)
        #expect(library.views.count == 1)
    }

    @Test func savingANewViewMakesAndShowsIt() async {
        let (browser, library) = Self.opened()
        browser.sidebarItem = .allNotes
        browser.viewMode = .table
        browser.openNewViewPanel(in: library)
        browser.viewPanel?.shownName = "Everything"
        browser.viewMode = .gallery
        await browser.saveViewPanel(
            window: SavedViews.window(browser, in: library, order: Self.order), newView: SavedViews.newViewSettings(browser, in: library),
            confirmed: true, in: library, order: Self.order)
        let made = library.views.first { $0.title == "Everything" }
        #expect(made != nil)
        #expect(browser.viewPanel == nil)
        #expect(browser.item == made.map { SidebarItem.view($0.id) })
        #expect(made.flatMap { ViewLayouts.stored(in: browser.defaults).settings(for: $0.id) }?.layout == .gallery)
        #expect(browser.viewMode == .gallery)
    }

    @Test func aNewViewTheServerRefusesKeepsItsNameAndThePanel() async {
        let (browser, library) = Self.opened()
        browser.sidebarItem = .allNotes
        browser.openNewViewPanel(in: library)
        browser.viewPanel?.shownName = "Everything"
        library.viewFailure = ViewWriteFailure(kind: .offline, message: "Offline")
        await browser.saveViewPanel(
            window: SavedViews.window(browser, in: library, order: Self.order), newView: SavedViews.newViewSettings(browser, in: library),
            confirmed: true, in: library, order: Self.order)
        #expect(browser.viewPanel?.shownName == "Everything")
        #expect(library.views.count == 1)
    }

    @Test func newViewAndEditViewShareOnePanelAtATime() {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        browser.openNewViewPanel(in: library)
        #expect(browser.viewPanel?.isNew == true)
    }

    // MARK: Duplicate

    @Test func duplicateMakesACopyWithTheSameSettingsAndShowsIt() async {
        let (browser, library) = Self.opened()
        ViewLayouts.update(in: browser.defaults) { $0.set(ViewMacSettings(layout: .gallery, hidesEmptyGroups: true), for: Self.id) }
        let copy = await browser.duplicateView(Self.id, in: library, order: Self.order)
        #expect(copy?.title == "Open Tasks Copy")
        #expect(copy?.query == Self.view().query)
        #expect(copy?.sort == Self.view().sort)
        #expect(copy?.group == Self.view().group)
        #expect(browser.item == copy.map { SidebarItem.view($0.id) })
        let kept = copy.flatMap { ViewLayouts.stored(in: browser.defaults).settings(for: $0.id) }
        #expect(kept?.layout == .gallery)
        #expect(kept?.hidesEmptyGroups == true)
    }

    @Test func duplicateNeedsTheServer() async {
        let (browser, library) = Self.opened(reachesServer: false)
        #expect(await browser.duplicateView(Self.id, in: library, order: Self.order) == nil)
        #expect(library.views.count == 1)
    }

    // MARK: Deleting

    @Test func deletingAViewForgetsWhatTheMacKept() async {
        let (browser, library) = Self.opened()
        ViewLayouts.update(in: browser.defaults) { $0.set(ViewMacSettings(layout: .gallery), for: Self.id) }
        await browser.deleteView(Self.id, in: library)
        #expect(Self.store(browser) == nil)
        #expect(browser.viewSeeds[Self.id] == nil)
    }

    @Test func aFailedDeleteKeepsWhatTheMacKept() async {
        let (browser, library) = Self.opened()
        ViewLayouts.update(in: browser.defaults) { $0.set(ViewMacSettings(layout: .gallery), for: Self.id) }
        library.viewFailure = ViewWriteFailure(kind: .offline, message: "Offline")
        await browser.deleteView(Self.id, in: library)
        #expect(Self.store(browser)?.layout == .gallery)
    }

    // MARK: What the Mac stored

    @Test func storedSettingsThatCannotBeReadOpenTheViewAsItIs() {
        let defaults = Self.defaults()
        defaults.set("not json", forKey: ViewLayouts.key)
        let library = FakeItemLibrary()
        library.views = [Self.view()]
        let browser = Browser()
        browser.defaults = defaults
        browser.adopt(library)
        browser.sidebarItem = .view(Self.id)
        browser.followView(in: library)
        #expect(!browser.hasViewChanges)
        #expect(browser.macSettings(for: Self.id).columns == ViewColumns())
    }

    @Test func aSavedColumnThatNoLongerExistsIsLeftOut() {
        let (browser, _) = Self.opened()
        let columns: [ItemTableColumn] = [.title, .type, .edited]
        browser.changeViewSettings(Self.id) {
            $0.columns.setShown(.created, true)
            $0.columns.move("created", before: nil, in: [.title, .type, .edited, .created])
        }
        #expect(browser.macSettings(for: Self.id).columns.shownColumns(columns).map(\.id) == ["title", "type", "edited"])
    }

    @Test func widthsAreKeptAtOnceAndSurviveASave() async {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        browser.keepWidths(Data([9]), of: Self.id)
        #expect(!browser.hasViewChanges)
        browser.viewMode = .gallery
        await Self.save(browser, library)
        #expect(Self.store(browser)?.widths == Data([9]))
        #expect(Self.store(browser)?.layout == .gallery)
    }

    // MARK: Reordering

    @Test func reorderingPutsAnEntryBeforeAnotherOrLast() {
        #expect(Reordering.moving("c", before: "a", in: ["a", "b", "c"]) == ["c", "a", "b"])
        #expect(Reordering.moving("a", before: nil, in: ["a", "b", "c"]) == ["b", "c", "a"])
        #expect(Reordering.moving("a", before: "a", in: ["a", "b"]) == ["a", "b"])
        #expect(Reordering.moving("z", before: "a", in: ["a", "b"]) == ["a", "b"])
        #expect(Reordering.moving("b", by: -1, in: ["a", "b", "c"]) == ["b", "a", "c"])
        #expect(Reordering.moving("a", by: -1, in: ["a", "b"]) == ["a", "b"])
    }
}
