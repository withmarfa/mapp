import Foundation
import Testing
@testable import MarfaMac

struct AppConfigurationTests {
    /// The tests are hosted in the Debug build, which has an identifier of its own so that it never shares the
    /// installed app's defaults, saved server, Marfa store or keychain items.
    @Test func theDebugBuildHasItsOwnBundleIdentifier() {
        #expect(Bundle.main.bundleIdentifier == "com.withmarfa.marfa.debug")
    }

    @Test func signInsAreKeptAndReturnedUnderTheBundleIdentifier() {
        let signIns = SystemSignIns(anchor: { nil })
        #expect(signIns.service == "com.withmarfa.marfa.debug.marfa-sign-in")
        #expect(signIns.scheme == "com.withmarfa.marfa.debug")
    }
}
