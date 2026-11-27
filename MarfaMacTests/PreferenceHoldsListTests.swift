import Foundation
import Testing
@testable import MarfaMac

/// The hold list's own rules, the orders in which a step can meet it, and what each store reports through its own entry
/// points. A test writes the list itself only where it stands for a crash or for another build.
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
    let search = PreferenceUnit.member(.search, SearchLeaveOuts.defaultsKey)
    let compact = #""compact""#
    let spacious = #""spacious""#
    let created = #"{"date":"created"}"#
    let edited = #"{"date":"edited"}"#

    deinit {
        try? FileManager.default.removeItem(at: points.folder)
    }

    // MARK: Helpers

    private func sync(_ copy: FakePreferencesCopy, build: String = PreferencesSync.appBuild) async -> PreferencesSync {
        let sync = PreferencesSync(
            defaults: defaults, domain: defaults.suite, enabled: true, coalescing: .milliseconds(50), build: build,
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
    private func placement(_ type: String) -> PreferenceUnit { .row(.types, setting: "pagePlacements", key: type) }
    private func panelPart(_ type: String) -> PreferenceUnit { .row(.types, setting: "panelPart", key: type) }
    private func density(_ place: PlaceView) -> PreferenceUnit { .row(.places, setting: "placeDensity", key: place.storageKey) }
    private func placeDefault(_ key: String) -> PreferenceUnit { .row(.places, setting: "placeDefaults", key: key) }
    private func viewOrder(_ key: String) -> PreferenceUnit { .row(.places, setting: "viewOrder", key: key) }
    private func layout(_ member: String) -> PreferenceUnit { .row(.sidebar, setting: "layout", key: member) }
    private func shortcut(_ command: ShortcutCommand) -> PreferenceUnit { .row(.commands, setting: "shortcut", key: command.id) }
    private func viewLayout(_ id: String) -> PreferenceUnit { .row(.views, setting: "viewLayout", key: id) }

    private func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])) ?? Data()
    }

    private func text(_ object: Any) -> String { String(decoding: json(object), as: UTF8.self) }

    private func local() -> PreferenceUnits {
        var units: PreferenceUnits = [:]
        for setting in PreferencesMap.synced {
            if case .units(let held) = setting.read(defaults, library: library) { units.merge(held) { a, _ in a } }
        }
        return units
    }

    private var entries: [PreferenceHolds.Entry] { PreferenceHolds.read(defaults).entries }

    /// The units the list holds, one for each unit entry.
    private var heldUnits: [PreferenceUnit] {
        entries.compactMap { if case .unit(let unit, _, _, _) = $0.kind { unit } else { nil } }
    }

    private var releases: [PreferenceUnit: String?] {
        var found: [PreferenceUnit: String?] = [:]
        for entry in entries { if case .release(let unit, let value) = entry.kind { found[unit] = value } }
        return found
    }

    private func frozen(_ unit: PreferenceUnit) -> PreferencesSync.Record.Frozen? {
        PreferencesSync.Record.read(defaults).marfas["instance-1"]?.frozen[unit]
    }

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

    /// The Library and Feed densities synced, Feed in a word this build does not know.
    private func densities() async -> (FakePreferencesCopy, String, PreferencesSync) {
        let copy = FakePreferencesCopy()
        let item = await copy.add([density(.library): compact, density(.feed): spacious])
        let sync = await sync(copy)
        return (copy, item, sync)
    }

    private func entry(_ key: String, _ kind: PreferenceHolds.Entry.Kind, library: String? = nil) -> PreferenceHolds.Entry {
        PreferenceHolds.Entry(key: key, library: library, build: "1", kind: kind)
    }

    // MARK: D. Orders and crashes

    @Test func aCrashBetweenAHoldAndItsValueHoldsNothing() async throws {
        let (copy, item, sync) = await densities()
        #expect(local()[density(.feed)] == spacious)
        let value = json([PlaceView.library.storageKey: "standard"])
        PreferenceHolds.willWrite(value, forKey: PlaceDensities.key, in: defaults,
                                  by: .person(dropped: .entries([PlaceView.feed.storageKey]), addressed: []))
        await sync.flush()
        #expect(frozen(density(.feed)) == nil)
        #expect(await copy.unitsHeld(item)[density(.feed)] == spacious)
        #expect(await copy.unitsHeld(item)[density(.library)] == compact)
        await flush(sync, times: 3)
        #expect(entries.isEmpty)
        #expect(frozen(density(.feed)) == nil)
        PlaceDensities.update(in: defaults) { $0.set(.standard, for: .library) }
        await flush(sync)
        #expect(frozen(density(.feed))?.reported == true)
        #expect(await copy.unitsHeld(item)[density(.feed)] == spacious)
        #expect(await copy.unitsHeld(item)[density(.library)] == #""standard""#)
    }

    @Test func aStepThatThrowsAfterJudgingKeepsItsEntries() async throws {
        let (copy, item, sync) = await densities()
        await copy.refuseNextWrite(to: .places)
        PlaceDensities.update(in: defaults) { $0.set(.standard, for: .library) }
        await sync.flush()
        await flush(sync, times: 3)
        #expect(frozen(density(.feed))?.reported == true)
        #expect(await copy.unitsHeld(item)[density(.feed)] == spacious)
        #expect(await copy.unitsHeld(item)[density(.library)] == #""standard""#)
    }

    @Test func aCrashAfterTheRecordSaveReappliesTheSameFreeze() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): created, look(task): edited])
        let sync = await sync(copy)
        defaults.set(json([library: [note: ["date": "created"], task: ["date": "bogus"]]]), forKey: TypeLooks.defaultsKey)
        looks.reload()
        let list = try #require(defaults.data(forKey: PreferenceHolds.key))
        await flush(sync)
        let record = PreferencesSync.Record.read(defaults)
        #expect(frozen(look(task))?.reported == true)
        defaults.set(list, forKey: PreferenceHolds.key)
        await flush(sync)
        #expect(PreferencesSync.Record.read(defaults) == record)
        #expect(await copy.unitsHeld(item)[look(task)] == edited)
        #expect(entries.isEmpty)
    }

    @Test func aSwitchDropsTheEntriesItRead() async throws {
        let one = FakePreferencesCopy()
        _ = await one.add([look(note): created, look(task): edited])
        let sync = await sync(one)
        sync.detach()
        defaults.set(json([library: [note: ["date": "created"], task: ["date": "bogus"]]]), forKey: TypeLooks.defaultsKey)
        looks.reload()
        let written = Set(entries.map(\.id))
        try #require(!written.isEmpty)
        let two = FakePreferencesCopy()
        await two.set(PreferencesReadiness(filled: true, holdsType: true, tablesWhole: true, instance: "instance-2"))
        _ = await two.add([theme: #""dark""#])
        sync.attach(two, library: library, name: { nil })
        await sync.flush()
        #expect(Set(entries.map(\.id)).isDisjoint(with: written))
    }

    @Test func anEntryWrittenDuringASwitchIsKept() async throws {
        let one = FakePreferencesCopy()
        _ = await one.add([theme: #""light""#])
        let sync = await sync(one)
        let two = FakePreferencesCopy()
        await two.set(PreferencesReadiness(filled: true, holdsType: true, tablesWhole: true, instance: "instance-2"))
        _ = await two.add([theme: #""dark""#])
        await two.whileReading { [defaults] in
            defaults.set("relative", forKey: DateFormat.key)
            DateFormat.setAsideUnreadable(in: defaults)
        }
        sync.attach(two, library: library, name: { nil })
        await sync.flush()
        #expect(entries.contains { $0.key == DateFormat.key })
    }

    @Test func aStaleEntryAfterAnEarlierBuildSentTheRowHoldsNothing() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): created, look(task): edited])
        let sync = await sync(copy)
        defaults.set(json([library: [note: ["date": "created"], task: ["date": "bogus"]]]), forKey: TypeLooks.defaultsKey)
        looks.reload()
        let list = try #require(defaults.data(forKey: PreferenceHolds.key))
        // An earlier build, which reads no list, sends the removal.
        defaults.removeObject(forKey: PreferenceHolds.key)
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(task)] == nil)
        defaults.set(list, forKey: PreferenceHolds.key)
        await flush(sync)
        #expect(frozen(look(task)) == nil)
        #expect(await copy.unitsHeld(item)[look(task)] == nil)
        #expect(entries.isEmpty)
    }

    @Test func aPendingUnitNeverFreezesALaterRemoval() async throws {
        let (copy, item, sync) = await densities()
        PreferenceHolds.willWrite(json([PlaceView.library.storageKey: "compact"]), forKey: PlaceDensities.key, in: defaults,
                                  by: .person(dropped: .entries([PlaceView.feed.storageKey]), addressed: []))
        await flush(sync, times: 3)
        PlaceDensities.update(in: defaults, addressing: [PlaceView.feed.storageKey]) { $0.set(nil, for: .feed) }
        await flush(sync)
        #expect(await copy.unitsHeld(item)[density(.feed)] == nil)
        #expect(await copy.unitsHeld(item)[density(.library)] == compact)
        #expect(frozen(density(.feed)) == nil)
    }

    @Test func aStepWithOnlyHeldUnitsWritesNothingAfterItsFirst() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): created, look(task): edited])
        let sync = await sync(copy)
        defaults.set(json([library: [note: ["date": "created"], task: ["date": "bogus"]]]), forKey: TypeLooks.defaultsKey)
        looks.reload()
        await flush(sync, times: 3)
        let count = await writes {
            for _ in 0..<4 { await sync.flush() }
        }
        #expect(count == 0)
        #expect(await copy.unitsHeld(item)[look(task)] == edited)
    }

    @Test func aFrozenUnitUnderAnImportTakesTheMarfasNewerValue() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): created, look(task): edited])
        let sync = await sync(copy)
        defaults.set(json([library: [note: ["date": "created"], task: ["date": "bogus"]]]), forKey: TypeLooks.defaultsKey)
        looks.reload()
        await flush(sync)
        let file = SettingsFile(units: [look(note): edited], build: "", date: .now)
        try await sync.importSettings(file, sections: [SettingsFile.Section(look(note))])
        await copy.change(item, [look(task): created])
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(task)] == created)
        #expect(local()[look(task)] == created)
        #expect(await copy.unitsHeld(item)[look(note)] == edited)
    }

    /// A record an earlier build saved has no `reported`, so its freezes stay its own; one this build saved reads back
    /// as it was written.
    @Test func anEarlierBuildsRecordKeepsAReportedFreezeAsAFreeze() throws {
        var record = PreferencesSync.Record()
        record.marfas["instance-1"] = .init(item: "item-1", base: [look(task): edited])
        record.marfas["instance-1"]?.frozen[look(task)] = .init(left: nil, reported: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let saved = String(decoding: try encoder.encode(record), as: UTF8.self)
        try #require(saved.contains(#""reported":true"#))
        let reread = try JSONDecoder().decode(PreferencesSync.Record.self, from: Data(saved.utf8))
        #expect(reread.marfas["instance-1"]?.frozen[look(task)]?.reported == true)
        let earlier = saved.replacingOccurrences(of: #","reported":true"#, with: "").replacingOccurrences(of: #""reported":true,"#, with: "")
            .replacingOccurrences(of: #""reported":true"#, with: "")
        let plain = try JSONDecoder().decode(PreferencesSync.Record.self, from: Data(earlier.utf8))
        #expect(plain.marfas["instance-1"]?.frozen[look(task)] == .init(left: nil))
    }

    @Test func entriesForAnotherLibraryAreDropped() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): created, look(task): edited])
        let sync = await sync(copy)
        let stored = try #require(defaults.data(forKey: TypeLooks.defaultsKey))
        var libraries = try #require(try JSONSerialization.jsonObject(with: stored) as? [String: Any])
        libraries["marfa:https://two"] = [task: ["date": "bogus"]]
        defaults.set(json(libraries), forKey: TypeLooks.defaultsKey)
        looks.reload()
        try #require(entries.contains { $0.library == "marfa:https://two" })
        await flush(sync)
        #expect(!entries.contains { $0.library == "marfa:https://two" })
        #expect(frozen(look(task)) == nil)
        #expect(await copy.unitsHeld(item)[look(task)] == edited)
        #expect(local()[look(task)] == edited)
    }

    @Test func anEqualEntryGetsANewIDAndMovesToTheEnd() {
        var list = PreferenceHolds.List()
        let whole = entry(TypeLooks.defaultsKey, .whole(left: [:], except: []))
        list.append(whole)
        list.append(entry(PlaceDensities.key, .unit(density(.feed), before: spacious, left: nil, seenPending: false)))
        let again = entry(TypeLooks.defaultsKey, .whole(left: [:], except: []))
        list.append(again)
        #expect(list.entries.map(\.key) == [PlaceDensities.key, TypeLooks.defaultsKey])
        #expect(list.entries.last?.id == again.id)
        #expect(list.watched == [TypeLooks.defaultsKey, PlaceDensities.key])
    }

    @Test func aRepeatedReleaseMovesToTheEndAndKeepsOnlyTheLatest() {
        var list = PreferenceHolds.List()
        list.append(entry(PlaceDensities.key, .release(density(.library), value: compact)))
        list.append(entry(PlaceDensities.key, .unit(density(.feed), before: spacious, left: nil, seenPending: false)))
        list.append(entry(PlaceDensities.key, .release(density(.library), value: #""standard""#)))
        #expect(list.entries.count == 2)
        #expect(list.entries.last?.kind == .release(density(.library), value: #""standard""#))
    }

    @Test func aDropThenAFillComposeIntoOneEntry() {
        var list = PreferenceHolds.List()
        list.append(entry(SidebarLayouts.defaultsKey, .unit(layout("hidden"), before: #"["feed"]"#, left: nil, seenPending: false), library: library))
        list.append(entry(SidebarLayouts.defaultsKey, .unit(layout("hidden"), before: nil, left: "[]", seenPending: false), library: library))
        #expect(list.entries.map(\.kind) == [.unit(layout("hidden"), before: #"["feed"]"#, left: "[]", seenPending: false)])
        list.append(entry(SidebarLayouts.defaultsKey, .unit(layout("hidden"), before: #"["own"]"#, left: nil, seenPending: false), library: library))
        #expect(list.entries.map(\.kind) == [.unit(layout("hidden"), before: #"["own"]"#, left: nil, seenPending: false)])
    }

    /// The Marfa holds a row the base lacks, and the store fills it with no earlier drop: the fill holds nothing.
    @Test func aStandaloneFillIsAppliedOnlyByAChain() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([layout("hidden"): #"["feed"]"#, layout("order"): #"["library"]"#])
        let sync = await sync(copy)
        try #require(local()[layout("collapsed")] == nil)
        await copy.change(item, [layout("collapsed"): #"["type:core.task"]"#])
        sidebar.update(library) { $0.setHidden(.type(task), true) }
        try #require(heldUnits.contains(layout("collapsed")))
        await flush(sync)
        #expect(frozen(layout("collapsed")) == nil)
    }

    @Test func aSwitchBackFindsItsKeysWatched() async throws {
        let one = FakePreferencesCopy()
        _ = await one.add([look(note): created, look(task): edited])
        let sync = await sync(one)
        defaults.set(json([library: [note: ["date": "created"], task: ["date": "bogus"]]]), forKey: TypeLooks.defaultsKey)
        looks.reload()
        await flush(sync)
        let two = FakePreferencesCopy()
        await two.set(PreferencesReadiness(filled: true, holdsType: true, tablesWhole: true, instance: "instance-2"))
        _ = await two.add([theme: #""dark""#])
        sync.attach(two, library: library, name: { nil })
        await flush(sync)
        #expect(PreferenceHolds.read(defaults).watched.contains(TypeLooks.defaultsKey))
    }

    @Test func manyWritesWithNoStepKeepTheListSmall() {
        for index in 0..<50 {
            defaults.set(json([PlaceView.library.storageKey: "compact", PlaceView.feed.storageKey: "spacious"]), forKey: PlaceDensities.key)
            PlaceDensities.update(in: defaults) { $0.set(index.isMultiple(of: 2) ? .standard : nil, for: .library) }
        }
        #expect(entries.count <= 2)
    }

    // MARK: C. A freeze the Marfa changes

    @Test func aReportedFreezeTheMarfaChangesBecomesPlain() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): created, look(task): edited])
        let sync = await sync(copy)
        defaults.set(json([library: [note: ["date": "created"], task: ["date": "bogus"]]]), forKey: TypeLooks.defaultsKey)
        looks.reload()
        await flush(sync)
        #expect(frozen(look(task))?.reported == true)
        await copy.change(item, [look(task): #"{"date":"other"}"#])
        await flush(sync)
        #expect(frozen(look(task)).map { $0.reported == nil } ?? true)
        #expect(await copy.unitsHeld(item)[look(task)] == #"{"date":"other"}"#)
    }

    // MARK: E. Store reports through each entry point

    @Test func densitiesHoldOnlyWhatTheyDropped() {
        defaults.set(json([PlaceView.library.storageKey: "compact", PlaceView.feed.storageKey: "spacious"]), forKey: PlaceDensities.key)
        PlaceDensities.update(in: defaults) { $0.set(.standard, for: .library) }
        #expect(heldUnits == [density(.feed)])
        #expect(entries.first?.kind == .unit(density(.feed), before: spacious, left: nil, seenPending: false))
    }

    @Test func densitiesNeverHoldAPersonsRemovalOfAReadableEntry() {
        defaults.set(json([PlaceView.library.storageKey: "compact", PlaceView.feed.storageKey: "spacious"]), forKey: PlaceDensities.key)
        PlaceDensities.update(in: defaults) { $0.set(nil, for: .library) }
        #expect(heldUnits == [density(.feed)])
    }

    @Test func densitiesReleaseWhatTheyChangeWhenWatched() {
        defaults.set(json([PlaceView.library.storageKey: "compact", PlaceView.feed.storageKey: "spacious"]), forKey: PlaceDensities.key)
        PlaceDensities.update(in: defaults) { $0.set(.standard, for: .library) }
        PlaceDensities.update(in: defaults) { $0.set(.compact, for: .library) }
        #expect(heldUnits == [density(.feed)])
        #expect(releases[density(.library)] == compact)
    }

    /// Reset View on a place this Mac cannot read removes its row: the place it addresses is released, never held.
    @Test func resetViewReleasesWhatItAddresses() {
        defaults.set(json([PlaceView.library.storageKey: "spacious", PlaceView.feed.storageKey: "spacious"]), forKey: PlaceDensities.key)
        PlaceDensities.update(in: defaults, addressing: [PlaceView.library.storageKey]) { $0.set(nil, for: .library) }
        #expect(heldUnits == [density(.feed)])
        #expect(releases[density(.library)] == .some(nil))
    }

    @Test func placeDefaultsHoldOnlyWhatTheyDropped() {
        defaults.set(json(["later-place": 5]), forKey: PlaceDefaults.key)
        PlaceDefaults.update(in: defaults) { $0.set(nil, for: .feed) }
        #expect(heldUnits == [placeDefault("later-place")])
    }

    @Test func viewOrdersHoldOnlyWhatTheyDropped() {
        defaults.set(json(["later-place": 5]), forKey: ViewOrders.key)
        ViewOrders.update(in: defaults) { $0.set([.favorites, .own], in: .library) }
        #expect(heldUnits == [viewOrder("later-place")])
    }

    @Test func viewLayoutsHoldEveryOtherViewWhenTheDocumentIsUnreadable() throws {
        ViewLayouts.update(in: defaults) { layouts in
            for id in ["v1", "v2"] { layouts.set(ViewMacSettings(), for: ItemID(id)) }
        }
        let stored = try #require(defaults.string(forKey: ViewLayouts.key))
        var document = try #require(PreferenceJSON.value(stored) as? [String: Any])
        document["v3"] = 5
        defaults.set(text(document), forKey: ViewLayouts.key)
        ViewLayouts.update(in: defaults) { layouts in
            var settings = ViewMacSettings()
            settings.hidesEmptyGroups = true
            layouts.set(settings, for: ItemID("v1"))
        }
        #expect(Set(heldUnits) == [viewLayout("v2"), viewLayout("v3")])
    }

    @Test func forgettingAViewNeverHoldsIt() throws {
        ViewLayouts.update(in: defaults) { layouts in
            for id in ["v1", "v2"] { layouts.set(ViewMacSettings(), for: ItemID(id)) }
        }
        let stored = try #require(defaults.string(forKey: ViewLayouts.key))
        var document = try #require(PreferenceJSON.value(stored) as? [String: Any])
        document["v3"] = 5
        defaults.set(text(document), forKey: ViewLayouts.key)
        let browser = Browser()
        browser.defaults = defaults
        browser.forgetView(ItemID("v1"))
        #expect(Set(heldUnits) == [viewLayout("v2"), viewLayout("v3")])
    }

    @Test func pagePlacementsHoldTheWholeOfADocumentThatIsNoObject() {
        defaults.set("[]", forKey: PagePlacements.key)
        PagePlacements.update(in: defaults) { $0.setPins(["starts_at"], of: TypeID(note)) }
        #expect(entries.count == 1)
        guard case .whole(_, let except)? = entries.first?.kind else {
            Issue.record("Expected a whole hold")
            return
        }
        #expect(except == [placement(note)])
    }

    @Test func panelPartsHoldTheWholeOfADocumentThatIsNoObject() {
        defaults.set("[1]", forKey: PanelParts.key)
        PanelParts.choose(.links, for: TypeID(note), in: defaults)
        guard case .whole(_, let except)? = entries.first?.kind else {
            Issue.record("Expected a whole hold")
            return
        }
        #expect(except == [panelPart(note)])
    }

    @Test func panelPartsHoldNothingForTheRowThePersonChooses() {
        defaults.set(text([note: ["part": "later"]]), forKey: PanelParts.key)
        PanelParts.choose(.links, for: TypeID(note), in: defaults)
        #expect(heldUnits.isEmpty)
    }

    @Test func aPersonsChangeToASyncedLookWritesNoHold() {
        looks.change(TypeID(note), in: library, catalogue: LookFixture.catalogue()) { $0.date = .occurred }
        looks.change(TypeID(task), in: library, catalogue: LookFixture.catalogue()) { $0.date = .edited }
        looks.restore(TypeID(task), in: library)
        #expect(entries.isEmpty)
    }

    @Test func aPersonsChangeToASyncedShortcutWritesNoHold() {
        bindings.set(Shortcut(key: "n", modifiers: [.command, .control]), for: .newItem)
        bindings.restoreDefaults()
        #expect(entries.isEmpty)
    }

    @Test func aPersonsChangeToSyncedSearchExclusionsWritesNoHold() {
        leaveOuts.update(library) { $0.types = [TypeID(note)] }
        leaveOuts.update(library) { $0.types = [] }
        #expect(entries.isEmpty)
    }

    @Test func aPersonsChangeToASidebarTheStoreWroteWritesNoHold() {
        sidebar.update(library) { $0.setCollapsed(.type(note), true) }
        defaults.removeObject(forKey: PreferenceHolds.key)
        sidebar.update(library) { $0.setCollapsed(.type(task), true) }
        #expect(heldUnits.isEmpty)
    }

    @Test func looksNeverWriteAStoreEntryFromAPersonsPath() {
        defaults.set(json([library: [note: ["date": "created"], task: ["date": "bogus"]]]), forKey: TypeLooks.defaultsKey)
        looks.reload()
        let before = entries.count
        looks.change(TypeID(note), in: library, catalogue: LookFixture.catalogue()) { $0.date = .occurred }
        looks.restore(TypeID(note), in: library)
        let onlyReleases = entries.dropFirst(before).allSatisfy { $0.isRelease }
        #expect(onlyReleases)
    }

    @Test func shortcutsNeverWriteAStoreEntryFromAPersonsPath() {
        defaults.set(json(["shortcuts": [ShortcutCommand.newItem.id: 42]]), forKey: ShortcutBindings.defaultsKey)
        bindings.reload()
        let before = entries.count
        bindings.set(Shortcut(key: "r", modifiers: [.command, .option]), for: .refresh)
        if let keys = ShortcutCommand.refresh.defaultShortcut { bindings.replace(keys, for: .newItem) }
        _ = bindings.apply([ShortcutCommand.newItem.id: ShortcutCommand.newItem.defaultShortcut])
        bindings.restoreDefaults()
        #expect(entries.count > before)
        let onlyReleases = entries.dropFirst(before).allSatisfy { $0.isRelease }
        #expect(onlyReleases)
        #expect(releases[shortcut(.newItem)] != nil)
        #expect(releases[shortcut(.refresh)] != nil)
    }

    @Test func searchExclusionsNeverWriteAStoreEntryFromAPersonsPath() {
        defaults.set(json([library: ["types": 5]]), forKey: SearchLeaveOuts.defaultsKey)
        leaveOuts.reload()
        let before = entries.count
        leaveOuts.update(library) { $0.types = [TypeID(note)] }
        let onlyReleases = entries.dropFirst(before).allSatisfy { $0.isRelease }
        #expect(onlyReleases)
    }

    @Test func theFastPathWritesNoList() {
        PlaceDensities.update(in: defaults) { $0.set(.standard, for: .library) }
        ViewOrders.update(in: defaults) { $0.set([.favorites, .own], in: .library) }
        PagePlacements.update(in: defaults) { $0.setPins(["starts_at"], of: TypeID(note)) }
        looks.change(TypeID(note), in: library, catalogue: LookFixture.catalogue()) { $0.date = .occurred }
        #expect(defaults.object(forKey: PreferenceHolds.key) == nil)
    }

    @Test func aSidebarWriteNeverTakesTheFastPath() throws {
        defaults.set(json([library: ["hidden": ["feed"]]]), forKey: SidebarLayouts.defaultsKey)
        sidebar.reload()
        try #require(entries.isEmpty)
        sidebar.update(library) { $0.setCollapsed(.type(note), true) }
        #expect(!heldUnits.isEmpty)
        #expect(!heldUnits.contains(layout("collapsed")))
        #expect(!heldUnits.contains(layout("hidden")))
    }

    @Test func aSidebarFillAfterADropHoldsOnlyUnalteredRows() {
        defaults.set(json([library: ["hidden": ["feed"], "order": ["library"], "tabs": 5]]), forKey: SidebarLayouts.defaultsKey)
        sidebar.reload()
        sidebar.update(library) { $0.setCollapsed(.type(note), true) }
        // The fill composes with the drop, so the Marfa's row stays while this Mac holds what the store filled.
        #expect(entries.contains { $0.kind == .unit(layout("hidden"), before: #"["feed"]"#, left: "[]", seenPending: false) })
        #expect(!heldUnits.contains(layout("collapsed")))
        #expect(releases[layout("collapsed")] == #"["type:\#(note)"]"#)
    }

    @Test func aPerServerValueThatIsNoObjectGetsAWholeHoldForAnyLibrary() {
        defaults.set(Data("[1]".utf8), forKey: TypeLooks.defaultsKey)
        looks.reload()
        #expect(entries.count == 1)
        #expect(entries.first?.library == nil)
        if case .whole(let left, let except)? = entries.first?.kind {
            #expect(left.isEmpty)
            #expect(except.isEmpty)
        } else {
            Issue.record("Expected a whole hold")
        }
    }

    @Test func aPerServerValueOfAnotherKindIsReadForTheLibraryThePersonWrites() throws {
        defaults.set(text([library: [note: ["date": "created"], task: ["date": "edited"]]]), forKey: TypeLooks.defaultsKey)
        looks.reload()
        defaults.removeObject(forKey: PreferenceHolds.key)
        defaults.set(text([library: [note: ["date": "created"], task: ["date": "edited"]]]), forKey: TypeLooks.defaultsKey)
        looks.change(TypeID(note), in: library, catalogue: LookFixture.catalogue()) { $0.date = .occurred }
        let written = try #require(local()[look(note)])
        let whole = entries.first { if case .whole = $0.kind { true } else { false } }
        #expect(whole?.library == nil)
        if case .whole(let left, let except)? = whole?.kind {
            #expect(left[look(note)] == written)
            #expect(except.contains(look(note)))
        } else {
            Issue.record("Expected a whole hold")
        }
    }
}
