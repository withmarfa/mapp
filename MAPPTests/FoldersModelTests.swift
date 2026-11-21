import Foundation
import Marfa
import Synchronization
import Testing
@testable import MAPP

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

    @Test func theFoldersAreListedWithWhereEachStands() async {
        let bench = OwnerBench()
        let model = model(bench, folders: [
            (OwnerFolder(id: "a", title: "Studio Notes"), FolderReport(copies: [Self.copy("1"), Self.copy("2", "marfa on Mac mini", downloads: 3)])),
            (OwnerFolder(id: "b", title: "Client Drawings"), FolderReport(copies: [Self.copy("3", removals: 12)])),
            (OwnerFolder(id: "c", title: "Empty"), FolderReport(copies: [])),
        ])
        await model.load()
        #expect(model.folders.map(\.title) == ["Studio Notes", "Client Drawings", "Empty"])
        #expect(model.condition(of: model.folders[0]) == .init(title: "3 to receive", tone: .quiet))
        #expect(model.condition(of: model.folders[1]) == .init(title: "12 removals wait", tone: .warning))
        #expect(model.condition(of: model.folders[2]) == .init(title: "No Copies", tone: .quiet))
        #expect(FoldersModel.copies(2) == "2 copies.")
        #expect(FoldersModel.copies(1) == "1 copy.")
    }

    @Test func aCopyWithNothingWaitingIsUpToDate() {
        #expect(FoldersModel.condition(of: Self.copy("1")) == .init(title: "Up to date", tone: .ok))
        #expect(FoldersModel.condition(of: Self.copy("1", uploads: 2)) == .init(title: "2 to send", tone: .quiet))
        #expect(FoldersModel.condition(of: Self.copy("1", uploads: 2, downloads: 3)) == .init(title: "5 waiting", tone: .quiet))
        #expect(FoldersModel.condition(of: Self.copy("1", waiting: true)) == .init(title: "Waiting to Start", tone: .quiet))
    }

    @Test func aProblemOutranksWhatIsWaiting() {
        let problem = FolderProblem(code: .heldFile, count: 8)
        #expect(FoldersModel.condition(of: Self.copy("1", downloads: 5, problems: [problem])) == .init(title: "Needs Attention", tone: .warning))
        #expect(FoldersModel.condition(of: Self.copy("1", removals: 1, problems: [problem])).title == "1 removal waits")
        #expect(FoldersModel.title(of: problem) == "8 files are held back")
        #expect(FoldersModel.title(of: FolderProblem(code: .conflict, count: 1)) == "1 conflicted copy")
    }

    @Test func everyProblemCodeTheServerStoresHasWords() {
        for code in FolderProblem.Code.allCases {
            #expect(!FoldersModel.title(of: FolderProblem(code: code, count: 2)).isEmpty)
        }
    }

    @Test func aCopyIsToldHowLongAgoItReported() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(FoldersModel.reported(ageSeconds: 1200, now: now) == "Reported 20 minutes ago.")
    }

    @Test func aRefusedListNamesThePermissionAndReadsTheGrantsAgain() async {
        let bench = OwnerBench()
        bench.calls.fail("folders", with: .notPermitted(nil))
        let model = FoldersModel(context: bench.context)
        await model.load()
        #expect(model.failure == .notPermitted(nil))
        #expect(bench.refreshed == 1)
    }

    @Test func theServerNotAnsweringShowsTheFailureNotAnEmptyList() async {
        let bench = OwnerBench()
        bench.calls.fail("folders", with: .unreachable)
        let model = FoldersModel(context: bench.context)
        await model.load()
        #expect(model.failure == .unreachable)
        #expect(model.folders.isEmpty)
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

    @Test func aFolderStoppedElsewhereLeavesTheList() async {
        let bench = OwnerBench()
        let model = model(bench, folders: [(OwnerFolder(id: "a", title: "Studio Notes"), FolderReport(copies: []))])
        await model.load()
        bench.calls.state.withLock { $0.reports = [:] }
        await model.loadReport("a")
        #expect(model.folder("a") == nil)
    }
}
