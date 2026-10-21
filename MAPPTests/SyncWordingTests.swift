import Foundation
import Marfa
import Testing
@testable import MAPP

/// What the window says of the connection and of each change that needs the person: state in, words out.
struct SyncStatusTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func report(
        waiting: Int = 0, oldest: TimeInterval? = nil, phase: SyncReport.Phase = .current, problems: [SyncProblemEntry] = []
    ) -> SyncReport {
        SyncReport(
            phase: phase, waiting: waiting, oldestWaiting: oldest.map { now - $0 }, problems: problems, queueRead: true)
    }

    private func entry(_ kind: SyncProblemEntry.Kind = .refused) -> SyncProblemEntry {
        SyncProblemEntry(
            id: .write("w"), itemID: nil, kind: kind, change: .edit, reason: nil, content: SyncContent(),
            actions: MarfaProblems.actions(for: kind))
    }

    @Test func nothingIsSaidWhileTheAppReadsAFolder() {
        let status = SyncStatus(state: .disconnected, report: report(waiting: 3, oldest: 99, problems: [entry()]), now: now)
        #expect(status.isQuiet)
        #expect(status.primary == nil)
    }

    @Test func nothingIsSaidWhileEverythingIsInStep() {
        for state in [MarfaHost.State.online, .connecting] {
            #expect(SyncStatus(state: state, report: report(), now: now).isQuiet)
        }
    }

    @Test func aChangeSentWithinMomentsIsNotWorthALine() {
        let status = SyncStatus(state: .online, report: report(waiting: 1, oldest: 1), now: now)
        #expect(status.isQuiet)
    }

    @Test func aChangeStillWaitingOnlineSaysItIsBeingSent() throws {
        let status = SyncStatus(state: .online, report: report(waiting: 3, oldest: SyncStatus.sendingDelay), now: now)
        let note = try #require(status.primary)
        #expect(note.kind == .sending)
        #expect(note.title == "Sending 3 changes")
        #expect(note.detail == "3 changes are waiting to be sent.")
        #expect(!note.isWarning)
    }

    @Test func offlineKeepsTheChangesAndSaysTheyWillGo() throws {
        let none = try #require(SyncStatus(state: .offline(reason: "network: refused"), report: report(), now: now).primary)
        #expect(none.kind == .offline)
        #expect(none.title == "Offline")
        #expect(none.detail == "Your changes are kept on this Mac and sent when you’re back online.")
        #expect(!none.detail.contains("network"), "the reason is the package's, not the person's")

        let some = try #require(SyncStatus(state: .offline(reason: nil), report: report(waiting: 1, oldest: 2), now: now).primary)
        #expect(some.detail == "1 change will be sent when you’re back online.")
    }

    @Test func catchingUpAfterReconnectingIsSaid() throws {
        let note = try #require(SyncStatus(state: .online, report: report(phase: .catchingUp), now: now).primary)
        #expect(note.kind == .catchingUp)
        #expect(note.title == "Catching up")
    }

    @Test func aSignOutPointsToSettingsAndSaysWhatWaits() throws {
        let status = SyncStatus(state: .signedOut, report: report(waiting: 2, oldest: 60), now: now)
        let note = try #require(status.primary)
        #expect(note.kind == .signedOut)
        #expect(note.title == "Signed out")
        #expect(note.detail == "MAPP needs your approval again. Sign in again in Settings. 2 changes are waiting to be sent.")
        #expect(note.isWarning)
        #expect(status.pointsToSettings)
        #expect(!status.notes.contains { $0.kind == .sending }, "the server is not being asked, so nothing is being sent")
    }

    @Test func aLibraryThatCannotBeOpenedPointsToSettings() throws {
        let status = SyncStatus(state: .unavailable(.damaged), report: report(), now: now)
        #expect(status.primary?.kind == .unavailable)
        #expect(status.pointsToSettings)
    }

    @Test func changesThatNeedThePersonCountedWithAnyOtherNote() throws {
        let status = SyncStatus(
            state: .offline(reason: nil), report: report(waiting: 1, oldest: 2, problems: [entry(), entry(.dead)]), now: now)
        #expect(status.notes.map(\.kind) == [.needsAttention, .offline])
        #expect(status.primary?.title == "Needs attention")
        #expect(status.primary?.detail == "2 changes need your attention.")
        #expect(!status.pointsToSettings)
    }

    @Test func aSignOutComesBeforeAnythingElse() {
        let status = SyncStatus(state: .signedOut, report: report(problems: [entry()]), now: now)
        #expect(status.notes.map(\.kind) == [.signedOut, .needsAttention])
    }

    @Test func countsAgreeWithTheirNouns() {
        #expect(Words.waiting(1) == "1 change is waiting to be sent.")
        #expect(Words.waiting(5) == "5 changes are waiting to be sent.")
        #expect(Words.sending(1) == "Sending 1 change")
        #expect(Words.needAttention(1) == "1 change needs your attention.")
        #expect(Words.notSent(1) == "1 change on this Mac hasn’t reached the server.")
        #expect(Words.notSent(2) == "2 changes on this Mac haven’t reached the server.")
        #expect(Words.moreNotShown(1) == "And 1 more change whose text can’t be shown.")
        #expect(Words.sentWhenOnline(2) == "2 changes will be sent when you’re back online.")
        #expect(Words.changes(1) == "1 change")
        #expect(Words.changes(4) == "4 changes")
    }

    @Test func noWordIsJargon() {
        let all = [MarfaHost.State.online, .offline(reason: nil), .signedOut, .unavailable(.other)].flatMap { state in
            SyncStatus(state: state, report: report(waiting: 2, oldest: 60, phase: .catchingUp, problems: [entry()]), now: now)
                .notes.flatMap { [$0.title, $0.detail] }
        }
        for text in all {
            for word in ["sync", "write", "queue", "drain", "verdict"] {
                #expect(!text.localizedCaseInsensitiveContains(word), "“\(text)” says “\(word)”")
            }
        }
    }
}

struct ProblemWordingTests {
    private func entry(
        _ kind: SyncProblemEntry.Kind, change: SyncProblemEntry.Change = .edit, reason: SyncProblem? = nil,
        title: String? = "Plan the launch", body: String? = "Line one", item: String? = "item"
    ) -> SyncProblemEntry {
        SyncProblemEntry(
            id: .write("w"), itemID: item.map { ItemID($0) }, kind: kind, change: change, reason: reason,
            content: SyncContent(title: title, body: body), actions: MarfaProblems.actions(for: kind))
    }

    private func wording(_ entry: SyncProblemEntry, titles: [String: String] = [:]) -> ProblemWording {
        ProblemWording(entry) { titles[$0.rawValue] }
    }

    @Test func aRefusalNamesTheItemAndOffersOnlyDiscardAndCopy() {
        let wording = wording(entry(.refused, reason: SyncProblem(code: "validation_error", message: "Some values are not allowed.")))
        #expect(wording.headline == "Changes to “Plan the launch” weren’t sent")
        #expect(wording.explanation.hasPrefix("The server refused it: Some values are not allowed."))
        #expect(wording.explanation.hasSuffix("To keep what you wrote, copy it before you discard this change."))
        #expect(wording.actions.map(\.action) == [.discard])
        #expect(wording.actions.first?.title == "Discard")
        #expect(wording.canCopyText)
    }

    @Test func aRefusedCreateSaysTheItemWasNotCreated() {
        #expect(wording(entry(.refused, change: .create)).headline == "“Plan the launch” wasn’t created")
        #expect(wording(entry(.refused, change: .create, title: nil, item: nil)).headline == "A new item wasn’t created")
    }

    @Test func anItemThatCarriedNoTitleIsNamedFromTheLibrary() {
        let wording = wording(entry(.refused, title: nil), titles: ["item": "Quarterly plan"])
        #expect(wording.headline == "Changes to “Quarterly plan” weren’t sent")
    }

    @Test func aMissingPermissionSaysWhoToAsk() {
        let grant = SyncProblem.Grant(kind: .type, name: "core.task", level: .write)
        let wording = wording(entry(.refused, reason: SyncProblem(code: "forbidden", grant: grant)))
        #expect(wording.explanation.hasPrefix("MAPP doesn’t have permission for “core.task”. Ask whoever runs the server to allow it"))
    }

    @Test func anItemInTheServersBinSaysToRestoreItFirst() {
        let wording = wording(entry(.refused, reason: SyncProblem(code: "gone", isTrashed: true)))
        #expect(wording.explanation.hasPrefix("The item is in Recently Deleted on the server"))
    }

    @Test func eachFieldTheServerRefusedIsGivenItsReason() {
        let reason = SyncProblem(code: "validation_error", fields: ["status": "not one of open, closed", "due_at": "not a date"])
        #expect(wording(entry(.refused, reason: reason)).details == ["Due at: not a date", "Status: not one of open, closed"])
    }

    @Test func aRefusalWithNoReasonStillSaysSomething() {
        let wording = wording(entry(.refused, title: nil, body: nil))
        #expect(wording.explanation == "The server refused it.")
        #expect(!wording.canCopyText, "nothing was written, so there is nothing to copy")
    }

    @Test func aWriteHeldForTheContractsReasonsOffersOnlyWhatTheContractAllows() {
        let spent = wording(entry(.blocked(.keySpent)))
        #expect(spent.actions.map(\.action) == [.tryAgain])
        #expect(spent.actions.first?.title == "Try Again")

        let missing = wording(entry(.blocked(.ancestorUnavailable)))
        #expect(missing.actions.map(\.action) == [.withdraw])
        #expect(missing.actions.first?.title == "Undo Change")
        #expect(missing.actions.first?.needsServer == true)

        let conflict = wording(entry(.blocked(.conflictUnresolved)))
        #expect(conflict.actions.map(\.action) == [.withdraw])

        let alone = wording(entry(.blocked(.failingAlone)))
        #expect(alone.actions.map(\.title) == ["Try Again", "Undo Change"])
        #expect(alone.actions.map(\.action) == [.tryAgain, .withdraw])
        #expect(alone.headline == "A change to “Plan the launch” is on hold")
        #expect(alone.explanation == "This change couldn’t be sent on its own, although the server took other changes. Try again to send it, or undo it to put the item back as the server has it.")

        let signedOut = wording(entry(.blocked(.credentialRefused)))
        #expect(signedOut.actions.isEmpty)
        #expect(signedOut.explanation == "It will be sent once you sign in again in Settings.")
    }

    @Test func aWriteThatDiedCanBeTriedAgainAndNothingElse() {
        let wording = wording(entry(.dead))
        #expect(wording.actions.map(\.action) == [.tryAgain])
        #expect(wording.headline == "A change to “Plan the launch” is on hold")
    }

    @Test func aConflictedCopyIsShownBesideItsOriginalWithAnExplanation() {
        let kind = SyncProblemEntry.Kind.conflicted(sibling: ItemID("copy"), original: ItemID("original"))
        let wording = wording(entry(kind, item: "copy"), titles: ["original": "Trip to Lisbon"])
        #expect(wording.headline == "Your changes to “Trip to Lisbon” were saved as a copy")
        #expect(wording.explanation == "The item was changed somewhere else while you were editing it. The server kept that version, and yours is the copy.")
        #expect(wording.original == ItemID("original"))
        #expect(wording.copy == ItemID("copy"))
        #expect(wording.actions.map(\.title) == ["Keep Copy", "Discard Copy"])
        #expect(wording.actions.map(\.action) == [.keep, .discard])
    }

    @Test func everyActionOfferedIsOneTheContractAllows() {
        let kinds: [SyncProblemEntry.Kind] = [
            .refused, .blocked(.credentialRefused), .blocked(.keySpent), .blocked(.ancestorUnavailable),
            .blocked(.conflictUnresolved), .blocked(.failingAlone), .dead, .conflicted(sibling: ItemID("c"), original: nil)
        ]
        for kind in kinds {
            #expect(wording(entry(kind)).actions.map(\.action) == MarfaProblems.actions(for: kind))
        }
    }

    @Test func noWordIsJargon() {
        let kinds: [SyncProblemEntry.Kind] = [
            .refused, .blocked(.credentialRefused), .blocked(.keySpent), .blocked(.ancestorUnavailable),
            .blocked(.conflictUnresolved), .blocked(.failingAlone), .dead, .conflicted(sibling: ItemID("c"), original: nil)
        ]
        for kind in kinds {
            let wording = wording(entry(kind))
            let text = ([wording.headline, wording.explanation] + wording.actions.map(\.title)).joined(separator: " ")
            for word in ["sync", "write", "queue", "idempotency", "verdict", "ancestor", "credential"] {
                #expect(!text.localizedCaseInsensitiveContains(word), "“\(text)” says “\(word)”")
            }
        }
    }
}

struct ConnectionStatusTests {
    @Test func eachStateIsToldInWords() {
        #expect(ConnectionStatus(.disconnected).title == "Not connected")
        #expect(ConnectionStatus(.connecting).title == "Connecting…")
        #expect(ConnectionStatus(.online).title == "Connected")
        #expect(ConnectionStatus(.online).detail == nil)
        #expect(ConnectionStatus(.offline(reason: "network: refused")).title == "Offline")
        #expect(ConnectionStatus(.signedOut).title == "Signed out")
        #expect(ConnectionStatus(.signedOut).detail?.contains("approve MAPP") == true)
        #expect(ConnectionStatus(.signedOut).isProblem)
        #expect(ConnectionStatus(.unavailable(.damaged)).detail == "MAPP can’t open or follow the copy of your library on this Mac. The copy may be damaged. Disconnect, then connect to the server again.")
        #expect(ConnectionStatus(.unavailable(.keychain)).isProblem)
    }

    /// Each way a copy can fail is told in the app's words, as what happened and what to do.
    @Test(arguments: [
        CopyFailure.openElsewhere, .storageFull, .needsUpdate, .keychain, .otherServer, .files, .damaged, .other,
    ])
    func eachWayACopyFailsIsToldInTheAppsWords(failure: CopyFailure) throws {
        let detail = try #require(ConnectionStatus(.unavailable(failure)).detail)
        #expect(detail.hasPrefix("MAPP can’t open or follow the copy of your library on this Mac. "))
        #expect(detail.hasSuffix("."))
        #expect(!failure.advice.isEmpty)
    }

    /// The package's errors reach the person only as one of the app's own failures.
    @Test func thePackagesErrorsAreReadAsTheAppsOwnFailures() {
        #expect(CopyFailure(.storageFull(message: "disk full")) == .storageFull)
        #expect(CopyFailure(.wrongSchema(path: "/x", reason: "newer", unsent: nil, message: "schema 9")) == .needsUpdate)
        #expect(CopyFailure(.contractMismatch(served: "9", expected: 1, status: 200, writeSent: false, message: "m")) == .needsUpdate)
        #expect(CopyFailure(.noKeychain(message: "m")) == .keychain)
        #expect(CopyFailure(.wrongServer(expected: "a", got: "b", message: "m")) == .otherServer)
        #expect(CopyFailure(.io(message: "EACCES")) == .files)
        #expect(CopyFailure(.store(message: "file is not a database")) == .damaged)
        #expect(CopyFailure(.server(status: 500, code: "internal", message: "m")) == .other)
    }

    @Test func theReasonOfBeingOfflineIsNotShown() {
        let status = ConnectionStatus(.offline(reason: "network: connection refused (os error 61)"))
        #expect(status.detail?.contains("os error") == false)
        #expect(!status.isProblem)
    }
}
