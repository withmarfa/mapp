import Foundation
import Testing
@testable import MarfaMac

/// The Include Subtypes choice kept in the defaults, and what it adds to a type's list.
@MainActor
@Suite(.hangLimit)
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
        let suite = "MarfaMac.IncludedSubtypesTests"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(IncludedSubtypes.stored(in: defaults) == IncludedSubtypes())
        IncludedSubtypes.update(in: defaults) { $0.set("aic.ticket", included: true) }
        #expect(IncludedSubtypes.stored(in: defaults).types == ["aic.ticket"])
        IncludedSubtypes.update(in: defaults) { $0.set("aic.ticket", included: false) }
        #expect(IncludedSubtypes.stored(in: defaults).types.isEmpty)
    }

}
