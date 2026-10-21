import Foundation
import Testing
@testable import MAPP

struct AppConfigurationTests {
    /// The tests are hosted in the Debug build, which has an identifier of its own so that it never shares the
    /// installed app's container, defaults, saved server, Marfa store or keychain items.
    @Test func theDebugBuildHasItsOwnBundleIdentifier() {
        #expect(Bundle.main.bundleIdentifier == "com.withmarfa.mapp.debug")
    }

    @Test func signInsAreKeptUnderTheBundleIdentifier() {
        #expect(KeychainSignIn.service == "com.withmarfa.mapp.debug.marfa-sign-in")
    }

    /// The browser returns to a private-use address whose scheme is the bundle identifier, which the app claims.
    @Test func theSignInRedirectIsOneTheAppClaims() throws {
        let redirect = try #require(KeychainSignIn.redirect)
        #expect(redirect.absoluteString == "com.withmarfa.mapp.debug:/signed-in")
        let types = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains(try #require(redirect.scheme)))
    }
}
