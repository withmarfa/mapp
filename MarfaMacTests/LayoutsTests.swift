import Foundation
import Testing
@testable import MarfaMac

/// Settings > Layouts: what a type's page offers for each place of its look, and that every change goes through the stores
/// that already hold it (`TypeLooks`, `PagePlacements`), so a list row and an item's page see it.
@MainActor
struct LayoutsTests {
    private let catalogue = LookFixture.catalogue()
    private let server = "marfa:http://one.test"
    private let task = TypeID("core.task")
    private let note = TypeID("core.note")

    private func looks(_ name: String) -> (store: TypeLooks, defaults: UserDefaults) {
        let defaults = ThrowawayDefaults.make("LayoutsTests.\(name)")
        return (TypeLooks(defaults: defaults, reporting: Reporting(sink: RecordingSink())), defaults)
    }

    // MARK: Changing a look

    @Test func aChangeIsKeptOnlyWhereItDiffersFromWhatThePresetGives() {
        let (store, _) = looks("kept")
        store.change(task, in: server, catalogue: catalogue) { $0.date = .created }
        #expect(store.choices(for: server)[task] == TypeLookChoice(date: .created))
        // Back to the preset's own: nothing is kept, so a later better preset still reaches it.
        store.change(task, in: server, catalogue: catalogue) { $0.date = .field("due_at") }
        #expect(store.choices(for: server)[task] == nil)
        #expect(!store.hasChoice(for: task, in: server))
    }

    @Test func aTypeKeepsItsChoicesApartFromAnotherTypesAndAnotherServers() {
        let (store, _) = looks("apart")
        store.change(task, in: server, catalogue: catalogue) { $0.date = .created }
        store.change(note, in: server, catalogue: catalogue) { $0.date = .occurred }
        #expect(store.choices(for: server)[note]?.date == .occurred)
        #expect(store.choices(for: "marfa:http://two.test")[task] == nil)
    }

    // MARK: Restore Defaults

    @Test func restoreDefaultsClearsOnlyThatTypesChoices() {
        let (store, defaults) = looks("restore")
        store.change(task, in: server, catalogue: catalogue) { $0.date = .created }
        store.change(note, in: server, catalogue: catalogue) { $0.date = .occurred }
        var placements = PagePlacements()
        placements.setPins([PagePlacement.tags], of: task)
        placements.setPins([PagePlacement.tags], of: note)

        store.restore(task, in: server)
        placements.reset(task)

        #expect(store.choices(for: server)[task] == nil)
        #expect(store.choices(for: server)[note]?.date == .occurred, "another type's look stays")
        #expect(!placements.hasChoice(for: task))
        #expect(placements.hasChoice(for: note), "another type's page stays")
        // It is kept for a later launch as it was restored.
        let reopened = TypeLooks(defaults: defaults, reporting: Reporting(sink: RecordingSink()))
        #expect(reopened.choices(for: server)[task] == nil)
        #expect(reopened.choices(for: server)[note]?.date == .occurred)
    }

    // MARK: The page

    @Test func aLayoutWriteKeepsUnreadablePlacementsUnderTheirKey() throws {
        let defaults = ThrowawayDefaults.make("LayoutsTests.setAside")
        let mixed = #"{"core.note":{"pins":["author"]},"missing.type":{"pins":42},"core.task":{"pins":["priority"]}}"#
        defaults.set(mixed, forKey: PagePlacements.key)
        let page = layoutPage(note, defaults: defaults)
        #expect(page.hasChanges)
        #expect(defaults.object(forKey: PagePlacements.setAsideKey) == nil, "reading alone leaves the stored document untouched")
        page.restore()
        let saved = try #require(defaults.stringArray(forKey: PagePlacements.setAsideKey)?.last)
        #expect(saved == mixed)
        let entries = try #require(JSONSerialization.jsonObject(with: Data(saved.utf8)) as? [String: Any])
        #expect(entries["missing.type"] as? [String: Int] == ["pins": 42])
        let remaining = PagePlacements.stored(in: defaults)
        #expect(!remaining.hasChoice(for: note))
        #expect(remaining.pins(of: task, in: catalogue) == ["priority"])
    }

    @Test func pinsAndLinkedFromAreReadBackFromThePlacementsStore() {
        let defaults = ThrowawayDefaults.make("LayoutsTests.pinsAndLinks")
        let page = layoutPage(task, defaults: defaults)
        PagePlacements.update(in: defaults) { $0.setPins([], of: task) }
        page.pin("priority")
        page.setLinkedFrom(.page)
        let saved = PagePlacements.stored(in: defaults)
        #expect(saved.pins(of: task, in: catalogue) == ["priority"])
        #expect(saved.placement(of: task, in: catalogue).linkedFromPlace == .page)
    }

    private func layoutPage(_ type: TypeID, defaults: UserDefaults) -> LayoutTypePage {
        let library = FakeItemLibrary()
        library.catalogue = catalogue
        return LayoutTypePage(type: type, placements: PagePlacements.stored(in: defaults), defaults: defaults,
                              typeLooks: TypeLooks(defaults: defaults), key: server, library: library)
    }

    @Test func aPageHoldsNoMoreThanFourPins() {
        var placements = PagePlacements()
        placements.setPins(["status", "due_at", "priority", "assignees"], of: task)
        let pinned = placements.pin("place", of: task, in: catalogue)
        #expect(!pinned)
        #expect(placements.pins(of: task, in: catalogue).count == PagePlacement.pinLimit)
    }
}
