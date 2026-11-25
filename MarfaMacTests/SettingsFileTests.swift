import Foundation
import Testing
@testable import MarfaMac

/// Exercises settings files and restore points with isolated defaults and a test hot key registrar.
@MainActor @Suite(.hangLimit) final class SettingsFileTests {
    let defaults = ThrowawayDefaults.make("MarfaMacTests.SettingsFile")
    /// The defaults' own domain, which a restore point reads.
    var suite: String { defaults.suite }
    let points = RestorePoints(folder: URL.temporaryDirectory.appending(path: "SettingsFileTests-\(UUID().uuidString)"))
    let bench = HostBench()
    let library = "marfa:https://one"
    let hotKey = Shortcut(key: "k", modifiers: [.command, .control], keyCode: 40)
    let refresh = Shortcut(key: "m", modifiers: [.command, .option], keyCode: 46)
    let view = ItemID("view-1")

    deinit {
        try? FileManager.default.removeItem(at: points.folder)
    }

    private func sync() -> PreferencesSync {
        PreferencesSync(defaults: defaults, domain: suite, enabled: false, restorePoints: points, library: { [library] in library }) {}
    }

    /// The app's stores over this suite's defaults, with the shortcuts that work in any app started.
    private func libraries(_ hotKeys: FakeHotKeys = FakeHotKeys()) -> Libraries {
        let libraries = Libraries(
            host: bench.host(), defaults: defaults, handOverPages: { $0(true) }, hotKeys: hotKeys, restorePoints: points,
            defaultsDomain: suite)
        libraries.anyAppShortcuts.start()
        return libraries
    }

    /// A value for every setting a file carries, each one its store keeps, and the stores read them.
    private func fillEverySetting(_ libraries: Libraries) {
        let library = libraries.libraryKey
        for setting in PreferencesMap.inFiles {
            guard case .member(let field) = setting.place else { continue }
            setting.write([.member(field, setting.key): #""chosen""#], to: defaults, library: library)
        }
        libraries.shortcuts.set(refresh, for: .refresh)
        #expect(libraries.anyAppShortcuts.set(hotKey, for: .commandPalette) == nil)
        libraries.sidebarLayouts.update(library) { $0.setHidden(.feed, true) }
        libraries.searchLeaveOuts.update(library) { $0.types.insert(TypeID("core.note")) }
        // Another Marfa's look too, which only a restore point holds.
        let looks = #"{"\#(library)":{"core.note":{"date":"created"}},"marfa:https://two":{"core.task":{"date":"created"}}}"#
        defaults.set(Data(looks.utf8), forKey: TypeLooks.defaultsKey)
        defaults.set(#"{"core.note":{"pins":["due_at"]}}"#, forKey: PagePlacements.key)
        ViewOrders.update(in: defaults) { $0.set([.favorites, .own], in: .library) }
        ViewLayouts.update(in: defaults) { $0.set(ViewMacSettings(layout: .board, widths: Data("widths".utf8)), for: view) }
        PlaceDefaults.update(in: defaults) {
            var choice = PlaceDefault()
            choice.compactBoard = true
            $0.set(choice, for: .favorites)
        }
        PlaceDensities.update(in: defaults) { $0.set(.compact, for: .favorites) }
        for place in IndexPlace.allCases {
            IndexPreferences.set(place.tabs[1], for: place, in: defaults)
            IndexPreferences.set(IndexSort(column: place.defaultSort.column, ascending: !place.defaultSort.ascending), for: place, in: defaults)
        }
        libraries.preferences.reload()
    }

    /// What the stores set aside because they could not read it.
    private func setAside() -> [String] {
        PreferencesMap.inFiles.compactMap { setting -> String? in
            switch setting.setAsideKind {
            case .data(let key), .string(let key): defaults.object(forKey: key) == nil ? nil : key
            case nil: nil
            }
        }
    }

    private func held(_ sync: PreferencesSync) -> PreferenceUnits { sync.settingsFile().units(in: Set(SettingsFile.Section.allCases)) }

    @Test func exportThenImportBringsBackEverySettingAsTheStoresHoldIt() async throws {
        let libraries = libraries()
        fillEverySetting(libraries)
        let sync = libraries.preferences
        let before = held(sync)
        #expect(PreferencesMap.inFiles.allSatisfy { setting in before.keys.contains(where: setting.owns) })
        #expect(setAside().isEmpty)
        let file = try SettingsFile.read(sync.settingsFile().encoded())
        MacSettings.reset(in: defaults)
        sync.reload()
        #expect(held(sync).isEmpty)
        let applied = try await sync.importSettings(file, sections: Set(SettingsFile.Section.allCases))
        #expect(held(sync) == before)
        #expect(applied == .init(applied: before.count, skipped: 0))
        #expect(setAside().isEmpty)
        #expect(libraries.sidebarLayouts.layout(for: libraries.libraryKey).isHidden(.feed))
        #expect(libraries.typeLooks.hasChoice(for: TypeID("core.note"), in: libraries.libraryKey))
        #expect(libraries.searchLeaveOuts.leaveOut(for: libraries.libraryKey).types == [TypeID("core.note")])
        #expect(libraries.shortcuts.shortcut(for: .refresh) == refresh)
        #expect(libraries.anyAppShortcuts.shortcut(for: .commandPalette) == hotKey)
    }

    @Test func importChangesOnlyTheChosenSectionsWholeAndSavesAPointFirst() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        defaults.set("blue", forKey: AppearanceKey.accent)
        defaults.set(true, forKey: PageKey.foldsHeadings)
        let sync = sync()
        let theme = PreferenceUnit.member(.appearance, AppearanceKey.theme)
        let unowned = PreferenceUnit.member(.appearance, "aSettingNoVersionHas")
        let file = SettingsFile(
            units: [theme: #""light""#, unowned: "1", .member(.editor, PageKey.foldsHeadings): "false"], build: "", date: .now)
        let applied = try await sync.importSettings(file, sections: [.appearance])
        #expect(defaults.string(forKey: AppearanceKey.theme) == "light")
        // The file holds no accent, so the section's accent goes back to its default.
        #expect(defaults.object(forKey: AppearanceKey.accent) == nil)
        #expect(defaults.bool(forKey: PageKey.foldsHeadings))
        #expect(applied == .init(applied: 1, skipped: 1))
        let point = try #require(points.list().first)
        #expect(point.reason == .import)
        #expect(try points.snapshot(of: point.id).value(forKey: AppearanceKey.theme) as? String == "dark")
    }

    @Test func aValueTheSettingCannotStoreIsSkippedAndChangesNothing() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        ViewOrders.update(in: defaults) { $0.set([.favorites, .own], in: .library); $0.set([.own], in: .feed) }
        let sync = sync()
        let before = held(sync)
        var units = before
        units[.row(.places, setting: "viewOrder", key: "library")] = "{not json"
        // The defaults cannot keep a null inside a value.
        units[.member(.appearance, AppearanceKey.theme)] = #"{"nested":[null]}"#
        let all = Set(SettingsFile.Section.allCases)
        let applied = try await sync.importSettings(SettingsFile(units: units, build: "", date: .now), sections: all)
        #expect(held(sync) == before)
        #expect(applied == .init(applied: 1, skipped: 2))
    }

    @Test func aFileThatIsNotOursOrFromALaterVersionIsRefused() throws {
        let later = try SettingsFile(units: [:], build: "", date: .now).encoded()
        let text = String(decoding: later, as: UTF8.self).replacingOccurrences(of: #""version" : 1"#, with: #""version" : 2"#)
        #expect(throws: SettingsFile.ReadError.newerVersion) { try SettingsFile.read(Data(text.utf8)) }
        #expect(throws: SettingsFile.ReadError.notOurs) { try SettingsFile.read(Data(#"{"format":"marfa-mac-shortcuts","version":1}"#.utf8)) }
        #expect(throws: SettingsFile.ReadError.notOurs) { try SettingsFile.read(Data("not json".utf8)) }
    }

    @Test func aValueThisMacCannotReadIsLeftOutAndKeptByAnotherSectionsImport() async throws {
        let unreadable = Data("not json".utf8)
        defaults.set(unreadable, forKey: TypeLooks.defaultsKey)
        defaults.set("dark", forKey: AppearanceKey.theme)
        let sync = sync()
        let file = sync.settingsFile()
        #expect(file.sections[.layouts] == nil)
        try await sync.importSettings(file, sections: [.appearance, .general])
        #expect(defaults.data(forKey: TypeLooks.defaultsKey) == unreadable)
        // Its own section's import sets it aside before writing over it.
        try await sync.importSettings(file, sections: [.layouts])
        #expect(defaults.array(forKey: TypeLooks.setAsideKey) as? [Data] == [unreadable])
    }

    @Test func textWhereTheStoreKeepsDataIsSetAsideByItsSectionsImport() async throws {
        let text = #"{"marfa:https://one":{}}"#
        defaults.set(text, forKey: TypeLooks.defaultsKey)
        let sync = sync()
        try await sync.importSettings(SettingsFile(units: [:], build: "", date: .now), sections: [.layouts])
        #expect(defaults.array(forKey: TypeLooks.setAsideKey) as? [Data] == [Data(text.utf8)])
        #expect(defaults.object(forKey: TypeLooks.defaultsKey) == nil)
    }

    @Test func anAnyAppShortcutTheSystemRefusesIsCountedAsSkipped() async throws {
        let hotKeys = FakeHotKeys()
        let libraries = libraries(hotKeys)
        #expect(libraries.anyAppShortcuts.set(hotKey, for: .commandPalette) == nil)
        let sync = libraries.preferences
        let section = PreferencesMap.anyAppShortcuts.section
        let file = sync.settingsFile()
        libraries.anyAppShortcuts.clearAll()
        hotKeys.heldByAnotherApp = [hotKey]
        let applied = try await sync.importSettings(file, sections: [section])
        #expect(applied == .init(applied: file.units(in: [section]).count - 1, skipped: 1))
        #expect(hotKeys.registered.isEmpty)
        // The same import again changes nothing stored, and the shortcut is still not registered.
        #expect(try await sync.importSettings(file, sections: [section]) == applied)
        #expect(libraries.anyAppShortcuts.refused == [.commandPalette])
    }

    @Test func resetLeavesAPointThatRestoreBringsBackWhole() async throws {
        let hotKeys = FakeHotKeys()
        let libraries = libraries(hotKeys)
        fillEverySetting(libraries)
        defaults.set(320.0, forKey: InterfaceKey.inspectorWidth)
        let sync = libraries.preferences
        // The library key the stores read with no Marfa connected.
        #expect(sync.settingsLibrary == libraries.libraryKey)
        let before = (held(sync), try SettingsSnapshot(of: defaults, domain: suite))

        libraries.resetMacSettings()
        #expect(hotKeys.registered.isEmpty)
        #expect(!libraries.typeLooks.hasChoice(for: TypeID("core.task"), in: "marfa:https://two"))
        let reset = try #require(sync.listRestorePoints().first)
        #expect(reset.reason == .reset)

        try await sync.restore(reset.id)
        #expect(held(sync) == before.0)
        #expect(try SettingsSnapshot(of: defaults, domain: suite) == before.1)
        #expect(libraries.typeLooks.hasChoice(for: TypeID("core.task"), in: "marfa:https://two"))
        #expect(defaults.double(forKey: InterfaceKey.inspectorWidth) == 320)
        #expect(hotKeys.registered[.commandPalette] == hotKey)
        // Restoring saved a point of its own, so the restore can be undone.
        #expect(sync.listRestorePoints().map(\.reason) == [.restoring, .reset])
    }

    @Test func restoringAfterAnImportBringsBackWhatStaysOnThisMac() async throws {
        let widths = Data("widths".utf8)
        ViewLayouts.update(in: defaults) { $0.set(ViewMacSettings(layout: .board, widths: widths), for: view) }
        let sync = sync()
        try await sync.importSettings(SettingsFile(units: [:], build: "", date: .now), sections: [.lists])
        #expect(ViewLayouts.stored(in: defaults).settings(for: view) == nil)
        try await sync.restore(try #require(sync.listRestorePoints().first).id)
        #expect(ViewLayouts.stored(in: defaults).settings(for: view)?.widths == widths)
    }

    @Test func resetThatCannotSaveItsPointChangesNothingAndSaysSo() throws {
        // A file where the points' folder would go.
        try Data().write(to: points.folder)
        defaults.set("dark", forKey: AppearanceKey.theme)
        let libraries = libraries()
        var followed = false
        libraries.resetMacSettings { followed = true }
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
        #expect(libraries.host.notices.waiting.map(\.title) == [String(localized: "Settings Not Reset")])
        #expect(!followed)
    }

    @Test func resetShowsTheDefaultsInTheStoresAtOnce() throws {
        let libraries = libraries()
        libraries.sidebarLayouts.update(libraries.libraryKey) { $0.setHidden(.feed, true) }
        var followed = false
        libraries.resetMacSettings { followed = true }
        #expect(!libraries.sidebarLayouts.layout(for: libraries.libraryKey).isHidden(.feed))
        #expect(followed)
    }

    /// The defaults call `true` and `1` equal, so a point is told from the newest by its bytes.
    @Test func aPointThatDiffersOnlyInAValuesTypeIsSaved() throws {
        func snapshot(_ value: Any) throws -> SettingsSnapshot {
            SettingsSnapshot(values: [InterfaceKey.textSize: try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)])
        }
        try points.save(try snapshot(true), reason: .reset, build: "")
        #expect(try points.save(try snapshot(1), reason: .reset, build: "") != nil)
        #expect(try points.save(try snapshot(1), reason: .reset, build: "") == nil)
        #expect(points.list().count == 2)
        #expect(try points.snapshot(of: points.list()[0].id) == (try snapshot(1)))
        #expect(try points.snapshot(of: points.list()[1].id) == (try snapshot(true)))
    }

    @Test func theNewestTenAreKeptAndAnUnreadablePointIsLeftOut() throws {
        func snapshot(_ size: Int) throws -> SettingsSnapshot {
            SettingsSnapshot(values: [InterfaceKey.textSize: try PropertyListSerialization.data(fromPropertyList: size, format: .binary, options: 0)])
        }
        for size in 1...11 { try points.save(try snapshot(size), reason: .reset, build: "") }
        // The same reason and settings as the newest point save nothing.
        #expect(try points.save(try snapshot(11), reason: .reset, build: "") == nil)
        let listed = points.list()
        #expect(listed.count == RestorePoints.kept)
        #expect(try points.snapshot(of: listed[0].id) == (try snapshot(11)))
        #expect(try points.snapshot(of: listed[9].id) == (try snapshot(2)))
        try Data("{".utf8).write(to: points.folder.appending(path: "999999999999999-corrupt.json"))
        #expect(points.list().count == RestorePoints.kept)
        #expect(throws: RestorePoints.Failure.unreadable) { try points.snapshot(of: "999999999999999-corrupt") }
    }

    /// A value JSON cannot hold, or would bring back as another kind, comes back from a point as it was.
    @Test func aPointKeepsEachValueAsTheDefaultsHeldIt() async throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000.123_456)
        let data = Data([0, 1, 2])
        let wrapped: [String: Any] = ["$data": "AAEC"]
        defaults.set(date, forKey: InterfaceKey.inspectorWidth)
        defaults.set(data, forKey: InterfaceKey.textSize)
        defaults.set(wrapped, forKey: AppearanceKey.theme)
        defaults.set([Double.infinity], forKey: AppearanceKey.accent)
        let sync = sync()
        let point = try #require(try sync.restorePoints.save(
            SettingsSnapshot(of: defaults, domain: suite), reason: .reset, build: ""))
        MacSettings.reset(in: defaults)
        try await sync.restore(point.id)
        #expect(defaults.object(forKey: InterfaceKey.inspectorWidth) as? Date == date)
        #expect(defaults.object(forKey: InterfaceKey.textSize) as? Data == data)
        #expect((defaults.object(forKey: AppearanceKey.theme) as? NSDictionary)?.isEqual(to: wrapped) == true)
        #expect(defaults.object(forKey: AppearanceKey.accent) as? [Double] == [.infinity])
    }

    /// A value the defaults inherit, such as the system's own Reopen Windows answer, is not the app's, so no point holds
    /// it and a restore does not make it the app's.
    @Test func aPointHoldsOnlyTheAppsOwnValues() async throws {
        let inherited = ThrowawayDefaults.make("MarfaMacTests.Global")
        inherited.set(false, forKey: ReopenWindows.key)
        defaults.addSuite(named: inherited.suite)
        defer { defaults.removeSuite(named: inherited.suite) }
        #expect(defaults.object(forKey: ReopenWindows.key) as? Bool == false)
        let sync = sync()
        try sync.saveRestorePoint(.reset)
        let point = try #require(sync.listRestorePoints().first)
        #expect(try points.snapshot(of: point.id).values[ReopenWindows.key] == nil)
        try await sync.restore(point.id)
        #expect(defaults.persistentDomain(forName: suite)?[ReopenWindows.key] == nil)
    }

    @Test func pointsMadeForTestsAreEachTheirOwnAndGoWithThem() throws {
        var first: RestorePoints? = .temporary()
        let second = RestorePoints.temporary()
        try first?.save(SettingsSnapshot(values: [:]), reason: .reset, build: "")
        #expect(second.list().isEmpty)
        let folder = try #require(first?.folder)
        first = nil
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }
}
