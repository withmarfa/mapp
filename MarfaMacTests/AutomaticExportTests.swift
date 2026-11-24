import Foundation
import Testing
@testable import MarfaMac

@Suite(.hangLimit) @MainActor struct AutomaticExportTests {
    private struct Archive: ArchiveSource {
        func stream(into write: @Sendable ([UInt8]) throws -> Void) async throws { try write([1, 2, 3]) }
    }

    private func exports(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    @Test func anExportThatIsDueRunsOnceAndOneNotYetDueDoesNot() async throws {
        let suite = "automatic-export-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = URL.temporaryDirectory.appending(path: "automatic-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        defaults.set(ExportSchedule.daily.rawValue, forKey: AutomaticExport.scheduleKey)
        defaults.set(folder.path, forKey: AutomaticExport.folderKey)

        var clock = Date(timeIntervalSince1970: 1_795_000_000)
        let export = AutomaticExport(
            defaults: defaults, target: { .init(address: "https://marfa.test", name: "Marfa", source: Archive()) }, tell: { _, _ in },
            now: { clock })

        await export.check()
        #expect(try exports(in: folder) == ["Marfa 2026-11-18.tar"], "none was made yet, so one is due at once")

        clock.addTimeInterval(3600)
        await export.check()
        #expect(try exports(in: folder).count == 1, "an hour later, a daily export is not due")

        clock.addTimeInterval(24 * 3600)
        await export.check()
        #expect(try exports(in: folder).count == 2, "a day on, it is due and the earlier one is kept")
    }

    @Test func aFailureIsToldOnceAndLeavesTheEarlierExportsAlone() async throws {
        struct Down: ArchiveSource {
            func stream(into write: @Sendable ([UInt8]) throws -> Void) async throws { throw URLError(.cannotConnectToHost) }
        }
        let suite = "automatic-export-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = URL.temporaryDirectory.appending(path: "automatic-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data([9]).write(to: folder.appending(path: "Marfa 2026-11-17.tar"))
        defaults.set(ExportSchedule.daily.rawValue, forKey: AutomaticExport.scheduleKey)
        defaults.set(folder.path, forKey: AutomaticExport.folderKey)

        var told = 0
        let export = AutomaticExport(
            defaults: defaults, target: { .init(address: "https://marfa.test", name: "Marfa", source: Down()) },
            tell: { _, _ in told += 1 })

        await export.check()
        await export.check()
        #expect(told == 1)
        #expect(try exports(in: folder) == ["Marfa 2026-11-17.tar"])
    }
}
