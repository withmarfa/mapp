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
        #expect(stored.density(for: .feed) == nil)
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

    /// A density this version does not know stays as stored beside the rest until the person sets that place, and is
    /// set aside with its place first.
    @Test func aDensityThisVersionDoesNotKnowStaysUntilThePlaceIsSet() throws {
        let defaults = Self.defaults()
        let key = PlaceView.library.storageKey
        let other = PlaceView.feed.storageKey
        defaults.set(try JSONEncoder().encode([key: "compact", other: "roomy"]), forKey: PlaceDensities.key)
        PlaceDensities.update(in: defaults) { $0.set(.standard, for: .favorites) }
        #expect(defaults.object(forKey: PlaceDensities.setAsideKey) == nil)
        #expect(try JSONDecoder().decode([String: String].self, from: #require(defaults.data(forKey: PlaceDensities.key)))[other] == "roomy")
        PlaceDensities.update(in: defaults) { $0.set(.standard, for: .feed) }
        let aside = try #require(defaults.array(forKey: PlaceDensities.setAsideKey) as? [Data])
        #expect(try aside.map { try JSONDecoder().decode([String: String].self, from: $0) } == [[other: "roomy"]])
        let stored = PlaceDensities.stored(in: defaults)
        #expect(stored.density(for: .library) == .compact)
        #expect(stored.density(for: .feed) == .standard)
    }
}
