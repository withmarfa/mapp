import Testing
@testable import MarfaMac

/// What `PlaceWork` holds and tells the window when a run ends.
@MainActor
@Suite(.hangLimit) struct PlaceWorkTests {
    /// A first answer the library outran is not held, but the window is told, so it asks again rather than wait on
    /// progress forever.
    @Test func anAnswerTurnedAwayStillTellsTheWindow() async {
        let work = PlaceWork<Int, String>()
        var landings = 0
        work.start(1, { "stale" }, accepts: { false }, landed: { landings += 1 })
        #expect(await eventually { landings == 1 })
        #expect(work.held == nil)
        #expect(work.runningKey == nil, "nothing still runs, so the next ask starts a fresh run")
        work.start(1, { "fresh" }, accepts: { true }, landed: { landings += 1 })
        #expect(await eventually { landings == 2 })
        #expect(work.held?.value == "fresh")
    }
}
