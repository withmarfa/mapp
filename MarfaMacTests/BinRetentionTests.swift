import Foundation
@testable import MarfaMac
import Synchronization
import Testing

/// Recently Deleted says how long the bin keeps items only when the server's settings say so.
@MainActor
@Suite(.hangLimit) struct BinRetentionTests {
    private func library(_ config: FakeInstanceConfig?) -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        return (MarfaLibrary(source: source, notices: Notices(), config: config), source)
    }

    @Test func aReadThatAnswersAfterASaveInThisMarfaLeavesTheSave() async throws {
        let config = FakeInstanceConfig([.trashRetentionDays: .number(30)])
        let (library, _) = library(config)
        try #require(await eventually { library.trashDays == 30 })
        config.holdNextRead()
        library.readTrashDays()
        try #require(await eventually { config.holdsARead })

        library.take(InstanceConfig(values: [.trashRetentionDays: .number(90)]))
        config.answerHeldReads()
        // Gives the held read time to answer, to see that it leaves the save's retention.
        try await Task.sleep(for: .milliseconds(200))
        #expect(library.trashDays == 90, "a read made before the save put back the older retention")
    }

    @Test func anOlderReadThatAnswersLastLeavesTheNewerOne() async throws {
        let config = FakeInstanceConfig([.trashRetentionDays: .number(30)])
        let (library, _) = library(config)
        try #require(await eventually { library.trashDays == 30 })
        config.config.withLock { $0.values[.trashRetentionDays] = .number(14) }
        config.holdNextRead()
        library.readTrashDays()
        try #require(await eventually { config.holdsARead })
        config.config.withLock { $0.values[.trashRetentionDays] = .number(7) }
        library.readTrashDays()
        try #require(await eventually { library.trashDays == 7 })

        config.answerHeldReads()
        // Gives the held read time to answer, to see that it leaves the newer read's retention.
        try await Task.sleep(for: .milliseconds(200))
        #expect(library.trashDays == 7, "an older read put back the retention it found")
    }

    @Test func aNewerReadThatFailsLeavesTheOlderReadsAnswer() async throws {
        let config = FakeInstanceConfig([.trashRetentionDays: .number(30)])
        let (library, _) = library(config)
        try #require(await eventually { library.trashDays == 30 })
        config.config.withLock { $0.values[.trashRetentionDays] = .number(14) }
        config.holdNextRead()
        library.readTrashDays()
        try #require(await eventually { config.holdsARead })
        config.readFailure.withLock { $0 = .unreachable }
        library.readTrashDays()

        config.answerHeldReads()
        #expect(await eventually { library.trashDays == 14 }, "a newer read that failed dropped the older read's answer")
    }
}
