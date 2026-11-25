import Foundation
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
}
