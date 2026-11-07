import Foundation
import Testing
@testable import MAPP

/// A new view's title stays where it was typed until the server takes it.
@MainActor
@Suite(.hangLimit)
struct ViewTitleFormTests {
    private static let draft = ViewDraft.Draft(query: LibraryViewQuery(), sort: [], group: nil)

    @Test func aRefusedTitleStaysForAnotherTry() async throws {
        let library = FakeItemLibrary()
        library.viewFailure = ViewWriteFailure(kind: .offline, message: "Offline")
        let form = ViewTitleForm(title: "Plans", library: library)
        #expect(await form.submit(Self.draft) == .refused)
        #expect(form.title == "Plans")
        #expect(form.canSubmit)

        library.viewFailure = nil
        guard case .done(let view) = await form.submit(Self.draft) else {
            Issue.record("The retry was not taken")
            return
        }
        #expect(view.title == "Plans")
        #expect(library.views.map(\.title) == ["Plans"])
    }

    @Test func aTitleTheWindowTakesAwayIsGivenBack() {
        let library = FakeItemLibrary()
        let form = ViewTitleForm(title: "Plans", library: library)
        form.handOff(because: .closed)
        #expect(library.notices.waiting.last?.text == "Plans")
        #expect(library.notices.waiting.last?.title == String(localized: "View Not Saved"))
    }

    @Test func aTitleTheTakenViewKeptIsNotGivenBack() async {
        let library = FakeItemLibrary()
        let form = ViewTitleForm(title: "Plans", library: library)
        _ = await form.submit(Self.draft)
        form.handOff(because: .closed)
        #expect(library.notices.waiting.isEmpty)
    }

    @Test func aCancelledTitleIsNotGivenBack() {
        let library = FakeItemLibrary()
        let form = ViewTitleForm(title: "Plans", library: library)
        form.discard()
        form.handOff(because: .closed)
        #expect(library.notices.waiting.isEmpty)
    }

    @Test func aBlankTitleCannotBeSubmitted() async {
        let library = FakeItemLibrary()
        let form = ViewTitleForm(title: "  ", library: library)
        #expect(!form.canSubmit)
        #expect(await form.submit(Self.draft) == .refused)
        #expect(library.views.isEmpty)
    }
}
