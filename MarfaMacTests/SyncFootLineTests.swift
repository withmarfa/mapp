import Foundation
import Testing
@testable import MarfaMac

/// What the line under the instance's name says: state in, words out. The clock is given, so each wording is exact.
struct SyncFootLineTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let english = Locale(identifier: "en_US")

    private func line(
        _ state: MarfaConnectionState = .online, waiting: Int = 0, oldest: TimeInterval? = nil, phase: SyncReport.Phase = .current,
        problems: [SyncProblemEntry] = [], synced: TimeInterval? = 120, fill: LibraryFill? = nil
    ) -> SyncFootLine? {
        let report = SyncReport(
            phase: phase, fill: fill, waiting: waiting, oldestWaiting: oldest.map { now - $0 }, problems: problems, queueRead: true)
        return SyncFootLine(state: state, report: report, lastSynced: synced.map { now - $0 }, now: now, locale: english)
    }

    private func problem() -> SyncProblemEntry {
        SyncProblemEntry(
            id: .write("w"), itemID: nil, kind: .refused, change: .edit, reason: nil, content: SyncContent(),
            actions: MarfaProblems.actions(for: .refused))
    }

    // MARK: States

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
        #expect(refused.help?.contains("sign") == true)

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
