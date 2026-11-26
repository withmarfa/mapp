import Foundation
import Testing
@testable import MarfaMac

/// Settings rows this Mac cannot read, or that a store set aside: none is deleted or overwritten but by the person's own
/// change here, and a step that changes nothing writes nothing. Each case is one a review reproduced.
@MainActor @Suite(.hangLimit) final class PreferencesUnreadableRowTests {
    let defaults = ThrowawayDefaults.make("MarfaMacTests.PreferencesUnreadableRows")
    let points = RestorePoints(folder: URL.temporaryDirectory.appending(path: "PreferencesUnreadableRowTests-\(UUID().uuidString)"))
    let library = "marfa:https://one"
    let placement = PreferenceUnit.row(.types, setting: "pagePlacements", key: "core.note")
    let theme = PreferenceUnit.member(.appearance, AppearanceKey.theme)
    /// The settings a library's earlier name still holds, as `LibrarySettings` says.
    var unsettled: Set<String> = []

    deinit {
        try? FileManager.default.removeItem(at: points.folder)
    }

    private func sync(_ copy: FakePreferencesCopy) async -> PreferencesSync {
        let sync = PreferencesSync(
            defaults: defaults, domain: defaults.suite, enabled: true, coalescing: .milliseconds(50), restorePoints: points,
            unsettled: { [weak self] _ in self?.unsettled ?? [] }) {}
        sync.attach(copy, library: library, name: { nil })
        await sync.flush()
        return sync
    }

    private func density(_ place: PlaceView) -> PreferenceUnit {
        .row(.places, setting: "placeDensity", key: place.storageKey)
    }

    private func hidden(_ view: ViewChoice) -> PreferenceUnit {
        .row(.places, setting: "viewHidden", key: ViewOrders.hiddenRowKey(view, in: .library))
    }

    /// What a store set aside, as text, in the order it was set aside.
    private func setAside(_ key: String) -> [String] {
        defaults.stringArray(forKey: key) ?? (defaults.array(forKey: key) as? [Data] ?? []).map { String(decoding: $0, as: UTF8.self) }
    }

    private func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys)) ?? Data()
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

    /// An earlier app recorded a row that is not JSON as held, without setting it aside or storing it: the first step of
    /// this one keeps it.
    @Test func aRowThatIsNotJSONAnEarlierAppRecordedStaysAfterTheUpgrade() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([placement: "{not json", theme: #""light""#])
        defaults.set("light", forKey: AppearanceKey.theme)
        var record = PreferencesSync.Record()
        record.marfas["instance-1"] = .init(item: item, base: [placement: "{not json", theme: #""light""#])
        record.last = "instance-1"
        record.save(defaults)
        let sync = await sync(copy)
        await sync.flush()
        #expect(await copy.unitsHeld(item)[placement] == "{not json")
        defaults.set(#"{"core.task":{"pins":["due_at"]}}"#, forKey: PagePlacements.key)
        await sync.flush()
        #expect(await copy.unitsHeld(item)[placement] == "{not json")
    }

    /// Reset made before this Mac received another Mac's new row that is not JSON keeps the row.
    @Test func resetKeepsARowThatIsNotJSONThisMacHasNotSeen() async throws {
        defaults.set(#"{"core.task":{"pins":[]}}"#, forKey: PagePlacements.key)
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        let item = try #require(await copy.activeIDs.first)
        await copy.change(item, [placement: "{not json"])
        MacSettings.reset(in: defaults)
        sync.replaced(PreferencesMap.synced)
        await sync.flush()
        await sync.flush()
        #expect(await copy.unitsHeld(item)[placement] == "{not json")
        #expect(setAside(PagePlacements.setAsideKey).contains("{not json"))
    }

    /// A store that sets aside a library's looks while the library's earlier name still holds them keeps every row once
    /// the name moves.
    @Test func aHoldWaitsWhileItsSettingIsUnsettled() async throws {
        let note = PreferenceUnit.row(.types, setting: "look", key: "core.note")
        let copy = FakePreferencesCopy()
        let item = await copy.add([note: #"{"date":"created"}"#])
        let sync = await sync(copy)
        #expect(defaults.data(forKey: TypeLooks.defaultsKey) != nil)
        unsettled = [TypeLooks.defaultsKey]
        defaults.set(json([library: [1]]), forKey: TypeLooks.defaultsKey)
        _ = TypeLooks(defaults: defaults)
        await sync.flush()
        unsettled = []
        await sync.flush()
        await sync.flush()
        #expect(await copy.unitsHeld(item)[note] == #"{"date":"created"}"#)
    }

    /// The person replaces a density this Mac cannot read, then clears their choice before the next step: the removal
    /// reaches the Marfa, and the density replaced is kept with its place.
    @Test func aDensityReplacedThenClearedBeforeTheNextStepIsRemoved() async throws {
        let place = density(.library)
        let copy = FakePreferencesCopy()
        let item = await copy.add([place: #""standard""#])
        let sync = await sync(copy)
        defaults.set(json([PlaceView.library.storageKey: "spacious"]), forKey: PlaceDensities.key)
        PlaceDensities.update(in: defaults) { $0.set(.compact, for: .library) }
        PlaceDensities.update(in: defaults) { $0.set(nil, for: .library) }
        await sync.flush()
        await sync.flush()
        #expect(await copy.unitsHeld(item)[place] == nil)
        #expect(setAside(PlaceDensities.setAsideKey) == [String(decoding: json([PlaceView.library.storageKey: "spacious"]), as: UTF8.self)])
    }

    /// A value set aside for every library, once each library's step has taken it, writes nothing at later steps.
    @Test func aValueSetAsideForEveryLibraryWritesNothingOnceTaken() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([theme: #""light""#])
        let sync = await sync(copy)
        defaults.set(Data("[1]".utf8), forKey: TypeLooks.defaultsKey)
        _ = TypeLooks(defaults: defaults)
        await sync.flush()
        await sync.flush()
        let count = await writes {
            for _ in 0..<4 { await sync.flush() }
        }
        #expect(count == 0)
        #expect(await copy.unitsHeld(item)[theme] == #""light""#)
    }

    /// A hidden view this Mac cannot read beside one it can: the Marfa keeps both rows, and a step that changes nothing
    /// writes nothing.
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
        await sync.flush()
        await sync.flush()
        let count = await writes {
            for _ in 0..<4 { await sync.flush() }
        }
        #expect(count == 0)
        #expect(await copy.unitsHeld(item)[own] == "true")
        #expect(await copy.unitsHeld(item)[favorites] == "true")
    }

    /// A type's page placements this Mac cannot read, replaced by the person's change, are set aside with the type they
    /// belong to.
    @Test func aPlacementReplacedIsSetAsideWithItsType() {
        defaults.set(#"{"core.note":"later","core.task":{"pins":["due_at"]}}"#, forKey: PagePlacements.key)
        PagePlacements.update(in: defaults) { $0.reset(TypeID("core.note")) }
        let kept = setAside(PagePlacements.setAsideKey).compactMap { PreferenceJSON.value($0) as? [String: Any] }
        #expect(kept.contains { $0["core.note"] as? String == "later" })
    }

    /// A density map restored as text rather than data is read as the same map: the person's choice for one place keeps
    /// every other place's density, here and in the Marfa.
    @Test func aDensityMapStoredAsTextKeepsTheOtherPlacesRows() async throws {
        let place = density(.library)
        let other = density(.favorites)
        let copy = FakePreferencesCopy()
        let item = await copy.add([place: #""compact""#, other: #""standard""#])
        let sync = await sync(copy)
        let text = String(decoding: json([PlaceView.library.storageKey: "compact", PlaceView.favorites.storageKey: "standard"]), as: UTF8.self)
        defaults.set(text, forKey: PlaceDensities.key)
        PlaceDensities.update(in: defaults) { $0.set(.standard, for: .library) }
        await sync.flush()
        await sync.flush()
        #expect(await copy.unitsHeld(item)[place] == #""standard""#)
        #expect(await copy.unitsHeld(item)[other] == #""standard""#)
        #expect(PlaceDensities.stored(in: defaults).density(for: .favorites) == .standard)
    }

    /// A restored density this Mac's store cannot read never replaces the Marfa's; the Marfa's comes back here.
    @Test func aRestoredDensityThisMacCannotReadLeavesTheMarfas() async throws {
        let place = density(.library)
        let copy = FakePreferencesCopy()
        let item = await copy.add([place: #""compact""#])
        let sync = await sync(copy)
        defaults.set(json([PlaceView.library.storageKey: "spacious"]), forKey: PlaceDensities.key)
        sync.replaced(PreferencesMap.synced.filter { $0.key == PlaceDensities.key })
        await sync.flush()
        await sync.flush()
        #expect(await copy.unitsHeld(item)[place] == #""compact""#)
        #expect(PlaceDensities.stored(in: defaults).density(for: .library) == .compact)
    }

    /// The same for a member: a restored theme this Mac cannot read never replaces the Marfa's.
    @Test func aRestoredThemeThisMacCannotReadLeavesTheMarfas() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([theme: #""dark""#])
        let sync = await sync(copy)
        defaults.set("a theme a later version names", forKey: AppearanceKey.theme)
        sync.replaced(PreferencesMap.synced.filter { $0.key == AppearanceKey.theme })
        await sync.flush()
        await sync.flush()
        #expect(await copy.unitsHeld(item)[theme] == #""dark""#)
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
    }
}
