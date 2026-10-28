import Foundation
import Testing
@testable import MAPP

/// A view's title or new name stays where it was typed until the server takes it.
@MainActor
@Suite(.hangLimit)
struct ViewTitleFormTests {
    private static let view = LibraryView(id: ItemID("view-open"), title: "Open", version: 1)
    private static let draft = ViewDraft.Draft(query: LibraryViewQuery(), sort: [], group: nil)

    private static func library() -> FakeItemLibrary {
        let library = FakeItemLibrary()
        library.views = [view]
        return library
    }

    @Test func aRenameIsBasedOnTheVersionTheSheetOpenedOn() async {
        let library = Self.library()
        let form = ViewTitleForm(renaming: Self.view, library: library)
        // Renamed elsewhere while the sheet was open.
        var elsewhere = Self.view
        elsewhere.title = "Elsewhere"
        elsewhere.version = 2
        library.views = [elsewhere]

        form.title = "Mine"
        #expect(await form.submit() == .refused)
        #expect(library.views.first?.title == "Elsewhere")
        #expect(form.title == "Mine")
    }

    @Test func aRefusedTitleStaysForAnotherTry() async throws {
        let library = Self.library()
        library.viewFailure = ViewWriteFailure(kind: .offline, message: "Offline")
        let form = ViewTitleForm(new: Self.draft, layout: .table, title: "Plans", library: library)
        #expect(await form.submit() == .refused)
        #expect(form.title == "Plans")
        #expect(form.canSubmit)

        library.viewFailure = nil
        guard case .done(let view?) = await form.submit() else {
            Issue.record("The retry was not taken")
            return
        }
        #expect(view.title == "Plans")
    }

    @Test func aTitleTheWindowTakesAwayIsGivenBack() {
        let library = Self.library()
        let form = ViewTitleForm(new: Self.draft, layout: .table, title: "Plans", library: library)
        form.handOff(because: .closed)
        #expect(library.notices.waiting.last?.text == "Plans")
        #expect(library.notices.waiting.last?.title == String(localized: "View Not Saved"))
        // A rename left as it was gives back nothing.
        let rename = ViewTitleForm(renaming: Self.view, library: library)
        let told = library.notices.waiting.count
        rename.handOff(because: .closed)
        #expect(library.notices.waiting.count == told)
    }
}
