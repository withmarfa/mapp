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
        browser.show(.itemType("core.task"), in: library, order: ItemOrder())
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

    @Test func theCalendarsCommandsMoveFromTheWeekTheLibrarysClockShows() throws {
        let clock = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let library = FakeItemLibrary(items: [Self.task("A", status: "todo")], now: clock)
        let browser = Self.browser(.calendar, in: library)
        let commands = ViewOptionCommand.commands(for: browser, in: library, storedColumns: .constant(Data()))
        let next = try #require(commands.first { $0.title == "Next Week" })
        next.action()
        let expected = try #require(Calendar.current.date(byAdding: .weekOfYear, value: 1, to: clock))
        #expect(browser.calendarDay == expected, "a week on from the clock's, not from the wall clock")
        let today = try #require(ViewOptionCommand.commands(for: browser, in: library, storedColumns: .constant(Data())).first { $0.title == "Go to Today" })
        today.action()
        #expect(browser.calendarDay == nil)
    }

    @Test func theGalleryOffersTheOtherCardSizes() {
        let library = FakeItemLibrary(items: [Self.task("A", status: "todo")])
        #expect(Self.titles(Self.browser(.gallery, in: library), library) == ["Small Cards", "Large Cards"])
    }

    @Test func theListAndSettingsOfferNoViewOptionCommands() {
        let library = FakeItemLibrary(items: [Self.task("A", status: "todo")])
        #expect(Self.titles(Self.browser(.list, in: library), library).isEmpty)
        let settings = Self.browser(.board, in: library)
        settings.showSettings()
        #expect(Self.titles(settings, library).isEmpty)
    }

    @Test func anItemPageOpenedFromATableTheBoardOrTheTimelineOffersNone() {
        let library = FakeItemLibrary(items: [Self.task("A", status: "todo")])
        for mode in [ItemViewMode.table, .board, .timeline] {
            let browser = Self.browser(mode, in: library)
            // The fixture has no date, so the timeline has nothing to offer even while it shows.
            if mode != .timeline { #expect(!Self.titles(browser, library).isEmpty, "\(mode) while it shows") }
            browser.selection = [ItemID("A")]
            browser.openCollectionSelection()
            #expect(!browser.showsCollection)
            #expect(Self.titles(browser, library).isEmpty, "\(mode) with an item page open")
            #expect(!browser.offersViewOptions)
        }
    }
}
