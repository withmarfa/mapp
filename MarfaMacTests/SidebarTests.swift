import Foundation
import Testing
@testable import MarfaMac

/// What a library reports for the sidebar: its collections, its types with their counts and how they nest, and the
/// plan the sidebar makes of them.
@MainActor
@Suite(.hangLimit)
struct SidebarTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: Marfa library

    func marfaLibrary(_ items: [Item] = LibraryFixture.items, catalogue: Catalogue = LibraryFixture.catalogue) async throws -> MarfaLibrary {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: items, catalogue: catalogue)))
        try #require(await eventually { library.isLoaded })
        return library
    }

    // MARK: Nesting

    static func counts(_ counts: [String: Int], in catalogue: Catalogue) -> [ItemTypeCount] {
        counts.map { id, count in
            ItemTypeCount(id: TypeID(id), label: catalogue.label(for: TypeID(id)), icon: nil, count: count, own: count)
        }
    }

    // MARK: Views

    private func viewsLibrary(_ titles: [String]) -> FakeItemLibrary {
        let library = FakeItemLibrary(items: [])
        library.views = LibraryView.ordered(titles.map { LibraryView(id: ItemID("v-" + $0), title: $0) })
        return library
    }

    private func titles(_ views: [LibraryView]) -> [String] { views.map(\.title) }
    private let viewKey: (LibraryView) -> String = { SidebarPlace.view($0.id).key }

    @Test func aMovedViewKeepsItsPlaceAndANewViewFollowsThePlacedOnes() {
        let library = viewsLibrary(["Apples", "Bears", "Cats"])
        var layout = SidebarLayout()
        let plan = SidebarPlan(library, layout: layout)
        layout.move(plan.views, shown: plan.shownViews, by: viewKey, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(titles(SidebarPlan(library, layout: layout).views) == ["Cats", "Apples", "Bears"])
        library.views = LibraryView.ordered(library.views + [LibraryView(id: ItemID("v-Aardvarks"), title: "Aardvarks")])
        #expect(titles(SidebarPlan(library, layout: layout).views) == ["Cats", "Apples", "Bears", "Aardvarks"])
    }

    @Test func movingAmongTheShownViewsKeepsAHiddenOneInItsSlot() {
        let library = viewsLibrary(["Apples", "Bears", "Cats", "Dogs"])
        var layout = SidebarLayout()
        layout.setHidden(.view(ItemID("v-Bears")), true)
        let plan = SidebarPlan(library, layout: layout)
        // Shown: Apples, Cats, Dogs. Dogs moves to the top.
        layout.move(plan.views, shown: plan.shownViews, by: viewKey, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        let after = SidebarPlan(library, layout: layout)
        #expect(titles(after.shownViews) == ["Dogs", "Apples", "Cats"])
        #expect(titles(after.views) == ["Dogs", "Bears", "Apples", "Cats"])
    }

    @Test func aViewsPlaceSurvivesRelaunch() {
        let defaults = ThrowawayDefaults.make("SidebarTests.views")
        SidebarLayouts(defaults: defaults).update("marfa:one") { $0.setHidden(.view(ItemID("v-Apples")), true) }
        #expect(SidebarLayouts(defaults: defaults).layout(for: "marfa:one").isHidden(.view(ItemID("v-Apples"))))
        #expect(!SidebarLayouts(defaults: defaults).layout(for: "marfa:one").isHidden(.view(ItemID("v-Bears"))))
    }

    // MARK: Layout

    @Test func aSectionCollapsedForOneLibraryStaysCollapsedForThatLibraryOnly() {
        let defaults = ThrowawayDefaults.make("SidebarTests.collapsed")
        let layouts = SidebarLayouts(defaults: defaults)
        layouts.update("marfa:one") { $0.setCollapsed(.types, true) }
        #expect(SidebarLayouts(defaults: defaults).layout(for: "marfa:one").isCollapsed(.types))
        #expect(!SidebarLayouts(defaults: defaults).layout(for: "marfa:one").isCollapsed(.collections))
        #expect(!layouts.layout(for: "marfa:two").isCollapsed(.types))
    }

    @Test func aLayoutSavedWithoutCollapsedSectionsStillReads() throws {
        let saved = Data(#"{"hidden":["favorites"],"order":["inbox"]}"#.utf8)
        let layout = try JSONDecoder().decode(SidebarLayout.self, from: saved)
        #expect(layout.isHidden(.favorites))
        #expect(!layout.isCollapsed(.favorites))
    }

    @Test func hidingAPlaceTakesItOutOfWhatShowsButKeepsItListed() async throws {
        let library = try await marfaLibrary()
        var layout = SidebarLayout()
        layout.setHidden(.type(LibraryFixture.entity.rawValue), true)
        layout.setHidden(.collections, true)
        let plan = SidebarPlan(library, layout: layout)
        #expect(plan.types.contains { $0.type == LibraryFixture.entity })
        #expect(!plan.shownTypes.contains { $0.type == LibraryFixture.entity })
        #expect(plan.shownLibrary == [.types])
        layout.setHidden(.collections, false)
        #expect(SidebarPlan(library, layout: layout).shownDestinations.contains(.collections))
    }

    @Test func hidingAPlaceTakesItOutOfBrowseWhileTheRestKeepTheirOrder() async throws {
        let library = try await marfaLibrary()
        var layout = SidebarLayout()
        layout.setHidden(.sources, true)
        let plan = SidebarPlan(library, layout: layout)
        #expect(plan.shownDestinations == [.all, .collections])
        #expect(plan.destinations == [.all, .sources, .collections])
    }

    @Test func hidingARowHidesWhatIsUnderIt() async throws {
        let library = try await marfaLibrary()
        var layout = SidebarLayout()
        layout.setHidden(.type(LibraryFixture.bug.rawValue), true)
        let ticket = SidebarPlan(library, layout: layout).shownTypes.first { $0.id == "aic.ticket" }
        #expect(ticket?.children.map(\.id) == ["aic.ticket.task"])
        layout.setHidden(.type(LibraryFixture.ticket.rawValue), true)
        #expect(!SidebarPlan(library, layout: layout).shownTypes.contains { $0.id == "aic.ticket" })
    }

    @Test func movingPlacesReordersThemWithinTheirGroup() {
        var layout = SidebarLayout()
        layout.move([.inbox, .all], fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(layout.ordered([.inbox, .all]) == [.all, .inbox])
        layout.move([.all, .inbox], fromOffsets: IndexSet(integer: 0), toOffset: 2)
        #expect(layout.ordered([.inbox, .all]) == [.inbox, .all])
    }

    @Test func aLayoutKeptForOneLibraryDoesNotChangeAnother() {
        let defaults = ThrowawayDefaults.make("SidebarTests.separate")
        let layouts = SidebarLayouts(defaults: defaults)
        layouts.update("marfa:one") { $0.setHidden(.favorites, true) }
        #expect(layouts.layout(for: "marfa:one").isHidden(.favorites))
        #expect(!layouts.layout(for: "marfa:two").isHidden(.favorites))
    }

    @Test func aLayoutIsFoundAgainByANewStore() {
        let defaults = ThrowawayDefaults.make("SidebarTests.persist")
        SidebarLayouts(defaults: defaults).update("marfa:one") {
            $0.setHidden(.type(LibraryFixture.entity.rawValue), true)
            $0.move([.inbox, .all], fromOffsets: IndexSet(integer: 1), toOffset: 0)
        }
        let layout = SidebarLayouts(defaults: defaults).layout(for: "marfa:one")
        #expect(layout.isHidden(.type(LibraryFixture.entity.rawValue)))
        #expect(layout.ordered([.inbox, .all]) == [.all, .inbox])
    }

    @Test func aStoredLayoutThatCannotBeReadLeavesTheDefault() {
        let defaults = ThrowawayDefaults.make("SidebarTests.unreadable")
        defaults.set(Data("not json".utf8), forKey: "sidebarLayouts")
        #expect(SidebarLayouts(defaults: defaults).layout(for: "any") == SidebarLayout())
    }

    @Test func aLayoutThatCannotBeReadIsKeptAsideAndLayoutsAreSavedAgain() throws {
        let defaults = ThrowawayDefaults.make("SidebarTests.unreadableKept")
        var two = SidebarLayout()
        two.setHidden(.favorites, true)
        let readable = try JSONEncoder().encode(["marfa:two": two])
        var stored = try #require(JSONSerialization.jsonObject(with: readable) as? [String: Any])
        stored["marfa:one"] = ["hidden": 7]
        defaults.set(try JSONSerialization.data(withJSONObject: stored), forKey: "sidebarLayouts")
        let sink = RecordingSink()

        let layouts = SidebarLayouts(defaults: defaults, reporting: Reporting(sink: sink))
        #expect(layouts.layout(for: "marfa:two").isHidden(.favorites), "a readable layout went with the unreadable one")
        #expect(layouts.layout(for: "marfa:one") == SidebarLayout())
        layouts.update("marfa:one") { $0.setCollapsed(.types, true) }

        let again = SidebarLayouts(defaults: defaults, reporting: Reporting(sink: RecordingSink()))
        #expect(again.layout(for: "marfa:one").isCollapsed(.types), "the change was not saved")
        #expect(again.layout(for: "marfa:two").isHidden(.favorites))
        let aside = try #require(defaults.array(forKey: SidebarLayouts.setAsideKey) as? [Data])
        #expect(aside.count == 1, "what could not be read was not kept aside once")
        let kept = try #require(JSONSerialization.jsonObject(with: aside[0]) as? [String: [String: Int]])
        #expect(kept == ["marfa:one": ["hidden": 7]])
        #expect(sink.errors.map(\.type) == ["sidebar_layouts_unreadable"])
    }

    @Test func storedLayoutsThatAreNotLayoutsAtAllAreKeptAsideWhole() throws {
        let defaults = ThrowawayDefaults.make("SidebarTests.unreadableWhole")
        let earlier = Data("set aside before".utf8)
        defaults.set([earlier], forKey: SidebarLayouts.setAsideKey)
        let stored = Data("not json".utf8)
        defaults.set(stored, forKey: "sidebarLayouts")

        let layouts = SidebarLayouts(defaults: defaults, reporting: Reporting(sink: RecordingSink()))
        layouts.update("marfa:one") { $0.setHidden(.favorites, true) }

        #expect(SidebarLayouts(defaults: defaults).layout(for: "marfa:one").isHidden(.favorites))
        #expect(defaults.array(forKey: SidebarLayouts.setAsideKey) as? [Data] == [earlier, stored])
    }
}
