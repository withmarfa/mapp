import Foundation
import SwiftUI
import Testing
@testable import MarfaMac

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

    @Test func aWindowModelUnderTestKeepsItsDefaultViewsApart() {
        let first = Browser()
        first.updatePlaceDefault(.recents) { $0.layout = .timeline }
        #expect(PlaceDefaults.stored(in: first.defaults).default(for: .recents)?.layout == .timeline)
        #expect(PlaceDefaults.stored(in: Browser().defaults).default(for: .recents) == nil)
    }

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
        #expect(options?.filter.valuesByField == [Self.status: ["todo"]])
        #expect(options?.filter.clauses.first?.op == .isNot)
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

    @Test func aSavedViewAndTheThreeIndexesHaveNoDefaultView() {
        #expect(!Browser.hasDefaultView(.view(ItemID("v"))))
        #expect(!Browser.hasDefaultView(.sources))
        #expect(!Browser.hasDefaultView(.collections))
        #expect(!Browser.hasDefaultView(.allItems))
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
        #expect(two.tableOptions[two.item]?.filter.valuesByField == [Self.status: ["todo"]])
        two.tableOptions[two.item, default: .init()].grouping = .none
        two.choicesChanged()
        let stored = PlaceDefaults.stored(in: defaults).default(for: Self.tasks)
        #expect(FilterState(clauses: stored?.filter ?? []).valuesByField == [Self.status: ["todo"]])
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
        #expect(browser.viewMode == Browser.naturalLayout)
        #expect(browser.density == nil)
        #expect(!browser.isDefaultViewChanged)
        #expect(PlaceDefaults.stored(in: defaults).default(for: Self.tasks) == nil)
        #expect(Self.window(defaults, library: library).tableOptions[Self.tasks]?.isFiltering != true)
    }

    @Test func aPlacesPropertiesAreKeptInItsDefaultViewAndResetViewPutsTheLooksBack() {
        let defaults = ViewPanelTests.defaults()
        let library = Self.library()
        let browser = Self.window(defaults, library: library)
        let created = ItemTableColumn.created
        #expect(!browser.properties.isChanged)
        browser.changeProperties { $0.setShown(created, true) }
        #expect(browser.properties.isShown(created))
        #expect(browser.isDefaultViewChanged)
        #expect(PlaceDefaults.stored(in: defaults).default(for: Self.tasks)?.properties.isChanged == true)
        // Another window opens the place with them, and they are the same for every layout.
        let other = Self.window(defaults, library: library)
        other.followPlaceDefault(in: library)
        #expect(other.properties.isShown(created))

        browser.resetView(in: library)
        #expect(!browser.properties.isChanged)
        #expect(!browser.isDefaultViewChanged)
        #expect(PlaceDefaults.stored(in: defaults).default(for: Self.tasks) == nil)
    }

    @Test func useLayoutsAndUndoGivePropertiesBack() {
        let defaults = ViewPanelTests.defaults()
        let library = Self.library()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let browser = Browser()
        browser.defaults = defaults
        browser.adopt(library, undoManager: undo)
        browser.sidebarItem = Self.tasks
        browser.followPlaceDefault(in: library)
        undo.beginUndoGrouping()
        browser.changeProperties { $0.setShown(.created, true) }
        undo.endUndoGrouping()
        undo.beginUndoGrouping()
        browser.useLayouts()
        undo.endUndoGrouping()
        #expect(!browser.properties.isChanged)
        undo.undo()
        #expect(browser.properties.isShown(.created))
        #expect(PlaceDefaults.stored(in: defaults).default(for: Self.tasks)?.properties.isChanged == true)
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
        #expect(browser.tableOptions[browser.item]?.filter.valuesByField == [Self.status: ["todo"]])
        #expect(FilterState(clauses: PlaceDefaults.stored(in: defaults).default(for: Self.tasks)?.filter ?? []).valuesByField == [Self.status: ["todo"]])
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
        #expect(window.filter.valuesByField == [Self.status: ["todo"]])
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
        #expect(browser.tableOptions[browser.item]?.filter.valuesByField == [Self.status: ["todo"]])
    }

    // MARK: What can have gone stale

    private static func store(_ value: PlaceDefault, for place: SidebarItem, in defaults: UserDefaults) {
        PlaceDefaults.update(in: defaults) { $0.set(value, for: place) }
    }

    @Test func aConditionOnAFieldTheTypeNoLongerDeclaresIsDroppedAndTheRestKept() {
        let defaults = ViewPanelTests.defaults()
        var stored = PlaceDefault()
        stored.filter = [
            FilterClause(field: "field.gone", op: .isNot, values: ["x"]), FilterClause(field: Self.status, op: .isNot, values: ["todo"]),
        ]
        stored.sort = [.init(column: "field.gone", reversed: false), .init(column: "title", reversed: true)]
        stored.grouping = .column("field.gone")
        Self.store(stored, for: Self.tasks, in: defaults)
        let browser = Self.window(defaults, library: Self.library())
        let options = browser.tableOptions[Self.tasks]
        #expect(options?.filter.valuesByField == [Self.status: ["todo"]])
        #expect(options?.filter.clauses.map(\.op) == [.isNot])
        #expect(options?.sort?.map(\.column.id) == ["title"])
        #expect(options?.grouping == .automatic)
    }

    @Test func aTypeThatNoLongerExistsIsIgnored() {
        let defaults = ViewPanelTests.defaults()
        var stored = PlaceDefault()
        stored.filter = FilterState(is: [Self.status: ["todo"], "type": ["test.gone"]]).clauses
        stored.layout = .board
        Self.store(stored, for: .itemType("test.gone"), in: defaults)
        Self.store(stored, for: .collection(ItemID("gone")), in: defaults)
        let library = Self.library()
        let browser = Self.window(defaults, library: library, place: .itemType("test.gone"))
        // Nothing of the type's fields is declared, so the field condition goes; the built-in column's stays.
        #expect(browser.tableOptions[browser.item]?.filter.valuesByField == ["type": ["test.gone"]])
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
        #expect(PlaceDefaults.stored(in: defaults).default(for: .favorites) == nil)
        Self.store(PlaceDefault(layout: .table), for: .favorites, in: defaults)
        #expect(defaults.array(forKey: PlaceDefaults.setAsideKey) as? [Data] == [garbage])
        #expect(PlaceDefaults.stored(in: defaults).default(for: .favorites)?.layout == .table)
    }

    @Test func aFieldThisVersionDoesNotKnowNeverVoidsTheRest() throws {
        let text = #"{"layout":"table","grouping":"by-magic","future":true}"#
        let value = try JSONDecoder().decode(PlaceDefault.self, from: Data(text.utf8))
        #expect(value.layout == .table)
        // A word for a grouping this version lacks is the place's own grouping, never "no grouping".
        #expect(value.grouping == nil)
    }

    @Test func aFieldThatIsThereAndCannotBeReadFailsTheEntry() {
        for text in [#"{"filter":"x"}"#, #"{"sort":"x"}"#, #"{"grouping":7}"#, #"{"layout":3}"#] {
            #expect(throws: (any Error).self) { try JSONDecoder().decode(PlaceDefault.self, from: Data(text.utf8)) }
        }
    }

    @Test func oneUnreadableEntryIsSetAsideAndTheOthersKeepWorking() throws {
        let defaults = ViewPanelTests.defaults()
        let bad = #"{"filter":"not a table","layout":"table"}"#
        let good = try String(decoding: JSONEncoder().encode(PlaceDefault(layout: .board)), as: UTF8.self)
        let object: [String: Any] = [
            Self.tasks.storageKey: try JSONSerialization.jsonObject(with: Data(bad.utf8)),
            SidebarItem.favorites.storageKey: try JSONSerialization.jsonObject(with: Data(good.utf8)),
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: PlaceDefaults.key)
        #expect(PlaceDefaults.stored(in: defaults).default(for: .favorites)?.layout == .board)
        #expect(PlaceDefaults.stored(in: defaults).default(for: Self.tasks) == nil)

        Self.store(PlaceDefault(layout: .table), for: .recents, in: defaults)
        let aside = try #require(defaults.array(forKey: PlaceDefaults.setAsideKey) as? [Data])
        #expect(aside.count == 1)
        let kept = try #require(JSONSerialization.jsonObject(with: aside[0]) as? [String: Any])
        #expect(Array(kept.keys) == [Self.tasks.storageKey])
        #expect((kept[Self.tasks.storageKey] as? [String: Any])?["filter"] as? String == "not a table")
        #expect(PlaceDefaults.stored(in: defaults).default(for: .favorites)?.layout == .board)
        #expect(PlaceDefaults.stored(in: defaults).default(for: .recents)?.layout == .table)
    }

    // MARK: Column layouts that cannot be read

    @Test func resetViewLeavesUnreadableColumnLayoutsAsTheyWere() {
        let defaults = ViewPanelTests.defaults()
        let garbage = Data("not json".utf8)
        defaults.set(garbage, forKey: ItemTableColumnLayouts.key)
        let library = Self.library()
        let browser = Self.window(defaults, library: library)
        browser.viewMode = .table
        browser.resetView(in: library)
        #expect(defaults.data(forKey: ItemTableColumnLayouts.key) == garbage)
        #expect(ItemTableColumnLayouts.removing(Self.tasks, in: garbage) == garbage)
    }

    @Test func storingAColumnLayoutKeepsUnreadableStoredLayoutsAside() {
        let defaults = ViewPanelTests.defaults()
        let garbage = Data("not json".utf8)
        var layout = TableColumnCustomization<ItemTableRow>()
        layout[visibility: "created"] = .visible
        let stored = ItemTableColumnLayouts.storing(layout, for: Self.tasks, in: garbage, setAsideIn: defaults)
        #expect(defaults.array(forKey: ItemTableColumnLayouts.setAsideKey) as? [Data] == [garbage])
        #expect(ItemTableColumnLayouts.layout(for: Self.tasks, in: stored)[visibility: "created"] == .visible)
        // Nothing stored yet, or readable layouts, set nothing aside.
        _ = ItemTableColumnLayouts.storing(layout, for: .favorites, in: stored, setAsideIn: defaults)
        _ = ItemTableColumnLayouts.storing(layout, for: .favorites, in: Data(), setAsideIn: defaults)
        #expect((defaults.array(forKey: ItemTableColumnLayouts.setAsideKey) as? [Data])?.count == 1)
    }

    // MARK: Pruning

    @Test func entriesOfWhatNoLongerExistsAreForgottenOnlyOnceTheCopyIsWhole() {
        let defaults = ViewPanelTests.defaults()
        let library = Self.library()
        let gone = SidebarItem.collection(ItemID("gone"))
        let lost = SidebarItem.itemType("test.gone")
        for place in [Self.tasks, gone, lost, .favorites] { Self.store(PlaceDefault(layout: .table), for: place, in: defaults) }
        let browser = Self.window(defaults, library: library)

        // A copy that is not known to be whole says nothing about what is missing.
        library.syncReport.fill = LibraryFill(state: .filling)
        browser.prunePlaceDefaults(in: library)
        #expect(PlaceDefaults.stored(in: defaults).places.count == 4)
        library.syncReport.fill = nil
        browser.prunePlaceDefaults(in: library)
        #expect(PlaceDefaults.stored(in: defaults).places.count == 4)

        library.syncReport.fill = LibraryFill(state: .complete)
        browser.prunePlaceDefaults(in: library)
        let stored = PlaceDefaults.stored(in: defaults)
        #expect(stored.default(for: gone) == nil)
        #expect(stored.default(for: lost) == nil)
        #expect(stored.default(for: Self.tasks) != nil)
        #expect(stored.default(for: .favorites) != nil)
    }

    // MARK: Reset View beside New View's panel

    @Test func resetViewIsNotOfferedWhileNewViewsPanelIsOpen() {
        let defaults = ViewPanelTests.defaults()
        let library = Self.library()
        let browser = Self.window(defaults, library: library)
        browser.setFilter(Self.status, values: ["todo"])
        browser.choicesChanged()
        #expect(browser.offersResetView)
        browser.openNewViewPanel(in: library)
        #expect(browser.isDefaultViewChanged)
        #expect(!browser.offersResetView)
        browser.escapeViewPanel(in: library)
        #expect(browser.offersResetView)
    }

    @Test func theChangedStateFollowsTheStoredDataWithoutBeingToldOfAWrite() {
        let defaults = ViewPanelTests.defaults()
        let browser = Self.window(defaults, library: Self.library())
        #expect(!browser.isDefaultViewChanged)
        Self.store(PlaceDefault(layout: .table), for: Self.tasks, in: defaults)
        #expect(browser.isDefaultViewChanged)
        PlaceDefaults.update(in: defaults) { $0.set(nil, for: Self.tasks) }
        #expect(!browser.isDefaultViewChanged)
        PlaceDensities.update(in: defaults) { $0.set(.compact, for: Self.tasks) }
        #expect(browser.isDefaultViewChanged)
    }
}

private extension PlaceDefault {
    init(layout: ItemViewMode) {
        self.init()
        self.layout = layout
    }
}
