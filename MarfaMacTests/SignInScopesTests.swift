import Foundation
import Marfa
import Testing
@testable import MarfaMac

/// What a sign-in asks the owner to approve, and how it learns what the server offers. A Marfa lists an app vendor's scope
/// only once a type sits under the vendor, so the first sign-in of an app asks for `app.*:write` (`keys-and-oauth/app-vendor-not-named`).
struct SignInScopesTests {
    nonisolated private static let common = [
        "*:read", "*:write", "edge.*:read", "edge.*:write", "items.purge", "config.manage", "schema.write", "profile.name:read",
    ]
    nonisolated private static let vendor = "app.marfa-mac.*:write"
    nonisolated private static let root = "app.*:write"
    nonisolated private static let registering = "metadata.types:write"
    nonisolated private static let address = URL(string: "https://marfa.example")!

    /// A server's metadata offering `scopes`.
    nonisolated private static func answer(_ scopes: [String], status: Int = 200) -> OfferedScopes {
        .reading { request in
            let body = try JSONSerialization.data(withJSONObject: ["issuer": "https://marfa.example", "scopes_supported": scopes])
            return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    /// The scopes the real sign-in hands the package for a server that answers as `offered`.
    nonisolated private static func asked(offering offered: OfferedScopes) async throws -> [String] {
        let signIns = SystemSignIns(bundleIdentifier: "com.withmarfa.marfa.debug", offered: offered, anchor: { nil })
        return try await signIns.authorization(for: try MarfaConnection(address: address.absoluteString), asking: []).client.scopes
    }

    // MARK: Which scope reaches the app's settings

    @Test func aServerThatOffersTheVendorScopeIsAskedForIt() {
        let asked = SystemSignIns.scopes(offered: ["*:read", Self.vendor, Self.root])
        #expect(asked == Self.common + [Self.vendor, Self.registering])
    }

    @Test func aServerThatDoesNotOfferTheVendorScopeIsAskedForTheAppRootAlone() {
        let asked = SystemSignIns.scopes(offered: ["*:read", Self.root, "app.*:read"])
        #expect(asked == Self.common + [Self.root, Self.registering])
        #expect(asked == SystemSignIns.scopes(offered: []))
    }

    /// An older Marfa with an `app.mapp` type, or other vendors' types, offers their scopes and not this app's.
    @Test func anotherVendorsScopeIsNotThisAppsAndIsNeverAsked() {
        let asked = SystemSignIns.scopes(offered: ["app.mapp.*:write", "app.other.*:read", Self.root])
        #expect(asked == Self.common + [Self.root, Self.registering])
    }

    @Test(arguments: [
        Set<String>(), ["app.marfa-mac.*:write"], ["app.*:write"], ["app.marfa-mac.*:write", "app.*:write"],
        ["app.mapp.*:write", "app.marfa-mac.*:read"],
    ])
    func neverBothAndNeverMoreOfTheAppRootThanOneScope(offered: Set<String>) {
        let asked = SystemSignIns.scopes(offered: offered)
        let app = asked.filter { $0.hasPrefix("app.") }
        #expect(app.count == 1 && (app == [Self.vendor] || app == [Self.root]), "\(app)")
        #expect(Array(asked.prefix(Self.common.count)) == Self.common, "nothing else in the list changes")
        #expect(asked.last == Self.registering)
    }

    // MARK: What the sign-in hands the package

    @Test func theSignInAsksThePackageForTheVendorScopeWhereTheServerOffersIt() async throws {
        let asked = try await Self.asked(offering: Self.answer(["content:read", Self.vendor, Self.root]))
        #expect(asked == SystemSignIns.scopes(offered: [Self.vendor]))
        #expect(asked.contains(Self.vendor) && !asked.contains(Self.root))
    }

    @Test func theSignInAsksThePackageForTheAppRootWhereTheServerOffersNoVendorScope() async throws {
        let asked = try await Self.asked(offering: Self.answer(["content:read", Self.root, "app.*:read"]))
        #expect(asked == SystemSignIns.scopes(offered: []))
        #expect(asked.contains(Self.root) && !asked.contains(Self.vendor))
    }

    /// A metadata read that fails starts no sign-in: asking for the root would widen what is asked where the vendor scope
    /// may be offered, and dropping the scope would leave the settings out of reach.
    @Test(arguments: [
        URLError(.notConnectedToInternet), URLError(.timedOut), URLError(.cannotFindHost),
    ])
    func aMetadataReadThatFailsAsksForNothing(error: URLError) async {
        let offered = OfferedScopes.reading { _ in throw error }
        await #expect(throws: URLError.self) { _ = try await Self.asked(offering: offered) }
    }

    @Test func aServerThatAnswersNoMetadataAsksForNothingAndIsNoMarfaServer() async {
        for status in [404, 500, 301] {
            do {
                _ = try await Self.asked(offering: Self.answer(["*:read"], status: status))
                Issue.record("a \(status) answer started a sign-in")
            } catch {
                #expect(SignInOutcome(error) == .notMarfa, "\(status)")
            }
        }
    }

    // MARK: Reading the metadata

    @Test func metadataListsTheScopesTheServerOffers() throws {
        let body = Data(#"{"issuer":"https://marfa.example","scopes_supported":["*:read","app.*:write"]}"#.utf8)
        #expect(try OfferedScopes.parse(status: 200, body: body) == ["*:read", "app.*:write"])
    }

    @Test(arguments: [
        #"{"issuer":"https://marfa.example"}"#, #"{"scopes_supported":"app.*:write"}"#, #"{"scopes_supported":[1,2]}"#,
        #"["app.*:write"]"#, "not json", "",
    ])
    func metadataWithoutAListOfScopesIsNoAnswer(body: String) {
        #expect(throws: SignInError.self) { try OfferedScopes.parse(status: 200, body: Data(body.utf8)) }
    }

    @Test func anAnswerThatIsNotOkIsRefusedAsAStatusWhateverItHolds() {
        let body = Data(#"{"scopes_supported":["app.marfa-mac.*:write"]}"#.utf8)
        for status in [204, 301, 404, 500] {
            #expect(throws: SignInError.refused(code: "http_\(status)", message: "the server answered \(status)")) {
                try OfferedScopes.parse(status: status, body: body)
            }
        }
        #expect(SignInOutcome(SignInError.refused(code: "http_404", message: "")) == .notMarfa)
    }

    /// The metadata is at the server's origin, however the address was typed.
    @Test func theMetadataIsReadAtTheServersOriginAndAskedForAsJSON() async throws {
        let seen = Seen()
        let offered = OfferedScopes.reading { request in
            seen.add(request)
            return (Data(#"{"scopes_supported":["app.marfa-mac.*:write"]}"#.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let typed = try MarfaConnection(address: "https://marfa.example:8210/some/path/")
        #expect(try await offered.read(typed.address) == ["app.marfa-mac.*:write"])
        #expect(try await offered.read(#require(URL(string: "https://marfa.example:8210/other?x=1#y"))) == ["app.marfa-mac.*:write"])
        #expect(seen.requests.count == 2)
        #expect(Set(seen.requests.compactMap { $0.url?.absoluteString }) == ["https://marfa.example:8210/.well-known/oauth-authorization-server"])
        let request = try #require(seen.requests.first)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.httpMethod == "GET" || request.httpMethod == nil)
    }

    /// A redirect to another server must not decide what the app asks this one for.
    @Test func anAnswerFromAnotherOriginIsNotTheServers() async {
        let offered = OfferedScopes.reading { _ in
            (Data(#"{"scopes_supported":["app.marfa-mac.*:write"]}"#.utf8),
                HTTPURLResponse(url: URL(string: "https://elsewhere.example/.well-known/oauth-authorization-server")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        await #expect(throws: SignInError.self) { _ = try await offered.read(Self.address) }
    }

    @Test func aReplyThatIsNotHTTPIsNoAnswer() async {
        let offered = OfferedScopes.reading { request in (Data(), URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)) }
        await #expect(throws: URLError.self) { _ = try await offered.read(Self.address) }
    }

    // MARK: What the sign-in holds

    /// The settings sync reaches the item with either scope; only the first Mac registers the type.
    @Test func aSignInHoldingTheAppRootAloneReachesTheSettings() {
        let held: Set<String> = [Self.root, Self.registering, "*:write"]
        #expect(PreferencesReach.includes(.init(typeHeld: true, scopes: [Self.root]), holdsTypeNow: false))
        #expect(PreferencesReach.includes(.init(typeHeld: false, scopes: held), holdsTypeNow: false))
        #expect(PreferencesReach.includes(.init(typeHeld: true, scopes: [Self.vendor]), holdsTypeNow: false))
        #expect(!PreferencesReach.includes(.init(typeHeld: true, scopes: ["*:write", Self.registering]), holdsTypeNow: false))
        #expect(PreferencesType.reachingScopes == [Self.vendor, Self.root])
    }

    @Test func theScriptedSignInAsksAsTheServerOffers() async throws {
        let signIns = ScriptedSignIns()
        let connection = try MarfaConnection(address: "https://one.example")
        _ = try await signIns.startCodeSignInScoped(to: connection)
        signIns.script(offering: [Self.vendor])
        _ = try await signIns.startCodeSignInScoped(to: connection)
        #expect(signIns.askedScopes == [SystemSignIns.scopes(offered: []), SystemSignIns.scopes(offered: [Self.vendor])])
    }
}

private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { stored } }
    func add(_ request: URLRequest) { lock.withLock { stored.append(request) } }
}

private extension ScriptedSignIns {
    /// A code sign-in that keeps a key, to record what it asked for.
    func startCodeSignInScoped(to connection: MarfaConnection) async throws -> CodeSignIn {
        script(codeKey: "scripted")
        return try await startCodeSignIn(to: connection, asking: [])
    }
}
