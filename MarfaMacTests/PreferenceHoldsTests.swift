import Foundation
import Testing
@testable import MarfaMac

/// A value a store sets aside, or rewrites on reading, is held in the Marfa as the sync holds one its store dropped
/// while the sync wrote it: no step deletes or overwrites the row for it, and the person's own changes are sent as
/// before. Every change goes through a store or the app's own entry point.
@MainActor @Suite(.hangLimit) final class PreferenceHoldsTests {
    let defaults = ThrowawayDefaults.make("MarfaMacTests.PreferenceHolds")
    let points = RestorePoints(folder: URL.temporaryDirectory.appending(path: "PreferenceHoldsTests-\(UUID().uuidString)"))
    let library = "marfa:https://one"
    /// The settings a library's earlier name still holds, as `LibrarySettings` says.
    var unsettled: Set<String> = []
    /// Runs after the stores at each reload, as another build's own store that sets something aside would.
    var alsoOnReload: () -> Void = {}
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
        alsoOnReload()
    }

    private func look(_ type: String) -> PreferenceUnit { .row(.types, setting: "look", key: type) }
    private func placement(_ type: String) -> PreferenceUnit { .row(.types, setting: "pagePlacements", key: type) }
    private func density(_ place: PlaceView) -> PreferenceUnit { .row(.places, setting: "placeDensity", key: place.storageKey) }
    private func layout(_ member: String) -> PreferenceUnit { .row(.sidebar, setting: "layout", key: member) }
    private func color(_ place: String) -> PreferenceUnit { .row(.sidebar, setting: "color", key: place) }
    private func shortcut(_ command: ShortcutCommand) -> PreferenceUnit { .row(.commands, setting: "shortcut", key: command.id) }
    private func viewLayout(_ id: String) -> PreferenceUnit { .row(.views, setting: "viewLayout", key: id) }
    private func hidden(_ view: ViewChoice) -> PreferenceUnit {
        .row(.places, setting: "viewHidden", key: ViewOrders.hiddenRowKey(view, in: .library))
    }

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

    private func frozen(_ unit: PreferenceUnit) -> PreferencesSync.Record.Frozen? {
        PreferencesSync.Record.read(defaults).marfas["instance-1"]?.frozen[unit]
    }

    private final class Count: @unchecked Sendable {
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

    /// Looks for Notes and Tasks synced; then Tasks' stored look uses a date this build does not know, and a store reads
    /// it at launch.
    private func lookSetAside() async -> (FakePreferencesCopy, String, PreferencesSync) {
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): created, look(task): edited])
        let sync = await sync(copy)
        defaults.set(json([library: [note: ["date": "created"], task: ["date": "bogus"]]]), forKey: TypeLooks.defaultsKey)
        _ = TypeLooks(defaults: defaults)
        await flush(sync)
        return (copy, item, sync)
    }

    // MARK: A. The issue

    @Test func aLookSetAsideAtLaunchStaysInTheMarfa() async throws {
        let (copy, item, _) = await lookSetAside()
        #expect(await copy.unitsHeld(item)[look(task)] == edited)
        #expect(await copy.unitsHeld(item)[look(note)] == created)
    }

    @Test func aLooksValueThatIsNoObjectStaysInTheMarfa() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): created, look(task): edited])
        let sync = await sync(copy)
        defaults.set(Data("[1]".utf8), forKey: TypeLooks.defaultsKey)
        looks.reload()
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(note)] == created)
        #expect(await copy.unitsHeld(item)[look(task)] == edited)
    }

    @Test(arguments: [false, true])
    func aLooksValueOfAnotherKindKeepsOtherLooksWhenThePersonChangesOne(native: Bool) async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): created, look(task): edited])
        let sync = await sync(copy)
        let stored: [String: Any] = [library: [note: ["date": "created"], task: ["date": "edited"]]]
        if native { defaults.set(stored, forKey: TypeLooks.defaultsKey) } else { defaults.set(text(stored), forKey: TypeLooks.defaultsKey) }
        looks.reload()
        looks.change(TypeID(note), in: library, catalogue: LookFixture.catalogue()) { $0.date = .occurred }
        let mine = try #require(local()[look(note)])
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(task)] == edited)
        #expect(await copy.unitsHeld(item)[look(note)] == mine)
    }

    @Test func aReadableLookASetAsideReencodesStaysInTheMarfa() async throws {
        let later = #"{"date":"created","glow":true}"#
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): later, look(task): edited])
        let sync = await sync(copy)
        defaults.set(json([library: [note: ["date": "created", "glow": true], task: ["date": "bogus"]]]), forKey: TypeLooks.defaultsKey)
        looks.reload()
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(note)] == later)
        #expect(await copy.unitsHeld(item)[look(task)] == edited)
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
        defaults.set(Data("[1]".utf8), forKey: ShortcutBindings.defaultsKey)
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

    /// The library's stored layout as synced, with a member this build cannot read.
    private var undecodableLayout: Data {
        json([library: ["hidden": ["feed"], "order": ["library"], "colors": ["P": "red"], "tabs": 5]])
    }

    private func collapse(_ layout: inout SidebarLayout) { layout.setCollapsed(.type(note), true) }

    @Test func aSidebarEntrySetAsideStaysInTheMarfa() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add(sidebarRows)
        let sync = await sync(copy)
        defaults.set(undecodableLayout, forKey: SidebarLayouts.defaultsKey)
        sidebar.reload()
        await flush(sync)
        for (unit, value) in sidebarRows { #expect(await copy.unitsHeld(item)[unit] == value) }
    }

    @Test func aSidebarChangeAfterASetAsideSendsOnlyTheChangedRow() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add(sidebarRows)
        let sync = await sync(copy)
        defaults.set(undecodableLayout, forKey: SidebarLayouts.defaultsKey)
        sidebar.reload()
        await flush(sync)
        sidebar.update(library, collapse)
        await flush(sync)
        #expect(await copy.unitsHeld(item)[layout("collapsed")] == #"["\#(note)"]"#)
        for (unit, value) in sidebarRows { #expect(await copy.unitsHeld(item)[unit] == value) }
    }

    @Test func aSidebarChangeBeforeTheFirstStepAfterASetAsideSendsOnlyTheChangedRow() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add(sidebarRows)
        let sync = await sync(copy)
        defaults.set(undecodableLayout, forKey: SidebarLayouts.defaultsKey)
        sidebar.reload()
        sidebar.update(library, collapse)
        await flush(sync)
        #expect(await copy.unitsHeld(item)[layout("collapsed")] == #"["\#(note)"]"#)
        for (unit, value) in sidebarRows { #expect(await copy.unitsHeld(item)[unit] == value) }
    }

    @Test func aSidebarChangeAfterAnApplyTimeDropSendsOnlyTheChangedRow() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add(sidebarRows)
        let sync = await sync(copy)
        await copy.change(item, [layout("tabs"): "5"])
        await sync.flush()
        await sync.flush()
        sidebar.update(library, collapse)
        await flush(sync)
        #expect(await copy.unitsHeld(item)[layout("collapsed")] == #"["\#(note)"]"#)
        for (unit, value) in sidebarRows { #expect(await copy.unitsHeld(item)[unit] == value) }
        #expect(await copy.unitsHeld(item)[layout("tabs")] == "5")
    }

    @Test func aSidebarValueThatIsNoObjectStaysInTheMarfa() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add(sidebarRows)
        let sync = await sync(copy)
        defaults.set(Data("[1]".utf8), forKey: SidebarLayouts.defaultsKey)
        sidebar.reload()
        await flush(sync)
        for (unit, value) in sidebarRows { #expect(await copy.unitsHeld(item)[unit] == value) }
    }

    @Test(arguments: [false, true])
    func aSidebarValueOfAnotherKindKeepsOtherRowsWhenThePersonChangesIt(native: Bool) async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add(sidebarRows)
        let sync = await sync(copy)
        let stored: [String: Any] = [library: ["hidden": ["feed"], "order": ["library"], "colors": ["P": "red"]]]
        if native {
            defaults.set(stored, forKey: SidebarLayouts.defaultsKey)
        } else {
            defaults.set(text(stored), forKey: SidebarLayouts.defaultsKey)
        }
        sidebar.reload()
        sidebar.update(library, collapse)
        await flush(sync)
        #expect(await copy.unitsHeld(item)[layout("collapsed")] == #"["\#(note)"]"#)
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
        defaults.set(Data("[1]".utf8), forKey: SearchLeaveOuts.defaultsKey)
        leaveOuts.reload()
        await flush(sync)
        #expect(await copy.unitsHeld(item)[search] == value)
    }

    @Test func aDensityThePersonSetsKeepsAnUnreadableNeighbour() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([density(.library): #""compact""#, density(.feed): #""compact""#])
        let sync = await sync(copy)
        defaults.set(json([PlaceView.library.storageKey: "compact", PlaceView.feed.storageKey: "spacious"]), forKey: PlaceDensities.key)
        PlaceDensities.update(in: defaults) { $0.set(.standard, for: .library) }
        await flush(sync)
        #expect(await copy.unitsHeld(item)[density(.feed)] == #""compact""#)
        #expect(await copy.unitsHeld(item)[density(.library)] == #""standard""#)
    }

    @Test func aDensityMapWithANumberKeepsEveryOtherPlace() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([density(.library): #""compact""#, density(.feed): #""compact""#])
        let sync = await sync(copy)
        defaults.set(json([PlaceView.library.storageKey: 99, PlaceView.feed.storageKey: "compact"]), forKey: PlaceDensities.key)
        PlaceDensities.update(in: defaults) { $0.set(.standard, for: .favorites) }
        await flush(sync)
        #expect(await copy.unitsHeld(item)[density(.library)] == #""compact""#)
        #expect(await copy.unitsHeld(item)[density(.feed)] == #""compact""#)
        #expect(await copy.unitsHeld(item)[density(.favorites)] == #""standard""#)
    }

    private enum Kind: CaseIterable { case text, data, native }

    @Test(arguments: Kind.allCases)
    private func pinningOverPlacementsThatAreNoObjectKeepsOtherTypes(_ kind: Kind) async throws {
        let tasks = #"{"pins":["due_at"]}"#
        let copy = FakePreferencesCopy()
        let item = await copy.add([placement(note): #"{"pins":["url"]}"#, placement(task): tasks])
        let sync = await sync(copy)
        switch kind {
        case .text: defaults.set("[]", forKey: PagePlacements.key)
        case .data: defaults.set(Data("[]".utf8), forKey: PagePlacements.key)
        case .native: defaults.set([note: ["pins": ["url"]], task: ["pins": ["due_at"]]], forKey: PagePlacements.key)
        }
        PagePlacements.update(in: defaults) { $0.setPins(["starts_at"], of: TypeID(note)) }
        let mine = try #require(local()[placement(note)])
        await flush(sync)
        #expect(await copy.unitsHeld(item)[placement(task)] == tasks)
        #expect(await copy.unitsHeld(item)[placement(note)] == mine)
    }

    /// Three views' layouts synced; the stored document holds one this build cannot read.
    private func viewLayouts() async throws -> (FakePreferencesCopy, String, PreferencesSync, PreferenceUnits) {
        ViewLayouts.update(in: defaults) { layouts in
            for (index, id) in ["v1", "v2", "v3"].enumerated() {
                var settings = ViewMacSettings()
                settings.hidesEmptyGroups = index > 0
                layouts.set(settings, for: ItemID(id))
            }
        }
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        let item = try #require(await copy.activeIDs.first)
        let synced = await copy.unitsHeld(item).filter { if case .row(.views, _, _) = $0.key { true } else { false } }
        try #require(synced.count == 3)
        let stored = try #require(defaults.string(forKey: ViewLayouts.key))
        var document = try #require(PreferenceJSON.value(stored) as? [String: Any])
        document["v3"] = 5
        let damaged = text(document)
        try #require(ViewLayouts(rawValue: damaged) == nil)
        defaults.set(damaged, forKey: ViewLayouts.key)
        return (copy, item, sync, synced)
    }

    @Test func aWidthDragOverAnUnreadableLayoutsDocumentKeepsOtherViews() async throws {
        let (copy, item, sync, synced) = try await viewLayouts()
        ViewLayouts.update(in: defaults) { layouts in
            var settings = layouts.settings(for: ItemID("v1")) ?? ViewMacSettings()
            settings.widths = Data("widths".utf8)
            layouts.set(settings, for: ItemID("v1"))
        }
        await flush(sync)
        #expect(await copy.unitsHeld(item)[viewLayout("v2")] == synced[viewLayout("v2")])
        #expect(await copy.unitsHeld(item)[viewLayout("v3")] == synced[viewLayout("v3")])
        #expect(await copy.unitsHeld(item)[viewLayout("v1")] == local()[viewLayout("v1")])
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

    @Test func aDateHoldWrittenDuringAStepsReadIsAppliedNextStep() async throws {
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

    @Test func anImportedLookTheStoreDropsLeavesTheMarfas() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): created])
        let sync = await sync(copy)
        let file = SettingsFile(units: [look(note): #"{"date":"bogus"}"#], build: "", date: .now)
        try await sync.importSettings(file, sections: [SettingsFile.Section(look(note))])
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(note)] == created)
    }

    @Test func twoMacsKeepARowOneOfThemSetsAside() async throws {
        let other = ThrowawayDefaults.make("MarfaMacTests.PreferenceHolds.other")
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): created, look(task): edited])
        let mine = await sync(copy)
        let theirs = await sync(copy, defaults: other)
        other.set(json([library: [note: ["date": "created"], task: ["date": "bogus"]]]), forKey: TypeLooks.defaultsKey)
        _ = TypeLooks(defaults: other)
        looks.change(TypeID(note), in: library, catalogue: LookFixture.catalogue()) { $0.date = .occurred }
        let changed = try #require(local()[look(note)])
        await flush(mine)
        await flush(theirs)
        await flush(mine)
        #expect(await copy.unitsHeld(item)[look(task)] == edited)
        #expect(await copy.unitsHeld(item)[look(note)] == changed)
        #expect(local(other)[look(note)] == changed)
    }

    /// From #683: a store that sets aside a library's looks while the library's earlier name still holds them keeps
    /// every row once the name moves.
    @Test func aHoldWaitsWhileItsSettingIsUnsettled() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): created])
        let sync = await sync(copy)
        #expect(defaults.data(forKey: TypeLooks.defaultsKey) != nil)
        unsettled = [TypeLooks.defaultsKey]
        defaults.set(json([library: [1]]), forKey: TypeLooks.defaultsKey)
        _ = TypeLooks(defaults: defaults)
        await sync.flush()
        unsettled = []
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(note)] == created)
    }

    /// From #683: a density map restored as text rather than data. The Marfa keeps the other place's density; this Mac
    /// does not read it back from text (a separate issue).
    @Test func aDensityMapStoredAsTextKeepsTheOtherPlacesRows() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([density(.library): #""compact""#, density(.favorites): #""standard""#])
        let sync = await sync(copy)
        defaults.set(text([PlaceView.library.storageKey: "compact", PlaceView.favorites.storageKey: "standard"]), forKey: PlaceDensities.key)
        PlaceDensities.update(in: defaults) { $0.set(.standard, for: .library) }
        await flush(sync)
        #expect(await copy.unitsHeld(item)[density(.library)] == #""standard""#)
        #expect(await copy.unitsHeld(item)[density(.favorites)] == #""standard""#)
        withKnownIssue("A value of another kind is written over here without being read (#681's class)") {
            #expect(PlaceDensities.stored(in: defaults).density(for: .favorites) == .standard)
        }
    }

    // MARK: B. Behavior kept

    @Test func aRemovalIsSent() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([density(.library): #""compact""#, density(.feed): #""compact""#])
        let sync = await sync(copy)
        PlaceDensities.update(in: defaults) { $0.set(nil, for: .library) }
        await flush(sync)
        #expect(await copy.unitsHeld(item)[density(.library)] == nil)
        #expect(await copy.unitsHeld(item)[density(.feed)] == #""compact""#)
    }

    @Test func setThenClearIsSent() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([density(.library): #""compact""#])
        let sync = await sync(copy)
        PlaceDensities.update(in: defaults) { $0.set(.standard, for: .library) }
        PlaceDensities.update(in: defaults) { $0.set(nil, for: .library) }
        await flush(sync)
        #expect(await copy.unitsHeld(item)[density(.library)] == nil)
    }

    @Test func aPersonsChangeToAHeldRowIsSent() async throws {
        let (copy, item, sync) = await lookSetAside()
        looks.change(TypeID(task), in: library, catalogue: LookFixture.catalogue()) { $0.date = .occurred }
        let mine = try #require(local()[look(task)])
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(task)] == mine)
    }

    @Test func aHeldLookSetAndRestoredBeforeAStepIsDeleted() async throws {
        let (copy, item, sync) = await lookSetAside()
        looks.change(TypeID(task), in: library, catalogue: LookFixture.catalogue()) { $0.date = .occurred }
        looks.restore(TypeID(task), in: library)
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(task)] == nil)
        #expect(await copy.unitsHeld(item)[look(note)] == created)
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

    @Test func resetViewOnAnUnreadableDensityDeletesIt() async throws {
        let tasks = PlaceView.type(TypeID(task))
        let copy = FakePreferencesCopy()
        let item = await copy.add([density(tasks): #""compact""#, density(.feed): #""compact""#])
        let sync = await sync(copy)
        let browser = browser(showing: tasks)
        defaults.set(json([tasks.storageKey: "spacious", PlaceView.feed.storageKey: "compact"]), forKey: PlaceDensities.key)
        browser.resetView(in: FakeItemLibrary(items: [], now: .now))
        await flush(sync)
        #expect(await copy.unitsHeld(item)[density(tasks)] == nil)
        #expect(await copy.unitsHeld(item)[density(.feed)] == #""compact""#)
    }

    @Test func resetViewOverADensityValueOfAnotherKindDeletesIt() async throws {
        let tasks = PlaceView.type(TypeID(task))
        let copy = FakePreferencesCopy()
        let item = await copy.add([density(tasks): #""compact""#, density(.feed): #""compact""#])
        let sync = await sync(copy)
        let browser = browser(showing: tasks)
        defaults.set(text([tasks.storageKey: "compact", PlaceView.feed.storageKey: "compact"]), forKey: PlaceDensities.key)
        browser.resetView(in: FakeItemLibrary(items: [], now: .now))
        await flush(sync)
        #expect(await copy.unitsHeld(item)[density(tasks)] == nil)
    }

    /// Shortcuts for New Item and Refresh synced; then the stored map holds an entry this build cannot read, so the store
    /// sets the whole of it aside at launch.
    private func shortcutsSetAside() async throws -> (FakePreferencesCopy, String, PreferencesSync) {
        bindings.set(Shortcut(key: "n", modifiers: [.command, .control]), for: .newItem)
        bindings.set(Shortcut(key: "r", modifiers: [.command, .option]), for: .refresh)
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        let item = try #require(await copy.activeIDs.first)
        let bytes = try #require(defaults.data(forKey: ShortcutBindings.defaultsKey))
        var stored = try #require(PreferenceJSON.value(String(decoding: bytes, as: UTF8.self)) as? [String: Any])
        var shortcuts = try #require(stored["shortcuts"] as? [String: Any])
        shortcuts["later.command"] = 42
        stored["shortcuts"] = shortcuts
        defaults.set(json(stored), forKey: ShortcutBindings.defaultsKey)
        bindings.reload()
        await flush(sync)
        try #require(await copy.unitsHeld(item)[shortcut(.newItem)] != nil)
        return (copy, item, sync)
    }

    @Test func recordingAFactoryShortcutAfterASetAsideClearsTheOverride() async throws {
        let (copy, item, sync) = try await shortcutsSetAside()
        bindings.set(ShortcutCommand.newItem.defaultShortcut, for: .newItem)
        await flush(sync)
        #expect(await copy.unitsHeld(item)[shortcut(.newItem)] == nil)
    }

    @Test func keyboardRestoreDefaultsAfterASetAsideClearsEveryOverride() async throws {
        let (copy, item, sync) = try await shortcutsSetAside()
        bindings.restoreDefaults()
        await flush(sync)
        #expect(await copy.unitsHeld(item)[shortcut(.newItem)] == nil)
        #expect(await copy.unitsHeld(item)[shortcut(.refresh)] == nil)
    }

    @Test func keyboardRestoreDefaultsSurvivesAnUpdate() async throws {
        let (copy, item, sync) = try await shortcutsSetAside()
        bindings.restoreDefaults()
        await flush(sync)
        sync.detach()
        let next = await self.sync(copy, build: "2")
        await flush(next)
        #expect(await copy.unitsHeld(item)[shortcut(.newItem)] == nil)
        #expect(await copy.unitsHeld(item)[shortcut(.refresh)] == nil)
        #expect(local()[shortcut(.newItem)] == nil)
        #expect(local()[shortcut(.refresh)] == nil)
    }

    @Test func replacingAShortcutAfterASetAsideClearsBothCommands() async throws {
        let (copy, item, sync) = try await shortcutsSetAside()
        let refreshKeys = try #require(ShortcutCommand.refresh.defaultShortcut)
        bindings.replace(refreshKeys, for: .newItem)
        let mine = local()
        await flush(sync)
        #expect(await copy.unitsHeld(item)[shortcut(.newItem)] == mine[shortcut(.newItem)])
        #expect(await copy.unitsHeld(item)[shortcut(.refresh)] == "null")
    }

    @Test func aKeyboardImportAfterASetAsideClearsTheAcceptedCommands() async throws {
        let (copy, item, sync) = try await shortcutsSetAside()
        _ = bindings.apply([ShortcutCommand.newItem.id: ShortcutCommand.newItem.defaultShortcut])
        await flush(sync)
        #expect(await copy.unitsHeld(item)[shortcut(.newItem)] == nil)
    }

    @Test func forgettingAViewWhileTheLayoutsDocumentIsUnreadableDeletesItAndKeepsTheOthers() async throws {
        let (copy, item, sync, synced) = try await viewLayouts()
        let browser = Browser()
        browser.defaults = defaults
        browser.forgetView(ItemID("v1"))
        await flush(sync)
        #expect(await copy.unitsHeld(item)[viewLayout("v1")] == nil)
        #expect(await copy.unitsHeld(item)[viewLayout("v2")] == synced[viewLayout("v2")])
        #expect(await copy.unitsHeld(item)[viewLayout("v3")] == synced[viewLayout("v3")])
    }

    @Test func anImportedLookTheStoreReencodesIsSent() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): created])
        let sync = await sync(copy)
        let file = SettingsFile(units: [look(note): #"{"date":"edited","glow":true}"#, look(task): #"{"date":"bogus"}"#], build: "", date: .now)
        try await sync.importSettings(file, sections: [SettingsFile.Section(look(note))])
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(note)] == edited)
    }

    @Test func aRestoreNotYetSentSurvivesALossyWriteBeforeItsStep() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): created])
        let sync = await sync(copy)
        defaults.set(json([library: [note: ["date": "edited", "glow": true]]]), forKey: TypeLooks.defaultsKey)
        try sync.saveRestorePoint(.import)
        let point = try #require(sync.listRestorePoints().first)
        defaults.set(json([library: [note: ["date": "created"]]]), forKey: TypeLooks.defaultsKey)
        looks.reload()
        await copy.set(PreferencesReadiness(filled: false, holdsType: true, tablesWhole: true, instance: "instance-1"))
        try await sync.restore(point.id)
        looks.change(TypeID(task), in: library, catalogue: LookFixture.catalogue()) { $0.date = .occurred }
        await copy.set(PreferencesReadiness(filled: true, holdsType: true, tablesWhole: true, instance: "instance-1"))
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(note)] == edited)
    }

    @Test func resetDeletesARowAStoreSetAside() async throws {
        let (copy, item, sync) = await lookSetAside()
        MacSettings.reset(in: defaults)
        sync.replaced(PreferencesMap.synced)
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(task)] == nil)
        #expect(await copy.unitsHeld(item)[look(note)] == nil)
    }

    @Test func importWithoutAHeldRowDeletesIt() async throws {
        let (copy, item, sync) = await lookSetAside()
        let file = SettingsFile(units: [look(note): created], build: "", date: .now)
        try await sync.importSettings(file, sections: [SettingsFile.Section(look(note))])
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(task)] == nil)
        #expect(await copy.unitsHeld(item)[look(note)] == created)
    }

    @Test func restoreOfAPointSavedWhileHeldDeletesTheRow() async throws {
        let (copy, item, sync) = await lookSetAside()
        try sync.saveRestorePoint(.import)
        let point = try #require(sync.listRestorePoints().first)
        try await sync.restore(point.id)
        await flush(sync)
        #expect(await copy.unitsHeld(item)[look(task)] == nil)
        #expect(await copy.unitsHeld(item)[look(note)] == created)
    }

    /// From #683: an earlier app recorded a row that is not JSON as held, without setting it aside or storing it.
    @Test func aRowThatIsNotJSONAnEarlierAppRecordedStaysAfterTheUpgrade() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([placement(note): "{not json", theme: #""light""#])
        defaults.set("light", forKey: AppearanceKey.theme)
        var record = PreferencesSync.Record()
        record.marfas["instance-1"] = .init(item: item, base: [placement(note): "{not json", theme: #""light""#])
        record.last = "instance-1"
        record.save(defaults)
        let sync = await sync(copy)
        await sync.flush()
        #expect(await copy.unitsHeld(item)[placement(note)] == "{not json")
        defaults.set(#"{"core.task":{"pins":["due_at"]}}"#, forKey: PagePlacements.key)
        await sync.flush()
        #expect(await copy.unitsHeld(item)[placement(note)] == "{not json")
    }

    /// From #683: Reset made before this Mac received another Mac's new row that is not JSON keeps the row.
    @Test func resetKeepsARowThatIsNotJSONThisMacHasNotSeen() async throws {
        defaults.set(#"{"core.task":{"pins":[]}}"#, forKey: PagePlacements.key)
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        let item = try #require(await copy.activeIDs.first)
        await copy.change(item, [placement(note): "{not json"])
        MacSettings.reset(in: defaults)
        sync.replaced(PreferencesMap.synced)
        await flush(sync)
        #expect(await copy.unitsHeld(item)[placement(note)] == "{not json")
        #expect(setAside(PagePlacements.setAsideKey).contains("{not json"))
    }

    /// From #683: the person replaces a density this Mac cannot read, then clears it before the next step.
    @Test func aDensityReplacedThenClearedBeforeTheNextStepIsRemoved() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([density(.library): #""standard""#])
        let sync = await sync(copy)
        defaults.set(json([PlaceView.library.storageKey: "spacious"]), forKey: PlaceDensities.key)
        PlaceDensities.update(in: defaults) { $0.set(.compact, for: .library) }
        PlaceDensities.update(in: defaults) { $0.set(nil, for: .library) }
        await flush(sync)
        #expect(await copy.unitsHeld(item)[density(.library)] == nil)
        #expect(setAside(PlaceDensities.setAsideKey) == [text([PlaceView.library.storageKey: "spacious"])])
    }

    /// From #683: a value set aside for every library, once taken, writes nothing at later steps.
    @Test func aValueSetAsideForEveryLibraryWritesNothingOnceTaken() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([theme: #""light""#])
        let sync = await sync(copy)
        defaults.set(Data("[1]".utf8), forKey: TypeLooks.defaultsKey)
        _ = TypeLooks(defaults: defaults)
        await flush(sync)
        let count = await writes {
            for _ in 0..<4 { await sync.flush() }
        }
        #expect(count == 0)
        #expect(await copy.unitsHeld(item)[theme] == #""light""#)
    }

    /// From #683: a hidden view this Mac cannot read beside one it can, and a step that changes nothing writes nothing.
    @Test func aHiddenViewThisMacCannotReadWritesNothingAtEachStep() async throws {
        let own = hidden(.own)
        let favorites = hidden(.favorites)
        let copy = FakePreferencesCopy()
        let item = await copy.add([own: "true", favorites: "true"])
        let sync = await sync(copy)
        defaults.set(
            json([ViewOrders.hiddenRowKey(.own, in: .library): "maybe", ViewOrders.hiddenRowKey(.favorites, in: .library): true]),
            forKey: ViewOrders.hiddenKey)
        ViewOrders.update(in: defaults) { $0.set([.favorites, .own], in: .library) }
        await flush(sync)
        let count = await writes {
            for _ in 0..<4 { await sync.flush() }
        }
        #expect(count == 0)
        #expect(await copy.unitsHeld(item)[own] == "true")
        #expect(await copy.unitsHeld(item)[favorites] == "true")
    }

    // MARK: C. Nothing of the person's is thrown away

    @Test func aPinOverAnUnreadableDocumentSurvivesAnUpdate() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([placement(note): #"{"pins":["url"]}"#, placement(task): #"{"pins":["due_at"]}"#])
        let sync = await sync(copy)
        defaults.set("[]", forKey: PagePlacements.key)
        PagePlacements.update(in: defaults) { $0.setPins(["starts_at"], of: TypeID(note)) }
        let mine = try #require(local()[placement(note)])
        await flush(sync)
        sync.detach()
        let next = await self.sync(copy, build: "2")
        await flush(next)
        #expect(local()[placement(note)] == mine)
        #expect(await copy.unitsHeld(item)[placement(note)] == mine)
    }

    @Test func aPinOverAnUnreadableDocumentSurvivesAnotherMacsChange() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([placement(note): #"{"pins":["url"]}"#, placement(task): #"{"pins":["due_at"]}"#])
        let sync = await sync(copy)
        defaults.set("[]", forKey: PagePlacements.key)
        PagePlacements.update(in: defaults) { $0.setPins(["starts_at"], of: TypeID(note)) }
        let mine = try #require(local()[placement(note)])
        await copy.change(item, [placement(note): #"{"pins":["name"]}"#])
        await flush(sync)
        #expect(await copy.unitsHeld(item)[placement(note)] == mine)
        #expect(local()[placement(note)] == mine)
    }

    @Test func aHeldLookTakesAnotherMacsReadableChange() async throws {
        let (copy, item, sync) = await lookSetAside()
        await copy.change(item, [look(task): created])
        await flush(sync)
        #expect(local()[look(task)] == created)
        #expect(frozen(look(task)) == nil)
    }

    @Test func aReportedFreezeStaysReportedAcrossAnUpdate() async throws {
        let format = DateFormat(usesWords: false, date: .system, time: .system).rawValue
        let copy = FakePreferencesCopy()
        let item = await copy.add([date: text(format)])
        let sync = await sync(copy)
        defaults.set("relative", forKey: DateFormat.key)
        DateFormat.setAsideUnreadable(in: defaults)
        await flush(sync)
        sync.detach()
        alsoOnReload = { [defaults] in DateFormat.setAsideUnreadable(in: defaults) }
        let next = await self.sync(copy, build: "2")
        await flush(next)
        MacSettings.reset(in: defaults)
        next.replaced(PreferencesMap.synced)
        await flush(next)
        #expect(await copy.unitsHeld(item)[date] == nil)
    }

    @Test func anEntryAnEarlierBuildWroteIsRetriedByTheNext() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([look(note): created, look(task): edited])
        let sync = await sync(copy)
        sync.detach()
        defaults.set(json([library: [note: ["date": "created"], task: ["date": "bogus"]]]), forKey: TypeLooks.defaultsKey)
        _ = TypeLooks(defaults: defaults)
        let next = PreferencesSync(
            defaults: defaults, domain: defaults.suite, enabled: true, coalescing: .milliseconds(50), build: "2",
            restorePoints: points) {}
        next.attach(copy, library: library, name: { nil })
        await flush(next)
        #expect(await copy.unitsHeld(item)[look(task)] == edited)
        #expect(local()[look(task)] == edited)
    }
}
