import Foundation
import Testing
@testable import MAPP

/// What a quit that runs out of time says about the stage it did not finish, without a window or a library.
struct TelemetryTests {
    @Test
    func aQuitStuckBehindTheEngineNamesTheStepAndWhatWaits() {
        let activity = EngineActivity()
        let began = ContinuousClock.now
        activity.tell()
        activity.tell()
        activity.begin("change.server", at: began)
        let trace = QuitTrace(activity: activity)
        trace.begin(.editors)
        trace.end(.editors)
        trace.begin(.queue)

        let text = trace.diagnosis(at: began + .milliseconds(3000))
        #expect(text.contains("queue did not finish"))
        #expect(text.contains("engine busy with change.server for 3000 ms, 1 waiting"))
        #expect(trace.unfinished == [.queue])
    }

    @Test
    func aQuitStuckInTheEditorsNamesThemAndNotTheQueue() {
        let trace = QuitTrace(activity: EngineActivity())
        trace.begin(.editors)

        let text = trace.diagnosis()
        #expect(text.contains("editors did not finish"))
        #expect(!text.contains("queue"))
    }

    @Test
    func anEngineThatTookNoEventStillSaysItIsIdleWithEventsWaiting() {
        let activity = EngineActivity()
        activity.tell()
        let trace = QuitTrace(activity: activity)
        trace.begin(.queue)

        #expect(trace.diagnosis().contains("engine idle, 1 waiting"))
    }

    @Test
    func aLibraryThatClosedSkipsTheQueueStage() {
        let trace = QuitTrace(activity: nil)
        trace.skip(.queue, because: "no library is open")

        #expect(trace.unfinished.isEmpty)
        #expect(trace.diagnosis().contains("between stages"))
    }
}
