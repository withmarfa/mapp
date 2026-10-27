import Foundation
import Testing
@testable import MAPP

/// The Include Subtypes choice kept in the defaults, and what it adds to a type's list.
@MainActor
struct IncludedSubtypesTests {
    func library() async throws -> MarfaLibrary {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        let ticket = LibraryFixture.item(ItemID("k1"), LibraryFixture.ticket, "A ticket", age: 10)
        source.send(.loaded(SourceSnapshot(items: LibraryFixture.items + [ticket], catalogue: LibraryFixture.catalogue)))
        try #require(await eventually { library.isLoaded })
        return library
    }

    // MARK: Stored value

    @Test func theChoiceRoundTripsThroughItsStoredText() throws {
        var included = IncludedSubtypes()
        included.set("aic.ticket", included: true)
        included.set("aic.project", included: true)
        #expect(IncludedSubtypes(rawValue: included.rawValue) == included)
        // The same choice is the same text, whatever order it was made in.
        #expect(included.rawValue == #"["aic.project","aic.ticket"]"#)
        included.set("aic.ticket", included: false)
        included.set("aic.project", included: false)
        #expect(included.types.isEmpty)
    }

    @Test func textThatIsNotAListOfIdentifiersIsNotAChoice() {
        #expect(IncludedSubtypes(rawValue: "[]") == IncludedSubtypes())
        #expect(IncludedSubtypes(rawValue: "not json") == nil)
        #expect(IncludedSubtypes(rawValue: #"{"aic.ticket":true}"#) == nil)
    }

    @Test func theDefaultsHoldTheChoiceUnderOneKey() throws {
        let suite = "MAPP.IncludedSubtypesTests"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(IncludedSubtypes.stored(in: defaults) == IncludedSubtypes())
        IncludedSubtypes.update(in: defaults) { $0.set("aic.ticket", included: true) }
        #expect(IncludedSubtypes.stored(in: defaults).types == ["aic.ticket"])
        IncludedSubtypes.update(in: defaults) { $0.set("aic.ticket", included: false) }
        #expect(IncludedSubtypes.stored(in: defaults).types.isEmpty)
    }

    // MARK: Including subtypes

    @Test func aTypeWithSubtypesHoldingItemsOffersToIncludeThem() async throws {
        let library = try await library()
        let browser = Browser()
        browser.sidebarItem = .itemType(LibraryFixture.ticket.rawValue)
        #expect(browser.stackableType(in: library) == LibraryFixture.ticket.rawValue)

        // A type with no subtypes, and a place that is no type, have nothing to include.
        browser.sidebarItem = .itemType(LibraryFixture.project.rawValue)
        #expect(browser.stackableType(in: library) == nil)
        browser.sidebarItem = .allNotes
        #expect(browser.stackableType(in: library) == nil)
    }

    @Test func includingSubtypesAddsTheirItemsToTheTypesOwnAndLeavesOtherTypesAlone() async throws {
        let library = try await library()
        let browser = Browser()
        let ticket = LibraryFixture.ticket.rawValue
        browser.sidebarItem = .itemType(ticket)
        // Opening a parent type lists its own items only.
        let own = browser.items(in: library)
        #expect(own.map(\.type) == [LibraryFixture.ticket])

        browser.stackedTypes = [ticket]
        let stacked = browser.items(in: library)
        #expect(Set(stacked.map(\.type)) == [LibraryFixture.ticket, LibraryFixture.bug, LibraryFixture.task])
        #expect(stacked.count == 3)
        #expect(Set(stacked.map(\.id)).isSuperset(of: own.map(\.id)))
        // The layouts on offer follow what is listed.
        #expect(browser.availableViewModes(in: library) == ItemViewMode.available(forTypes: Set(stacked.map(\.type)), catalogue: library.catalogue))

        // Another type is not stacked by it, and a type with no subtypes lists as ever.
        let project = SidebarItem.itemType(LibraryFixture.project.rawValue)
        browser.sidebarItem = project
        #expect(browser.items(in: library) == library.items(in: project))
        browser.stackedTypes = [LibraryFixture.project.rawValue]
        #expect(browser.items(in: library) == library.items(in: project))
    }
}
