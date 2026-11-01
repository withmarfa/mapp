import Foundation
import Testing
@testable import MAPP

struct AppConfigurationTests {
    /// The tests are hosted in the Debug build, which has an identifier of its own so that it never shares the
    /// installed app's container, defaults, saved server, Marfa store or keychain items.
    @Test func theDebugBuildHasItsOwnBundleIdentifier() {
        #expect(Bundle.main.bundleIdentifier == "com.withmarfa.mapp.debug")
    }

    @Test func signInsAreKeptAndReturnedUnderTheBundleIdentifier() {
        let signIns = SystemSignIns(anchor: { nil })
        #expect(signIns.service == "com.withmarfa.mapp.debug.marfa-sign-in")
        #expect(signIns.scheme == "com.withmarfa.mapp.debug")
    }
}
