import Foundation
import Testing
@testable import MAPP

/// Long lists of links draw a part of themselves, and a link to an item in the bin or one the library does not hold
/// says so.
@MainActor
@Suite(.hangLimit) struct LinkListTests {
    typealias F = LibraryFixture

    // MARK: The cut

    @Test(arguments: [(0, 0, 0), (1, 1, 0), (20, 20, 0), (21, 20, 1), (500, 20, 480)])
    func aGroupDrawsTwentyLinksAndCountsTheRest(count: Int, drawn: Int, hidden: Int) {
        let cut = LinkLimit.split(Array(0..<count), expanded: false)
        #expect(cut.shown.count == drawn)
        #expect(cut.hidden == hidden)
        #expect(Array(cut.shown) == Array(0..<drawn))
    }

    @Test func anExpandedGroupDrawsEveryLinkHoweverOftenItIsAskedFor() {
        let window = DetailsPresentation()
        let group = LinkGroup(item: F.p1, field: "inverse:about")
        for _ in 0..<2 {
            window.expandLinks(group)
            let cut = LinkLimit.split(Array(0..<500), expanded: window.expandedLinks.contains(group))
            #expect(cut.shown.count == 500)
            #expect(cut.hidden == 0)
        }
        #expect(window.expandedLinks == [group])
    }

    @Test func aGroupIsExpandedForItsItemAloneAndLongerThanTheItemIsShown() {
        let window = DetailsPresentation()
        window.expandLinks(LinkGroup(item: F.p1, field: "inverse:about"))
        #expect(!window.expandedLinks.contains(LinkGroup(item: F.p2, field: "inverse:about")))
        #expect(!window.expandedLinks.contains(LinkGroup(item: F.p1, field: "inverse:parent-of")))
        #expect(!window.expandedLinks.contains(.content(of: F.p1)))
    }

    // MARK: What the library gives the group

    private static func note(_ number: Int, state: ItemState = .active, about: ItemID? = F.p1) -> Item {
        let id = ItemID("note-\(number)")
        let edges = about.map { [Edge(id: EdgeID("about-\(number)"), type: "about", source: id, target: .item($0), origin: .property("about"))] } ?? []
        return F.item(id, F.note, "Note \(number)", age: 100 + number, state: state, edges: edges)
    }

    private static func loaded(_ extra: [Item]) async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: F.items + extra, catalogue: F.catalogue)))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    private func linked(_ library: MarfaLibrary) -> ItemRelationship? {
        library.relationships(for: F.p1).first { $0.field == "inverse:about" }
    }

    @Test func aGroupOfFiveHundredLinksIsOneListInAFixedOrder() async throws {
        let (library, _) = try await Self.loaded((1...500).map { Self.note($0) })
        let group = try #require(linked(library))
        // The note in the fixture that is about the project is among them.
        #expect(group.targets.count == 501)
        let cut = LinkLimit.split(group.targets, expanded: false)
        #expect(cut.shown.count == 20)
        #expect(cut.hidden == 481)
        #expect(group.targets.map(\.title).starts(with: ["Note 1", "Note 2", "Note 3"]))
    }

    @Test func aLinkToAnItemInTheBinIsMarkedAndTheMarkFollowsItsRecovery() async throws {
        let (library, source) = try await Self.loaded([Self.note(1), Self.note(2, state: .trashed)])
        let marks = { self.linked(library)?.targets.filter { $0.title.hasPrefix("Note") }.map(\.isDeleted) }
        #expect(marks() == [false, true])
        let binned = try #require(library.item(ItemID("note-2")))
        #expect(linked(library)?.targets.first { $0.itemID == binned.id }?.isOpenable == true)

        var restored = binned
        restored.state = .active
        source.send(.upserted([restored]))
        #expect(await eventually { marks() == [false, false] })

        var gone = restored
        gone.state = .trashed
        source.send(.upserted([gone]))
        #expect(await eventually { marks() == [false, true] })
    }

    @Test func aLinkToAnItemTheLibraryDoesNotHoldIsMissingAndKeepsItsID() async throws {
        let stray = ItemID("not-held")
        let holder = F.item(ItemID("holder"), F.note, "Holder", age: 50, edges: [
            Edge(id: EdgeID("stray"), type: "about", source: ItemID("holder"), target: .item(stray), origin: .property("about"))
        ])
        let (library, _) = try await Self.loaded([holder])
        let group = try #require(library.relationships(for: holder.id).first { $0.field == "about" })
        let target = try #require(group.targets.first)
        #expect(target.itemID == stray)
        #expect(target.resolution == .missing)
        #expect(!target.isOpenable)
        #expect(!target.isDeleted)
    }

    @Test func aLinkAddedOrRemovedShowsInTheGroupAtOnce() async throws {
        let (library, source) = try await Self.loaded((1...21).map { Self.note($0) })
        #expect(linked(library)?.targets.count == 22)
        source.send(.upserted([Self.note(22)]))
        #expect(await eventually { linked(library)?.targets.count == 23 })
        source.send(.upserted([Self.note(3, about: nil)]))
        #expect(await eventually { linked(library)?.targets.count == 22 })
        source.send(.removed([ItemID("note-4")]))
        #expect(await eventually { linked(library)?.targets.count == 21 })
    }

    // MARK: Opening

    @Test func aDeletedItemIsListedByRecentlyDeletedAndAnyOtherByAllItems() {
        let browser = Browser()
        let live = FakeItemLibrary.note("Live", modified: .now)
        let binned = FakeItemLibrary.note("Binned", modified: .now, state: .trashed)
        #expect(browser.place(listing: live) == .allNotes)
        #expect(browser.place(listing: binned) == .recentlyDeleted)
    }

    @Test func revealingADeletedItemShowsItInRecentlyDeleted() throws {
        let live = FakeItemLibrary.note("Live", modified: .now)
        let binned = FakeItemLibrary.note("Binned", modified: .now, state: .trashed)
        let library = FakeItemLibrary(items: [live, binned])
        let browser = Browser()
        browser.reveal(binned, in: library, order: NoteOrder())
        #expect(browser.item == .recentlyDeleted)
        #expect(browser.selection == [binned.id])
    }
}
