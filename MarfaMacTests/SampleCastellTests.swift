import Foundation
import Marfa
import Testing
@testable import MarfaMac

/// The sample libraries the design boards are drawn from: Castell Studio holds the counts its boards state, and the heavy
/// library builds about fifty thousand items quickly enough to be launched for a speed check. The time is printed as
/// `SAMPLE|<name>|<value>|<unit>`, for a person to read.
@Suite struct SampleCastellTests {
    @Test func theStudioHoldsItsBoardsCountsAndTheHeavyLibraryBuildsFast() {
        let studio = SampleCastell.world(.studio, now: .now)
        let library = studio.items.filter { $0.tier == .library && $0.state == .active }
        #expect(library.count == 1_205)
        #expect(studio.items.filter { $0.tier == .feed && $0.state == .active }.count == 69)
        let byType = Dictionary(grouping: library, by: \.type).mapValues(\.count)
        #expect(byType["core.note"] == 223)
        #expect(byType["core.task"] == 103)
        #expect(byType["core.bookmark"] == 168)
        #expect(byType["core.highlight"] == 130)
        #expect(byType["core.file"] == 149)
        #expect(byType["core.collection"] == 4)
        #expect(SampleCastell.libraryCounts(of: studio.items) == [
            "oauth:marfa-for-mac": 336, "studio-folder": 333, "readwise": 241, "rss": 140, "oauth:raycast": 109,
            "oauth:claude": 36, "github": 10,
        ])
        #expect(Set(studio.items.map(\.id)).count == studio.items.count)
        #expect(studio.items.contains { $0.state == .archived && $0.tier == .feed })
        #expect(studio.items.contains { $0.state == .archived && $0.tier == .library })
        #expect(studio.items.contains { $0.state == .trashed })
        #expect(studio.items.contains { $0.readOnly })

        let clock = ContinuousClock()
        var heavy = SampleCastell.World(items: [], edges: [])
        let took = clock.measure { heavy = SampleCastell.world(.heavy, now: .now) }
        let seconds = Double(took.components.seconds) + Double(took.components.attoseconds) / 1e18
        print("SAMPLE|heavyBuild|\(String(format: "%.0f", seconds * 1000))|ms")
        #expect(heavy.items.filter { $0.tier == .library && $0.state == .active }.count == 48_312)
        #expect(heavy.items.count > 49_000 && heavy.items.count < 51_000)
        #expect(Set(heavy.items.map(\.id)).count == heavy.items.count)
        #expect(seconds < 10)
    }
}
