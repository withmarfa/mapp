import Foundation
import Testing
@testable import MAPP

/// Which library the windows read, and when. Every host is on its own defaults, key store and store directory,
/// never the person's Keychain or saved server.
@MainActor struct LibrariesTests {
    private let address = "http://first.test:8210"

    private func libraries(_ bench: HostBench) throws -> Libraries {
        let defaults = try #require(UserDefaults(suiteName: "LibrariesTests-\(UUID().uuidString)"))
        return Libraries(folder: NotesFolder(defaults: defaults), host: bench.host())
    }

    @Test func withNoServerSetTheFolderIsAlwaysTheLibrary() {
        for state in [MarfaHost.State.disconnected, .online, .keyRefused] {
            for flag in [false, true] {
                #expect(Libraries.mode(hasSource: false, isConfigured: false, state: state, isLaunching: flag, isBusy: flag) == .files)
            }
        }
    }

    @Test func anOpenCopyIsTheLibraryWhateverTheServerSays() {
        for state in [MarfaHost.State.connecting, .online, .offline(reason: nil), .keyRefused, .unavailable(message: "x")] {
            #expect(Libraries.mode(hasSource: true, isConfigured: true, state: state, isLaunching: false, isBusy: false) == .marfa)
        }
    }

    @Test func aSavedServerIsOpeningUntilItsCopyIsTried() {
        #expect(Libraries.mode(hasSource: false, isConfigured: true, state: .disconnected, isLaunching: true, isBusy: false) == .opening)
        #expect(Libraries.mode(hasSource: false, isConfigured: true, state: .connecting, isLaunching: false, isBusy: true) == .opening)
    }

    @Test func aSavedServerWhoseCopyWillNotOpenIsNeverAnsweredWithTheFolder() {
        #expect(Libraries.mode(hasSource: false, isConfigured: true, state: .keyRefused, isLaunching: false, isBusy: false) == .failed)
        #expect(Libraries.mode(hasSource: false, isConfigured: true, state: .unavailable(message: "x"), isLaunching: false, isBusy: false) == .failed)
        #expect(Libraries.mode(hasSource: false, isConfigured: true, state: .disconnected, isLaunching: false, isBusy: false) == .failed)
    }

    /// A copy closed to open again, as when a key is replaced, is waited for: the windows never show the notes
    /// folder, nor say the library can't open, in between. Leaving a server forgets its address first, so the
    /// folder follows at once.
    @Test func aCopyBeingReopenedIsWaitedForNeverShownAsTheFolder() {
        for state in [MarfaHost.State.disconnected, .online, .offline(reason: nil), .keyRefused, .unavailable(message: "x")] {
            #expect(Libraries.mode(hasSource: false, isConfigured: true, state: state, isLaunching: false, isBusy: true) == .opening)
        }
    }

    @Test func withNoServerSetNothingChangesAndTheHostIsNeverOpened() throws {
        let bench = try HostBench()
        let libraries = try libraries(bench)
        #expect(libraries.mode == .files)
        #expect(libraries.isLaunching == false)
        #expect(libraries.current == nil, "no notes folder is chosen yet")
        #expect(libraries.host.source == nil)
        #expect(bench.servers.opened.isEmpty)
    }

    @Test func connectingChoosesTheServersLibraryAndDisconnectingGivesTheFolderBack() async throws {
        let bench = try HostBench()
        let libraries = try libraries(bench)
        try await libraries.host.connect(address: address, key: "key")
        #expect(libraries.mode == .marfa)
        let library = try #require(libraries.current as? MarfaLibrary)
        #expect(libraries.current as? MarfaLibrary === library, "one library for as long as its source is open")

        try await libraries.host.disconnect()
        #expect(libraries.mode == .files)
        #expect(libraries.current == nil)
    }

    @Test func anotherServerIsAnotherLibrary() async throws {
        let bench = try HostBench()
        let libraries = try libraries(bench)
        try await libraries.host.connect(address: address, key: "key")
        let first = try #require(libraries.current as? MarfaLibrary)
        try await libraries.host.changeAddress(to: "http://second.test:8210", key: "other")
        let second = try #require(libraries.current as? MarfaLibrary)
        #expect(first !== second)
    }

    @Test func aSavedServerOpensOnLaunchAndPaintsBeforeTheNetwork() async throws {
        let bench = try HostBench()
        let connection = try MarfaConnection(address: address)
        bench.defaults.set(address, forKey: "MarfaAddress")
        bench.keys.save("key", for: connection)
        let libraries = try libraries(bench)
        #expect(libraries.mode == .opening)
        #expect(libraries.current == nil)

        await libraries.launch()
        #expect(libraries.isLaunching == false)
        #expect(libraries.mode == .marfa)
        #expect(libraries.current is MarfaLibrary)
        #expect(libraries.host.state == .connecting, "the library shows before the server has answered")
    }

    @Test func aSavedServerWithNoKeyShowsAPageNotTheFolder() async throws {
        let bench = try HostBench()
        bench.defaults.set(address, forKey: "MarfaAddress")
        let libraries = try libraries(bench)
        await libraries.launch()
        #expect(libraries.mode == .failed)
        #expect(libraries.current == nil)
        #expect(libraries.host.state == .keyRefused)
    }
}
