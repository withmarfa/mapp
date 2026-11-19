import Foundation
import SwiftUI
import Testing
@testable import MAPP

/// A place that is not a saved view opens as the person left it, on this Mac: its filters, sort, grouping, layout and
/// the Mac's settings for each layout. Reset View puts it back, and Save as View… offers what it holds.
@MainActor
@Suite(.serialized, .hangLimit)
struct PlaceDefaultsTests {
    private static let tasks = SidebarItem.itemType("core.task")
    private static let status = "field.status"

    private static func library() -> FakeItemLibrary {
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let items = ["todo", "done"].enumerated().map { index, status in
            Item(
                id: ItemID("t\(index)"), type: TypeID("core.task"), title: "t\(index)", name: "t\(index)", titleRule: .firstLine,
                properties: [Property(key: "status", value: .string(status))], version: ItemVersion(1), created: date, modified: date)
        }
        return FakeItemLibrary(items: items, now: date)
    }

    /// A window on `place`, as the window opens one: the default view is followed before anything can change.
    private static func window(
        _ defaults: UserDefaults, library: FakeItemLibrary, place: SidebarItem = tasks
    ) -> Browser {
        let browser = Browser()
        browser.defaults = defaults
        browser.adopt(library)
        browser.sidebarItem = place
        browser.followPlaceDefault(in: library)
        browser.choicesChanged()
        return browser
    }

    // MARK: Kept and restored

    @Test func aPlaceOpensAsThePersonLeftIt() {
        let defaults = ViewPanelTests.defaults()
        let library = Self.library()
        let first = Self.window(defaults, library: library)
        first.setFilter(Self.status, values: ["todo"], negated: true)
        first.tableOptions[first.item, default: .init()].sort = [ItemTableComparator(column: .title, order: .forward)]
        first.tableOptions[first.item, default: .init()].grouping = .none
        first.choicesChanged()
        first.viewMode = .table
        first.timelineFields[first.item] = "due_at"
        first.choicesChanged()
        first.setCompactBoard(true, in: first.item)
        first.changeCards { $0.size = .large }
        first.changeCalendarScale(.month)

        let second = Self.window(defaults, library: library)
        let options = second.tableOptions[second.item]
        #expect(options?.filters == [Self.status: ["todo"]])
        #expect(options?.negated == [Self.status])
        #expect(options?.sort?.map(\.column.id) == ["title"])
        #expect(options?.grouping == ItemTableOptions.Grouping.none)
        #expect(second.viewMode == .table)
        #expect(second.timelineFields[second.item] == "due_at")
        #expect(second.compactBoards[second.item] == true)
        #expect(second.cards.size == .large)
        #expect(second.calendarScale == .month)
        // Opening is not the person's change: it makes no step of Undo and no write.
        #expect(second.liveChoices == second.observedChoices[second.item])
    }

    @Test func anotherPlaceKeepsItsOwnAndAPlaceNobodyChangedKeepsNothing() {
        let defaults = ViewPanelTests.defaults()
        let library = Self.library()
        let browser = Self.window(defaults, library: library)
        browser.setFilter(Self.status, values: ["todo"])
        browser.choicesChanged()
        let stored = PlaceDefaults.stored(in: defaults)
        #expect(stored.default(for: Self.tasks) != nil)
        #expect(stored.default(for: .recents) == nil)
        #expect(Self.window(defaults, library: library, place: .recents).tableOptions[.recents]?.isFiltering != true)
    }

    @Test func aSavedViewAndTheIndexesHaveNoDefaultView() {
        #expect(!Browser.hasDefaultView(.view(ItemID("v"))))
        #expect(!Browser.hasDefaultView(.sources))
        #expect(!Browser.hasDefaultView(.collections))
        #expect(Browser.hasDefaultView(.allItems))
        #expect(Browser.hasDefaultView(.collection(ItemID("c"))))
    }

    @Test func twoWindowsOnOnePlaceLetTheLastChangeWinAndTheOtherPicksItUpWhenItReopensThePlace() {
        let defaults = ViewPanelTests.defaults()
        let library = Self.library()
        let one = Self.window(defaults, library: library)
        let two = Self.window(defaults, library: library)
        one.setFilter(Self.status, values: ["todo"])
        one.choicesChanged()
        // The other window keeps what it shows until it opens the place again.
        #expect(two.tableOptions[two.item]?.isFiltering != true)
        two.sidebarItem = .recents
        two.sidebarItem = Self.tasks
        two.followPlaceDefault(in: library)
        #expect(two.tableOptions[two.item]?.filters == [Self.status: ["todo"]])
        two.tableOptions[two.item, default: .init()].grouping = .none
        two.choicesChanged()
        let stored = PlaceDefaults.stored(in: defaults).default(for: Self.tasks)
        #expect(stored?.filters == [Self.status: ["todo"]])
        #expect(stored?.grouping == PlaceDefault.Grouping.none)
    }

    // MARK: Reset View

    @Test func resetViewPutsThePlaceBackAndThenHides() {
        let defaults = ViewPanelTests.defaults()
        let library = Self.library()
        let browser = Self.window(defaults, library: library)
        #expect(!browser.isDefaultViewChanged)
        browser.setFilter(Self.status, values: ["todo"])
        browser.choicesChanged()
        browser.viewMode = .table
        browser.changeDensity(.compact)
        #expect(browser.isDefaultViewChanged)

        browser.resetView(in: library)
        #expect(browser.tableOptions[browser.item]?.isFiltering != true)
        #expect(browser.viewMode == Browser.naturalLayout(of: browser.item))
        #expect(browser.density == nil)
        #expect(!browser.isDefaultViewChanged)
        #expect(PlaceDefaults.stored(in: defaults).default(for: Self.tasks) == nil)
        #expect(Self.window(defaults, library: library).tableOptions[Self.tasks]?.isFiltering != true)
    }

    @Test func choosingThePlacesOwnLayoutIsNoChange() {
        let defaults = ViewPanelTests.defaults()
        let library = Self.library()
        let browser = Self.window(defaults, library: library)
        browser.viewMode = .table
        #expect(browser.isDefaultViewChanged)
        browser.viewMode = Browser.naturalLayout(of: browser.item)
        #expect(!browser.isDefaultViewChanged)
    }

    @Test func undoOfResetViewBringsTheChoicesBack() {
        let defaults = ViewPanelTests.defaults()
        let library = Self.library()
        let undo = UndoManager()
        // Each change is a step of its own, as a turn of the run loop makes it in the app; the test host cannot end
        // the manager's own groups.
        undo.groupsByEvent = false
        let browser = Browser()
        browser.defaults = defaults
        browser.adopt(library, undoManager: undo)
        browser.sidebarItem = Self.tasks
        browser.followPlaceDefault(in: library)
        undo.beginUndoGrouping()
        browser.setFilter(Self.status, values: ["todo"])
        browser.choicesChanged()
        undo.endUndoGrouping()
        undo.beginUndoGrouping()
        browser.resetView(in: library)
        undo.endUndoGrouping()
        #expect(PlaceDefaults.stored(in: defaults).default(for: Self.tasks) == nil)
        undo.undo()
        #expect(browser.tableOptions[browser.item]?.filters == [Self.status: ["todo"]])
        #expect(PlaceDefaults.stored(in: defaults).default(for: Self.tasks)?.filters == [Self.status: ["todo"]])
    }

    // MARK: Save as View…

    @Test func saveAsViewIsOfferedOnlyWithSomethingToKeepAndFillsNewViewsPanel() {
        let defaults = ViewPanelTests.defaults()
        let library = Self.library()
        let browser = Self.window(defaults, library: library)
        #expect(!SavedViews.hasChoicesToKeep(browser, in: library))
        browser.setFilter(Self.status, values: ["todo"])
        #expect(SavedViews.hasChoicesToKeep(browser, in: library))

        browser.openNewViewPanel(in: library)
        #expect(browser.viewPanel?.isNew == true)
        let window = SavedViews.window(browser, in: library)
        #expect(window.filters == [Self.status: ["todo"]])
        #expect(window.place == Self.tasks)
    }

    @Test func escapeOnANewViewLeavesThePlacesDefaultAsItWas() {
        let defaults = ViewPanelTests.defaults()
        let library = Self.library()
        let browser = Self.window(defaults, library: library)
        browser.setFilter(Self.status, values: ["todo"])
        browser.choicesChanged()
        let before = PlaceDefaults.stored(in: defaults).default(for: Self.tasks)
        browser.openNewViewPanel(in: library)
        browser.setFilter(Self.status, values: ["todo", "done"])
        browser.viewMode = .table
        browser.choicesChanged()
        #expect(PlaceDefaults.stored(in: defaults).default(for: Self.tasks) == before)
        browser.escapeViewPanel(in: library)
        #expect(PlaceDefaults.stored(in: defaults).default(for: Self.tasks) == before)
        #expect(browser.tableOptions[browser.item]?.filters == [Self.status: ["todo"]])
    }

    // MARK: What can have gone stale

    private static func store(_ value: PlaceDefault, for place: SidebarItem, in defaults: UserDefaults) {
        PlaceDefaults.update(in: defaults) { $0.set(value, for: place) }
    }

    @Test func aConditionOnAFieldTheTypeNoLongerDeclaresIsDroppedAndTheRestKept() {
        let defaults = ViewPanelTests.defaults()
        var stored = PlaceDefault()
        stored.filters = ["field.gone": ["x"], Self.status: ["todo"]]
        stored.negated = ["field.gone", Self.status]
        stored.sort = [.init(column: "field.gone", reversed: false), .init(column: "title", reversed: true)]
        stored.grouping = .column("field.gone")
        Self.store(stored, for: Self.tasks, in: defaults)
        let browser = Self.window(defaults, library: Self.library())
        let options = browser.tableOptions[Self.tasks]
        #expect(options?.filters == [Self.status: ["todo"]])
        #expect(options?.negated == [Self.status])
        #expect(options?.sort?.map(\.column.id) == ["title"])
        #expect(options?.grouping == .automatic)
    }

    @Test func aTypeThatNoLongerExistsIsIgnored() {
        let defaults = ViewPanelTests.defaults()
        var stored = PlaceDefault()
        stored.filters = [Self.status: ["todo"], "type": ["test.gone"]]
        stored.layout = .board
        Self.store(stored, for: .itemType("test.gone"), in: defaults)
        Self.store(stored, for: .collection(ItemID("gone")), in: defaults)
        let library = Self.library()
        let browser = Self.window(defaults, library: library, place: .itemType("test.gone"))
        // Nothing of the type's fields is declared, so the field condition goes; the built-in column's stays.
        #expect(browser.tableOptions[browser.item]?.filters == ["type": ["test.gone"]])
        #expect(browser.viewMode != .board)
        // The place a person is in is not touched by another's.
        #expect(Self.window(defaults, library: library).tableOptions[Self.tasks]?.isFiltering != true)
    }

    @Test func aLayoutThePlaceNoLongerOffersIsNotTaken() {
        let defaults = ViewPanelTests.defaults()
        var stored = PlaceDefault()
        stored.layout = .board
        Self.store(stored, for: .itemType("core.note"), in: defaults)
        let library = Self.library()
        let browser = Self.window(defaults, library: library, place: .itemType("core.note"))
        #expect(!browser.availableViewModes(in: library).contains(.board))
        #expect(browser.viewMode == .list)
    }

    @Test func unreadableStoredDefaultsAreSetAsideAndNeverRemoved() {
        let defaults = ViewPanelTests.defaults()
        let garbage = Data("not json".utf8)
        defaults.set(garbage, forKey: PlaceDefaults.key)
        #expect(PlaceDefaults.stored(in: defaults).default(for: .allItems) == nil)
        Self.store(PlaceDefault(layout: .table), for: .allItems, in: defaults)
        #expect(defaults.array(forKey: PlaceDefaults.setAsideKey) as? [Data] == [garbage])
        #expect(PlaceDefaults.stored(in: defaults).default(for: .allItems)?.layout == .table)
    }

    @Test func aFieldThisVersionDoesNotKnowNeverVoidsTheRest() throws {
        let text = #"{"layout":"table","grouping":7,"sort":"x","future":true}"#
        let value = try JSONDecoder().decode(PlaceDefault.self, from: Data(text.utf8))
        #expect(value.layout == .table)
        #expect(value.sort.isEmpty)
        #expect(value.grouping == nil)
    }
}

private extension PlaceDefault {
    init(layout: ItemViewMode) {
        self.init()
        self.layout = layout
    }
}
