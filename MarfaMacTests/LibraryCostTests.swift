import Foundation
import Synchronization
import Testing
@testable import MarfaMac

/// The Library's table on about fifty thousand items (`BigLibrary`), timed as it is shown and as it follows an edit. It
/// prints `COST|library|<action>|<milliseconds>|1` lines for a person to read and checks only that the data is the size it
/// claims. Run it with the Measure test plan, which sets `MARFA_MAC_MEASURE`; the other plans leave it out.
@MainActor
@Suite(.tags(.measure), .enabled(if: ProcessInfo.processInfo.environment["MARFA_MAC_MEASURE"] != nil), .serialized)
struct LibraryCostTests {
    private func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    }

    private func line(_ action: String, _ ms: Double) { print("COST|library|\(action)|\(String(format: "%.2f", ms))|1") }

    @Test func theLibraryShownAndEdited() async throws {
        let (library, source) = try await BigLibrary.loaded(scale: 75)
        let browser = Browser()
        browser.adopt(library)
        browser.showing = .library
        let count = library.items(in: .library).count
        #expect(count > 40_000)

        // The first table: what the window waits for before it draws the Library.
        var start = ContinuousClock.now
        let content = browser.tableContent(in: library)
        _ = content.rows.count
        line("show(\(count))", milliseconds(since: start))

        // The same table asked for again, as every redraw of the window does.
        start = ContinuousClock.now
        _ = browser.tableContent(in: library).rows.count
        line("showAgain", milliseconds(since: start))

        // One edit: how long the main actor holds the window to ask for the next table, then how long until it lands
        // (its sort runs off the main actor, after a run of edits is let settle).
        let before = browser.tableArrangements
        Cost.resetTallies()
        var edited = try #require(library.items(in: .library).first)
        edited.title = "Edited"
        edited.modified = .now
        let revision = library.contentRevision
        source.send(.upserted([edited]))
        try #require(await eventually { library.contentRevision != revision })
        start = ContinuousClock.now
        _ = browser.tableContent(in: library).rows.count
        line("afterEditMainActor", milliseconds(since: start))
        try #require(await eventually(within: .seconds(60)) { _ = browser.tableContent(in: library); return browser.tableArrangements > before })
        line("afterEditLanded", milliseconds(since: start))
        // The arrangement's own time on the main actor, which makes, filters and sorts the rows off it.
        line("afterEditArrangeMainActor", Cost.tallies[.tableArrange]?.milliseconds ?? 0)

        // Types and Sources, made again as at each change while one shows.
        for place in [PlaceView.types, .sources] {
            browser.showing = place
            start = ContinuousClock.now
            _ = browser.indexRows(in: library).count
            line("\(place.place.word)Rows", milliseconds(since: start))
        }
    }
    /// The Library grouped, as a person who groups it sees it: grouping and the choices of Add Sort and Filter By are made off the
    /// main actor with the rows, so an edit holds the window no longer than an ungrouped one.
    @Test func theGroupedLibraryEdited() async throws {
        let (library, source) = try await BigLibrary.loaded(scale: 75)
        let browser = Browser()
        browser.adopt(library)
        browser.showing = .library
        browser.tableOptions[.library, default: ItemTableOptions()].grouping = .column("field.status")
        let count = library.items(in: .library).count

        var start = ContinuousClock.now
        let content = browser.tableContent(in: library)
        _ = (content.groups.count, content.sortChoices.count, content.filterOffer.placeFields.count)
        line("groupedShow(\(count))", milliseconds(since: start))

        let before = browser.tableArrangements
        Cost.resetTallies()
        var edited = try #require(library.items(in: .library).first)
        edited.title = "Edited"
        edited.modified = .now
        let revision = library.contentRevision
        source.send(.upserted([edited]))
        try #require(await eventually { library.contentRevision != revision })
        try #require(await eventually(within: .seconds(60)) { _ = browser.tableContent(in: library); return browser.tableArrangements > before })
        // What the window reads of the landed table: its groups and the choices its menus offer.
        start = ContinuousClock.now
        let landed = browser.tableContent(in: library)
        _ = (landed.groups.count, landed.allGroups.count, landed.sortChoices.count, landed.filterOffer.placeFields.count)
        line("groupedAfterEditReadMainActor", milliseconds(since: start))
        line("groupedAfterEditArrangeMainActor", Cost.tallies[.tableArrange]?.milliseconds ?? 0)
    }

    /// A search with many results is arranged beside the Library's table, which stays held, so ending the search never builds
    /// the Library again on the main actor. The copy lists at most `SearchResults.limit` hits for a person, so the source
    /// here answers more, to reach the size a large search would.
    @Test func aSearchAndItsEnd() async throws {
        let (library, source) = try await BigLibrary.loaded(scale: 75)
        let browser = Browser()
        browser.adopt(library)
        browser.showing = .library
        let everything = count(of: library)
        _ = browser.tableContent(in: library).rows.count
        let ids = library.items(in: .library).map(\.id)
        source.hits.withLock { $0["aa"] = Array(ids.prefix(3_000)); $0["aab"] = Array(ids.prefix(2_500)) }

        browser.searchText = "aa"
        try #require(await eventually(within: .seconds(30)) { browser.searchResults(in: library)?.items.count == 3_000 })
        var start = ContinuousClock.now
        _ = browser.tableContent(in: library).rows.count
        line("searchShow(3000)", milliseconds(since: start))

        browser.searchText = "aab"
        try #require(await eventually(within: .seconds(30)) { browser.searchResults(in: library)?.items.count == 2_500 })
        let before = browser.tableArrangements
        start = ContinuousClock.now
        let shown = browser.tableContent(in: library)
        line("searchNextMainActor", milliseconds(since: start))
        #expect(shown.allRows.count == 3_000, "the last search's table stays while the next is arranged, never the whole Library")
        try #require(await eventually(within: .seconds(60)) { _ = browser.tableContent(in: library); return browser.tableArrangements > before })
        #expect(browser.tableContent(in: library).allRows.count == 2_500)

        browser.searchText = ""
        start = ContinuousClock.now
        let back = browser.tableContent(in: library)
        _ = back.rows.count
        line("searchEndedMainActor", milliseconds(since: start))
        #expect(back.allRows.count == everything)
    }

    private func count(of library: any ItemLibrary) -> Int { library.items(in: .library).count }
}
