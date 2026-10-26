import Foundation
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

    @Test func nothingIsSaidWhileDisconnected() {
        let status = SyncStatus(state: .disconnected, report: report(waiting: 3, oldest: 99, problems: [entry()]), now: now)
        #expect(status.notes.isEmpty)
        #expect(status.primary == nil)
    }

    @Test func nothingIsSaidWhileEverythingIsInStep() {
        for state in [MarfaHost.State.online, .connecting] {
            #expect(SyncStatus(state: state, report: report(), now: now).notes.isEmpty)
        }
    }

    @Test func aChangeSentWithinMomentsIsNotWorthALine() {
        let status = SyncStatus(state: .online, report: report(waiting: 1, oldest: 1), now: now)
        #expect(status.notes.isEmpty)
    }

    @Test func aChangeStillWaitingOnlineSaysItIsBeingSent() throws {
        let status = SyncStatus(state: .online, report: report(waiting: 3, oldest: SyncStatus.sendingDelay), now: now)
        let note = try #require(status.primary)
        #expect(note.kind == .sending)
        #expect(note.title == "Sending 3 changes")
        #expect(!note.isWarning)
    }

    @Test func offlineKeepsTheChangesAndSaysTheyWillGo() throws {
        let none = try #require(SyncStatus(state: .offline(reason: "network: refused"), report: report(), now: now).primary)
        #expect(none.kind == .offline)
        #expect(none.title == "Offline")
        #expect(!none.detail.contains("network"), "the reason is the package's, not the person's")

        let some = try #require(SyncStatus(state: .offline(reason: nil), report: report(waiting: 1, oldest: 2), now: now).primary)
        #expect(some.line == "Offline, 1 change waiting")
    }

    @Test func catchingUpAfterReconnectingIsSaid() throws {
        let note = try #require(SyncStatus(state: .online, report: report(phase: .catchingUp), now: now).primary)
        #expect(note.kind == .catchingUp)
        #expect(note.title == "Catching up")
    }

    @Test func aRefusedKeyPointsToSettingsAndSaysWhatWaits() throws {
        let status = SyncStatus(state: .keyRefused, report: report(waiting: 2, oldest: 60), now: now)
        let note = try #require(status.primary)
        #expect(note.kind == .keyRefused)
        #expect(note.title == "Key refused")
        #expect(note.detail.contains("Settings") && note.detail.contains("2 changes"))
        #expect(note.isWarning)
        #expect(note.line == "Key refused, 2 changes waiting")
        #expect(!status.notes.contains { $0.kind == .sending }, "the server is not being asked, so nothing is being sent")
    }

    @Test func aLibraryThatCannotBeOpenedPointsToSettings() throws {
        let status = SyncStatus(state: .unavailable(message: "The store is damaged."), report: report(), now: now)
        #expect(status.primary?.kind == .unavailable)
    }

    @Test func changesThatNeedThePersonCountedWithAnyOtherNote() throws {
        let status = SyncStatus(
            state: .offline(reason: nil), report: report(waiting: 1, oldest: 2, problems: [entry(), entry(.dead)]), now: now)
        #expect(status.notes.map(\.kind) == [.needsAttention, .offline])
        #expect(status.primary?.title == "Needs attention")
        #expect(status.primary?.line == "2 changes need attention")
    }

    @Test func aKeyThatIsRefusedComesBeforeAnythingElse() {
        let status = SyncStatus(state: .keyRefused, report: report(problems: [entry()]), now: now)
        #expect(status.notes.map(\.kind) == [.keyRefused, .needsAttention])
    }

    @Test func noWordIsJargon() {
        let all = [MarfaHost.State.online, .offline(reason: nil), .keyRefused, .unavailable(message: ""), .otherVersion(unsent: 2), .inUse].flatMap { state in
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
        #expect(wording.explanation.contains("copy it before you discard"))
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
        #expect(wording.explanation.hasPrefix("Your key doesn’t have permission for “core.task”. Ask whoever runs the server to allow it"))
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

        let key = wording(entry(.blocked(.credentialRefused)))
        #expect(key.actions.isEmpty)
        #expect(key.explanation.contains("Settings"))
    }

    /// Undo Change puts the item back as the server has it, so an edit that carried text is confirmed, as Discard is,
    /// and its text goes to the clipboard before it is withdrawn.
    @Test func undoingAnEditThatCarriedTextIsConfirmedAndCopiesTheText() {
        for kind in [SyncProblemEntry.Kind.blocked(.failingAlone), .blocked(.ancestorUnavailable), .blocked(.conflictUnresolved)] {
            let confirmation = wording(entry(kind)).confirmation(for: .withdraw)
            #expect(confirmation?.title == "Undo this change?")
            #expect(confirmation?.copiesText == true)
        }
        #expect(wording(entry(.blocked(.failingAlone), title: nil, body: nil)).confirmation(for: .withdraw) == nil)
        #expect(wording(entry(.refused)).confirmation(for: .discard)?.copiesText == false)
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
        #expect(ConnectionStatus(.keyRefused).title == "Key refused")
        #expect(ConnectionStatus(.keyRefused).isProblem)
        #expect(ConnectionStatus(.unavailable(message: "The store is damaged.")).detail?.hasSuffix("The store is damaged.") == true)
    }

    @Test func aCopyADifferentVersionMadeSaysWhatToDoWithoutTheErrorOrThePath() throws {
        let some = ConnectionStatus(.otherVersion(unsent: 3))
        #expect(some.title == "Library unavailable")
        #expect(some.isProblem)
        #expect(some.detail?.contains("3 changes") == true)
        #expect(some.detail?.contains("previous build") == true)
        #expect(Words.otherVersion(unsent: 1).contains("1 change on this Mac hasn’t reached the server."))

        // The count stays unread after the previous build sends everything, and the package never removes a copy it can’t count, so the way out is to remove the copy’s folder.
        let unknown = try #require(ConnectionStatus(.otherVersion(unsent: nil)).detail)
        #expect(unknown.contains("Keep Copy and Disconnect"), "an uncountable copy is never removed for the person, so the way out is named")

        let inUse = ConnectionStatus(.inUse)
        #expect(inUse.title == "Library unavailable")
        #expect(inUse.isProblem)

        for text in [some.detail, unknown, inUse.detail, Words.notReplaced].compactMap({ $0 }) {
            for raw in ["core", "schema", "hydrat", "queue", "drain", ".sqlite", "/"] {
                #expect(!text.localizedCaseInsensitiveContains(raw), "“\(text)” says “\(raw)”")
            }
        }
    }

    @Test(arguments: [MarfaHost.State.otherVersion(unsent: 2), .otherVersion(unsent: nil), .inUse])
    func theWindowSaysACopyThisVersionCantOpenIsUnavailable(state: MarfaHost.State) {
        let status = SyncStatus(state: state, report: SyncReport(), now: Date())
        #expect(status.primary?.kind == .unavailable)
    }

    @Test func theReasonOfBeingOfflineIsNotShown() {
        let status = ConnectionStatus(.offline(reason: "network: connection refused (os error 61)"))
        #expect(status.detail?.contains("os error") == false)
        #expect(!status.isProblem)
    }
}
