import Foundation
import Synchronization
import Testing
@testable import MAPP

nonisolated struct LatestTests {
    /// Cancelling a task that watches runs the stream's termination handler while the runtime holds that task's
    /// status lock, and telling the watcher a value needs the same lock. If the two take `Latest`'s lock and the
    /// task's in opposite orders, an updater and a canceller wait on each other for ever (withmarfa/mapp#91).
    @Test(.timeLimit(.minutes(1)))
    func watchersCancelledWhileValuesAreToldNeverBlockTheUpdaters() async {
        let latest = Latest(0)
        let group = DispatchGroup()
        for lane in 0..<2 {
            DispatchQueue.global().async(group: group) {
                for number in 1...30_000 { latest.set(number * 2 + lane) }
            }
        }
        for _ in 0..<3_000 {
            let watcher = Task { for await _ in latest.values() {} }
            await Task.yield()
            watcher.cancel()
            await watcher.value
        }
        await withCheckedContinuation { continuation in group.notify(queue: .global()) { continuation.resume() } }
    }

    /// Every watcher is told values in the order they were set, whichever thread sets them, and ends on the last.
    @Test(.timeLimit(.minutes(1)))
    func eachWatcherIsToldValuesInOrderAndEndsOnTheLast() async {
        let latest = Latest(0)
        let lanes = 4, perLane = 5_000
        let seen = Mutex<[Int]>([])
        let watching = Task {
            for await number in latest.values() {
                seen.withLock { $0.append(number) }
                if number == lanes * perLane { return }
            }
        }
        let group = DispatchGroup()
        for _ in 0..<lanes {
            DispatchQueue.global().async(group: group) {
                for _ in 0..<perLane { latest.update { $0 += 1 } }
            }
        }
        await watching.value
        let told = seen.withLock { $0 }
        #expect(told.last == lanes * perLane)
        #expect(told == told.sorted(), "a value set earlier is never told after one set later")
        #expect(Set(told).count == told.count)
    }

    @Test func aWatcherIsToldTheValueItCameTo() async {
        let latest = Latest("one")
        latest.set("two")
        var iterator = latest.values().makeAsyncIterator()
        #expect(await iterator.next() == "two")
        latest.set("three")
        #expect(await iterator.next() == "three")
        latest.finish()
        #expect(await iterator.next() == nil)
    }
}
