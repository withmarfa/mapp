import Foundation
import Testing
@testable import MarfaMac

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

    @Test func aRefusedKeyPointsToSettingsAndSaysWhatWaits() throws {
        let status = SyncStatus(state: .keyRefused, report: report(waiting: 2, oldest: 60), now: now)
        let note = try #require(status.primary)
        #expect(note.kind == .keyRefused)
        #expect(note.title == "Signed out")
        #expect(note.detail.contains("Settings") && note.detail.contains("2 changes"))
        #expect(note.isWarning)
        #expect(note.line == "Signed out, 2 changes waiting")
        #expect(!status.notices.contains { $0.kind == .sending }, "the server is not being asked, so nothing is being sent")
    }

    @Test func aLibraryThatCannotBeOpenedPointsToSettings() throws {
        let status = SyncStatus(state: .unavailable(message: "The store is damaged."), report: report(), now: now)
        #expect(status.primary?.kind == .unavailable)
    }

    @Test func aKeyThatIsRefusedComesBeforeAnythingElse() {
        let status = SyncStatus(state: .keyRefused, report: report(problems: [entry()]), now: now)
        #expect(status.notices.map(\.kind) == [.keyRefused, .needsAttention])
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

    @Test func eachFieldTheServerRefusedIsGivenItsReason() {
        let reason = SyncProblem(code: "validation_error", fields: ["status": "not one of open, closed", "due_at": "not a date"])
        var refused = entry(.refused, reason: reason)
        refused.fieldLabels = ["due_at": "Due at", "status": "Status"]
        #expect(wording(refused).details == ["Due at: not a date", "Status: not one of open, closed"])
        // A field the type no longer holds is named by its key.
        refused.fieldLabels = ["status": "Status"]
        #expect(wording(refused).details == ["due_at: not a date", "Status: not one of open, closed"])
    }

    @Test func aChangeFromACopyReadInPartIsHeldUntilThePersonSays() {
        let wording = wording(entry(.blocked(.recordUnread)))
        #expect(wording.headline == "A change to “Plan the launch” is on hold")
        #expect(wording.explanation.hasPrefix("This change came from a copy that the app could only partly read"))
        #expect(wording.actions.map(\.action) == [.tryAgain, .withdraw])
        #expect(wording.actions.map(\.title) == ["Try Again", "Undo Change"])
        #expect(wording.confirmation(for: .withdraw)?.copiesText == true)
    }

    @Test func aChangeThatWouldUndoARestoreIsHeldUntilThePersonSays() {
        let wording = wording(entry(.blocked(.serverRestored)))
        #expect(wording.headline == "A change to “Plan the launch” is on hold")
        #expect(wording.explanation.hasPrefix("The server was restored to an earlier point"))
        #expect(wording.actions.map(\.action) == [.tryAgain, .withdraw])
        #expect(wording.actions.map(\.title) == ["Try Again", "Undo Change"])
        #expect(wording.confirmation(for: .withdraw)?.copiesText == true)
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
            .blocked(.conflictUnresolved), .blocked(.failingAlone), .blocked(.instanceChanged), .blocked(.recordUnread), .blocked(.serverRestored), .dead,
            .conflicted(sibling: ItemID("c"), original: nil)
        ]
        for kind in kinds {
            #expect(wording(entry(kind)).actions.map(\.action) == MarfaProblems.actions(for: kind))
        }
    }
}

struct ConnectionStatusTests {
    @Test func aCopyADifferentVersionMadeSaysWhatToDoWithoutTheErrorOrThePath() throws {
        let some = ConnectionStatus(.otherVersion(unsent: 3))
        #expect(some.title == "Library unavailable")
        #expect(some.isProblem)
        #expect(some.detail?.contains("3 changes") == true)
        #expect(some.detail?.contains("previous version") == true)
        #expect(Words.otherVersion(unsent: 1).contains("1 change on this Mac hasn’t reached the server."))

        // The count stays unread after the previous version sends everything, and the package never removes a copy it can’t count, so the way out is to remove the copy’s folder.
        let unknown = try #require(ConnectionStatus(.otherVersion(unsent: nil)).detail)
        #expect(unknown.contains("Keep Copy and Disconnect"), "an uncountable copy is never removed for the person, so the way out is named")

        let inUse = ConnectionStatus(.inUse)
        #expect(inUse.title == "Library unavailable")
        #expect(inUse.isProblem)

        for text in [some.detail, unknown, inUse.detail, Words.otherServer(unsent: 2), Words.otherServer(unsent: nil), Words.signInUnreadable].compactMap({ $0 }) {
            for raw in ["core", "schema", "hydrat", "queue", "drain", ".sqlite", "/"] {
                #expect(!text.localizedCaseInsensitiveContains(raw), "“\(text)” says “\(raw)”")
            }
        }
    }
}
