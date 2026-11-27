import Foundation
import Testing
@testable import MarfaMac

/// The hold list's own rules, the orders in which a step can meet it, and what each store reports through its own entry
/// point. A test writes the list or the record itself only where it stands for a crash or for another build.
@MainActor @Suite(.hangLimit) final class PreferenceHoldsListTests {
    let defaults = ThrowawayDefaults.make("MarfaMacTests.PreferenceHoldsList")
    let points = RestorePoints(folder: URL.temporaryDirectory.appending(path: "PreferenceHoldsListTests-\(UUID().uuidString)"))
    let library = "marfa:https://one"
    lazy var looks = TypeLooks(defaults: defaults)
    lazy var sidebar = SidebarLayouts(defaults: defaults)
    lazy var leaveOuts = SearchLeaveOuts(defaults: defaults)
    lazy var bindings = ShortcutBindings(defaults: defaults)

    let note = "core.note"
    let task = "core.task"
    let theme = PreferenceUnit.member(.appearance, AppearanceKey.theme)
    let date = PreferenceUnit.member(.general, DateFormat.key)
    let search = PreferenceUnit.member(.search, SearchLeaveOuts.defaultsKey)
    let created = #"{"date":"created"}"#
    let edited = #"{"date":"edited"}"#

    deinit {
        try? FileManager.default.removeItem(at: points.folder)
    }

    // MARK: Helpers

    private func sync(_ copy: FakePreferencesCopy) async -> PreferencesSync {
        let sync = PreferencesSync(
            defaults: defaults, domain: defaults.suite, enabled: true, coalescing: .milliseconds(50),
            restorePoints: points, reload: { [weak self] in self?.reloadStores() })
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
    private func density(_ place: PlaceView) -> PreferenceUnit { .row(.places, setting: "placeDensity", key: place.storageKey) }
    private func shortcut(_ command: ShortcutCommand) -> PreferenceUnit { .row(.commands, setting: "shortcut", key: command.id) }

    private func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])) ?? Data()
    }

    private func local() -> PreferenceUnits {
        var units: PreferenceUnits = [:]
        for setting in PreferencesMap.synced {
            if case .units(let held) = setting.read(defaults, library: library) { units.merge(held) { a, _ in a } }
        }
        return units
    }

    private var entries: [PreferenceHolds.Entry] { PreferenceHolds.read(defaults) }

    private var held: Set<PreferenceUnit>? { PreferencesSync.Record.read(defaults).marfas["instance-1"]?.held }

    nonisolated private final class Count: @unchecked Sendable {
        var value = 0
    }

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

    /// The stored looks with Tasks' using a date this build does not know.
    private var damagedLooks: Data { json([library: [note: ["date": "created"], task: ["date": "bogus"]]]) }

    /// Looks for Notes and Tasks synced.
    private func syncedLooks() async -> (FakePreferencesCopy, String, PreferencesSync) {
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): created, look(task): edited])
        let sync = await sync(copy)
        return (copy, item, sync)
    }

    // MARK: Orders and crashes

    /// The store reported, then the app stopped before it wrote: this Mac still holds the row, so nothing is held.
    @Test func aCrashBetweenAnEntryAndItsValueHoldsNothing() async throws {
        let (copy, item, sync) = await syncedLooks()
        PreferenceHolds.willWrite(json([library: [note: ["date": "created"]]]), forKey: TypeLooks.defaultsKey, in: defaults)
        try #require(entries.count == 1)
        await sync.flush()
        #expect(entries.first?.seenPending == true)
        await flush(sync)
        #expect(entries.isEmpty)
        #expect(held == nil)
        #expect(await copy.unitsHeld(item)[look(task)] == edited)
        #expect(local()[look(task)] == edited)
    }

    @Test func aCrashAfterTheRecordSaveRepeatsTheSameHoldStep() async throws {
        let (copy, item, sync) = await syncedLooks()
        defaults.set(damagedLooks, forKey: TypeLooks.defaultsKey)
        looks.reload()
        let list = try #require(defaults.data(forKey: PreferenceHolds.key))
        await flush(sync)
        let record = PreferencesSync.Record.read(defaults)
        #expect(held == [look(task)])
        defaults.set(list, forKey: PreferenceHolds.key)
        await flush(sync)
        #expect(PreferencesSync.Record.read(defaults) == record)
        #expect(await copy.unitsHeld(item)[look(task)] == edited)
        #expect(entries.isEmpty)
    }

    @Test func aStepThatThrowsKeepsItsEntries() async throws {
        let (copy, item, sync) = await syncedLooks()
        defaults.set(json([library: [note: ["date": "edited"], task: ["date": "bogus"]]]), forKey: TypeLooks.defaultsKey)
        await copy.refuseNextWrite(to: .types)
        looks.reload()
        let written = entries
        try #require(written.count == 1)
        await sync.flush()
        #expect(entries == written)
        await flush(sync)
        #expect(entries.isEmpty)
        #expect(await copy.unitsHeld(item)[look(task)] == edited)
        #expect(await copy.unitsHeld(item)[look(note)] == edited)
    }

    @Test func aSwitchDropsEntriesAndClearsHeld() async throws {
        let (one, first, sync) = await syncedLooks()
        defaults.set(damagedLooks, forKey: TypeLooks.defaultsKey)
        looks.reload()
        await flush(sync)
        try #require(held == [look(task)])
        sync.detach()
        defaults.set("relative", forKey: DateFormat.key)
        DateFormat.setAsideUnreadable(in: defaults)
        try #require(!entries.isEmpty)
        let two = FakePreferencesCopy()
        await two.set(PreferencesReadiness(filled: true, holdsType: true, tablesWhole: true, instance: "instance-2"))
        _ = await two.add([theme: #""dark""#])
        sync.attach(two, library: library, name: { nil })
        await sync.flush()
        #expect(entries.isEmpty)
        sync.attach(one, library: library, name: { nil })
        await sync.flush()
        #expect(held == nil)
        #expect(await one.unitsHeld(first)[look(task)] == edited)
        #expect(local()[look(task)] == edited)
    }

    /// An earlier build drops `held` when it saves the record, and then sends the removal as it always did.
    @Test func anEarlierBuildsRecordWithoutHeldBehavesAsMain() async throws {
        let (copy, item, sync) = await syncedLooks()
        defaults.set(damagedLooks, forKey: TypeLooks.defaultsKey)
        looks.reload()
        await flush(sync)
        try #require(held == [look(task)])
        let saved = try #require(defaults.data(forKey: PreferencesSync.recordKey))
        var object = try #require(try JSONSerialization.jsonObject(with: saved) as? [String: Any])
        var marfas = try #require(object["marfas"] as? [String: Any])
        var adopted = try #require(marfas["instance-1"] as? [String: Any])
        adopted["held"] = nil
        marfas["instance-1"] = adopted
        object["marfas"] = marfas
        defaults.set(json(object), forKey: PreferencesSync.recordKey)
        #expect(held == nil)
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(task)] == nil)
        #expect(await copy.unitsHeld(item)[look(note)] == created)
    }

    @Test func entriesForAnotherLibraryAreDropped() async throws {
        let (copy, item, sync) = await syncedLooks()
        let stored = try #require(defaults.data(forKey: TypeLooks.defaultsKey))
        var libraries = try #require(try JSONSerialization.jsonObject(with: stored) as? [String: Any])
        libraries["marfa:https://two"] = [task: ["date": "bogus"]]
        defaults.set(json(libraries), forKey: TypeLooks.defaultsKey)
        looks.reload()
        try #require(entries.contains { $0.library == "marfa:https://two" })
        await flush(sync)
        #expect(entries.isEmpty)
        #expect(held == nil)
        #expect(await copy.unitsHeld(item)[look(task)] == edited)
        #expect(local()[look(task)] == edited)
    }

    @Test func anUnreadableListIsEmpty() async throws {
        let (copy, item, sync) = await syncedLooks()
        defaults.set(Data("not a list".utf8), forKey: PreferenceHolds.key)
        #expect(entries.isEmpty)
        defaults.set("dark", forKey: AppearanceKey.theme)
        await flush(sync)
        #expect(await copy.unitsHeld(item)[theme] == #""dark""#)
        #expect(held == nil)
    }

    @Test func anEqualEntryReplacesTheListedOneAndMovesToTheEnd() throws {
        defaults.set(damagedLooks, forKey: TypeLooks.defaultsKey)
        PreferenceHolds.willWrite(json([library: [note: ["date": "created"]]]), forKey: TypeLooks.defaultsKey, in: defaults)
        let first = try #require(entries.first)
        defaults.set("relative", forKey: DateFormat.key)
        DateFormat.setAsideUnreadable(in: defaults)
        PreferenceHolds.willWrite(json([library: [note: ["date": "created"]]]), forKey: TypeLooks.defaultsKey, in: defaults)
        #expect(entries.map(\.unit) == [date, look(task)])
        #expect(entries.last?.id != first.id)
    }

    @Test func aStepWithOnlyHeldUnitsWritesNothingAfterItsFirst() async throws {
        let (copy, item, sync) = await syncedLooks()
        defaults.set(damagedLooks, forKey: TypeLooks.defaultsKey)
        looks.reload()
        await flush(sync, times: 3)
        let count = await writes {
            for _ in 0..<4 { await sync.flush() }
        }
        #expect(count == 0)
        #expect(await copy.unitsHeld(item)[look(task)] == edited)
    }

    // MARK: Store reports: each of the five sources, through its own entry point

    private func reading(_ key: String, _ stored: Any?, library: String = "") -> PreferenceUnits {
        guard let setting = PreferencesMap.synced.first(where: { $0.key == key }),
              case .units(let units) = setting.read(stored: stored, library: library)
        else { return [:] }
        return units
    }

    @Test func looksReportOnlyTheRowsTheyCannotRead() {
        let stored = json([library: [note: ["date": "edited", "later": true], task: ["date": "bogus"]]])
        defaults.set(stored, forKey: TypeLooks.defaultsKey)
        _ = TypeLooks(defaults: defaults)
        #expect(entries.map(\.unit) == [look(task)])
        #expect(entries.first?.library == library)
        #expect(entries.first?.before == reading(TypeLooks.defaultsKey, stored, library: library)[look(task)])
    }

    @Test func looksThatCannotBeSplitReportNothing() {
        defaults.set(Data("[1]".utf8), forKey: TypeLooks.defaultsKey)
        _ = TypeLooks(defaults: defaults)
        #expect(entries.isEmpty)
    }

    @Test func aSidebarReportsTheRowsOfTheEntryItCannotRead() {
        let stored = json([library: ["hidden": ["feed"], "order": ["library"], "colors": ["P": "red"], "tabs": 5]])
        defaults.set(stored, forKey: SidebarLayouts.defaultsKey)
        sidebar.reload()
        #expect(Set(entries.map(\.unit)) == Set(reading(SidebarLayouts.defaultsKey, stored, library: library).keys))
        #expect(!entries.isEmpty)
    }

    @Test func aSidebarThatCannotBeSplitReportsNothing() {
        defaults.set(Data("[1]".utf8), forKey: SidebarLayouts.defaultsKey)
        sidebar.reload()
        #expect(entries.isEmpty)
    }

    @Test func searchExclusionsReportTheMemberTheyCannotRead() {
        defaults.set(json([library: ["types": 5]]), forKey: SearchLeaveOuts.defaultsKey)
        leaveOuts.reload()
        #expect(entries.map(\.unit) == [search])
    }

    @Test func searchExclusionsThatCannotBeSplitReportNothing() {
        defaults.set(Data("[1]".utf8), forKey: SearchLeaveOuts.defaultsKey)
        leaveOuts.reload()
        #expect(entries.isEmpty)
    }

    @Test func shortcutsReportEveryRowOfTheMapTheySetAside() {
        let stored = json(["shortcuts": [ShortcutCommand.newItem.id: 42, ShortcutCommand.refresh.id: NSNull()]])
        defaults.set(stored, forKey: ShortcutBindings.defaultsKey)
        bindings.reload()
        #expect(Set(entries.map(\.unit)) == [shortcut(.newItem), shortcut(.refresh)])
    }

    @Test func shortcutsThatCannotBeSplitReportNothing() {
        defaults.set(Data("[1]".utf8), forKey: ShortcutBindings.defaultsKey)
        bindings.reload()
        #expect(entries.isEmpty)
    }

    @Test func theDateFormatReportsTheWordItCannotRead() {
        defaults.set("relative", forKey: DateFormat.key)
        DateFormat.setAsideUnreadable(in: defaults)
        #expect(entries.map(\.unit) == [date])
        #expect(entries.first?.before == #""relative""#)
        #expect(entries.first?.library == nil)
    }

    @Test func aReadableDateFormatReportsNothing() {
        defaults.set(DateFormat.standard.rawValue, forKey: DateFormat.key)
        _ = DateFormat.stored(in: defaults)
        #expect(entries.isEmpty)
    }

    /// Every other writer, and the five stores' own writes for the person, report nothing, even over what they cannot read.
    @Test func noPersonsWriteRecordsAnEntry() {
        let catalogue = LookFixture.catalogue()
        defaults.set(json([library: [note: ["date": "edited"]]]), forKey: TypeLooks.defaultsKey)
        looks.reload()
        looks.change(TypeID(note), in: library, catalogue: catalogue) { $0.date = .created }
        looks.restore(TypeID(note), in: library)
        leaveOuts.update(library) { $0.types = [TypeID(task)] }
        leaveOuts.update(library) { $0.types = [] }
        sidebar.update(library) { $0.showTypesSection() }
        bindings.set(Shortcut(key: "n", modifiers: [.command, .control]), for: .newItem)
        bindings.restoreDefaults()
        defaults.set(json([PlaceView.library.storageKey: "standard", PlaceView.feed.storageKey: "spacious"]), forKey: PlaceDensities.key)
        PlaceDensities.update(in: defaults) { $0.set(.compact, for: .library) }
        defaults.set(json(["bad": 5]), forKey: PlaceDefaults.key)
        PlaceDefaults.update(in: defaults) { $0.set(nil, for: .feed) }
        defaults.set(json(["bad": 5]), forKey: ViewOrders.key)
        ViewOrders.update(in: defaults) { _ in }
        defaults.set(#"{"bad":5}"#, forKey: ViewLayouts.key)
        ViewLayouts.update(in: defaults) { _ in }
        defaults.set("[1]", forKey: PagePlacements.key)
        PagePlacements.update(in: defaults) { _ in }
        defaults.set("[1]", forKey: PanelParts.key)
        PanelParts.choose(.links, for: TypeID(note), in: defaults)
        defaults.set("dark", forKey: AppearanceKey.theme)
        defaults.set(DateFormat.standard.rawValue, forKey: DateFormat.key)
        MacSettings.reset(in: defaults)
        #expect(entries.isEmpty)
    }
}
