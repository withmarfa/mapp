import Foundation
import Testing
@testable import MarfaMac

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

    // MARK: New Items Are

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
            MarfaHost.addressKey, MarfaHost.discardedKey, ViewLayouts.setAsideKey, TypeLooks.setAsideKey, "NSWindow Frame MarfaMacSettings",
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

    @Test func resetPutsTheLiveShortcutsBackAtOnceAndStoresNothingOfThem() throws {
        let (defaults, done) = try defaults()
        defer { done() }
        let hotKeys = FakeHotKeys()
        let bench = try HostBench()
        let libraries = Libraries(host: bench.host(), defaults: defaults, handOverPages: { $0(true) }, hotKeys: hotKeys)
        libraries.anyAppShortcuts.start()
        libraries.shortcuts.set(nil, for: .newItem)
        libraries.shortcuts.set(Shortcut(key: "j", modifiers: [.command, .option]), for: .refresh)
        let hotKey = Shortcut(key: "k", modifiers: [.command, .control], keyCode: 40)
        #expect(libraries.anyAppShortcuts.set(hotKey, for: .commandPalette) == nil)
        #expect(hotKeys.registered[.commandPalette] == hotKey)
        #expect(defaults.data(forKey: ShortcutBindings.defaultsKey) != nil)
        #expect(defaults.data(forKey: AnyAppShortcuts.defaultsKey) != nil)

        libraries.resetMacSettings()

        #expect(libraries.shortcuts.shortcut(for: .newItem) == ShortcutCommand.newItem.defaultShortcut)
        #expect(libraries.shortcuts.shortcut(for: .refresh) == ShortcutCommand.refresh.defaultShortcut)
        #expect(libraries.anyAppShortcuts.shortcut(for: .commandPalette) == nil)
        #expect(hotKeys.registered.isEmpty)
        #expect(defaults.object(forKey: ShortcutBindings.defaultsKey) == nil)
        #expect(defaults.object(forKey: AnyAppShortcuts.defaultsKey) == nil)
    }

    @Test func theShortcutKeysAreInTheResetListAndTheSetAsideOnesAreNot() {
        #expect(MacSettings.keys.contains(ShortcutBindings.defaultsKey))
        #expect(MacSettings.keys.contains(AnyAppShortcuts.defaultsKey))
        #expect(!MacSettings.keys.contains(ShortcutBindings.setAsideKey))
        #expect(!MacSettings.keys.contains(AnyAppShortcuts.setAsideKey))
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
