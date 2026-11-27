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
    private func model(
        _ bench: OwnerBench, folders: [(OwnerFolder, FolderReport)], calls: FakeFolderCalls? = nil
    ) -> FoldersModel {
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

    /// One folder, its page open.
    private func opened(_ bench: OwnerBench, _ calls: FakeFolderCalls) async -> FoldersModel {
        let model = model(bench, folders: [(OwnerFolder(id: "a", title: "Studio Notes"), FolderReport(copies: []))], calls: calls)
        await model.load()
        model.open("a")
        return model
    }

    @Test func aReadWhileALimitIsTypedKeepsItAndItIsSentOnTheVersionSeen() async throws {
        let bench = OwnerBench()
        let calls = FakeFolderCalls(FakeFolderCalls.folder("a", "Studio Notes"))
        let model = await opened(bench, calls)
        #expect(model.removalDraft == "10")

        model.removalDraft = "5"
        calls.changeElsewhere("a", .removalThreshold(RemovalThreshold(files: 8)))
        await model.loadFolder("a")
        #expect(model.settings["a"]?.version == 2)
        #expect(model.removalDraft == "5")

        await model.commitLimit(.removalLimit)
        #expect(calls.changes.map(\.baseVersion) == [1])
        #expect(try await calls.settings(of: "a").removalThreshold.files == 8)
        #expect(model.removalDraft == "5")
        #expect(model.errors[.removalLimit]?.contains("8") == true)

        // Leaving the field sends nothing more; only Return sends the owner's value, on the version now read.
        await model.commitLimit(.removalLimit, explicitly: false)
        #expect(calls.changes.count == 1)
        await model.commitLimit(.removalLimit)
        #expect(calls.changes.last?.baseVersion == 2)
        #expect(try await calls.settings(of: "a").removalThreshold.files == 5)
        #expect(model.errors[.removalLimit] == nil)
    }

    @Test func aReadLeavesAnUntouchedLimitShowingWhatItReads() async {
        let bench = OwnerBench()
        let calls = FakeFolderCalls(FakeFolderCalls.folder("a", "Studio Notes"))
        let model = await opened(bench, calls)
        calls.changeElsewhere("a", .additionThreshold(AdditionThreshold(files: 30)))
        await model.loadFolder("a")
        #expect(model.additionDraft == "30")
        await model.commitLimit(.additionLimit, explicitly: false)
        #expect(calls.changes.isEmpty)
    }

    @Test func aRenameIsSentOnTheVersionSeenWhenItBegan() async throws {
        let bench = OwnerBench()
        let calls = FakeFolderCalls(FakeFolderCalls.folder("a", "Studio Notes"))
        let model = await opened(bench, calls)

        model.beginRename()
        model.renameDraft = "Mine"
        calls.changeElsewhere("a", .title("Theirs"))
        await model.loadFolder("a")
        await model.rename()
        #expect(calls.changes.map(\.baseVersion) == [1])
        #expect(try await calls.settings(of: "a").title == "Theirs")
        #expect(model.isRenaming)
        #expect(model.renameDraft == "Mine")
        #expect(model.errors[.title]?.contains("Theirs") == true)

        await model.rename()
        #expect(calls.changes.last?.baseVersion == 2)
        #expect(try await calls.settings(of: "a").title == "Mine")
        #expect(!model.isRenaming)
    }

    @Test func aPatternIsSentExactlyAsTyped() async throws {
        let bench = OwnerBench()
        let calls = FakeFolderCalls(FakeFolderCalls.folder("a", "Studio Notes"))
        let model = await opened(bench, calls)

        model.beginAdding(to: .ignore)
        model.ignoreDraft = ""
        await model.addPattern(to: .ignore)
        #expect(calls.changes.isEmpty)
        #expect(model.ignoreDraft == nil)

        model.beginAdding(to: .ignore)
        model.ignoreDraft = " draft\\ "
        await model.addPattern(to: .ignore)
        #expect(try await calls.settings(of: "a").ignore == [" draft\\ "])
        #expect(model.ignoreDraft == nil)
    }

    @Test func removingAPatternRemovesThatEntryAlone() async throws {
        let bench = OwnerBench()
        let calls = FakeFolderCalls(FakeFolderCalls.folder("a", "Studio Notes", ignore: ["*.tmp", "build", "*.tmp"]))
        let model = await opened(bench, calls)
        let shown = try #require(model.settings["a"])

        await model.removePattern(at: 2, from: .ignore, in: shown)
        #expect(try await calls.settings(of: "a").ignore == ["*.tmp", "build"])
    }

    @Test func aLooserLimitIsSentOnlyOnceTheOwnerAgrees() async throws {
        let bench = OwnerBench()
        let calls = FakeFolderCalls(FakeFolderCalls.folder("a", "Studio Notes"))
        let model = await opened(bench, calls)

        model.removalDraft = "40"
        await model.commitLimit(.removalLimit, explicitly: false)
        let asked = try #require(model.question)
        #expect(asked.kind == .loosen(.removalLimit, files: 40, base: try #require(model.settings["a"])))
        #expect(asked.message.contains("10") && asked.message.contains("40"))
        await model.commitLimit(.removalLimit)
        #expect(calls.changes.isEmpty)

        model.cancelQuestion()
        #expect(model.question == nil)
        #expect(model.removalDraft == "10")
        #expect(calls.changes.isEmpty)

        model.additionDraft = "200"
        await model.commitLimit(.additionLimit)
        await model.confirm(try #require(model.question))
        #expect(try await calls.settings(of: "a").additionThreshold.files == 200)

        // A tighter limit is sent at once.
        model.removalDraft = "4"
        await model.commitLimit(.removalLimit, explicitly: false)
        #expect(model.question == nil)
        #expect(try await calls.settings(of: "a").removalThreshold.files == 4)
    }

    @Test func raiseLimitSendsWhatItAskedOnTheVersionSeenWhateverIsReadMeanwhile() async throws {
        let bench = OwnerBench()
        let calls = FakeFolderCalls(FakeFolderCalls.folder("a", "Studio Notes"))
        let model = await opened(bench, calls)

        model.removalDraft = "40"
        await model.commitLimit(.removalLimit)
        let asked = try #require(model.question)
        calls.changeElsewhere("a", .removalThreshold(RemovalThreshold(files: 8)))
        await model.loadFolder("a")
        await model.commitLimit(.removalLimit, explicitly: false)
        #expect(model.question == asked)

        await model.confirm(asked)
        #expect(calls.changes.map(\.baseVersion) == [1])
        #expect(try await calls.settings(of: "a").removalThreshold.files == 8)
        #expect(model.removalDraft == "40")
        #expect(model.errors[.removalLimit]?.contains("8") == true)
    }

    @Test func aConflictTheCopyCannotShowYetSendsNothingUntilItCatchesUp() async throws {
        let bench = OwnerBench()
        let calls = FakeFolderCalls(FakeFolderCalls.folder("a", "Studio Notes"))
        let model = await opened(bench, calls)

        model.removalDraft = "5"
        calls.changeElsewhere("a", .removalThreshold(RemovalThreshold(files: 8)), copyLags: true)
        await model.commitLimit(.removalLimit)
        #expect(calls.changes.count == 1)
        #expect(model.errors[.removalLimit] == FoldersModel.catchingUpLine)
        #expect(model.removalDraft == "5")

        await model.commitLimit(.removalLimit)
        #expect(calls.changes.count == 1)

        calls.catchUp("a")
        await model.commitLimit(.removalLimit)
        #expect(calls.changes.count == 1)
        #expect(model.errors[.removalLimit]?.contains("8") == true)
        #expect(model.removalDraft == "5")

        await model.commitLimit(.removalLimit)
        #expect(calls.changes.last?.baseVersion == 2)
        #expect(try await calls.settings(of: "a").removalThreshold.files == 5)
    }

    @Test func aLimitOutsideTheContractsRangeIsRefusedBeforeItIsSent() async {
        let bench = OwnerBench()
        let calls = FakeFolderCalls(FakeFolderCalls.folder("a", "Studio Notes"))
        let model = await opened(bench, calls)

        for typed in ["9007199254740992", "-1", "2.5", ""] {
            model.removalDraft = typed
            await model.commitLimit(.removalLimit)
            #expect(model.errors[.removalLimit] == FoldersModel.rangeLine)
            #expect(model.removalDraft == typed)
        }
        #expect(model.question == nil)
        #expect(calls.changes.isEmpty)
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

    @Test func anEmptyFolderListStaysEmpty() async {
        let bench = OwnerBench()
        let model = FoldersModel(context: bench.context, folderCalls: FakeFolderCalls())
        await model.load()
        #expect(model.folders.isEmpty)
        #expect(model.hasLoaded)
        #expect(model.failure == nil)
    }

    @Test func aServerThatDoesNotAnswerLeavesFoldersUnread() async {
        let bench = OwnerBench()
        bench.calls.fail("folders", with: .unreachable)
        let model = FoldersModel(context: bench.context, folderCalls: FakeFolderCalls())
        await model.load()
        #expect(model.failure == .unreachable)
        #expect(model.folders.isEmpty)
    }

    @Test func aPausedCopyReadsPausedAndEveryFolderStaysInOneList() async {
        var here = Self.copy("c1", "Marfa for Mac", problems: [FolderProblem(code: .paused, count: 1)])
        here.signInID = "this"
        var away = Self.copy("c2", "marfa on Mac mini")
        away.signInID = "other"
        let bench = OwnerBench()
        let model = model(
            bench,
            folders: [
                (OwnerFolder(id: "a", title: "Studio Notes"), FolderReport(copies: [here])),
                (OwnerFolder(id: "b", title: "Client Drawings"), FolderReport(copies: [away])),
            ])
        await model.load()
        #expect(FoldersModel.condition(of: here) == FoldersModel.Condition(title: "Paused", tone: .quiet))
        #expect(model.folders.map(\.id) == ["a", "b"])
        #expect(model.condition(of: model.folders[0]) == FoldersModel.Condition(title: "Paused", tone: .quiet))
        #expect(model.condition(of: model.folders[1]) == FoldersModel.Condition(title: "Up to date", tone: .ok))
    }
}

/// The working copy's folder calls, scripted: each folder is held at a version, a change based on another version is a
/// conflict, as the server answers one to the same setting, and every change and stop is counted. A copy that lags reads
/// a folder as it was until it catches up.
nonisolated final class FakeFolderCalls: FolderCalls {
    struct State {
        var folders: [String: FolderSettingsReading] = [:]
        var changes: [(id: String, change: FolderSettingChange, baseVersion: Int64)] = []
        var stops: [String] = []
        /// What the copy reads for a folder changed elsewhere that it has not caught up with.
        var lagging: [String: FolderSettingsReading] = [:]
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
    func changeElsewhere(_ id: String, _ change: FolderSettingChange, copyLags: Bool = false) {
        state.withLock { state in
            guard let folder = state.folders[id] else { return }
            if copyLags, state.lagging[id] == nil { state.lagging[id] = folder }
            state.folders[id] = Self.applying(change, to: folder)
        }
    }

    func catchUp(_ id: String) {
        state.withLock { _ = $0.lagging.removeValue(forKey: id) }
    }

    func settings(of id: String) async throws(OwnerFailure) -> FolderSettingsReading {
        try state.withLock { state throws(OwnerFailure) in
            guard let folder = state.lagging[id] ?? state.folders[id] else { throw .notFound }
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
