import Foundation
import Testing
@testable import MarfaMac

/// What the right sidebar asks for when nothing is chosen, and what the Tags box does with a tag typed and not yet added.
@MainActor
struct InspectorPromptTests {
    @Test func aCalendarAsksForAnEventAndEveryOtherLayoutForAnItem() {
        #expect(InspectorPrompt.forItems(in: .calendar) == .event)
        for mode in ItemViewMode.allCases where mode != .calendar {
            #expect(InspectorPrompt.forItems(in: mode) == .item)
        }
    }

    @Test func eachIndexPageAsksForItsOwnKindOfRow() {
        #expect(InspectorPrompt.forIndex(.items) == .item)
        #expect(InspectorPrompt.forIndex(.collections) == .collection)
        #expect(InspectorPrompt.forIndex(.sources) == .source)
    }

    private func tagField(over item: Item, in library: FakeItemLibrary) -> ValueEditModel {
        ValueEditModel(ValueEditRequest(kind: .tags, library: library, item: item.id))
    }

    @Test func endingTheTagFieldAddsTheTagTypedAndNotYetAdded() {
        let item = FakeItemLibrary.note("First", modified: .now)
        let library = FakeItemLibrary(items: [item])
        library.catalogue = FakeItemLibrary.testCatalogue
        let model = tagField(over: item, in: library)
        model.query = "  exam "
        model.finishTagField()
        #expect(library.item(item.id)?.tags.contains("exam") == true)
        #expect(model.query.isEmpty)
    }

    @Test func endingTheTagFieldWithNothingTypedChangesNothing() {
        let item = FakeItemLibrary.note("First", modified: .now)
        let library = FakeItemLibrary(items: [item])
        library.catalogue = FakeItemLibrary.testCatalogue
        let model = tagField(over: item, in: library)
        model.finishTagField()
        #expect(library.item(item.id)?.tags.isEmpty == true)
        #expect(library.notices.told == 0)
    }

    @Test func aTagTheLibraryRefusesIsKeptAndToldWhenTheFieldEnds() {
        let item = FakeItemLibrary.note("First", modified: .now)
        let library = FakeItemLibrary(items: [item])
        library.catalogue = FakeItemLibrary.testCatalogue
        let model = tagField(over: item, in: library)
        model.query = ".."
        model.finishTagField()
        #expect(library.item(item.id)?.tags.isEmpty == true)
        #expect(library.notices.told == 1)
        #expect(library.notices.waiting.first?.text == "..")
    }
}
