import Foundation
import SwiftUI
import Testing
@testable import MAPP

struct ViewOptionCommandTests {
    private static func task(_ id: String, status: String) -> Item {
        Item(id: ItemID(id), type: TypeID("core.task"), title: id, titleRule: .property("title"),
             properties: [Property(key: "status", value: .string(status))],
             version: ItemVersion(1), created: .distantPast, modified: .distantPast)
    }

    private static func browser(_ mode: ItemViewMode, in library: FakeItemLibrary) -> Browser {
        let browser = Browser()
        browser.show(.itemType("core.task"), in: library, order: NoteOrder())
        browser.viewMode = mode
        return browser
    }

    private static func titles(_ browser: Browser, _ library: FakeItemLibrary) -> [String] {
        ViewOptionCommand.commands(for: browser, in: library, storedColumns: .constant(Data())).map(\.title)
    }

    @Test func theBoardOffersTheOtherGroupingsAndTheOtherDensity() throws {
        let library = FakeItemLibrary(items: [Self.task("A", status: "todo"), Self.task("B", status: "done")])
        let browser = Self.browser(.board, in: library)
        let titles = Self.titles(browser, library)
        #expect(titles.contains("Group by Priority"))
        #expect(!titles.contains("Group by Status"), "the grouping already chosen is not offered again")
        #expect(titles.contains("Compact Cards"))

        let compact = try #require(
            ViewOptionCommand.commands(for: browser, in: library, storedColumns: .constant(Data()))
                .first { $0.title == "Compact Cards" })
        compact.action()
        #expect(browser.compactBoards[browser.item] == true)
        #expect(Self.titles(browser, library).contains("Comfortable Cards"))
    }

    @Test func theListTheGalleryAndSettingsOfferNoViewOptionCommands() {
        let library = FakeItemLibrary(items: [Self.task("A", status: "todo")])
        for mode in [ItemViewMode.list, .gallery] {
            #expect(Self.titles(Self.browser(mode, in: library), library).isEmpty, "\(mode)")
        }
        let settings = Self.browser(.board, in: library)
        settings.showSettings()
        #expect(Self.titles(settings, library).isEmpty)
    }

    @Test func anItemPageOpenedFromATableTheBoardOrTheAgendaOffersNone() {
        let library = FakeItemLibrary(items: [Self.task("A", status: "todo")])
        for mode in [ItemViewMode.table, .board, .agenda] {
            let browser = Self.browser(mode, in: library)
            // The fixture has no date, so the agenda has nothing to offer even while it shows.
            if mode != .agenda { #expect(!Self.titles(browser, library).isEmpty, "\(mode) while it shows") }
            browser.selection = [ItemID("A")]
            browser.openCollectionSelection()
            #expect(!browser.showsCollection)
            #expect(Self.titles(browser, library).isEmpty, "\(mode) with an item page open")
            #expect(!browser.offersViewOptions)
        }
    }
}
