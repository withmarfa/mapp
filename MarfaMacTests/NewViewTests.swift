import Foundation
import Marfa
import Testing
@testable import MarfaMac

/// Making a view from a starting point, and the row of views: what Create View writes reads the same in any other app,
/// nothing the person chose is lost when Create View can't make the view, and the row keeps its order and hidden views.
@MainActor
@Suite(.serialized, .hangLimit)
struct NewViewTests {
    private static let task = TypeID("core.task")
    private static let order = ItemOrder()

    private static func window(
        _ place: PlaceView = PlaceView(.type(TypeID("core.task"))), views: [LibraryView] = [], reachesServer: Bool = true
    ) -> (Browser, FakeItemLibrary) {
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let tasks = ["todo", "done"].enumerated().map { index, status in
            Item(
                id: ItemID("t\(index)"), type: task, title: "t\(index)", name: "t\(index)", titleRule: .firstLine,
                properties: [Property(key: "status", value: .string(status))], version: ItemVersion(1), created: date, modified: date)
        }
        let library = FakeItemLibrary(items: tasks, now: date)
        library.views = views
        library.reachesServer = reachesServer
        // No undo manager: a step registered outside a group of the test's own leaves the host hanging (`ViewPanelTests`).
        let browser = Browser()
        browser.defaults = ThrowawayDefaults.make("MarfaMac.NewViewTests")
        browser.adopt(library)
        browser.showing = place
        browser.viewMode = .table
        return (browser, library)
    }

    /// The settings as the package is given them, and read back as any app reads a view through the package.
    private static func overTheWire(_ view: LibraryView) -> LibraryView? {
        MarfaMapping.view(SavedView(id: view.id.rawValue, version: view.version, settings: sent(view)))
    }

    private static func sent(_ view: LibraryView) -> ViewSettings {
        MarfaMapping.viewSettings(LibraryViewSettings(title: view.title, query: view.query, sort: view.sort, group: view.group))
    }

    private static func make(_ start: NewViewStart, in browser: Browser, _ library: FakeItemLibrary) async throws -> LibraryView {
        browser.openNewViewPanel(in: library)
        try #require(browser.newViewStarts(in: library).contains(start))
        browser.chooseStart(start, in: library)
        return try #require(await browser.finishViewPanel(in: library, order: order))
    }

    // MARK: This Search

    @Test func thisSearchComesFirstAndSavesOnlyTheTokensMarfaCanSay() async throws {
        let (browser, library) = Self.window()
        let tag = FilterClause(field: FilterTarget.tags.id, op: .includes, values: ["zine"])
        let lately = FilterClause(field: FilterTarget.created.id, op: .inLast, values: ["7"])
        browser.addSearchToken(tag)
        browser.addSearchToken(lately)
        #expect(browser.searchTokenFilters(in: library) == [tag])
        browser.openNewViewPanel(in: library)
        #expect(browser.newViewStarts(in: library).first == .search)
        #expect(browser.viewPanel?.start == .search)
        #expect(browser.tableOptions[browser.shown]?.filter.clauses == [tag])
        let draft = try #require(ViewDraft.draft(SavedViews.window(browser, in: library, order: Self.order), catalogue: library.catalogue, views: []))
        #expect(draft.unkept.contains { if case .searchToken = $0 { true } else { false } })
        let made = try #require(await browser.finishViewPanel(in: library, order: Self.order))
        let terms = try ViewDraft.terms(of: made.query.filter).terms
        #expect(terms.contains { $0.field == .tags && $0.operator == .contains && $0.value == .text("zine") })
        #expect(terms.count == 1)
    }

    @Test func withoutTokensThereIsNoThisSearch() {
        let (browser, library) = Self.window()
        browser.openNewViewPanel(in: library)
        #expect(!browser.newViewStarts(in: library).contains(.search))
    }

    // MARK: What Create View writes

    @Test func recentlyAddedIsSortedByCreatedNewestFirstOverTheWire() async throws {
        let (browser, library) = Self.window()
        let made = try await Self.make(.recentlyAdded, in: browser, library)
        let read = try #require(Self.overTheWire(made))
        let sent = Self.sent(made)
        #expect(sent.query.types == [Self.task.rawValue])
        #expect(sent.sort.first?.by == "created_at")
        #expect(sent.sort.first?.direction == .descending)
        #expect(read.query.types == [Self.task])
        #expect(read.sort.first == LibraryViewSort(field: "created_at", ascending: false))
        #expect(read.group == nil)
        #expect(Place.home(of: read.query, catalogue: library.catalogue) == .type(Self.task))
        #expect(browser.shown == PlaceView(.type(Self.task), .saved(made.id)))
    }

    @Test func byStatusGroupsByStatusGroupOnABoardOverTheWire() async throws {
        let (browser, library) = Self.window()
        let status = ItemTypeInfo.Field(key: "status", label: "Status", kind: .status([
            StatusWord(value: "todo", group: .notStarted), StatusWord(value: "done", group: .completed),
        ]), declaredBy: Self.task)
        library.catalogue = MarfaMac.Catalogue(itemTypes: [
            ItemTypeInfo(id: Self.task, label: "Task", fields: [status], titleField: "title", bodyField: "body", parent: nil),
        ])
        let made = try await Self.make(.byStatus, in: browser, library)
        let read = try #require(Self.overTheWire(made))
        #expect(Self.sent(made).group?.by == ViewDraft.statusGroupField)
        #expect(read.group?.field == ViewDraft.statusGroupField)
        #expect(ViewLayouts.stored(in: browser.defaults).settings(for: made.id)?.layout == .board)
    }

    @Test func favoritesIsTheTagConditionTheLibrarysFavoritesUses() async throws {
        let (browser, library) = Self.window()
        let made = try await Self.make(.favorites, in: browser, library)
        let read = try #require(Self.overTheWire(made))
        let terms = try ViewDraft.terms(of: read.query.filter).terms
        #expect(terms.contains { $0.field == .tags && $0.operator == .contains && $0.value == .text(ItemTag.favorite) })
        #expect(Place.home(of: read.query, catalogue: library.catalogue) == .type(Self.task))
    }

    @Test func anInboxOfSeveralSourcesStaysInTheFeedWithQuickActions() async throws {
        let (browser, library) = Self.window(.feed)
        browser.openNewViewPanel(in: library)
        browser.chooseStart(.inbox, in: library)
        var options = browser.tableOptions[browser.shown] ?? ItemTableOptions()
        options.filter.clauses.append(FilterClause(field: FilterTarget.source.id, op: .is, values: ["mail", "web"]))
        browser.tableOptions[browser.shown] = options
        let made = try #require(await browser.finishViewPanel(in: library, order: Self.order))
        let read = try #require(Self.overTheWire(made))
        #expect(Self.sent(made).query.tier == .feed)
        #expect(read.query.tier == .feed)
        #expect(Place.home(of: read.query, catalogue: library.catalogue) == .feed)
        #expect(ViewLayouts.stored(in: browser.defaults).settings(for: made.id)?.quickActions == true)
    }

    @Test func aStartingPointThePersonHasOpensTheirs() throws {
        let theirs = LibraryView(
            id: ItemID("v-board"), title: "Board", version: 1, query: LibraryViewQuery(types: [Self.task]),
            sort: [], group: LibraryViewGroup(field: ViewDraft.statusGroupField))
        let (browser, library) = Self.window(views: [theirs])
        browser.openNewViewPanel(in: library)
        let place = try #require(browser.existingView(for: .byStatus, in: library))
        browser.openExistingView(place, in: library, order: Self.order)
        #expect(browser.viewPanel == nil)
        #expect(browser.shown.savedView == theirs.id)
        #expect(library.views.count == 1)
    }

    // MARK: Nothing typed is lost

    @Test func offlineTheNewViewWaitsInThePanelWithItsNameAndChoices() async throws {
        let (browser, library) = Self.window(reachesServer: false)
        browser.openNewViewPanel(in: library)
        browser.chooseStart(.recentlyAdded, in: library)
        browser.viewPanel?.shownName = "Mine"
        let made = await browser.finishViewPanel(in: library, order: Self.order)
        #expect(made == nil)
        let panel = try #require(browser.viewPanel)
        #expect(panel.problem == .offline)
        #expect(browser.keepsNewViewOpen)
        #expect(panel.shownName == "Mine")
        #expect(browser.tableOptions[browser.shown]?.sort?.first?.column.id == ItemTableColumn.created.id)
        #expect(library.views.isEmpty)
        #expect(!library.notices.waiting.contains { $0.isNotKept })
        // Never queued: once the server is back, Create View makes it.
        library.reachesServer = true
        browser.reachabilityChanged(in: library)
        #expect(library.views.isEmpty)
        let later = try #require(await browser.finishViewPanel(in: library, order: Self.order))
        #expect(later.title == "Mine")
    }

    @Test func aNameAnotherViewHasKeepsThePanel() async throws {
        let other = LibraryView(id: ItemID("v-1"), title: "Open Tasks", version: 1, query: LibraryViewQuery(types: [Self.task]), sort: [], group: nil)
        let (browser, library) = Self.window(views: [other])
        browser.openNewViewPanel(in: library)
        browser.viewPanel?.shownName = "open tasks "
        let made = await browser.finishViewPanel(in: library, order: Self.order)
        #expect(made == nil)
        #expect(browser.viewPanel?.problem == .clash("open tasks"))
        #expect(browser.viewPanel?.shownName == "open tasks ")
        #expect(library.views.count == 1)
    }

    @Test func aRefusedViewKeepsThePanelForAnotherTry() async throws {
        let (browser, library) = Self.window()
        library.viewFailure = ViewWriteFailure(kind: .refused, message: "filter")
        browser.openNewViewPanel(in: library)
        browser.chooseStart(.favorites, in: library)
        browser.viewPanel?.shownName = "Starred"
        #expect(await browser.finishViewPanel(in: library, order: Self.order) == nil)
        #expect(browser.viewPanel?.problem == .refused)
        #expect(browser.viewPanel?.shownName == "Starred")
        #expect(browser.tableOptions[browser.shown]?.filter.clauses.count == 1)
        #expect(!library.notices.waiting.contains { $0.isNotKept })
        library.viewFailure = nil
        #expect(await browser.finishViewPanel(in: library, order: Self.order)?.title == "Starred")
    }

    @Test func theSuggestedNameFollowsTheStartUntilThePersonTypes() {
        let (browser, library) = Self.window()
        browser.openNewViewPanel(in: library)
        let blank = browser.viewPanel?.shownName
        browser.chooseStart(.recentlyAdded, in: library)
        #expect(browser.viewPanel?.shownName != blank)
        browser.viewPanel?.shownName = "Mine"
        browser.chooseStart(.favorites, in: library)
        #expect(browser.viewPanel?.shownName == "Mine")
    }

    // MARK: A pill's menu

    @Test func aRenameWhileAWriteIsUnderWayLandsAfterItAndKeepsBoth() async throws {
        let id = ItemID("v-open")
        let view = LibraryView(id: id, title: "Open", version: 1, query: LibraryViewQuery(types: [Self.task]), sort: [], group: nil)
        let (browser, library) = Self.window(PlaceView(.type(Self.task), .saved(id)), views: [view])
        browser.followView(in: library)
        browser.choicesChanged()
        var release: CheckedContinuation<Void, Never>?
        var held = false
        library.inViewChange = {
            guard !held else { return }
            held = true
            await withCheckedContinuation { release = $0 }
        }
        browser.chooseSort([ItemTableComparator(column: .created, order: .reverse)])
        let write = browser.choicesChanged()
        #expect(await eventually(within: .seconds(20)) { release != nil })
        let rename = Task { await browser.renameView(id, to: "Newest", from: "Open", in: library) }
        release?.resume()
        await write?.value
        #expect(await rename.value)
        let held2 = try #require(library.views.first)
        #expect(held2.title == "Newest")
        #expect(held2.sort.first == LibraryViewSort(field: "created_at", ascending: false))
    }

    @Test func anOfflineRenameGivesTheNameBack() async {
        let id = ItemID("v-open")
        let view = LibraryView(id: id, title: "Open", version: 1, query: LibraryViewQuery(types: [Self.task]), sort: [], group: nil)
        let (browser, library) = Self.window(views: [view], reachesServer: false)
        #expect(await browser.renameView(id, to: "Newest", from: "Open", in: library) == false)
        #expect(library.notices.waiting.contains { $0.isNotKept && $0.text == "Newest" })
        #expect(library.views.first?.title == "Open")
    }

    @Test func aRenameOfAViewRenamedSinceRenameBeganGivesTheNameBack() async {
        let id = ItemID("v-open")
        let view = LibraryView(id: id, title: "Theirs", version: 2, query: LibraryViewQuery(types: [Self.task]), sort: [], group: nil)
        let (browser, library) = Self.window(views: [view])
        #expect(await browser.renameView(id, to: "Newest", from: "Open", in: library) == false)
        #expect(library.notices.waiting.contains { $0.isNotKept && $0.text == "Newest" })
        #expect(library.views.first?.title == "Theirs")
    }

    @Test func aRenameThatMeetsAnotherAppsRenameGivesTheNameBack() async {
        let id = ItemID("v-open")
        let view = LibraryView(id: id, title: "Open", version: 1, query: LibraryViewQuery(types: [Self.task]), sort: [], group: nil)
        let (browser, library) = Self.window(PlaceView(.type(Self.task), .saved(id)), views: [view])
        browser.followView(in: library)
        library.changedElsewhere = { $0.title = "Theirs" }
        #expect(await browser.renameView(id, to: "Newest", from: "Open", in: library) == false)
        #expect(library.notices.waiting.contains { $0.isNotKept && $0.text == "Newest" })
        #expect(library.views.first?.title == "Theirs")
    }

    @Test func deleteViewFromAnyMenuClosesThePanelAndAsks() {
        let id = ItemID("v-open")
        let view = LibraryView(id: id, title: "Open", version: 1, query: LibraryViewQuery(types: [Self.task]), sort: [], group: nil)
        let (browser, library) = Self.window(PlaceView(.type(Self.task), .saved(id)), views: [view])
        browser.followView(in: library)
        browser.openViewPanel(in: library)
        #expect(browser.viewPanel != nil)
        browser.askToDeleteView(id, in: library)
        #expect(browser.viewPanel == nil)
        #expect(browser.deletingView == id)
        #expect(library.views.count == 1)
    }

    @Test func theViewMenuAndThePaletteDuplicateAndDeleteTheShownView() {
        let id = ItemID("v-open")
        let view = LibraryView(id: id, title: "Open", version: 1, query: LibraryViewQuery(types: [Self.task]), sort: [], group: nil)
        let (browser, library) = Self.window(PlaceView(.type(Self.task), .saved(id)), views: [view])
        browser.followView(in: library)
        let icons = SavedViewCommand.commands(for: browser, in: library, order: Self.order).map(\.systemImage)
        #expect(icons.contains("plus.square.on.square"))
        #expect(icons.contains("trash"))
        library.reachesServer = false
        let offline = SavedViewCommand.commands(for: browser, in: library, order: Self.order).map(\.systemImage)
        #expect(!offline.contains("plus.square.on.square"))
        #expect(!offline.contains("trash"))
    }

    @Test func aViewDeletedElsewhereWhileShownFallsToTheFirstView() {
        let keep = LibraryView(id: ItemID("v-a"), title: "A", version: 1, query: LibraryViewQuery(types: [Self.task]), sort: [], group: nil)
        let gone = LibraryView(id: ItemID("v-b"), title: "B", version: 1, query: LibraryViewQuery(types: [Self.task]), sort: [], group: nil)
        let (browser, library) = Self.window(PlaceView(.type(Self.task), .saved(gone.id)), views: [keep, gone])
        browser.followView(in: library)
        library.views = [keep]
        browser.followView(in: library)
        #expect(browser.shown == PlaceView(.type(Self.task)))
    }

    @Test func hidingTheShownViewFallsToTheFirstAndKeepsTheView() {
        let view = LibraryView(id: ItemID("v-a"), title: "A", version: 1, query: LibraryViewQuery(types: [Self.task]), sort: [], group: nil)
        let (browser, library) = Self.window(PlaceView(.type(Self.task), .saved(view.id)), views: [view])
        browser.setHidden(.saved(view.id), true, in: .type(Self.task), library: library, order: Self.order)
        #expect(browser.shown == PlaceView(.type(Self.task)))
        #expect(browser.hiddenViews(in: .type(Self.task)) == [.saved(view.id)])
        #expect(library.views.count == 1)
        browser.setHidden(.saved(view.id), false, in: .type(Self.task), library: library, order: Self.order)
        #expect(browser.hiddenViews(in: .type(Self.task)).isEmpty)
    }

    // MARK: The row's order

    @Test func aDraggedOrderPutsAViewMadeElsewhereLastAndADeletedOneLeavesNoGap() {
        let views = ["A", "B", "C"].map {
            LibraryView(id: ItemID("v-\($0)"), title: $0, version: 1, query: LibraryViewQuery(types: [Self.task]), sort: [], group: nil)
        }
        let place = Place.type(Self.task)
        let (browser, library) = Self.window(views: views)
        browser.moveView(.saved(views[2].id), onto: .own, in: place, library: library)
        #expect(browser.viewChoices(in: place, library: library) == [.saved(views[2].id), .own, .saved(views[0].id), .saved(views[1].id)])
        // "0" sorts before every other title, so it would lead the row if a placed order did not hold.
        let added = LibraryView(id: ItemID("v-0"), title: "0", version: 1, query: LibraryViewQuery(types: [Self.task]), sort: [], group: nil)
        library.views = views + [added]
        #expect(browser.viewChoices(in: place, library: library).last == .saved(added.id))
        library.views = [views[0], views[2], added]
        #expect(browser.viewChoices(in: place, library: library) == [.saved(views[2].id), .own, .saved(views[0].id), .saved(added.id)])
    }

    @Test func hiddenViewsAreASettingOfTheirOwnThatAReorderLeavesAlone() {
        let defaults = ThrowawayDefaults.make("MarfaMac.NewViewTests.hidden")
        ViewOrders.update(in: defaults) { $0.setHidden(.saved(ItemID("a")), true, in: .library) }
        #expect(defaults.data(forKey: ViewOrders.key) == nil)
        ViewOrders.update(in: defaults) { $0.set([.saved(ItemID("a")), .own], in: .library) }
        let stored = ViewOrders.stored(in: defaults)
        #expect(stored.hidden(in: .library) == [.saved(ItemID("a"))])
        #expect(stored.order(in: .library) == [.saved(ItemID("a")), .own])
    }

    @Test func aReorderKeepsAViewThisMacHasNotReadAtItsPlace() {
        let views = ["A", "B"].map {
            LibraryView(id: ItemID("v-\($0)"), title: $0, version: 1, query: LibraryViewQuery(types: [Self.task]), sort: [], group: nil)
        }
        let place = Place.type(Self.task)
        let (browser, library) = Self.window(views: views)
        let unread = ViewChoice.saved(ItemID("v-elsewhere"))
        ViewOrders.update(in: browser.defaults) { $0.set([.own, unread, .saved(views[0].id), .saved(views[1].id)], in: place) }
        browser.moveView(.saved(views[1].id), onto: .own, in: place, library: library)
        #expect(ViewOrders.stored(in: browser.defaults).order(in: place) == [.saved(views[1].id), unread, .own, .saved(views[0].id)])
    }

    // MARK: Round 1

    @Test func aTileForAViewThePersonHasAsksOnlyOnceTheDraftIsTheirs() throws {
        let theirs = LibraryView(
            id: ItemID("v-board"), title: "Board", version: 1, query: LibraryViewQuery(types: [Self.task]),
            sort: [], group: LibraryViewGroup(field: ViewDraft.statusGroupField))
        let status = ItemTypeInfo.Field(key: "status", label: "Status", kind: .status([
            StatusWord(value: "todo", group: .notStarted), StatusWord(value: "done", group: .completed),
        ]), declaredBy: Self.task)
        let (browser, library) = Self.window(views: [theirs])
        library.catalogue = MarfaMac.Catalogue(itemTypes: [
            ItemTypeInfo(id: Self.task, label: "Task", fields: [status], titleField: "title", bodyField: "body", parent: nil),
        ])
        browser.openNewViewPanel(in: library)
        browser.viewPanel?.shownName = "Mine"
        #expect(browser.keepsNewViewOpen)
        #expect(browser.pickStart(.byStatus, in: library, order: Self.order)?.view == .saved(theirs.id))
        #expect(browser.viewPanel?.shownName == "Mine")
        // A value changed is the person's too.
        browser.viewPanel?.shownName = ""
        browser.chooseStart(.recentlyAdded, in: library)
        #expect(!browser.keepsNewViewOpen)
        browser.setSort([ItemTableComparator(column: .title, order: .forward)])
        #expect(browser.pickStart(.byStatus, in: library, order: Self.order) != nil)
        #expect(browser.viewPanel != nil)
        // Untouched, the tile opens theirs at once.
        browser.chooseStart(.recentlyAdded, in: library)
        #expect(browser.pickStart(.byStatus, in: library, order: Self.order) == nil)
        #expect(browser.viewPanel == nil)
        #expect(browser.shown.savedView == theirs.id)
    }

    @Test func aTouchedDraftEndedByAPlaceChangeIsGivenBackInWords() throws {
        let (browser, library) = Self.window()
        browser.openNewViewPanel(in: library)
        browser.chooseStart(.recentlyAdded, in: library)
        browser.viewPanel?.shownName = "Newest Tasks"
        browser.show(.feed, in: library, order: Self.order)
        let notice = try #require(library.notices.waiting.first { $0.isNotKept })
        let text = try #require(notice.text)
        #expect(text.hasPrefix("Newest Tasks\n"))
        #expect(text.contains("sorted by"))
        #expect(text.contains(", newest first"))
        #expect(text.contains(ItemViewMode.list.title))
        #expect(text.contains("Add to Sidebar: "))
        // A task's place lists All Items, the Feed's tier among them, so Quick Actions is said too.
        #expect(text.contains("Quick Actions: "))
    }

    @Test func anUntouchedDraftEndsWithNothingGivenBack() {
        let (browser, library) = Self.window()
        browser.openNewViewPanel(in: library)
        browser.chooseStart(.recentlyAdded, in: library)
        #expect(!browser.keepsNewViewOpen)
        browser.show(.feed, in: library, order: Self.order)
        #expect(!library.notices.waiting.contains { $0.isNotKept })
    }

    @Test func aRefusedDraftIsStillGivenBackWhenTheWindowCloses() async throws {
        let (browser, library) = Self.window()
        library.viewFailure = ViewWriteFailure(kind: .refused, message: "filter")
        browser.openNewViewPanel(in: library)
        browser.chooseStart(.favorites, in: library)
        #expect(await browser.finishViewPanel(in: library, order: Self.order) == nil)
        #expect(browser.keepsNewViewOpen)
        browser.viewPanel?.handOff(because: .closed)
        let text = try #require(library.notices.waiting.first { $0.isNotKept }?.text)
        #expect(text.hasPrefix("Favorites\n"))
    }

    @Test func thisSearchSavesAFromTokenAsTheViewsTier() async throws {
        let (browser, library) = Self.window()
        let feed = FilterClause(field: FilterTarget.tier.id, op: .is, values: [Tier.feed.word])
        browser.addSearchToken(feed)
        browser.openNewViewPanel(in: library)
        #expect(browser.viewPanel?.start == .search)
        #expect(browser.listing.scope == .feed)
        let draft = try #require(ViewDraft.draft(SavedViews.window(browser, in: library, order: Self.order), catalogue: library.catalogue, views: []))
        #expect(draft.unkept.isEmpty)
        let made = try #require(await browser.finishViewPanel(in: library, order: Self.order))
        #expect(made.query.tier == .feed)
        #expect(made.query.filter == nil)
        #expect(Self.overTheWire(made)?.query.tier == .feed)
    }

    @Test func aFromTokenTheViewCannotSayIsNamed() throws {
        let (browser, library) = Self.window(.library)
        let feed = FilterClause(field: FilterTarget.tier.id, op: .is, values: [Tier.feed.word])
        let tag = FilterClause(field: FilterTarget.tags.id, op: .includes, values: ["zine"])
        browser.addSearchToken(feed)
        browser.addSearchToken(tag)
        browser.openNewViewPanel(in: library)
        #expect(browser.tableOptions[browser.shown]?.filter.clauses == [tag])
        let draft = try #require(ViewDraft.draft(SavedViews.window(browser, in: library, order: Self.order), catalogue: library.catalogue, views: []))
        let named = draft.unkept.compactMap { if case .searchToken(let words) = $0 { words } else { nil } }
        #expect(named.count == 1)
        #expect(named.first?.contains(Tier.feed.title) == true)
    }

    @Test func anotherStartingPointShowsItsOwnListAndTheSearchComesBack() async throws {
        let (browser, library) = Self.window()
        let tag = FilterClause(field: FilterTarget.tags.id, op: .includes, values: ["zine"])
        browser.addSearchToken(tag)
        browser.searchText = "zine"
        browser.openNewViewPanel(in: library)
        browser.chooseStart(.recentlyAdded, in: library)
        #expect(browser.searchTokens.isEmpty)
        #expect(!browser.isSearching)
        #expect(browser.newViewStarts(in: library).first == .search)
        browser.chooseStart(.search, in: library)
        #expect(browser.searchTokens == [tag])
        browser.chooseStart(.recentlyAdded, in: library)
        browser.escapeViewPanel(in: library)
        #expect(browser.searchTokens == [tag])
        #expect(browser.searchText == "zine")
        // Made, it is written with the starting point's own order.
        browser.openNewViewPanel(in: library)
        browser.chooseStart(.recentlyAdded, in: library)
        let made = try #require(await browser.finishViewPanel(in: library, order: Self.order))
        #expect(made.sort == [LibraryViewSort(field: "created_at", ascending: false)])
    }

    @Test func untickingTheLastInboxSourceLeavesNoneAndMakesNothing() async {
        let (browser, library) = Self.window(.feed)
        library.sources.counts = ["mail": 2]
        var mail = Item(
            id: ItemID("m0"), type: Self.task, title: "m0", name: "m0", titleRule: .firstLine, properties: [], version: ItemVersion(1),
            created: library.now(), modified: library.now())
        mail.tier = .feed
        mail.source = "mail"
        library.items.append(mail)
        browser.openNewViewPanel(in: library)
        browser.chooseStart(.inbox, in: library)
        #expect(browser.ticksSource("mail"))
        #expect(!browser.items(in: library).isEmpty)
        browser.setSource("mail", chosen: false, in: library)
        #expect(!browser.ticksSource("mail"))
        #expect(browser.viewPanel?.choosesNoSource == true)
        // No source chosen previews nothing, never every source.
        #expect(browser.items(in: library).isEmpty)
        #expect(browser.tableContent(in: library).kept.isEmpty)
        #expect(!browser.listsAnything(in: library))
        #expect(await browser.finishViewPanel(in: library, order: Self.order) == nil)
        #expect(library.views.isEmpty)
        browser.setSource("mail", chosen: true, in: library)
        #expect(browser.ticksSource("mail"))
        #expect(browser.viewPanel?.choosesNoSource == false)
        #expect(!browser.items(in: library).isEmpty)
    }

    @Test func aDraftRefusedAfterThePanelClosedIsGivenBack() async throws {
        let (browser, library) = Self.window()
        browser.openNewViewPanel(in: library)
        browser.chooseStart(.favorites, in: library)
        var release: CheckedContinuation<Void, Never>?
        library.inViewWrite = { await withCheckedContinuation { release = $0 } }
        library.viewFailure = ViewWriteFailure(kind: .refused, message: "filter")
        let create = Task { await browser.finishViewPanel(in: library, order: Self.order) }
        #expect(await eventually(within: .seconds(20)) { release != nil })
        // Submitted and not yet taken, the draft is the person's even with nothing changed.
        #expect(browser.keepsNewViewOpen)
        browser.closeViewPanel(in: library)
        #expect(!library.notices.waiting.contains { $0.isNotKept })
        release?.resume()
        #expect(await create.value == nil)
        let text = try #require(library.notices.waiting.first { $0.isNotKept }?.text)
        #expect(text.hasPrefix("Favorites\n"))
    }

    @Test func aDraftTakenAfterThePanelClosedGivesNothingBack() async throws {
        let (browser, library) = Self.window()
        browser.openNewViewPanel(in: library)
        browser.chooseStart(.favorites, in: library)
        var release: CheckedContinuation<Void, Never>?
        library.inViewWrite = { await withCheckedContinuation { release = $0 } }
        let create = Task { await browser.finishViewPanel(in: library, order: Self.order) }
        #expect(await eventually(within: .seconds(20)) { release != nil })
        browser.closeViewPanel(in: library)
        release?.resume()
        #expect(await create.value != nil)
        #expect(!library.notices.waiting.contains { $0.isNotKept })
    }

    @Test func aFromTokenTheChangedFromNoLongerSaysStopsNarrowingAndIsNamed() throws {
        let (browser, library) = Self.window()
        let feed = FilterClause(field: FilterTarget.tier.id, op: .is, values: [Tier.feed.word])
        browser.addSearchToken(feed)
        browser.openNewViewPanel(in: library)
        #expect(browser.listing.scope == .feed)
        #expect(browser.tableContent(in: library).kept.isEmpty)
        browser.tableOptions[browser.shown]?.scope = .all
        #expect(browser.fromTokensSetAside == [feed])
        #expect(browser.tableContent(in: library).kept.count == 2)
        let draft = try #require(ViewDraft.draft(SavedViews.window(browser, in: library, order: Self.order), catalogue: library.catalogue, views: []))
        let named = draft.unkept.compactMap { if case .searchToken(let words) = $0 { words } else { nil } }
        #expect(named.count == 1)
        // Back on the From the token names, it narrows and is saved again.
        browser.tableOptions[browser.shown]?.scope = .feed
        #expect(browser.fromTokensSetAside.isEmpty)
        let again = try #require(ViewDraft.draft(SavedViews.window(browser, in: library, order: Self.order), catalogue: library.catalogue, views: []))
        #expect(again.unkept.isEmpty)
    }

    @Test func aLayoutChosenAfterAStartingPointKeepsTheDraftsOwnSort() async throws {
        let (browser, library) = Self.window()
        browser.openNewViewPanel(in: library)
        browser.chooseStart(.recentlyAdded, in: library)
        let started = [LibraryViewSort(field: "created_at", ascending: false)]
        // A layout whose own order is not the starting point's.
        var draft: ViewDraft.Draft?
        for layout in browser.availableViewModes(in: library) where layout != .list {
            browser.viewMode = layout
            let window = SavedViews.window(browser, in: library, order: Self.order)
            if let found = ViewDraft.draft(window, catalogue: library.catalogue, views: []), found.sort != started {
                draft = found
                break
            }
        }
        let own = try #require(draft)
        let made = try #require(await browser.finishViewPanel(in: library, order: Self.order))
        #expect(made.sort == own.sort)
    }

    @Test func aSortChosenAfterAStartingPointIsTheOneWritten() async throws {
        let (browser, library) = Self.window()
        browser.openNewViewPanel(in: library)
        browser.chooseStart(.recentlyAdded, in: library)
        browser.tableOptions[browser.shown]?.sort = [ItemTableComparator(column: .title)]
        let made = try #require(await browser.finishViewPanel(in: library, order: Self.order))
        #expect(made.sort != [LibraryViewSort(field: "created_at", ascending: false)])
    }

    @Test func aPillRenameOfAViewDeletedElsewhereGivesTheNameBack() async {
        let id = ItemID("v-open")
        let (browser, library) = Self.window(views: [])
        #expect(await browser.renameView(id, to: "Newest", from: "Open", in: library) == false)
        let notice = library.notices.waiting.first { $0.isNotKept && $0.text == "Newest" }
        #expect(notice?.message.contains(Browser.deletedElsewhere) == true)
    }

    @Test func aPillRenameTheServerFindsGoneGivesTheNameBack() async {
        let id = ItemID("v-open")
        let view = LibraryView(id: id, title: "Open", version: 1, query: LibraryViewQuery(types: [Self.task]), sort: [], group: nil)
        let (browser, library) = Self.window(views: [view])
        library.viewFailure = ViewWriteFailure(kind: .gone, message: "Gone")
        #expect(await browser.renameView(id, to: "Newest", from: "Open", in: library) == false)
        let notice = library.notices.waiting.first { $0.isNotKept && $0.text == "Newest" }
        #expect(notice?.message.contains(Browser.deletedElsewhere) == true)
    }

    @Test func deleteAndDuplicateOfAViewGoneTellThePerson() async {
        let (browser, library) = Self.window(views: [])
        browser.askToDeleteView(ItemID("v-gone"), in: library)
        #expect(browser.deletingView == nil)
        #expect(await browser.duplicateView(ItemID("v-gone"), in: library, order: Self.order) == nil)
        #expect(library.notices.waiting.filter { $0.message == Browser.deletedElsewhere }.count == 2)
        #expect(library.views.isEmpty)
    }

    @Test func aHiddenLibraryViewShowsItsPillWhileChosen() {
        let view = LibraryView(id: ItemID("v-a"), title: "A", version: 1, query: LibraryViewQuery(), sort: [], group: nil)
        let (browser, library) = Self.window(.library, views: [view])
        ViewOrders.update(in: browser.defaults) { $0.setHidden(.saved(view.id), true, in: .library) }
        browser.showing = PlaceView(.library, .saved(view.id))
        let row = TopRowContent.make(browser: browser, library: library)
        #expect(row.views.contains { $0.id == ViewChoice.saved(view.id).word && $0.isHidden })
        #expect(row.chosen == ViewChoice.saved(view.id).word)
    }
}
