import AppKit
import MarfaTesting
import Testing
@testable import MAPP

/// The unit tests run inside the app, so these check that the app they run in stays out of the person's way and
/// away from their data.
struct TestHostTests {
    @Test func hostShowsNoDockIconAndNoScene() {
        #expect(NSRunningApplication.current.activationPolicy == .prohibited)
        #expect(!(NSApp.delegate is AppDelegate))
    }

    @Test func standardLibrariesKeepSignInsInMemoryAndAwayFromTheSavedServer() {
        let libraries = Libraries.standard()
        #expect(libraries.host.signIns is MemorySignIns)
        #expect(libraries.host.location.root != MarfaStoreLocation.applicationSupport)
        #expect(libraries.host.connection == nil)
    }
}
