import Foundation
import Testing
@testable import MAPP

/// What Settings > General keeps on this Mac and what the app does with it.
@MainActor
struct GeneralSettingsTests {
    private func defaults() throws -> (UserDefaults, () -> Void) {
        let suite = "GeneralSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    // MARK: Week Starts On

    @Test func theWeekStartsWhereTheSystemSaysUntilChosen() throws {
        let (defaults, done) = try defaults()
        defer { done() }
        var base = Calendar(identifier: .gregorian)
        base.firstWeekday = 2
        #expect(WeekStart.stored(in: defaults) == nil)
        #expect(WeekStart.calendar(base, in: defaults).firstWeekday == 2)
        defaults.set(1, forKey: WeekStart.key)
        #expect(WeekStart.calendar(base, in: defaults).firstWeekday == 1)
        defaults.set(0, forKey: WeekStart.key)
        #expect(WeekStart.stored(in: defaults) == nil)
        defaults.set(9, forKey: WeekStart.key)
        #expect(WeekStart.stored(in: defaults) == nil)
    }

    @Test func aChosenFirstDayChangesACalendarsFirstColumn() throws {
        let (defaults, done) = try defaults()
        defer { done() }
        var base = Calendar(identifier: .gregorian)
        base.timeZone = TimeZone(identifier: "Europe/London")!
        base.firstWeekday = 2
        let day = base.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 12))!
        func firstColumn(_ calendar: Calendar) -> Int {
            let week = CalendarLayout.interval(of: .week, containing: day, calendar: calendar)
            return calendar.component(.weekday, from: week.start)
        }
        #expect(firstColumn(WeekStart.calendar(base, in: defaults)) == 2)
        defaults.set(1, forKey: WeekStart.key)
        #expect(firstColumn(WeekStart.calendar(base, in: defaults)) == 1)
        defaults.set(7, forKey: WeekStart.key)
        #expect(firstColumn(WeekStart.calendar(base, in: defaults)) == 7)
        let month = CalendarMonth.make(entries: [], around: day, calendar: WeekStart.calendar(base, in: defaults), now: day)
        let firstRow = try #require(month.weeks.first)
        #expect(base.component(.weekday, from: try #require(firstRow.first).date) == 7)
    }

    // MARK: Start With

    @Test func aChoiceOfPlaceIsReadBackAndAnythingElseIsWhereIWasLeft() throws {
        let (defaults, done) = try defaults()
        defer { done() }
        #expect(StartWith.stored(in: defaults) == .leftOff)
        for choice in [StartWith.leftOff, .place(.inbox), .place(.itemType("core.task")), .place(.allItems)] {
            defaults.set(choice.rawValue, forKey: StartWith.key)
            #expect(StartWith.stored(in: defaults) == choice)
        }
        defaults.set("nowhere", forKey: StartWith.key)
        #expect(StartWith.stored(in: defaults) == .leftOff)
    }

    @Test func whereILeftOffIsTheLastPlaceAndAChosenPlaceIsThatPlace() throws {
        let (defaults, done) = try defaults()
        defer { done() }
        #expect(StartWith.leftOff.startingPlace(in: defaults) == nil)
        StartWith.remember(.itemType("core.task"), in: defaults)
        #expect(StartWith.leftOff.startingPlace(in: defaults) == .itemType("core.task"))
        #expect(StartWith.place(.inbox).startingPlace(in: defaults) == .inbox)
    }

    @Test func aWindowWithNothingToRestoreOpensInTheStartPlaceAndARestoredOneKeepsItsOwn() {
        let library = FakeItemLibrary()
        let browser = Browser()
        browser.restore(from: nil, in: library, order: ItemOrder(), start: .favorites)
        #expect(browser.item == .favorites)

        let kept = Browser()
        let snapshot = try? JSONEncoder().encode(Browser.Snapshot(place: .recents, selection: []))
        kept.restore(from: snapshot, in: library, order: ItemOrder(), start: .favorites)
        #expect(kept.item == .recents)
    }

    // MARK: New Items Are

    @Test func aChosenKindIsUsedOutsideATypesOwnListAndTheLastUsedOtherwise() {
        let catalogue = Catalogue()
        let offered = ["core.note", "core.task", "core.event"]
        func kind(place: SidebarItem = .allItems, chosen: String?, remembered: String?) -> String? {
            QuickAdd.startingType(asked: nil, place: place, chosen: chosen, remembered: remembered, offered: offered, in: catalogue)
        }
        #expect(kind(chosen: nil, remembered: "core.event") == "core.event")
        #expect(kind(chosen: "core.task", remembered: "core.event") == "core.task")
        #expect(kind(place: .itemType("core.event"), chosen: "core.task", remembered: nil) == "core.event")
        // A kind the server no longer offers is passed over.
        #expect(kind(chosen: "core.gone", remembered: "core.event") == "core.event")
    }

    @Test func theChosenKindIsReadFromTheDefaultsAndEmptyMeansLastUsed() throws {
        let (defaults, done) = try defaults()
        defer { done() }
        #expect(NewItemType.stored(in: defaults) == nil)
        defaults.set("core.task", forKey: NewItemType.key)
        #expect(NewItemType.stored(in: defaults) == "core.task")
        defaults.set("", forKey: NewItemType.key)
        #expect(NewItemType.stored(in: defaults) == nil)
    }

    // MARK: Reopen Windows

    @Test func reopeningWindowsFollowsTheMacUntilChangedAndOnlyAChangeWritesTheKey() throws {
        let (defaults, done) = try defaults()
        defer { done() }
        // Unset, the answer is the Mac's own, or windows come back where it has none.
        #expect(ReopenWindows.stored(in: defaults) == (ReopenWindows.system() ?? ReopenWindows.standard))
        defaults.set(false, forKey: ReopenWindows.key)
        #expect(ReopenWindows.stored(in: defaults) == false)
        defaults.set(true, forKey: ReopenWindows.key)
        #expect(ReopenWindows.stored(in: defaults))
    }

    // MARK: Reset

    @Test func resetClearsEverySettingTheListNamesAndNothingElse() throws {
        let (defaults, done) = try defaults()
        defer { done() }
        for key in MacSettings.keys { defaults.set("chosen", forKey: key) }
        defaults.set("chosen", forKey: "\(InterfaceKey.inspectorAppOpen).app.one")
        // What is not a setting: the connection, the sign-in's pending state, a value set aside, a window's frame.
        let kept = [
            MarfaHost.addressKey, MarfaHost.discardedKey, ViewLayouts.setAsideKey, TypeLooks.setAsideKey, "NSWindow Frame MAPPSettings",
        ]
        for key in kept { defaults.set("kept", forKey: key) }

        MacSettings.reset(in: defaults)

        for key in MacSettings.keys {
            #expect(defaults.object(forKey: key) == nil, "\(key) was not reset")
        }
        #expect(defaults.object(forKey: "\(InterfaceKey.inspectorAppOpen).app.one") == nil)
        for key in kept { #expect(defaults.string(forKey: key) == "kept", "\(key) was cleared") }
        // Reopen Windows is removed, not written, so the Mac's own answer stands again.
        #expect(ReopenWindows.stored(in: defaults) == (ReopenWindows.system() ?? ReopenWindows.standard))
    }

    @Test func everyKeyASettingsGroupNamesIsInTheResetList() {
        let groups: [[String]] = [
            OrderKey.all, PageKey.all, ListKey.all, InterfaceKey.all, AppearanceKey.all,
            [DateFormat.key, WeekStart.key, StartWith.key, StartWith.lastPlaceKey, ReopenWindows.key, NewItemType.key],
        ]
        let keys = Set(MacSettings.keys)
        for key in groups.flatMap({ $0 }) { #expect(keys.contains(key), "\(key) is not in the reset list") }
        #expect(keys.count == MacSettings.keys.count, "a key is listed twice")
    }

    @Test func aStoredColumnWidthIsClearedByResetToo() throws {
        let (defaults, done) = try defaults()
        defer { done() }
        defaults.set(300.0, forKey: ColumnWidth.sidebar.key)
        MacSettings.reset(in: defaults)
        #expect(ColumnWidth.sidebar.stored(in: defaults) == ColumnWidth.sidebar.defaultWidth)
    }
}
