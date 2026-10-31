import Foundation
@testable import MAPP
import Synchronization
import Testing

/// Recently Deleted says how long the bin keeps items only when the server's settings say so.
@MainActor
@Suite(.hangLimit) struct BinRetentionTests {
    private func library(_ config: FakeInstanceConfig?) -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        return (MarfaLibrary(source: source, notices: Notices(), config: config), source)
    }

    @Test func theBinShowsTheRetentionTheServerGives() async {
        let (library, _) = library(FakeInstanceConfig([.trashRetentionDays: .number(30)]))
        #expect(await eventually { library.trashDays == 30 })
    }

    @Test func theBinShowsNothingWhereTheServerSetsNone() async throws {
        let config = FakeInstanceConfig([.name: .text("Library")])
        let (library, _) = library(config)
        // Gives the read on opening time to answer, to see that it leaves the retention unsaid.
        try await Task.sleep(for: .milliseconds(200))
        #expect(library.trashDays == nil)
    }

    @Test func aBinKeptWithoutLimitOrAKeyThatMayNotReadTheSettingsShowsNothing() async throws {
        let (unlimited, _) = library(FakeInstanceConfig([.trashRetentionDays: .number(0)]))
        let refused = FakeInstanceConfig([.trashRetentionDays: .number(30)])
        refused.readFailure.withLock { $0 = .notPermitted }
        let (forbidden, _) = library(refused)
        let (sample, _) = library(nil)
        // Gives the reads on opening time to answer, to see that each leaves the retention unsaid.
        try await Task.sleep(for: .milliseconds(200))
        #expect(unlimited.trashDays == nil)
        #expect(forbidden.trashDays == nil)
        #expect(sample.trashDays == nil)
    }

    @Test func theRetentionIsReadAgainWhenTheServerIsReachedAgain() async throws {
        let config = FakeInstanceConfig([.trashRetentionDays: .number(30)])
        let (library, source) = library(config)
        try #require(await eventually { library.trashDays == 30 })
        source.state.set(.offline(reason: "network"))
        #expect(await eventually { library.connection == .offline(reason: "network") })
        config.config.withLock { $0.values[.trashRetentionDays] = .number(7) }

        source.state.set(.online)
        #expect(await eventually { library.trashDays == 7 })
    }

    @Test func aSaveInThisMarfaChangesTheRetentionAtOnce() async throws {
        let (library, _) = library(FakeInstanceConfig([.trashRetentionDays: .number(30)]))
        try #require(await eventually { library.trashDays == 30 })
        library.take(InstanceConfig(values: [.trashRetentionDays: .number(90)]))
        #expect(library.trashDays == 90)
    }
}
