import Foundation
import Testing
@testable import MarfaMac

@Suite(.hangLimit) @MainActor struct AutomaticExportTests {
    /// A whole archive: a manifest naming `files` files, of which it carries `carried`.
    private struct Archive: ArchiveSource {
        var files = 0
        var carried = 0
        func stream(into write: @Sendable ([UInt8]) throws -> Void) async throws {
            try write(manifestEntry(files: files, carried: carried))
        }
    }

    /// An archive that sends its manifest and then waits until its task is cancelled.
    private struct Held: ArchiveSource {
        func stream(into write: @Sendable ([UInt8]) throws -> Void) async throws {
            try write(manifestEntry())
            while true { try await Task.sleep(for: .milliseconds(10)) }
        }
    }

    private struct Down: ArchiveSource {
        func stream(into write: @Sendable ([UInt8]) throws -> Void) async throws { throw URLError(.cannotConnectToHost) }
    }

    /// The Marfa a test has open, which it can switch.
    private final class Open {
        var address = "https://one.test"
        var instance: String? = "instance-one"
        var source: (any ArchiveSource)? = Archive()
        var marfa: AutomaticExport.Marfa? {
            let instance = instance
            return .init(address: address, name: "Marfa", instance: { instance }, source: source)
        }
    }

    private func folder() throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "automatic-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "automatic-export-\(UUID())"))
    }

    private func files(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    @Test func anExportThatIsDueRunsOnceAndOneNotYetDueDoesNot() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let open = Open()
        var clock = Date(timeIntervalSince1970: 1_795_000_000)
        let export = AutomaticExport(defaults: try defaults(), marfa: { open.marfa }, tell: { _, _ in }, now: { clock })
        await export.learn()
        export.set(.daily, folder: folder)

        await export.check()
        #expect(try files(in: folder) == ["Marfa 2026-11-18.tar"], "none was made yet, so one is due at once")

        clock.addTimeInterval(3600)
        await export.check()
        #expect(try files(in: folder).count == 1, "an hour later, a daily export is not due")

        clock.addTimeInterval(24 * 3600)
        await export.check()
        #expect(try files(in: folder).count == 2, "a day on, it is due and the earlier one is kept")
    }

    @Test func aPlanBelongsToTheMarfaItWasSetFor() async throws {
        let first = try folder()
        defer { try? FileManager.default.removeItem(at: first) }
        let defaults = try defaults()
        let open = Open()
        let export = AutomaticExport(defaults: defaults, marfa: { open.marfa }, tell: { _, _ in })
        export.set(.daily, folder: first)
        await export.learn()
        #expect(export.current?.instance == "instance-one", "a plan set before the id was known is bound to it once learnt")

        open.address = "https://two.test"
        open.instance = "instance-two"
        await export.check()
        #expect(export.current == nil, "another Marfa shows Never")
        #expect(try files(in: first).isEmpty, "another Marfa is never exported into the first one's folder")

        open.address = "https://one.test"
        open.instance = "instance-three"
        await export.check()
        #expect(export.current == nil, "another instance at the first address is another Marfa")
        #expect(try files(in: first).isEmpty)

        open.address = "https://one-moved.test"
        open.instance = "instance-one"
        let reopened = AutomaticExport(defaults: defaults, marfa: { open.marfa }, tell: { _, _ in })
        await reopened.check()
        #expect(reopened.current?.folder == first.path, "the first Marfa keeps its plan at a new address and after a relaunch")
        #expect(try files(in: first).count == 1)
    }

    @Test func eachDistinctFailureIsToldOnceAndLeavesEarlierExportsAlone() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data([9]).write(to: folder.appending(path: "Marfa 2026-11-17.tar"))
        let open = Open()
        open.source = Down()
        var told: [String] = []
        var clock = Date(timeIntervalSince1970: 1_795_000_000)
        let export = AutomaticExport(defaults: try defaults(), marfa: { open.marfa }, tell: { told.append($1) }, now: { clock })
        await export.learn()
        export.set(.daily, folder: folder)

        await export.check()
        await export.check()
        #expect(told.count == 1, "the same failure is told once")
        #expect(try files(in: folder) == ["Marfa 2026-11-17.tar"])

        let gone = folder.appending(path: "gone", directoryHint: .isDirectory)
        export.set(.daily, folder: gone)
        open.source = Archive()
        await export.check()
        await export.check()
        #expect(told.count == 2, "a new kind of failure is told, once")

        export.set(.daily, folder: folder)
        open.source = Archive(files: 3, carried: 1)
        await export.check()
        clock.addTimeInterval(24 * 3600)
        await export.check()
        #expect(try files(in: folder).count == 3, "both exports were saved")
        #expect(told.count == 3 && told.last?.contains("lacks 2 files") == true, "files not carried are told, once")
        #expect(export.current?.last == clock, "an export with files not carried still counts as run")
    }

    @Test func aResetStopsARunningExportAndNothingIsWrittenBack() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = try defaults()
        let open = Open()
        open.source = Held()
        let export = AutomaticExport(defaults: defaults, marfa: { open.marfa }, tell: { _, _ in Issue.record("nothing is told") })
        await export.learn()
        export.set(.daily, folder: folder)
        let check = Task { await export.check() }
        #expect(await eventually { (try? files(in: folder).count) == 1 }, "the export has begun its temporary file")

        MacSettings.reset(in: defaults)
        export.reset()
        _ = await check.value
        #expect(export.current == nil && export.plans.isEmpty)
        #expect(defaults.data(forKey: AutomaticExport.plansKey) == nil)
        #expect(try files(in: folder).isEmpty, "the stopped export removed its temporary file")
    }

    @Test func aQuitStopsTheChecksAndLeavesNoHalfFile() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let open = Open()
        open.source = Held()
        let export = AutomaticExport(defaults: try defaults(), marfa: { open.marfa }, tell: { _, _ in })
        await export.learn()
        export.set(.daily, folder: folder)
        let check = Task { await export.check() }
        #expect(await eventually { (try? files(in: folder).count) == 1 })

        await export.stop(within: .seconds(2))
        #expect(try files(in: folder).isEmpty, "no half file is left")
        _ = await check.value
        open.source = Archive()
        await export.check()
        #expect(try files(in: folder).isEmpty, "no check runs after a quit")
        #expect(export.current?.last == nil)
    }
}
