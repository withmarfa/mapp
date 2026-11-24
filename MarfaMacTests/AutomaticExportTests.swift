import Foundation
import Synchronization
import Testing
@testable import MarfaMac

@Suite(.hangLimit) @MainActor struct AutomaticExportTests {
    /// A whole archive of `instance`, naming `files` files of which it carries `carried`.
    private struct Archive: ArchiveSource {
        var instance = "instance-one"
        var files = 0
        var carried = 0
        func stream(into write: @Sendable ([UInt8]) throws -> Void) async throws {
            try write(archiveBytes(instance: instance, files: files, carried: carried))
        }
    }

    /// An archive that sends every byte but its end, says it has begun, and then waits until its task is cancelled.
    private final class Held: ArchiveSource {
        let begun = Mutex(false)
        func stream(into write: @Sendable ([UInt8]) throws -> Void) async throws {
            try write(Array(archiveBytes().dropLast(1024)))
            begun.withLock { $0 = true }
            // Hold the stream open until the test cancels it.
            try await Task.sleep(for: .seconds(3600))
        }
    }

    /// An archive that sends every byte but its end, then waits for its latch before it sends the end.
    private final class Gated: ArchiveSource {
        let latch = Latch()
        func stream(into write: @Sendable ([UInt8]) throws -> Void) async throws {
            let bytes = archiveBytes()
            try write(Array(bytes.dropLast(1024)))
            await latch.wait()
            try write(Array(bytes.suffix(1024)))
        }
    }

    private struct Down: ArchiveSource {
        func stream(into write: @Sendable ([UInt8]) throws -> Void) async throws { throw URLError(.cannotConnectToHost) }
    }

    /// Holds a question until the test lets it go.
    private final class Latch: Sendable {
        private let waiting = Mutex<CheckedContinuation<Void, Never>?>(nil)
        var isWaiting: Bool { waiting.withLock { $0 != nil } }
        func wait() async {
            await withCheckedContinuation { continuation in waiting.withLock { $0 = continuation } }
        }
        func open() {
            waiting.withLock {
                $0?.resume()
                $0 = nil
            }
        }
    }

    /// The Marfa a test has open, which it can switch.
    private final class Open {
        var address = "https://one.test"
        var instance: String? = "instance-one"
        var latch: Latch?
        var source: (any ArchiveSource)? = Archive()
        var marfa: AutomaticExport.Marfa? {
            let (instance, latch) = (instance, latch)
            return .init(
                address: address, name: "Marfa",
                instance: {
                    await latch?.wait()
                    return instance
                }, source: source)
        }
    }

    private func folder() throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "automatic-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func defaults() -> UserDefaults {
        ThrowawayDefaults.make("AutomaticExportTests")
    }

    private func files(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    /// An export of the open Marfa, its plan set to `schedule` into `folder`.
    private func export(
        _ open: Open, defaults: UserDefaults? = nil, folder: URL, schedule: ExportSchedule = .daily,
        tell: @escaping (String, String) -> Void = { _, _ in }, now: @escaping () -> Date = { .now }
    ) async -> AutomaticExport {
        let export = AutomaticExport(defaults: defaults ?? self.defaults(), marfa: { open.marfa }, tell: tell, now: now)
        await export.learn()
        export.set(schedule, folder: folder, for: "instance-one")
        return export
    }

    @Test func anExportThatIsDueRunsOnceAndOneNotYetDueDoesNot() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var clock = Date(timeIntervalSince1970: 1_795_000_000)
        let export = await export(Open(), folder: folder, now: { clock })

        #expect(await export.check())
        #expect(try files(in: folder) == ["Marfa 2026-11-18.tar"], "none was made yet, so one is due at once")

        clock.addTimeInterval(3600)
        await export.check()
        #expect(try files(in: folder).count == 1, "an hour later, a daily export is not due")

        clock.addTimeInterval(24 * 3600)
        await export.check()
        #expect(try files(in: folder).count == 2, "a day on, it is due and the earlier one is kept")
    }

    @Test func aCheckAsksAgainSoonWhileTheCopyCannotSayWhichMarfaItIs() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = defaults()
        _ = await export(Open(), defaults: defaults, folder: folder)
        let open = Open()
        open.instance = nil
        let launched = AutomaticExport(defaults: defaults, marfa: { open.marfa }, tell: { _, _ in })
        #expect(await launched.check() == false, "a launch before the copy knows its id asks again soon, not in an hour")
        open.source = nil
        open.instance = "instance-one"
        #expect(await launched.check() == false, "a server not answering is asked again soon")
        open.source = Down()
        #expect(await launched.check() == false, "a server that fails to answer at launch is asked again soon, not in an hour")
        open.source = Archive()
        #expect(await launched.check())
        #expect(try files(in: folder).count == 1)
    }

    @Test func aPlanBelongsToTheMarfaItWasSetFor() async throws {
        let first = try folder()
        defer { try? FileManager.default.removeItem(at: first) }
        let defaults = defaults()
        let open = Open()
        let export = await export(open, defaults: defaults, folder: first)

        open.address = "https://two.test"
        open.instance = "instance-two"
        open.source = Archive(instance: "instance-two")
        await export.check()
        #expect(export.current == nil, "another Marfa shows Never")
        export.set(.weekly, for: "instance-one")
        #expect(export.plans.map(\.schedule) == [.daily], "a choice made for one Marfa is not kept once another is open")
        #expect(try files(in: first).isEmpty, "another Marfa is never exported into the first one's folder")

        open.address = "https://one-moved.test"
        open.instance = "instance-one"
        open.source = Archive()
        let reopened = AutomaticExport(defaults: defaults, marfa: { open.marfa }, tell: { _, _ in })
        await reopened.check()
        #expect(reopened.current?.folder == first.path, "the first Marfa keeps its plan at a new address and after a relaunch")
        #expect(try files(in: first).count == 1)
    }

    @Test func anArchiveOfAnotherMarfaIsNotSavedAndIsTold() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let open = Open()
        open.source = Archive(instance: "instance-two")
        var told: [String] = []
        let export = await export(open, folder: folder, tell: { told.append($1) })
        await export.check()
        #expect(try files(in: folder).isEmpty)
        #expect(told.count == 1 && told.first?.contains("another Marfa") == true)
        #expect(export.current?.last == nil, "the schedule does not advance")
    }

    @Test func eachKindOfFailureIsToldOnceUntilAnExportIsSaved() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data([9]).write(to: folder.appending(path: "Marfa 2026-11-17.tar"))
        let open = Open()
        var told: [String] = []
        var clock = Date(timeIntervalSince1970: 1_795_000_000)
        let export = await export(open, folder: folder, tell: { told.append($1) }, now: { clock })

        for _ in 0..<2 {
            open.source = Down()
            await export.check()
            open.source = Archive(instance: "instance-two")
            await export.check()
        }
        #expect(told.count == 2, "two kinds, each told once however they alternate")
        #expect(export.current?.last == nil)

        open.source = Archive(files: 3, carried: 1)
        await export.check()
        clock.addTimeInterval(24 * 3600)
        await export.check()
        #expect(try files(in: folder).count == 3, "both exports were saved and the earlier file kept")
        #expect(told.count == 3 && told.last?.contains("lacks 2 files") == true, "files not carried are told once for their count")
        #expect(export.current?.last == clock, "an export with files not carried still counts as run")

        open.source = Down()
        clock.addTimeInterval(24 * 3600)
        await export.check()
        #expect(told.count == 4, "a failure after a saved export is told again")
    }

    @Test func aResetStopsARunningExportAndNothingIsPublishedOrWrittenBack() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = defaults()
        let open = Open()
        let held = Held()
        open.source = held
        let export = await export(open, defaults: defaults, folder: folder, tell: { _, _ in Issue.record("nothing is told") })
        let check = Task { await export.check() }
        #expect(await eventually { held.begun.withLock { $0 } })

        MacSettings.reset(in: defaults)
        export.reset()
        _ = await check.value
        #expect(export.current == nil && export.plans.isEmpty)
        #expect(defaults.data(forKey: AutomaticExport.plansKey) == nil)
        #expect(try files(in: folder).isEmpty)
    }

    @Test func aCheckThatWaitedAcrossAResetDoesNothing() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let open = Open()
        let export = await export(open, folder: folder, tell: { _, _ in Issue.record("nothing is told") })
        let latch = Latch()
        open.latch = latch
        let check = Task { await export.check() }
        #expect(await eventually { latch.isWaiting })
        export.reset()
        open.latch = nil
        export.set(.daily, folder: folder, for: "instance-one")
        latch.open()
        _ = await check.value
        #expect(try files(in: folder).isEmpty, "the check begun before the reset exports nothing under the new plan")
        #expect(export.current?.last == nil)
    }

    @Test func aNewChoiceWhileAnExportRunsStopsIt() async throws {
        let first = try folder()
        let second = try folder()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let open = Open()
        let held = Held()
        open.source = held
        let export = await export(open, folder: first)
        let check = Task { await export.check() }
        #expect(await eventually { held.begun.withLock { $0 } })
        export.set(.daily, folder: second, for: "instance-one")
        _ = await check.value
        #expect(export.current?.last == nil, "the export under the earlier choice counts for nothing")

        open.source = Archive()
        await export.check()
        #expect(try files(in: first).isEmpty)
        #expect(try files(in: second).count == 1)
    }

    @Test func aRestoreIsReadAgainAndStopsAnExportUnderAPlanItChanged() async throws {
        let first = try folder()
        let second = try folder()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let defaults = defaults()
        let open = Open()
        let held = Held()
        open.source = held
        let export = await export(open, defaults: defaults, folder: first)
        let check = Task { await export.check() }
        #expect(await eventually { held.begun.withLock { $0 } })

        let restored = [ExportPlan(instance: "instance-one", schedule: .weekly, folder: second.path)]
        defaults.set(try JSONEncoder().encode(restored), forKey: AutomaticExport.plansKey)
        export.reload()
        _ = await check.value
        #expect(export.current == restored.first, "the restored plan is the one in use, and the stopped export wrote nothing back")

        open.source = Archive()
        await export.check()
        #expect(try files(in: first).isEmpty)
        #expect(try files(in: second).count == 1)
        let kept = try JSONDecoder().decode([ExportPlan].self, from: try #require(defaults.data(forKey: AutomaticExport.plansKey)))
        #expect(kept.map(\.folder) == [second.path], "saving the export's time keeps the restored plan")
    }

    @Test func aRestoreOfThePlanStopsARunningExportSoItsTimeIsNotWrittenOverIt() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = defaults()
        let open = Open()
        let gated = Gated()
        open.source = gated
        let export = await export(open, defaults: defaults, folder: folder)
        let check = Task { await export.check() }
        #expect(await eventually { gated.latch.isWaiting })

        var restored = try #require(export.current)
        restored.last = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(try JSONEncoder().encode([restored]), forKey: AutomaticExport.plansKey)
        export.reload()
        gated.latch.open()
        _ = await check.value
        #expect(export.current == restored)
        let kept = try JSONDecoder().decode([ExportPlan].self, from: try #require(defaults.data(forKey: AutomaticExport.plansKey)))
        #expect(kept == [restored], "the export under the plan as it was before the restore writes nothing back")
        #expect(try files(in: folder).isEmpty)
    }

    @Test func aSyncThatLeavesThePlansAsTheyWereLetsAnExportFinish() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let open = Open()
        let gated = Gated()
        open.source = gated
        let export = await export(open, folder: folder)
        let check = Task { await export.check() }
        #expect(await eventually { gated.latch.isWaiting })
        export.reload()
        gated.latch.open()
        _ = await check.value
        #expect(try files(in: folder).count == 1)
        #expect(export.current?.last != nil)
    }

    @Test func aQuitStopsTheChecksAndPublishesNothing() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let open = Open()
        let held = Held()
        open.source = held
        let export = await export(open, folder: folder)
        let check = Task { await export.check() }
        #expect(await eventually { held.begun.withLock { $0 } })

        await export.stop(within: .seconds(2))
        _ = await check.value
        open.source = Archive()
        await export.check()
        #expect(try files(in: folder).isEmpty, "nothing is published and no check runs after a quit")
        #expect(export.current?.last == nil)
    }
}
