import Foundation
import Testing
@testable import MarfaMac

/// The density each place keeps on this Mac.
struct PlaceDensitiesTests {
    private static func defaults() -> UserDefaults {
        let defaults = ThrowawayDefaults.make("MarfaMac.PlaceDensitiesTests")
        return defaults
    }

    @Test func eachPlaceKeepsItsOwnDensityAndOneWithNoneFollowsSettings() {
        let defaults = Self.defaults()
        PlaceDensities.update(in: defaults) {
            $0.set(.compact, for: .library)
            $0.set(.standard, for: .type(TypeID("core.task")))
        }
        let stored = PlaceDensities.stored(in: defaults)
        #expect(stored.density(for: .library) == .compact)
        #expect(stored.density(for: .type(TypeID("core.task"))) == .standard)
        #expect(stored.density(for: .type(TypeID("core.note"))) == nil)
        #expect(stored.density(for: .recents) == nil)
    }

    @Test func clearingTheLastDensityRemovesTheKey() {
        let defaults = Self.defaults()
        PlaceDensities.update(in: defaults) { $0.set(.compact, for: .library) }
        PlaceDensities.update(in: defaults) { $0.set(nil, for: .library) }
        #expect(defaults.data(forKey: PlaceDensities.key) == nil)
        #expect(defaults.array(forKey: PlaceDensities.setAsideKey) == nil)
    }

    @Test func unreadableTextIsSetAsideAndNeverRemoved() {
        let defaults = Self.defaults()
        let garbage = Data("not json".utf8)
        defaults.set(garbage, forKey: PlaceDensities.key)
        #expect(PlaceDensities.stored(in: defaults).density(for: .library) == nil)
        PlaceDensities.update(in: defaults) { $0.set(.compact, for: .library) }
        #expect(defaults.array(forKey: PlaceDensities.setAsideKey) as? [Data] == [garbage])
        #expect(PlaceDensities.stored(in: defaults).density(for: .library) == .compact)
    }

    @Test func allItemsKeepsTheKeyItWasStoredUnder() {
        #expect(PlaceView.library.storageKey == #"{"allNotes":{}}"#)
    }

    @Test func aDensityThisVersionDoesNotKnowIsSetAsideWhileTheRestIsKept() throws {
        let defaults = Self.defaults()
        let key = PlaceView.library.storageKey
        defaults.set(try JSONEncoder().encode([key: "compact", "other": "roomy"]), forKey: PlaceDensities.key)
        PlaceDensities.update(in: defaults) { $0.set(.standard, for: .recents) }
        let aside = try #require(defaults.array(forKey: PlaceDensities.setAsideKey) as? [Data])
        #expect(try JSONDecoder().decode([String: String].self, from: aside[0]) == ["other": "roomy"])
        let stored = PlaceDensities.stored(in: defaults)
        #expect(stored.density(for: .library) == .compact)
        #expect(stored.density(for: .recents) == .standard)
    }
}
