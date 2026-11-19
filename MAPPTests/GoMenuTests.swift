import Foundation
import Testing
@testable import MAPP

/// What the Go menu lists for a library and a sidebar layout.
@MainActor
@Suite(.hangLimit)
struct GoMenuTests {
    private func marfaLibrary(extraTypes: Int = 0) async throws -> MarfaLibrary {
        var catalogue = LibraryFixture.catalogue
        var items = LibraryFixture.items
        for number in 0..<extraTypes {
            let id = TypeID("test.kind\(number)")
            let label = "Kind \(number)"
            catalogue.itemTypes[id] = ItemTypeInfo(
                id: id, label: label, plural: label, fields: [], titleField: nil, bodyField: nil, parent: nil)
            items.append(LibraryFixture.item(ItemID("k\(number)"), id, "A \(label)", age: 100 + number))
        }
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: items, catalogue: catalogue)))
        try #require(await eventually { library.isLoaded })
        return library
    }

    private func titles(_ entries: [GoMenu.Entry]) -> [String] { entries.map(\.title) }

    @Test func aLibraryWithNoSavedViewsHasNoViewsSection() async throws {
        let library = try await marfaLibrary()
        let menu = GoMenu(library: library, layout: SidebarLayout())
        #expect(menu.places.map(\.place) == [.all, .sources, .collections, .inbox, .recents, .favorites])
        #expect(menu.views.isEmpty)
        #expect(menu.moreTypes.isEmpty)
    }

    @Test func typesAreTheOnesTheSidebarShowsInItsOrderWithSubtypesNamedByTheirParent() async throws {
        let library = try await marfaLibrary()
        let menu = GoMenu(library: library, layout: SidebarLayout())
        let plan = SidebarPlan(library, layout: SidebarLayout())
        #expect(titles(menu.types) == ["Notes", "Projects", "Tickets > Bugs", "Tickets > Tasks", "Entities"])
        #expect(menu.types.first?.item == .itemType("core.note"))
        #expect(plan.shownTypes.map(\.label) == ["Notes", "Projects", "Tickets", "Entities"])
    }

    @Test func aHiddenTypeAndItsSubtypesAreLeftOut() async throws {
        let library = try await marfaLibrary()
        var layout = SidebarLayout()
        layout.setHidden(.type("aic.ticket"), true)
        layout.setHidden(.type("core.entity"), true)
        #expect(titles(GoMenu(library: library, layout: layout).types) == ["Notes", "Projects"])
        layout.setHidden(.types, true)
        #expect(GoMenu(library: library, layout: layout).types.isEmpty)
    }

    @Test func manyTypesStopAtTheSidebarsLimitAndTheRestAreUnderAllTypes() async throws {
        let library = try await marfaLibrary(extraTypes: 6)
        let menu = GoMenu(library: library, layout: SidebarLayout())
        let top = SidebarPlan(library, layout: SidebarLayout()).shownTypes
        #expect(top.count == 10)
        #expect(Set(menu.types.map(\.place)).isDisjoint(with: menu.moreTypes.map(\.place)))
        // The sidebar's first six rows, with their subtypes, are the menu's own.
        let first = top.prefix(SidebarPlan.shownTypeCount).map(\.label)
        #expect(first.allSatisfy { label in menu.types.contains { $0.title == label || $0.title.hasPrefix(label + " > ") } })
        #expect(menu.moreTypes.count == 4)
    }

    @Test func savedViewsFollowTheSidebarAndHiddenOnesAreLeftOut() {
        let library = FakeItemLibrary(items: [])
        library.views = LibraryView.ordered(["Cats", "Apples", "Bears"].map { LibraryView(id: ItemID("v-" + $0), title: $0) })
        var layout = SidebarLayout()
        #expect(titles(GoMenu(library: library, layout: layout).views) == ["Apples", "Bears", "Cats"])
        layout.setHidden(.view(ItemID("v-Bears")), true)
        #expect(titles(GoMenu(library: library, layout: layout).views) == ["Apples", "Cats"])
        layout.setHidden(.views, true)
        #expect(GoMenu(library: library, layout: layout).views.isEmpty)
    }

    @Test func aViewDeletedOrATypeRemovedWhileTheMenuIsOpenOpensItems() async throws {
        let library = try await marfaLibrary()
        let fake = FakeItemLibrary(items: [])
        fake.views = [LibraryView(id: ItemID("v-1"), title: "One")]
        let views = GoMenu(library: fake, layout: SidebarLayout())
        let entry = try #require(views.views.first)
        #expect(views.destination(of: entry, in: fake) == .view(ItemID("v-1")))
        fake.views = []
        #expect(views.destination(of: entry, in: fake) == .allItems)

        let menu = GoMenu(library: library, layout: SidebarLayout())
        let note = try #require(menu.types.first)
        #expect(menu.destination(of: note, in: library) == .itemType("core.note"))
        let gone = GoMenu.Entry(place: .type("test.gone"), item: .itemType("test.gone"), title: "Gone", icon: .type(nil))
        #expect(menu.destination(of: gone, in: library) == .allItems)
    }
}
