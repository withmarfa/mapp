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
        let undo = UndoManager()
        undo.groupsByEvent = false
        let browser = Browser()
        browser.defaults = ThrowawayDefaults.make("MarfaMac.NewViewTests")
        browser.adopt(library, undoManager: undo)
        browser.showing = place
        browser.viewMode = .table
        return (browser, library)
    }

    /// The settings as the server is sent them, through JSON, and read back as any app reads a view.
    private static func overTheWire(_ view: LibraryView) throws -> LibraryView? {
        let sent = MarfaMapping.viewSettings(LibraryViewSettings(title: view.title, query: view.query, sort: view.sort, group: view.group))
        let read = try JSONDecoder().decode(ViewSettings.self, from: JSONEncoder().encode(sent))
        return MarfaMapping.view(SavedView(id: view.id.rawValue, version: view.version, settings: read))
    }

    private static func make(_ start: NewViewStart, in browser: Browser, _ library: FakeItemLibrary) async throws -> LibraryView {
        browser.openNewViewPanel(in: library)
        try #require(browser.newViewStarts(in: library).contains(start))
        browser.chooseStart(start, in: library)
        return try #require(await browser.finishViewPanel(in: library, order: order))
    }

    // MARK: What Create View writes

    @Test func recentlyAddedIsSortedByCreatedNewestFirstOverTheWire() async throws {
        let (browser, library) = Self.window()
        let made = try await Self.make(.recentlyAdded, in: browser, library)
        let read = try #require(try Self.overTheWire(made))
        #expect(read.query.types == [Self.task])
        #expect(read.sort.first == LibraryViewSort(field: "created_at", ascending: false))
        #expect(read.group == nil)
        #expect(Place.home(of: read.query, catalogue: library.catalogue) == .type(Self.task))
        #expect(browser.shown == PlaceView(.type(Self.task), .saved(made.id)))
    }

    @Test func byStatusGroupsByStatusGroupOnABoardOverTheWire() async throws {
        let (browser, library) = Self.window()
        let made = try await Self.make(.byStatus, in: browser, library)
        let read = try #require(try Self.overTheWire(made))
        #expect(read.group?.field == ViewDraft.statusGroupField)
        #expect(ViewLayouts.stored(in: browser.defaults).settings(for: made.id)?.layout == .board)
    }

    @Test func favoritesIsTheTagConditionTheLibrarysFavoritesUses() async throws {
        let (browser, library) = Self.window()
        let made = try await Self.make(.favorites, in: browser, library)
        let read = try #require(try Self.overTheWire(made))
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
        let read = try #require(try Self.overTheWire(made))
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
        #expect(panel.holdsUnmadeView)
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
        let rename = Task { await browser.renameView(id, to: "Newest", in: library) }
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
        #expect(await browser.renameView(id, to: "Newest", in: library) == false)
        #expect(library.notices.waiting.contains { $0.isNotKept && $0.text == "Newest" })
        #expect(library.views.first?.title == "Open")
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

    @Test func anEarlierCopyLeavesAHiddenViewAloneAndKeepsItThroughItsOwnOrder() {
        var orders = ViewOrders()
        orders.set([.own, .saved(ItemID("a"))], in: .library)
        orders.setHidden(.saved(ItemID("a")), true, in: .library)
        // What an earlier copy reads: the hidden word is one it does not know.
        #expect(orders.order(in: .library) == [.own, .saved(ItemID("a"))])
        #expect(orders.places[Place.library.word]?.contains { ViewChoice(knownWord: $0) == nil } == true)
        orders.set([.saved(ItemID("a")), .own], in: .library)
        #expect(orders.hidden(in: .library) == [.saved(ItemID("a"))])
    }
}
