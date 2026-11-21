import Foundation
import Testing
@testable import MAPP

/// Settings > Layouts: what a type's page offers for each place of its look, and that every change goes through the stores
/// that already hold it (`TypeLooks`, `PagePlacements`), so a list row and an item's page see it.
@MainActor
struct LayoutsTests {
    private let catalogue = LookFixture.catalogue()
    private let server = "marfa:http://one.test"
    private let task = TypeID("core.task")
    private let note = TypeID("core.note")

    private func looks(_ name: String) -> (store: TypeLooks, defaults: UserDefaults) {
        let suite = "LayoutsTests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (TypeLooks(defaults: defaults, reporting: Reporting(sink: RecordingSink())), defaults)
    }

    // MARK: What each place offers

    @Test func aPlaceOffersOnlyWhatTheTypeHas() {
        let choices = LayoutChoices(type: task, catalogue: catalogue)
        #expect(choices.dates.contains(.field("due_at")))
        #expect(!choices.dates.contains(.field("hired_at")))
        #expect(choices.dates.suffix(4) == [.created, .edited, .occurred, .off])
        #expect(choices.parts.contains(.field("place")))
        #expect(!choices.parts.contains(.file), "a task is no file")
        #expect(!choices.facts.contains(.field("status")), "the status always comes first, so it is no fact")
        #expect(!choices.parts.contains(.field("title")) && !choices.parts.contains(.field("body")), "the row says them already")
        #expect(choices.parts.contains(.time("due_at")), "a date with a time offers its time of day")
    }

    @Test func aFileTypeOffersItsKindAndSize() {
        let choices = LayoutChoices(type: TypeID("core.file"), catalogue: catalogue)
        #expect(choices.parts.contains(.file))
        #expect(choices.parts.contains(.site), "a file with a url names its website")
        #expect(!choices.facts.contains(.count(.members)))
    }

    @Test func everyOfferHasWordsForAPerson() {
        for type in catalogue.itemTypes.keys {
            let choices = LayoutChoices(type: type, catalogue: catalogue)
            for date in choices.dates { #expect(!choices.title(of: date).isEmpty) }
            for part in choices.parts { #expect(!choices.title(of: part).isEmpty) }
            for fact in choices.facts { #expect(!choices.title(of: fact).isEmpty) }
        }
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

    @Test func aChangeShowsInTheLookEveryViewReads() {
        let (store, _) = looks("shows")
        store.change(task, in: server, catalogue: catalogue) {
            $0.secondary = [.field("place")]
            $0.facts = [.tags, .field("priority")]
        }
        let look = store.looks(in: catalogue, library: server)[task]
        #expect(look?.secondary == [.field("place")])
        #expect(look?.facts == [.tags, .field("priority")])
        #expect(look?.date == .field("due_at"), "what was not changed stays the preset's")
        #expect(store.changeCount(for: task, in: server) == 2)
    }

    @Test func aChangeReachesTheRowOfAnItemOfTheType() {
        let (store, _) = looks("row")
        var item = Item(
            id: .mint(), type: task, title: "Pay the bill", name: "Pay the bill", titleRule: .firstLine,
            properties: [Property(key: "place", value: .string("Lewes"))], preview: "", tags: [], version: ItemVersion(1),
            created: .distantPast, modified: .distantPast)
        item.occurred = nil
        let list = RowList(day: Calendar.current.startOfDay(for: .now))
        func secondary() -> String? {
            let look = store.looks(in: catalogue, library: server)[task]!
            return RowContent.make(for: item, look: look, catalogue: catalogue, list: list).secondary
        }
        #expect(secondary() != "Lewes")
        store.change(task, in: server, catalogue: catalogue) { $0.secondary = [.field("place")] }
        #expect(secondary() == "Lewes")
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
        placements.setPins([PagePlacement.updated], of: task)
        placements.setPins([PagePlacement.type], of: note)

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

    @Test func theRowsAPageCanPinAreTheTypesAndLinkedFromIsNeverPinned() {
        let rows = PageLayout.rows(ofType: task, catalogue: catalogue)
        #expect(rows.map(\.id).contains("status") && rows.map(\.id).contains("due_at"))
        #expect(!rows.map(\.id).contains("title") && !rows.map(\.id).contains("body"))
        let layout = PageLayout(rows: rows, placement: PagePlacements().placement(of: task, in: catalogue))
        #expect(layout.moving(PagePlacement.linkedFrom, to: .pinned) == nil)
    }

    @Test func aPinFromLayoutsIsTheSameChoiceCustomizeLayoutOnAnItemReads() {
        var placements = PagePlacements()
        let rows = PageLayout.rows(ofType: task, catalogue: catalogue)
        // As the Layouts page writes it.
        placements.setPins(["due_at", "status"], of: task)
        let pinned = placements.pin("priority", of: task, in: catalogue)
        #expect(pinned)
        // As Customize Layout reads it, through the same store.
        let layout = PageLayout(rows: rows, placement: placements.placement(of: task, in: catalogue))
        #expect(layout.pinned.map(\.id) == ["due_at", "status", "priority"])
        // And as Customize Layout writes it, which the Layouts page then reads.
        var moved = layout.moving("priority", to: .page)!
        placements.apply(moved, of: task, in: catalogue)
        #expect(placements.pins(of: task, in: catalogue) == ["due_at", "status"])
        moved = PageLayout(rows: rows, placement: placements.placement(of: task, in: catalogue))
        #expect(moved.pinned.map(\.id) == ["due_at", "status"])
    }

    @Test func aPageHoldsNoMoreThanFourPins() {
        var placements = PagePlacements()
        placements.setPins(["status", "due_at", "priority", "assignees"], of: task)
        let pinned = placements.pin("place", of: task, in: catalogue)
        #expect(!pinned)
        #expect(placements.pins(of: task, in: catalogue).count == PagePlacement.pinLimit)
    }

    // MARK: The list

    @Test func theLayoutsListWordsWhereATypeStartsAndHowMuchWasChanged() {
        #expect(LookPreset.task.startsAs == "As a task")
        #expect(LookPreset.event.startsAs == "As an event")
        #expect(LayoutsListWords.line(startsAs: "As a task", changes: 0) == "As a task.")
        #expect(LayoutsListWords.line(startsAs: "As a task", changes: 1) == "As a task, with one change.")
        #expect(LayoutsListWords.line(startsAs: "As a task", changes: 3) == "As a task, with 3 changes.")
    }

    @Test func aSubpageNamesTheTypeItIsFor() {
        let subpage = LayoutsSubpage.subpage(for: task, label: "Task")
        #expect(LayoutsSubpage.type(of: subpage) == task)
        #expect(LayoutsSubpage.type(of: SettingsSubpage(id: "all-deleted", title: "x")) == nil)
        #expect(LayoutsSubpage.type(of: nil) == nil)
    }
}
