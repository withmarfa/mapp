import Foundation
import Testing
@testable import MAPP

/// What the line under the instance's name says: state in, words out. The clock is given, so each wording is exact.
struct SyncFootLineTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let english = Locale(identifier: "en_US")

    private func line(
        _ state: MarfaConnectionState = .online, waiting: Int = 0, oldest: TimeInterval? = nil, phase: SyncReport.Phase = .current,
        problems: [SyncProblemEntry] = [], synced: TimeInterval? = 120
    ) -> SyncFootLine? {
        let report = SyncReport(
            phase: phase, waiting: waiting, oldestWaiting: oldest.map { now - $0 }, problems: problems, queueRead: true)
        return SyncFootLine(state: state, report: report, lastSynced: synced.map { now - $0 }, now: now, locale: english)
    }

    private func problem() -> SyncProblemEntry {
        SyncProblemEntry(
            id: .write("w"), itemID: nil, kind: .refused, change: .edit, reason: nil, content: SyncContent(),
            actions: MarfaProblems.actions(for: .refused))
    }

    // MARK: Time

    @Test func theTimeIsToTheWholeUnitAndChangesWhenTheUnitTurns() {
        let cases: [(TimeInterval, String?)] = [
            (0, nil), (59, nil), (60, "1 minute ago"), (119, "1 minute ago"), (120, "2 minutes ago"),
            (3599, "59 minutes ago"), (3600, "1 hour ago"), (3 * 3600 + 1800, "3 hours ago"),
            (86399, "23 hours ago"), (86400, "1 day ago"), (3 * 86400, "3 days ago"),
        ]
        for (elapsed, words) in cases {
            #expect(SyncFootLine.age(of: now - elapsed, now: now, locale: english) == words, "\(elapsed) s")
        }
    }

    @Test func aDateAheadOfTheClockReadsAsJustNow() {
        #expect(SyncFootLine.updated(since: now + 90, now: now, locale: english) == "Updated just now")
    }

    @Test func theTimeIsInThePersonsLanguage() {
        let german = Locale(identifier: "de_DE")
        #expect(SyncFootLine.age(of: now - 300, now: now, locale: german) == "vor 5 Minuten")
    }

    // MARK: States

    @Test func nothingIsSaidWithNoLibrary() {
        #expect(line(.disconnected) == nil)
    }

    @Test func aLibraryInStepSaysWhenItWasUpdated() throws {
        let line = try #require(line(synced: 120))
        #expect(line.kind == .updated)
        #expect(line.text == "Updated 2 minutes ago")
        #expect(!line.showsSpinner)
        #expect(self.line(synced: 10)?.text == "Updated just now")
    }

    @Test func aLibraryNotYetSyncedHasNothingToSayOnceItIsNotSyncing() {
        #expect(line(.online, synced: nil) == nil)
    }

    @Test func aPullUnderWaySaysSyncingWithASpinner() throws {
        for phase in [SyncReport.Phase.updating, .catchingUp] {
            let line = try #require(line(phase: phase))
            #expect(line.kind == .syncing)
            #expect(line.text == "Syncing…")
            #expect(line.showsSpinner)
        }
    }

    @Test func aCopyNotYetHeardFromTheServerSaysSyncing() throws {
        #expect(try #require(line(.connecting, synced: 3 * 3600)).kind == .syncing)
        #expect(try #require(line(.connecting, synced: nil)).kind == .syncing)
    }

    @Test func changesStillWaitingOnlineSayTheyAreWaitingToSend() throws {
        let line = try #require(line(waiting: 3, oldest: SyncStatus.sendingDelay))
        #expect(line.kind == .waiting)
        #expect(line.text == "3 changes waiting to send")
        // One made moments ago goes at once and is not worth a line.
        #expect(self.line(waiting: 1, oldest: 1)?.kind == .updated)
    }

    @Test func offlineSaysWhenTheCopyLastSynced() throws {
        let line = try #require(line(.offline(reason: nil), synced: 3 * 3600))
        #expect(line.kind == .offline)
        #expect(line.text == "Offline, updated 3 hours ago")
        #expect(self.line(.offline(reason: nil), synced: 5)?.text == "Offline, updated just now")
        #expect(self.line(.offline(reason: nil), synced: nil)?.text == "Offline")
    }

    @Test func offlineWithChangesWaitingSaysSoInsteadOfTheTime() throws {
        let line = try #require(line(.offline(reason: "network"), waiting: 3, oldest: 600, synced: 3600))
        #expect(line.text == "Offline, 3 changes waiting")
    }

    @Test func aWriteTheServerRefusedNeedsAttentionWhateverElseIsTrue() throws {
        let line = try #require(line(problems: [problem(), problem()]))
        #expect(line.kind == .needsAttention)
        #expect(line.text == "2 changes need attention")
        #expect(line.help == Words.needAttention(2))
    }

    @Test func aRefusedKeyOrAnUnusableCopyCouldNotSyncAndSaysWhyInTheTooltip() throws {
        let refused = try #require(line(.keyRefused))
        #expect(refused.kind == .failed)
        #expect(refused.text == "Couldn’t sync")
        #expect(refused.help?.contains("key") == true)

        let unusable = try #require(line(.unavailable(message: "The store is damaged.")))
        #expect(unusable.text == "Couldn’t sync")
        #expect(unusable.help == "The store is damaged.")

        for state in [MarfaConnectionState.otherVersion(unsent: 2), .inUse] {
            let line = try #require(line(state))
            #expect(line.kind == .failed)
            #expect(line.help?.isEmpty == false)
        }
    }
}
