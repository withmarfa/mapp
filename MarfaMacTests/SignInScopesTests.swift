import Foundation
import Marfa
import Testing
@testable import MarfaMac

/// What a sign-in asks the owner to approve: every owner permission, what the app's own settings need and registering link types. The vendor
/// scope is unavailable before its first type exists (`keys-and-oauth/app-vendor-not-named`), and discovery never lists it
/// afterward.
@Suite(.hangLimit)
struct SignInScopesTests {
    /// Every permission in the contract's table (`keys-and-oauth`, "The fifteen permissions") but `connectors.host`, which
    /// only a connector host's own key holds. Written out, so a change to the package's list is seen here.
    nonisolated private static let ownerPermissions = [
        "audit.read", "backups.manage", "blobs.manage", "config.manage", "connectors.manage", "grants.manage", "instance.maintain",
        "instance.read", "items.purge", "keys.manage", "keys.mint", "schema.write", "sign_ins.manage", "webhooks.manage",
    ]
    nonisolated private static let common = ["*:read", "*:write", "edge.*:read", "edge.*:write"] + ownerPermissions + ["profile.name:read"]
        + ["profile.username:read", "profile.email:read", "profile.name:write", "profile.avatar:read", "profile.avatar:write"]
    nonisolated private static let vendor = "app.marfa-mac.*:write"
    nonisolated private static let root = "app.*:write"
    nonisolated private static let registering = "metadata.types:write"
    nonisolated private static let linkTypes = "metadata.edge_types:write"

    @Test func theScopesAskForTheAppRootAndNotTheVendor() {
        #expect(SystemSignIns.scopes == Self.common + [Self.root, Self.registering, Self.linkTypes])
        #expect(!SystemSignIns.scopes.contains(Self.vendor))
        #expect(SystemSignIns.scopes.filter { $0.hasPrefix("app.") } == [Self.root])
    }

    @Test func aSignInAsksForEveryOwnerPermissionButTheConnectorHosts() {
        #expect(SystemSignIns.askedAtSignIn.map(\.rawValue).sorted() == Self.ownerPermissions)
        #expect(SystemSignIns.scopes.filter { InstancePermission(rawValue: $0) != nil } == Self.ownerPermissions)
        #expect(!SystemSignIns.scopes.contains("connectors.host"))
        #expect(SystemSignIns.askedAtSignIn.isSuperset(of: MarfaSettingsPage.allCases.compactMap(\.permission)))
    }

    /// A browser sign-in, a code sign-in, Sign In Again and Allow More… all ask through the same list.
    @Test func aSignInHandsThePackageTheSameList() throws {
        let signIns = SystemSignIns(bundleIdentifier: "com.withmarfa.marfa.debug", anchor: { nil })
        let connection = try MarfaConnection(address: "https://marfa.example")
        #expect(try signIns.authorization(for: connection).client.scopes == SystemSignIns.scopes)
    }

    @Test(arguments: [
        (nil as String?, "Marfa for Mac"),
        (" \t\u{2003}\n", "Marfa for Mac"),
        ("  Studio Mac  ", "Marfa for Mac on Studio Mac"),
        ("Étage 🖥️", "Marfa for Mac on Étage 🖥️"),
        (String(repeating: "🚀", count: 90), "Marfa for Mac on " + String(repeating: "🚀", count: 83)),
        (String(repeating: "e\u{301}", count: 50), "Marfa for Mac on " + String(repeating: "e\u{301}", count: 41)),
    ])
    func aNewRegistrationNamesTheMac(computerName: String?, expected: String) throws {
        let signIns = SystemSignIns(bundleIdentifier: "com.withmarfa.marfa.debug", computerName: computerName, anchor: { nil })
        let connection = try MarfaConnection(address: "https://marfa.example")
        let client = try signIns.authorization(for: connection).client
        #expect(client.name == expected)
        #expect(client.name.unicodeScalars.count <= 100)
        #expect(client.redirect?.absoluteString == "com.withmarfa.marfa.debug:/signed-in")
        #expect(signIns.service == "com.withmarfa.marfa.debug.marfa-sign-in")
    }

    @Test func theScriptedSignInRecordsTheList() async throws {
        let signIns = ScriptedSignIns()
        signIns.script(codeKey: "scripted")
        _ = try await signIns.startCodeSignIn(to: try MarfaConnection(address: "https://one.example"))
        #expect(signIns.askedScopes == [SystemSignIns.scopes])
        #expect(signIns.asked == [SystemSignIns.askedAtSignIn])
    }

    /// The slice includes existing settings with the app root, and a missing settings type with registration permission.
    @Test func aSignInHoldingTheAppRootReachesTheSettings() {
        #expect(PreferencesType.reachingScopes == [Self.vendor, Self.root])
        #expect(PreferencesReach.includes(.init(typeHeld: true, scopes: [Self.root]), holdsTypeNow: false))
        #expect(PreferencesReach.includes(.init(typeHeld: false, scopes: [Self.root, Self.registering]), holdsTypeNow: false))
        #expect(!PreferencesReach.includes(.init(typeHeld: true, scopes: ["*:write", Self.registering]), holdsTypeNow: false))
    }
}
