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

    /// A second view, so that a list of views without the first is a list that was read.
    private static let other = LibraryView(id: ItemID("view-everything"), title: "Everything Else", version: 1, query: LibraryViewQuery(states: [.active]))

    private static func opened(reachesServer: Bool = true) -> (Browser, FakeItemLibrary) {
        let library = FakeItemLibrary()
        library.views = [view(), other]
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

    private static func held(_ library: FakeItemLibrary) -> LibraryView? {
        library.views.first { $0.id == id }
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


    // MARK: What the app does is not the person's change

    @Test func choosingItemsFromAViewIsNoChangeOfTheViews() {
        let (browser, library) = Self.opened()
        browser.set(layout: .list)
        browser.choose(.allNotes, in: library, order: Self.order)
        #expect(browser.viewMode == .gallery)
        #expect(browser.viewWorking[Self.id] == nil)
        browser.sidebarItem = .view(Self.id)
        browser.followView(in: library)
        #expect(!browser.hasViewChanges)
    }

    @Test func aLayoutTheViewHoldsNoneOfIsKeptNilNotPinned() {
        let (browser, library) = Self.opened()
        #expect(browser.viewSeeds[Self.id]?.mac.layout == nil)
        browser.openViewPanel(in: library)
        browser.changeViewSettings(Self.id) { $0.hidesEmptyGroups = true }
        #expect(browser.hasViewChanges)
        #expect(browser.macSettings(for: Self.id).layout == nil)
    }

    @Test func savingAColumnChangeKeepsNoLayoutTheViewNeverHad() async {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        browser.changeViewSettings(Self.id) { $0.columns.setShown(.created, true) }
        await Self.save(browser, library)
        #expect(Self.store(browser)?.layout == nil)
        #expect(Self.store(browser)?.columns.isShown(.created) == true)
    }

    @Test func backInTheLayoutAViewOpenedInIsNoChange() {
        let (browser, library) = Self.opened()
        browser.viewMode = .gallery
        #expect(browser.hasViewChanges)
        browser.viewMode = .table
        #expect(!browser.hasViewChanges)
        browser.viewMode = .board
        browser.revertView(in: library)
        #expect(browser.viewMode == .table)
        #expect(!browser.hasViewChanges)
    }

    // MARK: A name the person typed is not lost

    private static func texts(_ library: FakeItemLibrary) -> [String] {
        library.notices.waiting.compactMap(\.text)
    }

    @Test func aViewChangedElsewhereKeepsTheNameTypedInThePanel() async {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        browser.viewPanel?.shownName = "Mine"
        browser.tableOptions[browser.item]?.grouping = .none
        var renamed = Self.view(version: 2)
        renamed.title = "Theirs"
        library.views = [renamed, Self.other]
        await Self.save(browser, library)
        #expect(browser.viewPanel?.shownName == "Mine")
        #expect(browser.viewPanel?.failure != nil)
        // Saved again, the name is still the person's.
        await Self.save(browser, library)
        #expect(library.views.first { $0.id == Self.id }?.title == "Mine")
    }

    @Test func aViewChangedElsewhereShowsItsNameWhereTheNameWasNotTyped() async {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        browser.tableOptions[browser.item]?.grouping = .none
        var renamed = Self.view(version: 2)
        renamed.title = "Theirs"
        library.views = [renamed, Self.other]
        await Self.save(browser, library)
        #expect(browser.viewPanel?.shownName == "Theirs")
    }

    @Test func aViewTheServerSaysIsGoneHandsOverTheNameTypedAndClosesThePanel() async {
        let (browser, library) = Self.opened()
        ViewLayouts.update(in: browser.defaults) { $0.set(ViewMacSettings(layout: .gallery), for: Self.id) }
        browser.openViewPanel(in: library)
        browser.viewPanel?.shownName = "Mine"
        library.viewFailure = ViewWriteFailure(kind: .gone, message: "Gone")
        await Self.save(browser, library)
        #expect(browser.viewPanel == nil)
        #expect(Self.texts(library) == ["Mine"])
        #expect(Self.store(browser)?.layout == .gallery)
    }

    @Test func aViewGoneWithNoNameTypedIsToldAndClosesThePanel() async {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        browser.tableOptions[browser.item]?.grouping = .none
        library.viewFailure = ViewWriteFailure(kind: .gone, message: "Gone")
        await Self.save(browser, library)
        #expect(browser.viewPanel == nil)
        // The panel's own notice comes with the library's about the refused write; neither is a name given back.
        #expect(library.notices.waiting.map(\.title).contains("View Deleted"))
        #expect(!library.notices.waiting.contains { $0.isNotKept })
    }

    @Test func aViewMissingWhenSaveIsPressedHandsOverTheNameTyped() async {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        browser.viewPanel?.shownName = "Mine"
        library.views = []
        await Self.save(browser, library)
        #expect(browser.viewPanel == nil)
        #expect(Self.texts(library) == ["Mine"])
    }

    @Test func aChangeOfPlaceHandsOverANewViewsTitle() {
        let (browser, library) = Self.opened()
        browser.sidebarItem = .allNotes
        browser.openNewViewPanel(in: library)
        browser.viewPanel?.shownName = "Everything"
        browser.sidebarItem = .view(Self.id)
        #expect(browser.viewPanel == nil)
        #expect(Self.texts(library) == ["Everything"])
    }

    @Test func closingTheSidebarHandsOverANewViewsTitle() {
        let (browser, library) = Self.opened()
        browser.sidebarItem = .allNotes
        browser.openNewViewPanel(in: library)
        browser.viewPanel?.shownName = "Everything"
        browser.closeViewPanel(in: library)
        #expect(browser.viewPanel == nil)
        #expect(Self.texts(library) == ["Everything"])
    }

    @Test func cancellingANewViewDropsItsTitleBecauseThePersonAskedTo() {
        let (browser, library) = Self.opened()
        browser.sidebarItem = .allNotes
        browser.openNewViewPanel(in: library)
        browser.viewPanel?.shownName = "Everything"
        browser.cancelViewPanel(in: library)
        #expect(library.notices.waiting.isEmpty)
    }

    @Test func aChangeOfPlaceHandsOverARenameTyped() {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        browser.viewPanel?.shownName = "Mine"
        browser.sidebarItem = .allNotes
        #expect(Self.texts(library) == ["Mine"])
    }

    @Test func closingTheSidebarHandsOverARenameTyped() {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        browser.viewPanel?.shownName = "Mine"
        browser.closeViewPanel(in: library)
        #expect(Self.texts(library) == ["Mine"])
    }

    @Test func openingNewViewHandsOverARenameTyped() {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        browser.viewPanel?.shownName = "Mine"
        browser.openNewViewPanel(in: library)
        #expect(browser.viewPanel?.isNew == true)
        #expect(Self.texts(library) == ["Mine"])
    }

    @Test func aNameLeftAsItWasHandsOverNothing() {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        browser.closeViewPanel(in: library)
        browser.openViewPanel(in: library)
        browser.sidebarItem = .allNotes
        #expect(library.notices.waiting.isEmpty)
    }

    @Test func quittingHandsOverARenameTyped() {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        browser.viewPanel?.shownName = "Mine"
        ViewPanel.handOffAll()
        #expect(Self.texts(library) == ["Mine"])
        ViewPanel.handOffAll()
        #expect(Self.texts(library) == ["Mine"])
    }

    // MARK: A view that is not in the list

    @Test func aViewAbsentFromAListThatWasReadClosesThePanelAndKeepsWhatTheMacHeld() {
        let (browser, library) = Self.opened()
        ViewLayouts.update(in: browser.defaults) { $0.set(ViewMacSettings(layout: .gallery), for: Self.id) }
        browser.openViewPanel(in: library)
        library.views = [Self.other]
        browser.reconcileViewPanel(in: library)
        #expect(browser.viewPanel == nil)
        #expect(library.notices.waiting.count == 1)
        #expect(Self.store(browser)?.layout == .gallery)
    }

    @Test func anEmptyListProvesNothingAboutAView() {
        let (browser, library) = Self.opened()
        ViewLayouts.update(in: browser.defaults) { $0.set(ViewMacSettings(layout: .gallery), for: Self.id) }
        browser.openViewPanel(in: library)
        library.views = []
        browser.reconcileViewPanel(in: library)
        #expect(browser.viewPanel != nil)
        #expect(library.notices.waiting.isEmpty)
        #expect(Self.store(browser)?.layout == .gallery)
    }

    @Test func aViewDeletedHereWithItsPanelOpenIsNotDeletedElsewhere() async {
        let (browser, library) = Self.opened()
        browser.openViewPanel(in: library)
        browser.viewPanel?.shownName = "Mine"
        library.inViewWrite = { browser.reconcileViewPanel(in: library) }
        await browser.deleteView(Self.id, in: library)
        #expect(browser.viewPanel == nil)
        #expect(library.notices.waiting.isEmpty)
        #expect(Self.store(browser) == nil)
    }

    // MARK: Saving a new view

    @Test func aNewViewMadeAsThePlaceChangedStillKeepsItsMacSettings() async {
        let (browser, library) = Self.opened()
        browser.sidebarItem = .allNotes
        browser.viewMode = .table
        browser.openNewViewPanel(in: library)
        browser.viewPanel?.shownName = "Everything"
        browser.viewMode = .gallery
        library.inViewWrite = { browser.sidebarItem = .favorites }
        await browser.saveViewPanel(
            window: SavedViews.window(browser, in: library, order: Self.order), newView: SavedViews.newViewSettings(browser, in: library),
            confirmed: true, in: library, order: Self.order)
        let made = library.views.first { $0.title == "Everything" }
        #expect(made != nil)
        #expect(made.flatMap { ViewLayouts.stored(in: browser.defaults).settings(for: $0.id) }?.layout == .gallery)
        // The title the server took is nobody's to be given back.
        #expect(library.notices.waiting.isEmpty)
    }

    @Test func cancelWaitsForASaveUnderWay() async {
        let (browser, library) = Self.opened()
        browser.sidebarItem = .allNotes
        browser.viewMode = .table
        browser.openNewViewPanel(in: library)
        browser.viewPanel?.shownName = "Everything"
        browser.viewMode = .gallery
        library.inViewWrite = { browser.cancelViewPanel(in: library) }
        await browser.saveViewPanel(
            window: SavedViews.window(browser, in: library, order: Self.order), newView: SavedViews.newViewSettings(browser, in: library),
            confirmed: true, in: library, order: Self.order)
        let made = library.views.first { $0.title == "Everything" }
        #expect(browser.item == made.map { SidebarItem.view($0.id) })
        #expect(made.flatMap { ViewLayouts.stored(in: browser.defaults).settings(for: $0.id) }?.layout == .gallery)
        #expect(browser.viewPanel == nil)
    }

    // MARK: Offline

    @Test func saveAndRevertStayInThePaletteWithNoServer() {
        let (browser, library) = Self.opened(reachesServer: false)
        browser.viewMode = .gallery
        let titles = SavedViewCommand.commands(for: browser, in: library, order: Self.order).map(\.title)
        #expect(titles.contains(String(localized: "Edit View")))
        #expect(titles.contains(String(localized: "Save View")))
        #expect(titles.contains(String(localized: "Revert View")))
        #expect(!titles.contains(String(localized: "New View")))
        #expect(!titles.contains(String(localized: "Duplicate View")))
        #expect(!titles.contains(String(localized: "Delete View…")))
    }

    @Test func everySavedViewCommandIsOfferedWithAServer() {
        let (browser, library) = Self.opened()
        browser.viewMode = .gallery
        let titles = SavedViewCommand.commands(for: browser, in: library, order: Self.order).map(\.title)
        for title in ["Edit View", "New View", "Save View", "Revert View", "Duplicate View", "Delete View…"] {
            #expect(titles.contains(String(localized: String.LocalizationValue(title))))
        }
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
        #expect(Self.held(library)?.group == nil)
        #expect(Self.held(library)?.version == 2)
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
        #expect(Self.held(library)?.title == "Tasks Still Open")
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
        library.views = [Self.other]
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
        #expect(library.views.count == 2)
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
        #expect(library.views.count == 2)
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
        #expect(library.views.count == 2)
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

    // MARK: Cards

    @Test func aViewWithNoCardChoicesDrawsTheCardsAsTheyWere() {
        let (browser, _) = Self.opened()
        #expect(browser.cards == ViewCards())
        browser.changeCards { $0.size = .medium }
        #expect(!browser.hasViewChanges, "a choice that is the default is no change")
    }

    @Test func aViewsCardsAreHeldCountedAndNotStoredUntilSave() {
        let (browser, _) = Self.opened()
        browser.changeCards { $0.preview = .none; $0.setShown("tags", true) }
        #expect(browser.hasViewChanges)
        #expect(browser.cards.preview == .none)
        #expect(browser.cards.properties == ["tags"])
        #expect(Self.store(browser) == nil)
    }

    @Test func revertAndCancelPutACardsChoicesBack() {
        let (browser, library) = Self.opened()
        browser.changeCards { $0.size = .large }
        browser.revertView(in: library)
        #expect(!browser.hasViewChanges)
        #expect(browser.cards == ViewCards())

        browser.openViewPanel(in: library)
        browser.changeCards { $0.subtext = .none }
        browser.cancelViewPanel(in: library)
        #expect(!browser.hasViewChanges)
        #expect(browser.cards == ViewCards())
    }

    @Test func saveWritesTheCardsToThisMac() async {
        let (browser, library) = Self.opened(reachesServer: false)
        browser.openViewPanel(in: library)
        browser.changeCards { $0.fitsPicture = true; $0.size = .small; $0.setShown("field.status", true) }
        await Self.save(browser, library)
        let stored = Self.store(browser)?.cards
        #expect(stored?.fitsPicture == true)
        #expect(stored?.size == .small)
        #expect(stored?.properties == ["field.status"])
        #expect(!browser.hasViewChanges)
    }

    @Test func aPlacesCardsLastAsLongAsTheWindowAndAreNoChangeToAView() {
        let (browser, library) = Self.opened()
        browser.sidebarItem = .allNotes
        #expect(browser.cards == ViewCards())
        browser.changeCards { $0.preview = .text }
        #expect(browser.cards.preview == .text)
        #expect(!browser.hasViewChanges)
        browser.sidebarItem = .view(Self.id)
        #expect(browser.cards == ViewCards(), "the view has its own")
        browser.sidebarItem = .allNotes
        #expect(browser.cards.preview == .text)
        browser.changeCards { $0.preview = .pictureOrText }
        #expect(browser.placeCards[.allNotes] == nil, "the default is kept as none")
        browser.changeCards { $0.preview = .picture }
        browser.adopt(FakeItemLibrary())
        #expect(browser.cards == ViewCards(), "another library starts again")
    }

    @Test func cancellingANewViewPutsThePlacesCardsBack() {
        let (browser, library) = Self.opened()
        browser.sidebarItem = .allNotes
        browser.changeCards { $0.size = .large }
        browser.openNewViewPanel(in: library)
        browser.changeCards { $0.size = .small }
        browser.cancelViewPanel(in: library)
        #expect(browser.cards.size == .large)
    }

    @Test func aNewViewStartsWithTheCardsOfThePlaceItIsMadeFrom() {
        let (browser, library) = Self.opened()
        browser.sidebarItem = .allNotes
        browser.changeCards { $0.size = .large; $0.setShown("created", true) }
        let settings = SavedViews.newViewSettings(browser, in: library)
        #expect(settings.cards.size == .large)
        #expect(settings.cards.properties == ["created"])
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
