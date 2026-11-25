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

    /// The places show the studio as its boards count it, read through the library's place calls: the Library holds only
    /// Library items, the Feed only Feed items, the Archive every archived item of both tiers, and each source, type and
    /// collection what it wrote or holds.
    @MainActor @Test func thePlacesListWhatTheBoardsCount() async throws {
        let world = SampleCastell.world(.studio, now: .now)
        let source = SampleLibrary.open(SampleLibrary.connection, castell: .studio)
        let library = MarfaLibrary(source: source, notices: Notices())
        source.refresh()
        try #require(await eventually { library.isLoaded })

        func ids(_ place: Place, _ scope: ListScope = .all, archived: ArchivedItems = .hidden, kinds: Bool = true) -> Set<ItemID> {
            Set(library.items(in: place, scope: scope, archived: archived, includingKinds: kinds).map(\.id))
        }
        let active = world.items.filter { $0.state == .active }
        let archived = world.items.filter { $0.state == .archived }

        #expect(library.count(in: .library, scope: .library) == 1_205)
        #expect(library.count(in: .feed, scope: .feed) == 69)
        #expect(ids(.library) == Set(active.filter { $0.tier == .library }.map { ItemID($0.id) }))
        #expect(ids(.feed) == Set(active.filter { $0.tier == .feed }.map { ItemID($0.id) }))
        #expect(library.items(in: .library, scope: .library, archived: .hidden, includingKinds: true).allSatisfy { $0.tier == .library && $0.state == .active })
        #expect(library.items(in: .feed, scope: .feed, archived: .hidden, includingKinds: true).allSatisfy { $0.tier == .feed && $0.state == .active })

        let inArchive = library.items(in: .archive, scope: .all, archived: .only, includingKinds: true)
        #expect(Set(inArchive.map(\.id)) == Set(archived.map { ItemID($0.id) }))
        #expect(inArchive.allSatisfy { $0.state == .archived })
        #expect(Set(inArchive.map(\.tier)) == [.library, .feed])
        let archiveCounts = library.scopeCounts(in: .archive)
        #expect(archiveCounts == ScopeCounts(library: archived.filter { $0.tier == .library }.count, feed: archived.filter { $0.tier == .feed }.count))
        #expect(archiveCounts.library > 0 && archiveCounts.feed > 0)
        print("SAMPLE|studioArchive|\(archiveCounts.library)+\(archiveCounts.feed)|items")
        #expect(!world.items.filter { $0.state == .trashed }.contains { ids(.library).contains(ItemID($0.id)) })

        // Each source lists what it wrote in the tiers asked for, and the Library tier alone counts as the Sources board does.
        for (code, count) in SampleCastell.libraryCounts(of: world.items) {
            #expect(library.count(in: .source(code), scope: .library) == count, "\(code)")
        }
        for code in SampleCastell.sourceInfos.map(\.code) {
            let wrote = active.filter { $0.source == code }
            #expect(library.scopeCounts(in: .source(code)) == ScopeCounts(
                library: wrote.filter { $0.tier == .library }.count, feed: wrote.filter { $0.tier == .feed }.count), "\(code)")
            #expect(ids(.source(code), .all) == Set(wrote.map { ItemID($0.id) }), "\(code)")
        }
        #expect(ids(.source(SampleCastell.Code.readwise), .feed).count > 0)

        // Each type lists its items, and its kinds when asked.
        for type in Set(active.map(\.type)) {
            let own = active.filter { $0.type == type }
            let counts = library.scopeCounts(in: .type(TypeID(type)))
            #expect(counts.library >= own.filter { $0.tier == .library }.count, "\(type)")
            #expect(ids(.type(TypeID(type)), .all, kinds: false) == Set(own.map { ItemID($0.id) }), "\(type)")
            #expect(ids(.type(TypeID(type)), .all).isSuperset(of: ids(.type(TypeID(type)), .all, kinds: false)), "\(type)")
        }
        // The boards count a type's own items; its place also lists its kinds, as the count of the place says.
        for type in Set(active.map(\.type)) {
            #expect(library.count(in: .type(TypeID(type)), scope: .library) == ids(.type(TypeID(type)), .library).count, Comment(rawValue: type))
        }
        #expect(ids(.type(TypeID(SampleCastell.Kind.note)), .library, kinds: false).count == 223)
        #expect(ids(.type(TypeID(SampleCastell.Kind.task)), .library, kinds: false).count == 103)
        #expect(ids(.type(TypeID(SampleCastell.Kind.bookmark)), .library, kinds: false).count == 168)
        #expect(ids(.type(TypeID(SampleCastell.Kind.highlight)), .library, kinds: false).count == 130)
        #expect(ids(.type(TypeID(SampleCastell.Kind.file)), .library, kinds: false).count == 149)
        #expect(ids(.type(TypeID(SampleCastell.Kind.collection)), .library, kinds: false).count == 4)

        // Each collection lists the active items filed in it.
        let collections = active.filter { $0.type == SampleCastell.Kind.collection }
        #expect(collections.count == 4)
        for collection in collections {
            let members = Set(world.edges.filter { $0.edgeType == "in-collection" && $0.toId == collection.id }.map(\.fromId))
            let expected = Set(active.filter { members.contains($0.id) }.map { ItemID($0.id) })
            #expect(ids(.collection(ItemID(collection.id)), .all) == expected, Comment(rawValue: collection.id))
            #expect(!expected.isEmpty, Comment(rawValue: collection.id))
        }
    }
}
