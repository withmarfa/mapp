import Foundation
import Testing

@testable import MarfaMac

/// How a sidebar an earlier copy arranged reads in this one, and what this copy writes back: what the person placed is
/// under Pinned or in their own sections, nothing is lost without a word, and every word this copy does not read is
/// written back as it was, for the copies that do.
@Suite
@MainActor
struct SidebarReadingTests {
    private func library() -> FakeItemLibrary {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("One", modified: .now)])
        library.views = ["A", "B", "C"].map { LibraryView(id: ItemID("v-\($0)"), title: $0) }
        library.items += [FakeItemLibrary.collection("Kept"), FakeItemLibrary.collection("Loose")]
        return library
    }

    private func read(_ json: String) throws -> SidebarLayout {
        try JSONDecoder().decode(SidebarLayout.self, from: Data(json.utf8))
    }

    private func view(_ name: String) -> SidebarPlace { .view(ItemID("v-" + name)) }

    /// An arranged sidebar as an earlier copy wrote it: Library and Views sections, a section of the person's own, a
    /// section of a kind no copy here knows, colors, and keys that name what is gone.
    private func arranged(_ library: FakeItemLibrary) -> String {
        let kept = SidebarPlace.collection(library.collections[0].id).key
        let loose = SidebarPlace.collection(library.collections[1].id).key
        return """
        {"hidden":["favorites","view:v-C","recents"],"order":["inbox","favorites","view:v-B","view:v-A","\(loose)"],
        "collapsed":["type:core.note"],
        "tabs":[{"id":"home","name":"Home","symbol":"house"},{"id":"work","name":"Work","symbol":"rectangle.stack"}],
        "groups":[
        {"id":"shortcuts","kind":"shortcuts","tab":"home","isHidden":false,"shortcuts":["new","search","go:view:v-A"]},
        {"id":"library","kind":"library","tab":"home","isHidden":false,"shortcuts":[]},
        {"id":"views","kind":"views","tab":"home","title":"Reading","isHidden":false,"shortcuts":[]},
        {"id":"later","kind":"pinboard","tab":"home","extra":1},
        {"id":"types","kind":"types","tab":"home","isHidden":false,"shortcuts":[]},
        {"id":"mine","kind":"custom","tab":"work","title":"Mine","isHidden":false,"shortcuts":[]}],
        "homes":{"view:v-A":"mine","\(kept)":"mine","\(loose)":"views","source:rss":"library","sources":"library","all":"library",
        "inbox":"views","favorites":"views"},
        "colors":{"view:v-A":"purple","inbox":"blue"}}
        """
    }

    // MARK: Reading

    @Test func aSidebarNobodyArrangedReadsWithTheSavedViewsPinned() throws {
        let layout = try read(#"{"hidden":["favorites","view:v-C"],"order":["view:v-B","view:v-A"],"collapsed":[]}"#)
        let plan = SidebarPlan(library(), layout: layout)
        #expect(plan.groups(in: SidebarTab.homeID, customizing: false).map(\.group.kind) == [.shortcuts, .places, .pinned, .types])
        #expect(plan.section(.shortcuts)?.group.shortcuts == [.search, .new])
        #expect(plan.section(.places)?.shown == [.library, .feed], "the Library's pages leave the sidebar")
        #expect(plan.section(.pinned)?.shown == [view("B"), view("A")], "the person's order, and a hidden view stays hidden")
    }

    @Test func anArrangedSidebarKeepsItsSectionsAndPinsWhatWasPlacedUnderLibraryOrViews() throws {
        let library = library()
        let layout = try read(arranged(library))
        let plan = SidebarPlan(library, layout: layout)
        let kept = SidebarPlace.collection(library.collections[0].id)
        let loose = SidebarPlace.collection(library.collections[1].id)

        #expect(layout.allTabs.map(\.id) == ["home", "work"])
        #expect(layout.groups(in: "home").map(\.kind) == [.shortcuts, .places, .pinned, .types])
        #expect(plan.section(.shortcuts)?.group.shortcuts == [.new, .search, .go("view:v-A")], "the person's commands, as stored")
        #expect(plan.section(.places)?.shown == [.library, .feed])
        let pinned = try #require(plan.section(.pinned))
        #expect(pinned.group.name == "Reading", "Pinned keeps the name the person gave their views")
        #expect(pinned.shown == [view("B"), loose], "what was placed under Views is pinned; hidden stays hidden")
        #expect(!pinned.members.contains(.source("rss")), "a source the copy does not hold has no row")
        #expect(plan.groups.first { $0.id == "mine" }?.shown == [view("A"), kept], "the person's own section keeps what they put there")
        #expect(!plan.groups.contains { $0.members.contains(.sources) || $0.members.contains(.collections) })
        #expect(layout.isCollapsed(.type("core.note")))
    }

    @Test func aSourceOrCollectionPlacedUnderTheLibraryIsPinned() throws {
        let library = library()
        let collection = SidebarPlace.collection(library.collections[0].id)
        let layout = try read("""
            {"groups":[{"id":"library","kind":"library","tab":"home","isHidden":false,"shortcuts":[]},
            {"id":"views","kind":"views","tab":"home","isHidden":true,"shortcuts":[]}],
            "homes":{"\(collection.key)":"library"}}
            """)
        let pinned = try #require(SidebarPlan(library, layout: layout).section(.pinned))
        #expect(pinned.members.contains(collection))
        #expect(pinned.group.isHidden, "Views was hidden, so Pinned is, and the Section place shows it again")
    }

    @Test func viewsAnEarlierCopyHidAllAtOnceStayHiddenAndOneComesBackAlone() throws {
        var layout = try read(#"{"hidden":["views"]}"#)
        let library = library()
        #expect(SidebarPlan(library, layout: layout).section(.pinned)?.shown.isEmpty == true)
        layout.show(ItemID("v-B"), among: library.views.map(\.id))
        layout.put(view("B"), in: "pinned")
        #expect(SidebarPlan(library, layout: layout).section(.pinned)?.shown == [view("B")])
    }

    @Test func aViewsSectionInAnotherTabBringsPinnedThere() throws {
        let layout = try read("""
            {"tabs":[{"id":"home","name":"Home","symbol":"house"},{"id":"work","name":"Work","symbol":"rectangle.stack"}],
            "groups":[{"id":"shortcuts","kind":"shortcuts","tab":"home","isHidden":false,"shortcuts":["new"]},
            {"id":"library","kind":"library","tab":"home","isHidden":false,"shortcuts":[]},
            {"id":"views","kind":"views","tab":"work","isHidden":false,"shortcuts":[]}]}
            """)
        #expect(layout.groups(in: "home").map(\.kind) == [.shortcuts, .places])
        #expect(layout.groups(in: "work").map(\.kind) == [.pinned])
    }

    // MARK: Writing back

    @Test func writingBackKeepsEveryWordThisCopyDoesNotRead() throws {
        let library = library()
        var layout = try read(arranged(library))
        layout.setCollapsed(.type("core.task"), true)
        let written = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(layout)) as? [String: Any])

        let groups = try #require(written["groups"] as? [[String: Any]])
        let kinds = groups.compactMap { $0["kind"] as? String }
        #expect(kinds.filter { ["library", "views", "pinboard"].contains($0) } == ["library", "views", "pinboard"])
        #expect(kinds.contains("places") && kinds.contains("pinned"))
        let earlierViews = try #require(groups.first { $0["kind"] as? String == "views" })
        #expect(earlierViews["id"] as? String == "views" && earlierViews["title"] as? String == "Reading" && earlierViews["tab"] as? String == "home")
        #expect(groups.first { $0["kind"] as? String == "pinboard" }?["extra"] as? Int == 1)

        let homes = try #require(written["homes"] as? [String: String])
        #expect(homes["inbox"] == "views" && homes["sources"] == "library" && homes["source:rss"] == "library", "homes are kept as written")
        #expect(Set(written["hidden"] as? [String] ?? []) == ["favorites", "view:v-C", "recents"])
        #expect(written["colors"] as? [String: String] == ["view:v-A": "purple", "inbox": "blue"])
        #expect((written["tabs"] as? [[String: Any]])?.count == 2)

        // Read again, it is the same sidebar.
        let again = try JSONDecoder().decode(SidebarLayout.self, from: JSONEncoder().encode(layout))
        #expect(again == layout)
    }

    @Test func readingAloneWritesNothingNew() throws {
        let defaults = ThrowawayDefaults.make("SidebarReadingTests.unchanged")
        let stored = #"{"marfa:one":{"hidden":["favorites"],"order":[],"collapsed":[],"groups":[{"id":"views","kind":"views","tab":"home","isHidden":false,"shortcuts":[]}]}}"#
        defaults.set(Data(stored.utf8), forKey: SidebarLayouts.defaultsKey)
        let layouts = SidebarLayouts(defaults: defaults)
        _ = SidebarPlan(library(), layout: layouts.layout(for: "marfa:one"))
        layouts.update("marfa:one") { _ in }
        #expect(defaults.data(forKey: SidebarLayouts.defaultsKey) == Data(stored.utf8), "nothing changed, so nothing is written")
    }

    @Test func whatThisCopyPinsIsWrittenUnderItsOwnSection() throws {
        let library = library()
        var layout = try read(arranged(library))
        let loose = SidebarPlace.collection(library.collections[1].id)
        layout.put(loose, in: SidebarGroup.pinnedID)
        let written = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(layout)) as? [String: Any])
        #expect((written["homes"] as? [String: String])?[loose.key] == "pinned")
        #expect(SidebarPlan(library, layout: layout).section(.pinned)?.shown.last == loose)
    }
}
