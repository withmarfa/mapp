import Foundation
@testable import MAPP
import Testing

/// Deleting for good, writing a view and choosing a type's icon are never queued, so each is offered by one rule:
/// `ItemLibrary.reachesServer`, true only while the server can be reached.
@Suite(.hangLimit)
@MainActor struct ServerReachTests {
    private nonisolated static let states: [(MarfaConnectionState, Bool)] = [
        (.connecting, false), (.online, true), (.offline(reason: "network"), false), (.keyRefused, false),
        (.unavailable(message: "Stopped."), false),
    ]

    /// A key the server takes reaches it, whatever the key may write: MAPP does not know a key's permissions, so a
    /// key that can read but not write is offered these commands, and the server's refusal is told (as
    /// `TypeIconPickerTests.aRefusalChangesNothingAndSaysWhy` and the view write tests show). A refused key does not.
    @Test(arguments: 0..<states.count)
    func everyCommandThatNeedsTheServerFollowsOneRule(index: Int) async throws {
        let (state, reaches) = Self.states[index]
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: [], catalogue: LibraryFixture.catalogue)))
        try #require(await eventually { library.isLoaded })
        source.state.set(state)
        #expect(await eventually { library.connection == state })

        #expect(library.reachesServer == reaches)
        #expect(TypeIconPickerModel(type: TypeID("core.task"), library: library).canChoose == reaches)
        library.deletePermanentlyOnConfirm([])
        #expect(library.notices.waiting.isEmpty == reaches, "a purge out of reach is refused and told")
    }

    /// With no server set there is no library, so nothing that needs a server is offered.
    @Test func noInstanceHasNoLibraryToOfferThem() throws {
        let host = try HostBench().host()
        #expect(host.library == nil)
        #expect(host.state == .disconnected)
    }
}
