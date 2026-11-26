import Foundation
import Marfa
import Testing
@testable import MarfaMac

@MainActor @Suite(.hangLimit) final class PreferencesSyncTests {
    let defaults = ThrowawayDefaults.make("MarfaMacTests.PreferencesSync")
    /// The defaults' own domain, which a restore point reads.
    var suite: String { defaults.suite }
    var reloads = 0
    let theme = PreferenceUnit.member(.appearance, AppearanceKey.theme)
    let accent = PreferenceUnit.member(.appearance, AppearanceKey.accent)
    let placement = PreferenceUnit.row(.types, setting: "pagePlacements", key: "core.note")
    let points = RestorePoints(folder: URL.temporaryDirectory.appending(path: "PreferencesSyncTests-\(UUID().uuidString)"))

    deinit {
        try? FileManager.default.removeItem(at: points.folder)
    }

    /// The restore points saved, oldest first, with the theme each holds.
    private func saved() throws -> [(RestorePoint.Reason, String?)] {
        try points.list().reversed().map { ($0.reason, try points.snapshot(of: $0.id).value(forKey: AppearanceKey.theme) as? String) }
    }

    private func sync(_ copy: FakePreferencesCopy, library: String = "marfa:https://one") async -> PreferencesSync {
        let sync = PreferencesSync(defaults: defaults, domain: suite, enabled: true, coalescing: .milliseconds(50), restorePoints: points) {
            [weak self] in self?.reloads += 1
        }
        sync.attach(copy, library: library, name: { "Demo" })
        await sync.flush()
        return sync
    }

    /// A sync whose stores read the defaults again as the app's do, setting aside what they cannot read.
    private func syncWithStores(_ copy: FakePreferencesCopy, library: String = "marfa:https://one") async -> PreferencesSync {
        let stores = (
            SidebarLayouts(defaults: defaults), TypeLooks(defaults: defaults), SearchLeaveOuts(defaults: defaults),
            ShortcutBindings(defaults: defaults), AnyAppShortcuts(defaults: defaults, registrar: NoHotKeys()))
        let sync = PreferencesSync(defaults: defaults, domain: suite, enabled: true, coalescing: .milliseconds(50), restorePoints: points) {
            stores.0.reload()
            stores.1.reload()
            stores.2.reload()
            stores.3.reload()
            stores.4.reload()
        }
        sync.attach(copy, library: library, name: { "Demo" })
        await sync.flush()
        return sync
    }

    // MARK: The first launch

    @Test func aMarfaWithNoSettingsTakesThisMacsAndSavesARestorePointFirst() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        defaults.set(#"{"core.note":{"pins":["due_at"]}}"#, forKey: PagePlacements.key)
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        #expect(sync.standing == .syncing)
        #expect(await copy.creates == 1)
        let item = try #require(await copy.activeIDs.first)
        let held = await copy.unitsHeld(item)
        #expect(held[theme] == #""dark""#)
        #expect(held[placement] == #"{"pins":["due_at"]}"#)
        #expect(try saved().map(\.0) == [.firstSync])
        #expect(try saved().map(\.1) == ["dark"])
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
    }

    @Test func withoutThePermissionNothingChanges() async {
        defaults.set("dark", forKey: AppearanceKey.theme)
        let copy = FakePreferencesCopy()
        await copy.set(PreferencesReadiness(filled: true, holdsType: false, tablesWhole: false, instance: "instance-1"))
        let sync = await sync(copy)
        #expect(sync.standing == .off(.needsPermission))
        #expect(await copy.creates == 0)
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
        #expect(points.list().isEmpty)
    }

    @Test func aCopyThatIsNotWholeDecidesNothing() async {
        defaults.set("dark", forKey: AppearanceKey.theme)
        let copy = FakePreferencesCopy()
        await copy.add([theme: #""light""#])
        for readiness in [
            PreferencesReadiness(filled: false, holdsType: true, tablesWhole: true, instance: "instance-1"),
            PreferencesReadiness(filled: true, holdsType: true, tablesWhole: false, instance: "instance-1"),
        ] {
            await copy.set(readiness)
            let sync = await sync(copy)
            #expect(sync.standing == .off(.notFilled))
            sync.detach()
        }
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
        #expect(await copy.updates.isEmpty)
        #expect(points.list().isEmpty)
    }

    @Test func anItemAnotherMacMadeWinsAndIsFilledFromThisMac() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        defaults.set("blue", forKey: AppearanceKey.accent)
        let copy = FakePreferencesCopy()
        let item = await copy.add([theme: #""light""#])
        let sync = await sync(copy)
        #expect(sync.standing == .syncing)
        #expect(defaults.string(forKey: AppearanceKey.theme) == "light")
        #expect(await copy.unitsHeld(item)[accent] == #""blue""#)
        #expect(await copy.unitsHeld(item)[theme] == #""light""#)
        #expect(reloads == 1)
        // The point holds this Mac's settings from before it took the other Mac's.
        #expect(try saved().map(\.0) == [.adoption])
        #expect(try saved().map(\.1) == ["dark"])
    }

    @Test func twoItemsUseTheOneMadeFirstFilledFromTheOther() async throws {
        let copy = FakePreferencesCopy()
        let first = await copy.add([theme: #""light""#], createdAt: "2026-01-01T00:00:00Z")
        let second = await copy.add([theme: #""dark""#, accent: #""red""#], createdAt: "2026-01-02T00:00:00Z")
        _ = await sync(copy)
        #expect(defaults.string(forKey: AppearanceKey.theme) == "light")
        #expect(defaults.string(forKey: AppearanceKey.accent) == "red")
        #expect(await copy.unitsHeld(first)[accent] == #""red""#)
        #expect(await copy.unitsHeld(second) == [theme: #""dark""#, accent: #""red""#])
    }

    @Test func aMacThatAdoptedAnotherMarfaStartsANewOneFromTheAppsDefaults() async throws {
        var record = PreferencesSync.Record()
        record.marfas["instance-0"] = .init(item: "elsewhere", base: [theme: #""dark""#])
        record.last = "instance-0"
        record.save(defaults)
        defaults.set("dark", forKey: AppearanceKey.theme)
        let copy = FakePreferencesCopy()
        _ = await sync(copy)
        #expect(defaults.object(forKey: AppearanceKey.theme) == nil)
        let item = try #require(await copy.activeIDs.first)
        #expect(await copy.unitsHeld(item).isEmpty)
        #expect(try saved().map(\.0) == [.firstSync])
        #expect(try saved().map(\.1) == ["dark"])
    }

    @Test func aMacWithNothingOfItsOwnCarriesWhatAnEarlierCopyOnAnotherMacSynced() async throws {
        let task = #"{"itemType":{"_0":"core.task"}}"#
        let copy = FakePreferencesCopy()
        let item = await copy.add([
            .member(.general, StartWith.earlierKey): try #require(PreferenceJSON.text(#"{"favorites":{}}"#)),
            .row(.places, setting: "placeDefaults", key: task): #"{"layout":"board"}"#,
            .row(.places, setting: "placeDensity", key: #"{"recents":{}}"#): #""compact""#,
        ])
        let sync = await sync(copy)
        #expect(StartWith.stored(in: defaults) == .place(.favorites))
        #expect(PlaceDefaults.stored(in: defaults).default(for: .type(TypeID("core.task")))?.layout == .board)
        #expect(PlaceDensities.stored(in: defaults).density(for: .library) == .compact)
        await sync.flush()
        let held = await copy.unitsHeld(item)
        #expect(held[.member(.general, StartWith.key)] == PreferenceJSON.text(StartWith.place(.favorites).rawValue))
        let earlierRow = try #require(held[.row(.places, setting: "placeDefaults", key: task)], "the earlier row stays")
        #expect(try JSONDecoder().decode(PlaceDefault.self, from: Data(earlierRow.utf8)).layout == .board)
        // Copied once: what the person clears at the new key stays clear through the next sync.
        PlaceDensities.update(in: defaults) { $0.set(nil, for: .library) }
        await sync.flush()
        #expect(PlaceDensities.stored(in: defaults).density(for: .library) == nil)
    }

    // MARK: Following

    @Test func anotherMacsChangeReachesTheDefaultsAndIsNotSentBack() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        let item = try #require(await copy.activeIDs.first)
        let reloaded = reloads
        await copy.change(item, [theme: #""light""#, placement: #"{"pins":[]}"#])
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.theme) == "light")
        #expect(defaults.string(forKey: PagePlacements.key) == #"{"core.note":{"pins":[]}}"#)
        #expect(reloads == reloaded + 1)
        let updates = await copy.updates.count
        let batches = await copy.batches
        await sync.flush()
        #expect(await copy.updates.count == updates)
        #expect(await copy.batches == batches)
    }

    @Test func aChangeOnThisMacIsCoalescedIntoOneWrite() async throws {
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        let before = await copy.updates.count
        for size in 1...20 { defaults.set(Double(size), forKey: InterfaceKey.textSize) }
        #expect(try await eventuallyAsking { await copy.updates.count == before + 1 })
        // Lets a second write, which would be wrong, arrive if one were coming.
        try await Task.sleep(for: .milliseconds(300))
        #expect(await copy.updates.count == before + 1)
        let item = try #require(await copy.activeIDs.first)
        #expect(await copy.unitsHeld(item)[.member(.appearance, InterfaceKey.textSize)] == "20")
        _ = sync
    }

    // MARK: The row of views on two Macs

    private let viewOrder = PreferenceUnit.row(.places, setting: "viewOrder", key: "library")
    private let viewHidden = PreferenceUnit.row(.places, setting: "viewHidden", key: #"["library","favorites"]"#)
    private let ownHidden = PreferenceUnit.row(.places, setting: "viewHidden", key: #"["library","own"]"#)

    @Test func aHideHereAndAReorderOnAnotherMacBothStand() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([viewOrder: #"["own","favorites"]"#])
        let sync = await sync(copy)
        ViewOrders.update(in: defaults) { $0.setHidden(.favorites, true, in: .library) }
        await copy.change(item, [viewOrder: #"["favorites","own"]"#])
        await sync.flush()
        #expect(try await eventuallyAsking { await copy.unitsHeld(item)[self.viewHidden] != nil })
        let stored = ViewOrders.stored(in: defaults)
        #expect(stored.order(in: .library) == [.favorites, .own])
        #expect(stored.hidden(in: .library) == [.favorites])
        #expect(await copy.unitsHeld(item)[viewOrder] == #"["favorites","own"]"#)
    }

    @Test func aReorderHereLeavesAHideOnAnotherMacStanding() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([viewOrder: #"["own","favorites"]"#])
        let sync = await sync(copy)
        ViewOrders.update(in: defaults) { $0.set([.favorites, .own], in: .library) }
        await copy.change(item, [viewHidden: "true"])
        await sync.flush()
        #expect(try await eventuallyAsking { await copy.unitsHeld(item)[self.viewOrder] == #"["favorites","own"]"# })
        await sync.flush()
        let stored = ViewOrders.stored(in: defaults)
        #expect(stored.hidden(in: .library) == [.favorites])
        #expect(stored.order(in: .library) == [.favorites, .own])
        #expect(await copy.unitsHeld(item)[viewHidden] == "true")
    }

    /// An earlier copy of the app kept another Mac's hidden views in the sync's record without storing them, so the
    /// upgraded app holds none: they are taken from the Marfa, never deleted there.
    @Test func hiddenViewsAnEarlierCopyNeverStoredAreTakenNotDeleted() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([viewHidden: "true", viewOrder: #"["own","favorites"]"#])
        defaults.set(Data(#"{"library":["own","favorites"]}"#.utf8), forKey: ViewOrders.key)
        var record = PreferencesSync.Record()
        record.marfas["instance-1"] = .init(item: item, base: [viewHidden: "true", viewOrder: #"["own","favorites"]"#])
        record.last = "instance-1"
        record.save(defaults)
        let sync = await sync(copy)
        await sync.flush()
        #expect(await copy.unitsHeld(item)[viewHidden] == "true")
        #expect(ViewOrders.stored(in: defaults).hidden(in: .library) == [.favorites])
        // Shown again here, the view's row says so, and the next step leaves it.
        ViewOrders.update(in: defaults) { $0.setHidden(.favorites, false, in: .library) }
        #expect(try await eventuallyAsking { await copy.unitsHeld(item)[self.viewHidden] == "false" })
        await sync.flush()
        #expect(ViewOrders.stored(in: defaults).hidden(in: .library).isEmpty)
    }

    @Test func twoMacsHidingDifferentViewsBothStand() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([viewOrder: #"["own","favorites"]"#])
        let sync = await sync(copy)
        ViewOrders.update(in: defaults) { $0.setHidden(.own, true, in: .library) }
        await copy.change(item, [viewHidden: "true"])
        await sync.flush()
        #expect(try await eventuallyAsking { await copy.unitsHeld(item)[self.ownHidden] == "true" })
        await sync.flush()
        #expect(await copy.unitsHeld(item)[viewHidden] == "true")
        #expect(ViewOrders.stored(in: defaults).hidden(in: .library) == [.own, .favorites])
        // Showing one changes only its row.
        ViewOrders.update(in: defaults) { $0.setHidden(.own, false, in: .library) }
        #expect(try await eventuallyAsking { await copy.unitsHeld(item)[self.ownHidden] == "false" })
        #expect(await copy.unitsHeld(item)[viewHidden] == "true")
        #expect(ViewOrders.stored(in: defaults).hidden(in: .library) == [.favorites])
    }

    @Test func aMarfaValueThatCannotBeReadIsSetAsideOnceAndLeftInTheMarfa() async throws {
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        let item = try #require(await copy.activeIDs.first)
        await copy.change(item, [placement: "{not json"])
        await sync.flush()
        #expect(defaults.stringArray(forKey: PagePlacements.setAsideKey) == ["{not json"])
        #expect(defaults.string(forKey: PagePlacements.key) == nil)
        await sync.flush()
        #expect(defaults.stringArray(forKey: PagePlacements.setAsideKey) == ["{not json"])
        #expect(await copy.unitsHeld(item)[placement] == "{not json")
    }

    @Test func aConflictedFieldKeepsEachMembersLaterWrite() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([theme: #""light""#, accent: #""blue""#])
        let sync = await sync(copy)
        await copy.holdNextAnswer()
        defaults.set("red", forKey: AppearanceKey.accent)
        await sync.flush()
        // The server kept another Mac's field, which changed the theme, and wrote this Mac's to a conflicted copy.
        await copy.change(item, [theme: #""dark""#, accent: #""blue""#])
        let sibling = await copy.add([theme: #""light""#, accent: #""red""#], conflicted: true)
        await copy.answer(try #require(await copy.writeIDs.last), .lost)
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
        #expect(defaults.string(forKey: AppearanceKey.accent) == "red")
        #expect(await copy.unitsHeld(item)[accent] == #""red""#)
        #expect(await copy.unitsHeld(item)[theme] == #""dark""#)
        #expect(await copy.removed == [sibling])
    }

    @Test func resetPutsTheMarfasSettingsBackInOneWriteAndOneBatchPerTable() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        defaults.set(true, forKey: PageKey.foldsHeadings)
        defaults.set(#"{"core.note":{"pins":[]}}"#, forKey: PagePlacements.key)
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        let item = try #require(await copy.activeIDs.first)
        let (updates, batches) = (await copy.updates.count, await copy.batches)
        MacSettings.reset(in: defaults)
        await sync.flush()
        #expect(await copy.unitsHeld(item).isEmpty)
        #expect(await copy.updates.count == updates + 1)
        #expect(await copy.updates.last == [.appearance, .editor])
        #expect(await copy.batches[.types] == (batches[.types] ?? 0) + 1)
    }

    @Test func removedSettingsAreNotMadeAgain() async throws {
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        try await sync.remove()
        await sync.flush()
        #expect(sync.standing == .off(.removed))
        #expect(await copy.creates == 1)
        try await sync.startAgain()
        #expect(sync.standing == .syncing)
        #expect(await copy.creates == 2)
    }

    // MARK: Review findings

    /// A value a later version of the app wrote, which a store here sets aside, stays in the Marfa for the Macs that read it: the
    /// store dropping it on this Mac is no change of the person's.
    @Test(arguments: [
        PreferenceUnit.row(.types, setting: "look", key: "core.note"),
        PreferenceUnit.row(.sidebar, setting: "layout", key: "tabs"),
        PreferenceUnit.member(.search, "searchLeaveOuts"),
        PreferenceUnit.row(.commands, setting: "shortcut", key: "newItem"),
        PreferenceUnit.row(.commands, setting: "anyAppShortcut", key: "quickAdd"),
    ])
    func aValueAStoreCannotReadIsNeverDeletedFromTheMarfa(unit: PreferenceUnit) async throws {
        let later = #""a shape a later version of the app writes""#
        let copy = FakePreferencesCopy()
        let item = await copy.add([theme: #""light""#])
        let sync = await syncWithStores(copy)
        await copy.change(item, [unit: later])
        await sync.flush()
        await sync.flush()
        #expect(await copy.unitsHeld(item)[unit] == later)
        // A change to another setting, here one in the same field as the search member, still writes the member.
        defaults.set(true, forKey: SearchOptions.keys[0])
        await sync.flush()
        #expect(await copy.unitsHeld(item)[unit] == later)
        await sync.flush()
        #expect(await copy.unitsHeld(item)[unit] == later)
    }

    /// Connecting to another Marfa starts the settings shared by every Marfa from the app's defaults, but keeps what this
    /// Mac already holds for this Marfa alone.
    @Test func aNewMarfaKeepsItsOwnSettingsOnThisMac() async throws {
        var record = PreferencesSync.Record()
        record.marfas["instance-0"] = .init(item: "elsewhere", base: [theme: #""dark""#])
        record.last = "instance-0"
        record.save(defaults)
        defaults.set("dark", forKey: AppearanceKey.theme)
        let leaveOut = #"{"marfa:https://one":{"sources":[],"types":["core.note"]}}"#
        defaults.set(Data(leaveOut.utf8), forKey: SearchLeaveOuts.defaultsKey)
        let copy = FakePreferencesCopy()
        _ = await sync(copy)
        #expect(defaults.object(forKey: AppearanceKey.theme) == nil)
        let stored = try #require(defaults.data(forKey: SearchLeaveOuts.defaultsKey))
        #expect(String(decoding: stored, as: UTF8.self).contains("core.note"))
        let item = try #require(await copy.activeIDs.first)
        #expect(await copy.unitsHeld(item)[.member(.search, SearchLeaveOuts.defaultsKey)] == #"{"sources":[],"types":["core.note"]}"#)
    }

    /// Another Mac's change arrives late, after the server kept its field and before the conflicted copy reached
    /// this Mac: the member this Mac wrote is still its later write.
    @Test func aConflictedCopyThatArrivesLateStillKeepsThisMacsMember() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([theme: #""light""#, accent: #""blue""#])
        let sync = await sync(copy)
        await copy.holdNextAnswer()
        defaults.set("red", forKey: AppearanceKey.accent)
        await sync.flush()
        let write = try #require(await copy.writeIDs.last)
        // The item's new value reaches the copy before the answer is taken.
        await copy.change(item, [theme: #""dark""#, accent: #""blue""#])
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.accent) == "red")
        await copy.answer(write, .lost)
        await sync.flush()
        #expect(await copy.unitsHeld(item)[accent] == #""red""#)
        // The conflicted copy arrives last.
        let sibling = await copy.add([theme: #""light""#, accent: #""red""#], conflicted: true)
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
        #expect(defaults.string(forKey: AppearanceKey.accent) == "red")
        #expect(await copy.unitsHeld(item)[accent] == #""red""#)
        #expect(await copy.removed == [sibling])
    }

    /// A write the item took, then another Mac's later change of the same member: the later change wins here too.
    @Test func anotherMacsChangeAfterThisMacsWriteWasTakenWins() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([accent: #""blue""#])
        let sync = await sync(copy)
        await copy.holdNextAnswer()
        defaults.set("red", forKey: AppearanceKey.accent)
        await sync.flush()
        let write = try #require(await copy.writeIDs.last)
        await copy.answer(write, .taken)
        await copy.change(item, [accent: #""green""#])
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.accent) == "green")
        #expect(await copy.unitsHeld(item)[accent] == #""green""#)
    }

    /// A field write answered while the app was not running, whose answer no sync took, is judged by its conflicted copy.
    @Test func aWriteAnsweredBeforeARelaunchIsJudgedByItsConflictedCopy() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([theme: #""light""#, accent: #""blue""#])
        let sync = await sync(copy)
        await copy.holdNextAnswer()
        defaults.set("red", forKey: AppearanceKey.accent)
        await sync.flush()
        sync.detach()
        await copy.change(item, [theme: #""dark""#, accent: #""blue""#])
        let sibling = await copy.add([theme: #""light""#, accent: #""red""#], conflicted: true)
        await copy.reopen()
        sync.attach(copy, library: "marfa:https://one", name: { nil })
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.accent) == "red")
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
        #expect(await copy.unitsHeld(item)[accent] == #""red""#)
        #expect(await copy.removed == [sibling])
    }

    /// A setting a store dropped is tried again by another app build, which may read it.
    @Test func aDroppedSettingIsTriedAgainByAnotherBuild() async throws {
        let look = PreferenceUnit.row(.types, setting: "look", key: "core.note")
        let copy = FakePreferencesCopy()
        let item = await copy.add([look: #""later""#])
        let looks = TypeLooks(defaults: defaults)
        let first = PreferencesSync(defaults: defaults, domain: suite, enabled: true, coalescing: .milliseconds(50), build: "1") { looks.reload() }
        first.attach(copy, library: "marfa:https://one", name: { nil })
        await first.flush()
        #expect(defaults.data(forKey: TypeLooks.defaultsKey).map { String(decoding: $0, as: UTF8.self) }?.contains("later") != true)
        first.detach()
        // A build whose store reads the value keeps it.
        let second = PreferencesSync(defaults: defaults, domain: suite, enabled: true, coalescing: .milliseconds(50), build: "2") {}
        second.attach(copy, library: "marfa:https://one", name: { nil })
        await second.flush()
        #expect(defaults.data(forKey: TypeLooks.defaultsKey).map { String(decoding: $0, as: UTF8.self) }?.contains("later") == true)
        #expect(await copy.unitsHeld(item)[look] == #""later""#)
    }

    /// A binned settings item's tables, which the copy never fills, and another type's tables, do not keep the
    /// settings from being judged whole.
    @Test func onlyTheTablesOfItemsOutsideTheBinCount() {
        let whole = PreferencesTable.allCases.map { HeldTable(itemId: "kept", table: $0.rawValue, state: .whole, rows: 0) }
        let binned = PreferencesTable.allCases.map { HeldTable(itemId: "binned", table: $0.rawValue, state: .owed, rows: 0) }
        let other = HeldTable(itemId: "other-type", table: PreferencesTable.commands.rawValue, state: .filling, rows: 0)
        #expect(WorkingCopyPreferences.tablesWhole(whole + binned + [other], of: ["kept"]))
        #expect(!WorkingCopyPreferences.tablesWhole(whole + binned, of: ["kept", "binned"]))
    }

    @Test func anItemWithNoTableListedIsNotWhole() {
        #expect(!WorkingCopyPreferences.tablesWhole([], of: ["kept"]))
        let other = HeldTable(itemId: "other-type", table: PreferencesTable.commands.rawValue, state: .whole, rows: 0)
        #expect(!WorkingCopyPreferences.tablesWhole([other], of: ["kept"]))
        let whole = PreferencesTable.allCases.map { HeldTable(itemId: "kept", table: $0.rawValue, state: .whole, rows: 0) }
        #expect(!WorkingCopyPreferences.tablesWhole(whole, of: ["kept", "unlisted"]))
    }

    @Test func anItemMissingOneTableIsNotWhole() {
        let tables = PreferencesTable.allCases
        let all = tables.map { HeldTable(itemId: "kept", table: $0.rawValue, state: .whole, rows: 0) }
        #expect(WorkingCopyPreferences.tablesWhole(all, of: ["kept"]))
        #expect(!WorkingCopyPreferences.tablesWhole(Array(all.dropLast()), of: ["kept"]))
    }

    @Test func noItemIsWhole() {
        #expect(WorkingCopyPreferences.tablesWhole([], of: []))
    }

    /// Start Again after another Marfa was adopted keeps this Mac's settings, as it says.
    @Test func startingAgainKeepsThisMacsSettings() async throws {
        var record = PreferencesSync.Record()
        record.marfas["instance-0"] = .init(item: "elsewhere", base: [:])
        record.save(defaults)
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        defaults.set("dark", forKey: AppearanceKey.theme)
        await sync.flush()
        try await sync.remove()
        await sync.flush()
        try await sync.startAgain()
        #expect(sync.standing == .syncing)
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
        let made = try #require(await copy.activeIDs.first)
        #expect(await copy.unitsHeld(made)[theme] == #""dark""#)
    }

    /// A change the person makes while a step reads the Marfa is not written over by what the step read.
    @Test func aChangeMadeWhileAStepReadsIsKept() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        let item = try #require(await copy.activeIDs.first)
        await copy.change(item, [theme: #""light""#])
        await copy.whileReading { [defaults] in defaults.set("green", forKey: AppearanceKey.theme) }
        await sync.flush()
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.theme) == "green")
        #expect(await copy.unitsHeld(item)[theme] == #""green""#)
    }

    /// An item that went without passing through the bin, as a discarded offline create or a restored server leaves
    /// it, is made again from this Mac's settings; only a binned item means the settings were removed.
    @Test func anItemGoneWithoutTheBinIsMadeAgain() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        let first = try #require(await copy.activeIDs.first)
        await copy.forget(first)
        await sync.flush()
        #expect(sync.standing == .syncing)
        #expect(await copy.creates == 2)
        let made = try #require(await copy.activeIDs.first)
        #expect(await copy.unitsHeld(made)[theme] == #""dark""#)
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
    }

    @Test func switchingMarfasLoadsEachOnesSettings() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        defaults.set(Data(#"{"marfa:https://one":{"core.note":{"date":"created"}}}"#.utf8), forKey: TypeLooks.defaultsKey)
        let one = FakePreferencesCopy()
        let sync = await sync(one)
        let other = FakePreferencesCopy()
        await other.set(PreferencesReadiness(filled: true, holdsType: true, tablesWhole: true, instance: "instance-2"))
        await other.add([theme: #""light""#])
        sync.attach(other, library: "marfa:https://two", name: { nil })
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.theme) == "light")
        sync.attach(one, library: "marfa:https://one", name: { nil })
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
        #expect(await one.updates.isEmpty)
        // Each switch saved the settings of the Marfa followed before it.
        #expect(try saved().map(\.0) == [.firstSync, .adoption, .switching])
        #expect(try saved().map(\.1) == ["dark", "dark", "light"])
        // A setting kept for each server is held whole, so no point mixes one Marfa's entry with another's settings.
        for point in points.list() {
            let looks = try #require(try points.snapshot(of: point.id).value(forKey: TypeLooks.defaultsKey) as? Data)
            #expect((try JSONSerialization.jsonObject(with: looks) as? [String: Any])?["marfa:https://one"] != nil)
        }
    }

    @Test func aStepWhoseRestorePointCannotBeSavedChangesNothingAndTriesAgain() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        // A file where the points' folder would go.
        try Data().write(to: points.folder)
        let copy = FakePreferencesCopy()
        await copy.add([theme: #""light""#])
        let sync = PreferencesSync(defaults: defaults, domain: suite, enabled: true, coalescing: .milliseconds(50), restorePoints: points) {}
        sync.attach(copy, library: "marfa:https://one", name: { nil })
        await sync.flush()
        #expect(sync.standing != .syncing)
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
        #expect(await copy.updates.isEmpty)
        try FileManager.default.removeItem(at: points.folder)
        await sync.flush()
        #expect(sync.standing == .syncing)
        #expect(defaults.string(forKey: AppearanceKey.theme) == "light")
        #expect(try saved().map(\.0) == [.adoption])
    }

    /// What an import wrote wins at the next step, even over another Mac's change this Mac had not taken.
    @Test func anImportWinsOverAChangeNotYetTaken() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([accent: #""blue""#])
        var record = PreferencesSync.Record()
        record.marfas["instance-1"] = .init(item: item, base: [:])
        record.last = "instance-1"
        record.save(defaults)
        let sync = PreferencesSync(defaults: defaults, domain: suite, enabled: true, coalescing: .milliseconds(50), restorePoints: points) {}
        try await sync.importSettings(SettingsFile(units: [:], build: "", date: .now), sections: [.appearance])
        sync.attach(copy, library: "marfa:https://one", name: { nil })
        await sync.flush()
        #expect(defaults.object(forKey: AppearanceKey.accent) == nil)
        #expect(await copy.unitsHeld(item)[accent] == nil)
        #expect(PreferencesSync.Record.read(defaults).winning == nil)
    }

    /// An import's write the copy refuses is sent again alone: what the writes before it carried no longer wins, so
    /// another Mac's later change to it stands.
    @Test func aPartlyWrittenImportSendsAgainOnlyWhatWasNotWritten() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        let item = try #require(await copy.activeIDs.first)
        await copy.refuseNextWrite(to: .types)
        let file = SettingsFile(units: [theme: #""light""#, placement: #"{"pins":["due_at"]}"#], build: "", date: .now)
        try await sync.importSettings(file, sections: [SettingsFile.Section(theme), SettingsFile.Section(placement)])
        #expect(await copy.unitsHeld(item)[placement] == nil)
        await copy.change(item, [theme: #""dark""#])
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
        #expect(await copy.unitsHeld(item)[theme] == #""dark""#)
        #expect(await copy.unitsHeld(item)[placement] == #"{"pins":["due_at"]}"#)
        #expect(PreferencesSync.Record.read(defaults).winning == nil)
    }

    /// Another Mac's value that a step wrote into the defaults stays the Marfa's when the copy then refuses this Mac's
    /// write: the retry takes that Mac's later change and never sends the earlier value back as this Mac's.
    @Test func anotherMacsValueTakenBeforeARefusedWriteIsNotSentBack() async throws {
        defaults.set("system", forKey: AppearanceKey.theme)
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        let item = try #require(await copy.activeIDs.first)
        sync.detach()
        await copy.change(item, [theme: #""dark""#])
        let file = SettingsFile(units: [placement: #"{"pins":["due_at"]}"#], build: "", date: .now)
        try await sync.importSettings(file, sections: [SettingsFile.Section(placement)])
        await copy.refuseNextWrite(to: .types)
        sync.attach(copy, library: "marfa:https://one", name: { nil })
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
        #expect(await copy.unitsHeld(item)[placement] == nil)
        await copy.change(item, [theme: #""light""#])
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.theme) == "light")
        #expect(await copy.unitsHeld(item)[theme] == #""light""#)
        #expect(await copy.unitsHeld(item)[placement] == #"{"pins":["due_at"]}"#)
    }

    /// A value an import skipped is what this Mac held, not the import's, so it does not win over another Mac's change.
    @Test func aValueAnImportSkippedDoesNotWin() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        let item = try #require(await copy.activeIDs.first)
        sync.detach()
        await copy.change(item, [theme: #""light""#])
        // The defaults cannot keep a null inside a value.
        try await sync.importSettings(
            SettingsFile(units: [theme: #"{"nested":[null]}"#], build: "", date: .now), sections: [.appearance])
        sync.attach(copy, library: "marfa:https://one", name: { nil })
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.theme) == "light")
        #expect(await copy.unitsHeld(item)[theme] == #""light""#)
    }

    /// Reset waits for a step under way, so the step does not write what it read over the defaults, and Reset wins.
    @Test func resetWhileAStepAwaitsTheCopyIsResetOnBothSides() async throws {
        let bench = HostBench()
        let libraries = Libraries(
            host: bench.host(), defaults: defaults, handOverPages: { $0(true) }, syncsPreferences: true, restorePoints: points,
            defaultsDomain: suite)
        let sync = libraries.preferences
        let copy = FakePreferencesCopy()
        sync.attach(copy, library: "marfa:https://one", name: { nil })
        await sync.flush()
        let item = try #require(await copy.activeIDs.first)
        var followed = false
        await copy.whileReading { libraries.resetMacSettings { followed = true } }
        await copy.change(item, [theme: #""light""#])
        await sync.flush()
        let reset = try await eventuallyAsking {
            guard defaults.object(forKey: AppearanceKey.theme) == nil else { return false }
            return await copy.unitsHeld(item)[theme] == nil
        }
        #expect(reset)
        #expect(followed)
        #expect(try saved().map(\.0) == [.firstSync, .reset])
    }

    /// Reset that waits for a step and then cannot save its point changes nothing, and what follows it does not run.
    @Test func resetThatWaitsAndCannotSaveItsPointRunsNothingAfter() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        let bench = HostBench()
        let libraries = Libraries(
            host: bench.host(), defaults: defaults, handOverPages: { $0(true) }, syncsPreferences: true, restorePoints: points,
            defaultsDomain: suite)
        let sync = libraries.preferences
        let copy = FakePreferencesCopy()
        sync.attach(copy, library: "marfa:https://one", name: { nil })
        await sync.flush()
        var followed = false
        await copy.whileReading { [points] in
            // A file where the points' folder was, so the point Reset saves after the step cannot be written.
            try? FileManager.default.removeItem(at: points.folder)
            try? Data().write(to: points.folder)
            libraries.resetMacSettings { followed = true }
        }
        let item = try #require(await copy.activeIDs.first)
        await copy.change(item, [accent: #""blue""#])
        await sync.flush()
        let told = await eventually { libraries.host.notices.waiting.map(\.title) == [String(localized: "Settings Not Reset")] }
        #expect(told)
        #expect(!followed)
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
    }

    /// A step that tries again after a refused write saves no second copy of the same point, which would push a real
    /// one out of the ten.
    @Test func aStepThatTriesAgainSavesOnePoint() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        let copy = FakePreferencesCopy()
        await copy.refuseNextCreate()
        let sync = await sync(copy)
        #expect(sync.standing != .syncing)
        await sync.flush()
        #expect(sync.standing == .syncing)
        #expect(try saved().map(\.0) == [.firstSync])
    }

    @Test func aDroppedSettingThePersonChangesAndThenClearsIsDeletedFromTheMarfa() async throws {
        let look = PreferenceUnit.row(.types, setting: "look", key: "core.note")
        let copy = FakePreferencesCopy()
        let item = await copy.add([look: #""later""#])
        let looks = TypeLooks(defaults: defaults)
        let sync = PreferencesSync(defaults: defaults, domain: suite, enabled: true, coalescing: .milliseconds(50), build: "1") { looks.reload() }
        sync.attach(copy, library: "marfa:https://one", name: { nil })
        await sync.flush()
        await sync.flush()
        #expect(await copy.unitsHeld(item)[look] == #""later""#)
        defaults.set(Data(#"{"marfa:https://one":{"core.note":{"date":"created"}}}"#.utf8), forKey: TypeLooks.defaultsKey)
        await sync.flush()
        #expect(await copy.unitsHeld(item)[look] == #"{"date":"created"}"#)
        defaults.set(Data(#"{"marfa:https://one":{}}"#.utf8), forKey: TypeLooks.defaultsKey)
        await sync.flush()
        await sync.flush()
        #expect(await copy.unitsHeld(item)[look] == nil)
    }

    @Test func removedSettingsStayRemovedOnceTheBinIsEmptied() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        let copy = FakePreferencesCopy()
        let sync = PreferencesSync(defaults: defaults, domain: suite, enabled: true, coalescing: .milliseconds(50)) {}
        sync.attach(copy, library: "marfa:https://one", name: { nil })
        await sync.flush()
        let first = try #require(await copy.activeIDs.first)
        try await sync.remove()
        await sync.flush()
        #expect(sync.standing == .off(.removed))
        await copy.forget(first)
        await sync.flush()
        #expect(sync.standing == .off(.removed))
        #expect(await copy.creates == 1)
    }
}

@MainActor @Suite(.hangLimit) struct PreferencesWiringTests {
    /// The library's copy is followed as it opens and let go as it closes; a copy whose slice lacks the type, as the
    /// sample's does, changes nothing on this Mac.
    @Test func theSettingsFollowTheOpenLibrary() async throws {
        let bench = HostBench()
        let host = bench.host(opener: { connection, _, _ in SampleLibrary.open(connection) })
        let libraries = Libraries(host: host, defaults: bench.defaults, syncsPreferences: true, defaultsDomain: bench.suite)
        bench.defaults.set("dark", forKey: AppearanceKey.theme)
        #expect(libraries.preferences.standing == .off(.noMarfa))
        try await host.connect(address: SampleLibrary.connection.address.absoluteString, key: "sample")
        #expect(await eventually { libraries.preferences.standing != .off(.noMarfa) })
        await libraries.preferences.flush()
        #expect(libraries.preferences.standing != .syncing)
        #expect(bench.defaults.string(forKey: AppearanceKey.theme) == "dark")
        try await host.disconnect()
        #expect(libraries.preferences.standing == .off(.noMarfa))
    }
}
