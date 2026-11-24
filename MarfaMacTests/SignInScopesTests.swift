import Foundation
import Marfa
import Testing
@testable import MarfaMac

/// What a sign-in asks the owner to approve for the app's own settings. Discovery never lists an app's vendor scope, and a
/// first type is registered only while holding `app.*:write` (`keys-and-oauth/app-vendor-not-named`), so every sign-in asks
/// for `app.*:write` and never the scope that names the vendor.
@Suite(.hangLimit)
struct SignInScopesTests {
    nonisolated private static let common = [
        "*:read", "*:write", "edge.*:read", "edge.*:write", "items.purge", "config.manage", "schema.write", "profile.name:read",
    ]
    nonisolated private static let vendor = "app.marfa-mac.*:write"
    nonisolated private static let root = "app.*:write"
    nonisolated private static let registering = "metadata.types:write"

    @Test func theScopesAskForTheAppRootAndNotTheVendor() {
        #expect(SystemSignIns.scopes == Self.common + [Self.root, Self.registering])
        #expect(!SystemSignIns.scopes.contains(Self.vendor))
        #expect(SystemSignIns.scopes.filter { $0.hasPrefix("app.") } == [Self.root])
    }

    /// A browser sign-in, a code sign-in, Sign In Again and Allow More… all ask through the same list.
    @Test func aSignInHandsThePackageTheSameList() throws {
        let signIns = SystemSignIns(bundleIdentifier: "com.withmarfa.marfa.debug", anchor: { nil })
        let connection = try MarfaConnection(address: "https://marfa.example")
        for permissions in [Set<InstancePermission>(), SystemSignIns.askedAtSignIn, Set(InstancePermission.allCases)] {
            let asked = try signIns.authorization(for: connection, asking: permissions).client.scopes
            #expect(asked == SystemSignIns.scopes)
        }
    }

    @Test func theScriptedSignInRecordsTheList() async throws {
        let signIns = ScriptedSignIns()
        signIns.script(codeKey: "scripted")
        _ = try await signIns.startCodeSignIn(to: try MarfaConnection(address: "https://one.example"), asking: [])
        #expect(signIns.askedScopes == [SystemSignIns.scopes])
    }

    /// The settings sync reaches the item with the app root alone, and the first Mac registers the type with it and
    /// `metadata.types:write`.
    @Test func aSignInHoldingTheAppRootReachesTheSettings() {
        #expect(PreferencesType.reachingScopes == [Self.vendor, Self.root])
        #expect(PreferencesReach.includes(.init(typeHeld: true, scopes: [Self.root]), holdsTypeNow: false))
        #expect(PreferencesReach.includes(.init(typeHeld: false, scopes: [Self.root, Self.registering]), holdsTypeNow: false))
        #expect(!PreferencesReach.includes(.init(typeHeld: true, scopes: ["*:write", Self.registering]), holdsTypeNow: false))
    }
}
