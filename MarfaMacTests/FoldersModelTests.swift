import Foundation
import Marfa
import Synchronization
import Testing
@testable import MarfaMac

@MainActor
@Suite(.hangLimit) struct FoldersModelTests {
    private static func copy(
        _ id: String, _ signIn: String = "marfa on MacBook Pro", uploads: Int = 0, downloads: Int = 0, removals: Int = 0,
        waiting: Bool = false, problems: [FolderProblem] = [], age: Int = 60
    ) -> FolderCopy {
        FolderCopy(
            id: id, signIn: signIn, pendingUploads: uploads, pendingDownloads: downloads, pausedRemovals: removals,
            firstSyncWaiting: waiting, problems: problems, ageSeconds: age)
    }

    /// The folders listed, each with its report and, through the copy, its settings.
    private func model(_ bench: OwnerBench, folders: [(OwnerFolder, FolderReport)], calls: FakeFolderCalls? = nil) -> FoldersModel {
        bench.calls.state.withLock { state in
            state.folders = folders.map(\.0)
            state.reports = Dictionary(uniqueKeysWithValues: folders.map { ($0.0.id, $0.1) })
        }
        let held = calls ?? FakeFolderCalls()
        held.state.withLock { state in
            for (folder, _) in folders where state.folders[folder.id] == nil {
                state.folders[folder.id] = FakeFolderCalls.folder(folder.id, folder.title)
            }
        }
        return FoldersModel(context: bench.context, folderCalls: held)
    }

    @Test func stopSyncingIsSentOnlyOnceTheOwnerAgrees() async throws {
        let bench = OwnerBench()
        let calls = FakeFolderCalls(FakeFolderCalls.folder("a", "Studio Notes"))
        let model = model(bench, folders: [(OwnerFolder(id: "a", title: "Studio Notes"), FolderReport(copies: []))], calls: calls)
        await model.load()
        model.open("a")

        model.askToStop()
        #expect(model.question != nil)
        #expect(calls.stops.isEmpty)
        model.cancelQuestion()
        #expect(model.question == nil)
        #expect(calls.stops.isEmpty)

        model.askToStop()
        let asked = try #require(model.question)
        await model.confirm(asked)
        #expect(calls.stops == ["a"])
        #expect(model.folder("a") == nil)
        #expect(model.stopped == "a")
    }

    @Test func aLimitChangedElsewhereIsToldAndNotWrittenOver() async throws {
        let bench = OwnerBench()
        let calls = FakeFolderCalls(FakeFolderCalls.folder("a", "Studio Notes"))
        let model = model(bench, folders: [(OwnerFolder(id: "a", title: "Studio Notes"), FolderReport(copies: []))], calls: calls)
        await model.load()
        model.open("a")
        #expect(model.removalDraft == "10")

        calls.changeElsewhere("a", .removalThreshold(RemovalThreshold(files: 25)))
        model.removalDraft = "40"
        await model.commitLimit(.removalLimit)
        #expect(calls.changes.map(\.baseVersion) == [1])
        #expect(try await calls.settings(of: "a").removalThreshold.files == 25)
        #expect(model.removalDraft == "40")
        #expect(model.errors[.removalLimit]?.contains("25") == true)
        #expect(model.settings["a"]?.version == 2)

        // Leaving the field sends nothing more; only Return sends the owner's value, on the version now read.
        await model.commitLimit(.removalLimit, explicitly: false)
        #expect(calls.changes.count == 1)
        await model.commitLimit(.removalLimit)
        #expect(calls.changes.last?.baseVersion == 2)
        #expect(try await calls.settings(of: "a").removalThreshold.files == 40)
        #expect(model.errors[.removalLimit] == nil)
    }

    @Test func aRefusedListNamesThePermissionAndReadsTheGrantsAgain() async {
        let bench = OwnerBench()
        bench.calls.fail("folders", with: .notPermitted(nil))
        let model = FoldersModel(context: bench.context, folderCalls: FakeFolderCalls())
        await model.load()
        #expect(model.failure == .notPermitted(nil))
        #expect(bench.refreshed == 1)
    }

    @Test func aFolderWhoseReportCannotBeReadKeepsItsRowWithOneLineOnItsPage() async {
        let bench = OwnerBench()
        let model = model(bench, folders: [(OwnerFolder(id: "a", title: "Studio Notes"), FolderReport(copies: []))])
        bench.calls.fail("folderReport", with: .unreachable)
        await model.load()
        #expect(model.folders.count == 1)
        #expect(model.condition(of: model.folders[0]) == nil)
        #expect(model.reportFailures["a"] == .unreachable)
    }

    @Test func aCopyWithRemovalsOrAProblemIsToldUnderNeedsAttentionOnly() {
        #expect(FoldersModel.needsAttention(Self.copy("1", removals: 2)))
        #expect(FoldersModel.needsAttention(Self.copy("1", problems: [FolderProblem(code: .paused, count: 1)])))
        #expect(!FoldersModel.needsAttention(Self.copy("1", downloads: 4)))
    }
}

/// The working copy's folder calls, scripted: each folder is held at a version, a change based on another version is a
/// conflict, as the server answers one to the same setting, and every change and stop is counted.
nonisolated final class FakeFolderCalls: FolderCalls {
    struct State {
        var folders: [String: FolderSettingsReading] = [:]
        var changes: [(id: String, change: FolderSettingChange, baseVersion: Int64)] = []
        var stops: [String] = []
    }

    let state = Mutex(State())

    init(_ folders: FolderSettingsReading...) {
        state.withLock { $0.folders = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) }) }
    }

    static func folder(_ id: String, _ title: String, types: [String] = [], ignore: [String] = [], version: Int64 = 1) -> FolderSettingsReading {
        FolderSettingsReading(
            id: id, version: version, isStopped: false, title: title, types: types, tier: nil, isNarrowed: false, newFileType: types.first,
            include: [], ignore: ignore, removalThreshold: RemovalThreshold(), additionThreshold: AdditionThreshold())
    }

    var changes: [(id: String, change: FolderSettingChange, baseVersion: Int64)] { state.withLock { $0.changes } }
    var stops: [String] { state.withLock { $0.stops } }

    /// Changes a folder as another device would, taking it to the next version.
    func changeElsewhere(_ id: String, _ change: FolderSettingChange) {
        state.withLock { state in
            guard let folder = state.folders[id] else { return }
            state.folders[id] = Self.applying(change, to: folder)
        }
    }

    func settings(of id: String) async throws(OwnerFailure) -> FolderSettingsReading {
        try state.withLock { state throws(OwnerFailure) in
            guard let folder = state.folders[id] else { throw .notFound }
            return folder
        }
    }

    func change(_ id: String, _ change: FolderSettingChange, baseVersion: Int64) async throws(OwnerFailure) -> FolderSettingsReading {
        try state.withLock { state throws(OwnerFailure) in
            state.changes.append((id, change, baseVersion))
            guard let folder = state.folders[id], !folder.isStopped else { throw .notFound }
            guard folder.version == baseVersion else { throw .conflict }
            let changed = Self.applying(change, to: folder)
            state.folders[id] = changed
            return changed
        }
    }

    func release() async {}

    func stopSyncing(_ id: String) async throws(OwnerFailure) {
        try state.withLock { state throws(OwnerFailure) in
            guard var folder = state.folders[id] else { throw .notFound }
            state.stops.append(id)
            folder.isStopped = true
            state.folders[id] = folder
        }
    }

    private static func applying(_ change: FolderSettingChange, to folder: FolderSettingsReading) -> FolderSettingsReading {
        var changed = FolderSettingsReading(
            id: folder.id, version: folder.version + 1, isStopped: folder.isStopped, title: folder.title, types: folder.types, tier: folder.tier,
            isNarrowed: folder.isNarrowed, newFileType: folder.newFileType, include: folder.include, ignore: folder.ignore,
            removalThreshold: folder.removalThreshold, additionThreshold: folder.additionThreshold)
        switch change {
        case .title(let title): changed.title = title
        case .include(let patterns): changed.include = patterns
        case .ignore(let patterns): changed.ignore = patterns
        case .removalThreshold(let threshold): changed.removalThreshold = threshold
        case .additionThreshold(let threshold): changed.additionThreshold = threshold
        }
        return changed
    }
}
