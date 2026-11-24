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

    private func model(_ bench: OwnerBench, folders: [(OwnerFolder, FolderReport)]) -> FoldersModel {
        bench.calls.state.withLock { state in
            state.folders = folders.map(\.0)
            state.reports = Dictionary(uniqueKeysWithValues: folders.map { ($0.0.id, $0.1) })
        }
        return FoldersModel(context: bench.context)
    }

    @Test func aRefusedListNamesThePermissionAndReadsTheGrantsAgain() async {
        let bench = OwnerBench()
        bench.calls.fail("folders", with: .notPermitted(nil))
        let model = FoldersModel(context: bench.context)
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
