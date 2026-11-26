import Foundation
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

    /// Under a steady stream of changes every answer is outrun, so a first one the library has outrun `Outrun.limit`
    /// times lands as it is, and the answer for the key asked now follows it.
    @Test func aFirstAnswerOutrunAFewTimesLandsAsItIs() async {
        let work = PlaceWork<Int, String>()
        let started = Started()
        let releases = (0...Outrun.limit + 1).map { _ in DispatchSemaphore(value: 0) }
        var landings = 0
        func ask(_ key: Int) {
            work.start(key, { started.note(key); releases[key].wait(); return "answer \(key)" }, landed: { landings += 1 })
        }
        ask(0)
        for key in 0...Outrun.limit {
            #expect(await eventually { started.has(key) }, "the run for \(key) works")
            // The library changes under it.
            ask(key + 1)
            releases[key].signal()
            if key < Outrun.limit {
                #expect(await eventually { started.has(key + 1) })
                #expect(work.held == nil, "the first \(key + 1) answers are turned away")
            }
        }
        #expect(await eventually { work.held != nil })
        #expect(work.held?.key == Outrun.limit, "the answer that was outrun lands")
        #expect(landings == 1)
        // The run for the key asked now goes on and brings it up to date.
        releases[Outrun.limit + 1].signal()
        #expect(await eventually { work.held?.key == Outrun.limit + 1 })
    }

    /// A library that changes only now and then outruns nothing: its answer lands at once, and the count starts again.
    @Test func anAnswerNobodyOutranLandsAtOnce() async {
        let work = PlaceWork<Int, String>()
        var landings = 0
        work.start(1, { "answer" }, landed: { landings += 1 })
        #expect(await eventually { landings == 1 })
        #expect(work.held?.value == "answer")
    }

    /// An answer for another choice is no stand-in for the one asked now, however often it is outrun.
    @Test func anAnswerForAnotherChoiceNeverLandsAsItIs() async {
        let work = PlaceWork<Int, String>(isSameAsk: { _, _ in false })
        let started = Started()
        let releases = (0...Outrun.limit + 1).map { _ in DispatchSemaphore(value: 0) }
        func ask(_ key: Int) {
            work.start(key, { started.note(key); releases[key].wait(); return "answer \(key)" }, landed: {})
        }
        ask(0)
        for key in 0...Outrun.limit + 1 {
            #expect(await eventually { started.has(key) })
            if key <= Outrun.limit { ask(key + 1) }
            // Every earlier answer is turned away, as often as it is outrun.
            if key == Outrun.limit + 1 { #expect(work.held == nil) }
            releases[key].signal()
        }
        #expect(await eventually { work.held?.key == Outrun.limit + 1 })
    }

    private nonisolated final class Started: @unchecked Sendable {
        private let lock = NSLock()
        private var keys: Set<Int> = []
        nonisolated func note(_ key: Int) { lock.lock(); keys.insert(key); lock.unlock() }
        nonisolated func has(_ key: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return keys.contains(key) }
    }
}
