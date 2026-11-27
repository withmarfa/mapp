import Foundation
import Testing
@testable import MarfaMac

/// A row a store's reload removes because it cannot read it stays in the Marfa as it is, where the next step would
/// otherwise send the removal. Every other decision, on this Mac and in the Marfa, is the one the sync makes without
/// the hold. Every change goes through a store or the app's own entry point.
@MainActor @Suite(.hangLimit) final class PreferenceHoldsTests {
    let defaults = ThrowawayDefaults.make("MarfaMacTests.PreferenceHolds")
    let points = RestorePoints(folder: URL.temporaryDirectory.appending(path: "PreferenceHoldsTests-\(UUID().uuidString)"))
    let library = "marfa:https://one"
    /// The settings a library's earlier name still holds, as `LibrarySettings` says.
    var unsettled: Set<String> = []
    lazy var looks = TypeLooks(defaults: defaults)
    lazy var sidebar = SidebarLayouts(defaults: defaults)
    lazy var leaveOuts = SearchLeaveOuts(defaults: defaults)
    lazy var bindings = ShortcutBindings(defaults: defaults)

    let note = "core.note"
    let task = "core.task"
    let date = PreferenceUnit.member(.general, DateFormat.key)
    let theme = PreferenceUnit.member(.appearance, AppearanceKey.theme)
    let search = PreferenceUnit.member(.search, SearchLeaveOuts.defaultsKey)

    deinit {
        try? FileManager.default.removeItem(at: points.folder)
    }

    // MARK: Helpers

    /// A sync whose stores read the defaults again as the app's do. `build` stands for another app build.
    private func sync(_ copy: FakePreferencesCopy, build: String = PreferencesSync.appBuild, defaults: ThrowawayDefaults? = nil)
        async -> PreferencesSync
    {
        let defaults = defaults ?? self.defaults
        let reload: @MainActor () -> Void
        if defaults === self.defaults {
            reload = { [weak self] in self?.reloadStores() }
        } else {
            let stores = (TypeLooks(defaults: defaults), SidebarLayouts(defaults: defaults), SearchLeaveOuts(defaults: defaults))
            reload = {
                stores.0.reload()
                stores.1.reload()
                stores.2.reload()
            }
        }
        let sync = PreferencesSync(
            defaults: defaults, domain: defaults.suite, enabled: true, coalescing: .milliseconds(50), build: build,
            restorePoints: points, unsettled: { [weak self] _ in self?.unsettled ?? [] }, reload: reload)
        sync.attach(copy, library: library, name: { nil })
        await sync.flush()
        return sync
    }

    private func reloadStores() {
        looks.reload()
        sidebar.reload()
        leaveOuts.reload()
        bindings.reload()
    }

    private func look(_ type: String) -> PreferenceUnit { .row(.types, setting: "look", key: type) }
    private func placement(_ type: String) -> PreferenceUnit { .row(.types, setting: "pagePlacements", key: type) }
    private func density(_ place: PlaceView) -> PreferenceUnit { .row(.places, setting: "placeDensity", key: place.storageKey) }
    private func shortcut(_ command: ShortcutCommand) -> PreferenceUnit { .row(.commands, setting: "shortcut", key: command.id) }

    private func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])) ?? Data()
    }

    private func text(_ object: Any) -> String { String(decoding: json(object), as: UTF8.self) }

    /// What this Mac holds of the settings now, as a step reads them.
    private func local(_ defaults: UserDefaults? = nil) -> PreferenceUnits {
        var units: PreferenceUnits = [:]
        for setting in PreferencesMap.synced {
            if case .units(let held) = setting.read(defaults ?? self.defaults, library: library) { units.merge(held) { a, _ in a } }
        }
        return units
    }

    /// What a store set aside, as text, in the order it was set aside.
    private func setAside(_ key: String) -> [String] {
        defaults.stringArray(forKey: key) ?? (defaults.array(forKey: key) as? [Data] ?? []).map { String(decoding: $0, as: UTF8.self) }
    }

    nonisolated private final class Count: @unchecked Sendable {
        var value = 0
    }

    /// How many times the defaults are written while `work` runs; each write asks for another step.
    private func writes(during work: () async -> Void) async -> Int {
        let count = Count()
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: nil) { _ in count.value += 1 }
        await work()
        NotificationCenter.default.removeObserver(observer)
        return count.value
    }

    private func flush(_ sync: PreferencesSync, times: Int = 2) async {
        for _ in 0..<times { await sync.flush() }
    }

    private let created = #"{"date":"created"}"#
    private let edited = #"{"date":"edited"}"#
    private let occurred = #"{"date":"occurred"}"#

    /// The stored looks with Tasks' using a date this build does not know.
    private var damagedLooks: Data { json([library: [note: ["date": "created"], task: ["date": "bogus"]]]) }

    /// Looks for Notes and Tasks synced; then Tasks' stored look uses a date this build does not know, and a store reads
    /// it at launch. `flushing` runs the step that holds the row.
    private func lookSetAside(flushing: Bool = true) async -> (FakePreferencesCopy, String, PreferencesSync) {
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): created, look(task): edited])
        let sync = await sync(copy)
        defaults.set(damagedLooks, forKey: TypeLooks.defaultsKey)
        _ = TypeLooks(defaults: defaults)
        if flushing { await flush(sync) }
        return (copy, item, sync)
    }

    private func changeLook(_ type: String, to date: LookDate) {
        looks.change(TypeID(type), in: library, catalogue: LookFixture.catalogue()) { $0.date = date }
    }

    /// Shortcuts for New Item and Refresh synced; then the stored map holds an entry this build cannot read, so the store
    /// sets the whole of it aside.
    private func shortcutsSetAside(flushing: Bool = true) async throws -> (FakePreferencesCopy, String, PreferencesSync) {
        bindings.set(Shortcut(key: "n", modifiers: [.command, .control]), for: .newItem)
        bindings.set(Shortcut(key: "r", modifiers: [.command, .option]), for: .refresh)
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        let item = try #require(await copy.activeIDs.first)
        try #require(await copy.unitsHeld(item)[shortcut(.newItem)] != nil)
        let bytes = try #require(defaults.data(forKey: ShortcutBindings.defaultsKey))
        var stored = try #require(PreferenceJSON.value(String(decoding: bytes, as: UTF8.self)) as? [String: Any])
        var shortcuts = try #require(stored["shortcuts"] as? [String: Any])
        shortcuts["later.command"] = 42
        stored["shortcuts"] = shortcuts
        defaults.set(json(stored), forKey: ShortcutBindings.defaultsKey)
        bindings.reload()
        try #require(local()[shortcut(.newItem)] == nil)
        if flushing { await flush(sync) }
        return (copy, item, sync)
    }

    /// The JSON a shortcut's row holds.
    private func shortcutText(_ keys: Shortcut, for command: ShortcutCommand) -> String? {
        let other = ThrowawayDefaults.make("MarfaMacTests.PreferenceHolds.shortcut")
        ShortcutBindings(defaults: other).set(keys, for: command)
        return local(other)[shortcut(command)]
    }

    private func browser(showing place: PlaceView) -> Browser {
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let library = FakeItemLibrary(items: [], now: date)
        let browser = Browser()
        browser.defaults = defaults
        browser.adopt(library)
        browser.showing = place
        browser.followPlaceDefault(in: library)
        return browser
    }

    // MARK: The issue: each fails without the hold

    @Test func aLookSetAsideAtLaunchStaysInTheMarfa() async throws {
        let (copy, item, _) = await lookSetAside()
        #expect(await copy.unitsHeld(item)[look(task)] == edited)
        #expect(await copy.unitsHeld(item)[look(note)] == created)
        #expect(local()[look(task)] == nil)
    }

    @Test func aLookSetAsideAfterAnImportStaysInTheMarfa() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): created, look(task): edited])
        let sync = await sync(copy)
        let file = SettingsFile(units: [look(note): created, look(task): #"{"date":"bogus"}"#], build: "", date: .now)
        try await sync.importSettings(file, sections: [SettingsFile.Section(look(task))])
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(task)] == edited)
        #expect(await copy.unitsHeld(item)[look(note)] == created)
    }

    /// One command's entry is damaged, so the store sets the whole map aside: every row stays.
    @Test func shortcutsSetAsideWholeStayInTheMarfa() async throws {
        bindings.set(Shortcut(key: "n", modifiers: [.command, .control]), for: .newItem)
        bindings.set(nil, for: .refresh)
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        let item = try #require(await copy.activeIDs.first)
        let held = await copy.unitsHeld(item)
        let newItem = try #require(held[shortcut(.newItem)])
        #expect(held[shortcut(.refresh)] == "null")
        defaults.set(json(["shortcuts": [ShortcutCommand.newItem.id: 42, ShortcutCommand.refresh.id: NSNull()]]), forKey: ShortcutBindings.defaultsKey)
        bindings.reload()
        await flush(sync)
        #expect(await copy.unitsHeld(item)[shortcut(.newItem)] == newItem)
        #expect(await copy.unitsHeld(item)[shortcut(.refresh)] == "null")
    }

    private let sidebarRows: PreferenceUnits = [
        .row(.sidebar, setting: "layout", key: "hidden"): #"["feed"]"#,
        .row(.sidebar, setting: "layout", key: "order"): #"["library"]"#,
        .row(.sidebar, setting: "color", key: "P"): #""red""#,
    ]

    @Test func aSidebarEntrySetAsideStaysInTheMarfa() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add(sidebarRows)
        let sync = await sync(copy)
        defaults.set(json([library: ["hidden": ["feed"], "order": ["library"], "colors": ["P": "red"], "tabs": 5]]), forKey: SidebarLayouts.defaultsKey)
        sidebar.reload()
        await flush(sync)
        for (unit, value) in sidebarRows { #expect(await copy.unitsHeld(item)[unit] == value) }
    }

    @Test func searchExclusionsSetAsideStayInTheMarfa() async throws {
        let value = #"{"sources":[],"types":["core.note"]}"#
        let copy = FakePreferencesCopy()
        let item = await copy.add([search: value])
        let sync = await sync(copy)
        defaults.set(json([library: ["types": 5]]), forKey: SearchLeaveOuts.defaultsKey)
        leaveOuts.reload()
        await flush(sync)
        #expect(await copy.unitsHeld(item)[search] == value)
    }

    private let unknownDate = #""relative""#

    @Test func aDateFormatSetAsideAtLaunchStaysInTheMarfa() async throws {
        let format = DateFormat(usesWords: false, date: .system, time: .system).rawValue
        let copy = FakePreferencesCopy()
        let item = await copy.add([date: text(format)])
        let sync = await sync(copy)
        #expect(defaults.string(forKey: DateFormat.key) == format)
        defaults.set("relative", forKey: DateFormat.key)
        DateFormat.setAsideUnreadable(in: defaults)
        await flush(sync)
        #expect(await copy.unitsHeld(item)[date] == text(format))
    }

    @Test func aDateFormatSetAsideAfterSwitchingBackStaysInTheMarfa() async throws {
        let one = FakePreferencesCopy()
        let first = await one.add([theme: #""light""#])
        let sync = await sync(one)
        let two = FakePreferencesCopy()
        await two.set(PreferencesReadiness(filled: true, holdsType: true, tablesWhole: true, instance: "instance-2"))
        _ = await two.add([theme: #""dark""#])
        sync.attach(two, library: library, name: { nil })
        await sync.flush()
        await one.change(first, [date: unknownDate])
        sync.attach(one, library: library, name: { nil })
        await sync.flush()
        #expect(defaults.string(forKey: DateFormat.key) == "relative")
        _ = DateFormat.stored(in: defaults)
        await flush(sync)
        #expect(await one.unitsHeld(first)[date] == unknownDate)
    }

    @Test func aDateFormatSetAsideDuringAdoptionStaysInTheMarfa() async throws {
        defaults.set(#"{"core.task":{"pins":["due_at"]}}"#, forKey: PagePlacements.key)
        let copy = FakePreferencesCopy()
        let item = await copy.add([date: unknownDate, theme: #""dark""#])
        await copy.whileWriting { [defaults] in DateFormat.setAsideUnreadable(in: defaults) }
        let sync = await sync(copy)
        #expect(defaults.object(forKey: DateFormat.key) == nil)
        await flush(sync)
        #expect(await copy.unitsHeld(item)[date] == unknownDate)
    }

    @Test func aDateEntryWrittenDuringAStepsReadIsJudgedNextStep() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([theme: #""light""#])
        let sync = await sync(copy)
        await copy.change(item, [date: unknownDate])
        await sync.flush()
        #expect(defaults.string(forKey: DateFormat.key) == "relative")
        await copy.change(item, [theme: #""dark""#])
        await copy.whileReading { [defaults] in DateFormat.setAsideUnreadable(in: defaults) }
        await flush(sync, times: 3)
        #expect(await copy.unitsHeld(item)[date] == unknownDate)
    }

    @Test func aHeldLookKeepsAnotherMacsNewerLook() async throws {
        let (copy, item, sync) = await lookSetAside(flushing: false)
        await copy.change(item, [look(task): occurred])
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(task)] == occurred)
        #expect(local()[look(task)] == nil)
    }

    @Test func twoMacsKeepARowOneOfThemSetsAside() async throws {
        let other = ThrowawayDefaults.make("MarfaMacTests.PreferenceHolds.other")
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): created, look(task): edited])
        let mine = await sync(copy)
        let theirs = await sync(copy, defaults: other)
        other.set(damagedLooks, forKey: TypeLooks.defaultsKey)
        _ = TypeLooks(defaults: other)
        changeLook(note, to: .occurred)
        let changed = try #require(local()[look(note)])
        await flush(mine)
        await flush(theirs)
        await flush(mine)
        #expect(await copy.unitsHeld(item)[look(task)] == edited)
        #expect(await copy.unitsHeld(item)[look(note)] == changed)
        #expect(local(other)[look(note)] == changed)
    }

    /// From #683: a store that sets a library's look aside while the library's earlier name still holds the looks keeps
    /// the row once the name moves.
    @Test func aHoldWaitsWhileItsSettingIsUnsettled() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): created])
        let sync = await sync(copy)
        #expect(defaults.data(forKey: TypeLooks.defaultsKey) != nil)
        unsettled = [TypeLooks.defaultsKey]
        defaults.set(json([library: [note: ["date": "bogus"]]]), forKey: TypeLooks.defaultsKey)
        _ = TypeLooks(defaults: defaults)
        await sync.flush()
        unsettled = []
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(note)] == created)
    }

    // MARK: Decided as the sync decides without the hold: each passes either way

    @Test func aLookChosenOverAHeldRowIsSentOverAnotherMacsLaterLook() async throws {
        let (copy, item, sync) = await lookSetAside()
        await copy.change(item, [look(task): created])
        changeLook(task, to: .occurred)
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(task)] == occurred)
        #expect(local()[look(task)] == occurred)
    }

    @Test func aHeldLookSetAndRestoredTakesAnotherMacsLaterLook() async throws {
        let (copy, item, sync) = await lookSetAside()
        await copy.change(item, [look(task): created])
        changeLook(task, to: .occurred)
        looks.restore(TypeID(task), in: library)
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(task)] == created)
        #expect(local()[look(task)] == created)
    }

    @Test func aHeldRowTakesAnotherMacsLaterChange() async throws {
        let (copy, item, sync) = await lookSetAside()
        await copy.change(item, [look(task): created])
        await flush(sync)
        #expect(local()[look(task)] == created)
        #expect(await copy.unitsHeld(item)[look(task)] == created)
    }

    @Test func aHeldRowIsNotPutBackByAnotherBuild() async throws {
        let (copy, _, sync) = await lookSetAside()
        sync.detach()
        let next = await self.sync(copy, build: "2")
        await flush(next)
        #expect(local()[look(task)] == nil)
    }

    @Test func aHeldRowWaitsWhileItsSettingCannotBeRead() async throws {
        let (copy, item, sync) = await lookSetAside()
        let readable = try #require(defaults.data(forKey: TypeLooks.defaultsKey))
        // Text where the store keeps data: the step cannot read the looks, and no store has read them yet.
        defaults.set(String(decoding: readable, as: UTF8.self), forKey: TypeLooks.defaultsKey)
        await copy.change(item, [look(task): occurred])
        await flush(sync)
        defaults.set(readable, forKey: TypeLooks.defaultsKey)
        looks.reload()
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(task)] == occurred)
        #expect(local()[look(task)] == occurred)
    }

    @Test func aChoiceOverAHeldRowSurvivesARefusedWrite() async throws {
        let (copy, item, sync) = await lookSetAside()
        changeLook(task, to: .occurred)
        await copy.change(item, [look(note): edited])
        await copy.refuseNextWrite(to: .types)
        await sync.flush()
        #expect(local()[look(note)] == edited)
        changeLook(task, to: .created)
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(task)] == created)
        #expect(local()[look(task)] == created)
    }

    @Test func anInterruptedImportTakesAnotherMacsChoice() async throws {
        let (copy, item, sync) = await lookSetAside()
        sync.detach()
        await copy.change(item, [look(task): occurred])
        // An import of Notes' look that stopped after writing the defaults, before the stores read them.
        defaults.set(json([library: [note: ["date": "edited"]]]), forKey: TypeLooks.defaultsKey)
        looks.reload()
        sync.attach(copy, library: library, name: { nil })
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(task)] == occurred)
        #expect(local()[look(task)] == occurred)
    }

    @Test func anInterruptedImportSendsTheImportedDate() async throws {
        let later = #"{"date":"edited","glow":true}"#
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): later])
        let sync = await sync(copy)
        sync.detach()
        // The import wrote Notes' look beside a Tasks look this build cannot read, and stopped before the stores read it.
        defaults.set(damagedLooks, forKey: TypeLooks.defaultsKey)
        _ = TypeLooks(defaults: defaults)
        sync.attach(copy, library: library, name: { nil })
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(note)] == created)
    }

    @Test func anImportedLookTheReloadReencodesIsSent() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): created])
        let sync = await sync(copy)
        let file = SettingsFile(units: [look(note): #"{"date":"edited","glow":true}"#, look(task): #"{"date":"bogus"}"#], build: "", date: .now)
        try await sync.importSettings(file, sections: [SettingsFile.Section(look(note))])
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(note)] == edited)
    }

    @Test func aRemovalBeforeTheDocumentBecameUnreadableIsSent() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([density(.library): #""standard""#, density(.feed): #""compact""#])
        let sync = await sync(copy)
        browser(showing: .feed).changeDensity(nil)
        try #require(local()[density(.feed)] == nil)
        defaults.set(Data(#"{"\#(PlaceView.library.storageKey)":"stan"#.utf8), forKey: PlaceDensities.key)
        PlaceDensities.update(in: defaults) { $0.set(.compact, for: .library) }
        await flush(sync)
        #expect(await copy.unitsHeld(item)[density(.feed)] == nil)
        #expect(await copy.unitsHeld(item)[density(.library)] == #""compact""#)
    }

    /// Codex round 3 finding 9: a held unit is never sent again for a write of this Mac's that lost.
    @Test func aHeldSearchExclusionIsNeverReclaimed() async throws {
        let value = #"{"sources":[],"types":["core.note"]}"#
        let copy = FakePreferencesCopy()
        let item = await copy.add([search: value])
        let sync = await sync(copy)
        await copy.holdNextAnswer()
        leaveOuts.update(library) { $0.types = [TypeID(task)] }
        await flush(sync)
        let write = try #require(await copy.writeIDs.last)
        let mine = try #require(await copy.unitsHeld(item)[search])
        await copy.change(item, [:], removing: [search])
        _ = await copy.add([search: mine], conflicted: true)
        await copy.answer(write, .lost)
        defaults.set(json([library: ["types": 5]]), forKey: SearchLeaveOuts.defaultsKey)
        leaveOuts.reload()
        let writes = await copy.writeIDs.count
        await flush(sync)
        #expect(await copy.unitsHeld(item)[search] == nil)
        #expect(await copy.writeIDs.count == writes)
    }

    /// A person's write that drops what its store cannot read is a separate issue: the row goes, as without the hold.
    @Test func aDensityDroppedByAPersonsWriteIsDeletedAsMainDoes() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([density(.library): #""standard""#, density(.feed): #""compact""#])
        let sync = await sync(copy)
        defaults.set(json([PlaceView.library.storageKey: "standard", PlaceView.feed.storageKey: "spacious"]), forKey: PlaceDensities.key)
        PlaceDensities.update(in: defaults) { $0.set(.compact, for: .library) }
        await flush(sync)
        #expect(await copy.unitsHeld(item)[density(.feed)] == nil)
        #expect(await copy.unitsHeld(item)[density(.library)] == #""compact""#)
    }

    @Test func aHeldShortcutIsNotFilledIntoASecondMarfa() async throws {
        let (_, _, sync) = try await shortcutsSetAside()
        let two = FakePreferencesCopy()
        await two.set(PreferencesReadiness(filled: true, holdsType: true, tablesWhole: true, instance: "instance-2"))
        let second = await two.add([theme: #""dark""#])
        sync.attach(two, library: library, name: { nil })
        await flush(sync)
        #expect(await two.unitsHeld(second)[shortcut(.newItem)] == nil)
        #expect(await two.unitsHeld(second)[shortcut(.refresh)] == nil)
    }

    // MARK: Residuals: each pins a declared difference, and fails without the hold, which deletes the row

    /// Residual 1: an act that leaves a held row as the store left it is not sent.
    @Test func anImportAtPresetOfAHeldLookLeavesTheMarfas() async throws {
        let (copy, item, sync) = await lookSetAside()
        let catalogue = LookFixture.catalogue()
        let resolved = looks.looks(in: catalogue, library: library)
        looks.importLooks(LooksFile(looks: [TypeID(task): try #require(resolved[TypeID(task)])]), into: library, in: catalogue)
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(task)] == edited)
        #expect(local()[look(task)] == nil)
    }

    /// Residual 1: Reset deletes every other look, and leaves the held one in the Marfa.
    @Test func resetLeavesAHeldLookInTheMarfa() async throws {
        let (copy, item, sync) = await lookSetAside()
        MacSettings.reset(in: defaults)
        sync.replaced(PreferencesMap.synced)
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(note)] == nil)
        #expect(await copy.unitsHeld(item)[look(task)] == edited)
        #expect(local()[look(task)] == nil)
    }

    /// Residual 1, in Codex's order: Restore Defaults made while a step reads leaves this Mac at the defaults, and the
    /// Marfa keeps another Mac's shortcut.
    @Test func keyboardRestoreDefaultsDuringAStepsReadKeepsDefaultsHere() async throws {
        let (copy, item, sync) = try await shortcutsSetAside(flushing: false)
        let theirs = try #require(shortcutText(Shortcut(key: "m", modifiers: [.command, .option]), for: .newItem))
        await copy.change(item, [shortcut(.newItem): theirs])
        let bindings = bindings
        await copy.whileReading { bindings.restoreDefaults() }
        await flush(sync)
        #expect(await copy.unitsHeld(item)[shortcut(.newItem)] == theirs)
        #expect(local()[shortcut(.newItem)] == nil)
    }

    /// Residual 2: another Mac's change that brings a held row back to its value at the hold step is not taken.
    @Test func aHeldRowDoesNotTakeAWriteBackToItsHoldTimeValue() async throws {
        let (copy, item, sync) = await lookSetAside()
        await copy.change(item, [look(task): created])
        await copy.change(item, [look(task): edited])
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(task)] == edited)
        #expect(local()[look(task)] == nil)
    }
}
