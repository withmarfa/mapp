import Foundation
import Testing
@testable import MAPP

/// The density each place keeps on this Mac.
struct PlaceDensitiesTests {
    private static func defaults() -> UserDefaults {
        let suite = "MAPP.PlaceDensitiesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func eachPlaceKeepsItsOwnDensityAndOneWithNoneFollowsSettings() {
        let defaults = Self.defaults()
        PlaceDensities.update(in: defaults) {
            $0.set(.compact, for: .allNotes)
            $0.set(.standard, for: .itemType("core.task"))
        }
        let stored = PlaceDensities.stored(in: defaults)
        #expect(stored.density(for: .allNotes) == .compact)
        #expect(stored.density(for: .itemType("core.task")) == .standard)
        #expect(stored.density(for: .itemType("core.note")) == nil)
        #expect(stored.density(for: .recents) == nil)
    }

    @Test func clearingTheLastDensityRemovesTheKey() {
        let defaults = Self.defaults()
        PlaceDensities.update(in: defaults) { $0.set(.compact, for: .allNotes) }
        PlaceDensities.update(in: defaults) { $0.set(nil, for: .allNotes) }
        #expect(defaults.data(forKey: PlaceDensities.key) == nil)
        #expect(defaults.array(forKey: PlaceDensities.setAsideKey) == nil)
    }

    @Test func unreadableTextIsSetAsideAndNeverRemoved() {
        let defaults = Self.defaults()
        let garbage = Data("not json".utf8)
        defaults.set(garbage, forKey: PlaceDensities.key)
        #expect(PlaceDensities.stored(in: defaults).density(for: .allNotes) == nil)
        PlaceDensities.update(in: defaults) { $0.set(.compact, for: .allNotes) }
        #expect(defaults.array(forKey: PlaceDensities.setAsideKey) as? [Data] == [garbage])
        #expect(PlaceDensities.stored(in: defaults).density(for: .allNotes) == .compact)
    }

    @Test func aDensityThisVersionDoesNotKnowIsSetAsideWhileTheRestIsKept() throws {
        let defaults = Self.defaults()
        let key = SidebarItem.allNotes.storageKey
        defaults.set(try JSONEncoder().encode([key: "compact", "other": "roomy"]), forKey: PlaceDensities.key)
        PlaceDensities.update(in: defaults) { $0.set(.standard, for: .recents) }
        let aside = try #require(defaults.array(forKey: PlaceDensities.setAsideKey) as? [Data])
        #expect(try JSONDecoder().decode([String: String].self, from: aside[0]) == ["other": "roomy"])
        let stored = PlaceDensities.stored(in: defaults)
        #expect(stored.density(for: .allNotes) == .compact)
        #expect(stored.density(for: .recents) == .standard)
    }
}
